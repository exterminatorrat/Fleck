#!/usr/bin/env python3
"""Compile-only Fleck build inputs for split-machine packaging.

`build` compiles the Release products on a build machine and exports them with
an immutable JSON receipt. `verify` re-checks that receipt on the packaging
machine and stages a private copy of every input.

Neither command reads or writes the accepted-build registry or the build
identity allocator. A receipt never claims an allocated build identity; the
packaging machine still allocates that through fleck-build-identity.py.

The build and packaging machines may run different Swift, Xcode, and SDK
versions, so `verify` checks the receipted producer toolchain for structure
under the trusted receipt digest and then confirms from each product's Mach-O
load commands that it is a thin arm64 executable linked at the receipt's
minimum OS and SDK.
"""
import argparse
import datetime as dt
import hashlib
import importlib.util
import json
import os
import platform
import posixpath
import re
import subprocess
import sys
import uuid
from pathlib import Path

SCHEMA_VERSION = 1
RECEIPT_NAME = "receipt.json"
RECEIPT_STATUS = "compile-inputs-not-a-candidate"
CONFIGURATION = "Release"
ARCHITECTURE = "arm64"
MINIMUM_OS_VERSION = "14.0"
PRODUCTS = ["Fleck", "fleck-agent"]
SPARKLE_LINK = "@rpath/Sparkle.framework/Versions/B/Sparkle"
SPARKLE_FRAMEWORK = (
    ".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/"
    "macos-arm64_x86_64/Sparkle.framework"
)
GRAPH_ENVIRONMENT_KEYS = ("FLECK_ENHANCED_CANDIDATE", "FLECK_BUILD_WITHOUT_SPARKLE")
HEX40_RE = re.compile(r"^[0-9a-f]{40}$")
HEX64_RE = re.compile(r"^[0-9a-f]{64}$")
SWIFT_VERSION_RE = re.compile(r"^(?:Apple )?Swift version [0-9]+(?:\.[0-9]+)+(?: \([^()]+\))?$")
XCODE_VERSION_RE = re.compile(r"^Xcode [0-9]+(?:\.[0-9]+)+$")
XCODE_BUILD_VERSION_RE = re.compile(r"^[0-9]+[A-Z][0-9]+[a-z]?$")
SDK_VERSION_RE = re.compile(r"^[0-9]+(?:\.[0-9]+)+$")
TOOLCHAIN_KEYS = [
    "swiftVersion",
    "xcodeVersion",
    "xcodeBuildVersion",
    "sdkVersion",
    "minimumOSVersion",
]
RECEIPT_KEYS = {
    "schemaVersion",
    "status",
    "receiptID",
    "createdAt",
    "source",
    "productVersion",
    "configuration",
    "architecture",
    "toolchain",
    "build",
    "dependencies",
    "frameworks",
    "inventory",
}
ALLOCATED_IDENTITY_KEYS = {
    "buildID",
    "buildNumber",
    "bundleVersion",
    "artifactName",
    "candidateStatus",
    "FleckBuildID",
    "FleckBuildNumber",
    "FleckBuildLabel",
}


class InputError(Exception):
    pass


def fail(message):
    raise InputError(message)


def load_identity_tool():
    path = Path(__file__).resolve().with_name("fleck-build-identity.py")
    if not path.is_file():
        fail(f"build identity helper is missing: {path.name}")
    spec = importlib.util.spec_from_file_location("fleck_build_identity", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


IDENTITY = load_identity_tool()


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path):
    try:
        return sha256_bytes(Path(path).read_bytes())
    except OSError as error:
        fail(f"could not read {path}: {error}")


def mode_text(mode):
    return f"{mode & 0o7777:04o}"


def create_time():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def run_captured(arguments, cwd, environment=None):
    result = subprocess.run(
        arguments, cwd=str(cwd), text=True, capture_output=True, env=environment
    )
    if result.returncode:
        detail = (result.stderr or "").strip() or (result.stdout or "").strip()
        tail = detail.splitlines()[-20:]
        fail(f"command failed ({' '.join(arguments)}): {' | '.join(tail)}")
    return result.stdout


def run_streaming(arguments, cwd, environment=None):
    try:
        result = subprocess.run(arguments, cwd=str(cwd), env=environment)
    except OSError as error:
        fail(f"could not launch {arguments[0]}: {error}")
    if result.returncode:
        fail(
            f"command failed ({' '.join(arguments)}) "
            f"with exit status {result.returncode}"
        )


def read_json_file(path, label):
    try:
        return json.loads(Path(path).read_bytes())
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        fail(f"could not read {label}: {error}")


def require_plain_directory(path, label):
    path = Path(path)
    if path.is_symlink() or not path.is_dir():
        fail(f"{label} must be a real directory: {path}")
    return path


def safe_relative_path(value, label):
    if not isinstance(value, str) or not value:
        fail(f"{label} path must be a nonempty string")
    if "\x00" in value or "\\" in value:
        fail(f"{label} path contains an unsupported character: {value!r}")
    if value.startswith("/"):
        fail(f"{label} path must be relative: {value}")
    if any(part in ("", ".", "..") for part in value.split("/")):
        fail(f"{label} path must be a normalized relative path: {value}")
    if posixpath.normpath(value) != value:
        fail(f"{label} path must be a normalized relative path: {value}")
    return value


def resolve_within(root, relative, label):
    root = Path(root).resolve()
    candidate = root / relative
    try:
        Path(candidate).resolve().relative_to(root)
    except ValueError:
        fail(f"{label} path escapes the input directory: {relative}")
    return candidate


def pinned_dependencies(repo):
    path = Path(repo) / "Package.resolved"
    try:
        data = path.read_bytes()
    except OSError as error:
        fail(f"could not read Package.resolved: {error}")
    document = read_json_file(path, "Package.resolved")
    pins = document.get("pins")
    if not isinstance(pins, list):
        fail("Package.resolved is missing its pins")
    dependencies = []
    for pin in pins:
        if not isinstance(pin, dict):
            fail("Package.resolved contains a malformed pin")
        identity = pin.get("identity")
        location = pin.get("location")
        state = pin.get("state")
        if not isinstance(identity, str) or not identity:
            fail("Package.resolved contains a pin without an identity")
        if not isinstance(location, str) or not location:
            fail(f"Package.resolved pin has no location: {identity}")
        if not isinstance(state, dict) or not HEX40_RE.fullmatch(str(state.get("revision"))):
            fail(f"Package.resolved pin has no full revision: {identity}")
        version = state.get("version") or state.get("branch")
        dependencies.append(
            {
                "identity": identity,
                "location": location,
                "revision": state["revision"],
                "version": version if isinstance(version, str) and version else None,
            }
        )
    dependencies.sort(key=lambda item: item["identity"])
    if len({item["identity"] for item in dependencies}) != len(dependencies):
        fail("Package.resolved repeats a dependency identity")
    return data, dependencies


def normalized_location(value):
    text = value.strip().lower()
    while text.endswith("/"):
        text = text[:-1]
    if text.endswith(".git"):
        text = text[:-4]
    return text


def dependency_checkouts(repo):
    root = Path(repo) / ".build/checkouts"
    if root.is_symlink() or not root.is_dir():
        fail("resolved dependency checkouts are missing; the build did not resolve dependencies")
    checkouts = []
    for entry in sorted(root.iterdir()):
        if entry.is_symlink() or not entry.is_dir():
            fail(f"dependency checkout is not a plain directory: {entry.name}")
        try:
            location = IDENTITY.run("git", "-C", str(entry), "config", "--get", "remote.origin.url")
            revision = IDENTITY.run("git", "-C", str(entry), "rev-parse", "HEAD^{commit}")
            status = IDENTITY.run(
                "git", "-C", str(entry), "status", "--porcelain=v1", "--untracked-files=all"
            )
        except IDENTITY.IdentityError as error:
            fail(f"dependency checkout could not be inspected ({entry.name}): {error}")
        if not location:
            fail(f"dependency checkout has no origin remote: {entry.name}")
        if not HEX40_RE.fullmatch(revision):
            fail(f"dependency checkout has no full revision: {entry.name}")
        if status:
            fail(f"dependency checkout is dirty: {entry.name}")
        checkouts.append(
            {"checkout": entry.name, "location": location, "revision": revision}
        )
    return checkouts


def require_checkout_agreement(dependencies, checkouts):
    by_location = {}
    for checkout in checkouts:
        by_location.setdefault(normalized_location(checkout["location"]), []).append(checkout)
    for dependency in dependencies:
        matches = by_location.get(normalized_location(dependency["location"]), [])
        if len(matches) != 1:
            fail(
                "resolved dependency checkout is missing or ambiguous: "
                f"{dependency['identity']}"
            )
        if matches[0]["revision"] != dependency["revision"]:
            fail(
                "dependency checkout revision does not match Package.resolved: "
                f"{dependency['identity']}"
            )
    pinned = {normalized_location(item["location"]) for item in dependencies}
    for checkout in checkouts:
        if normalized_location(checkout["location"]) not in pinned:
            fail(f"unexpected dependency checkout is present: {checkout['checkout']}")


def toolchain_state():
    if platform.system() != "Darwin":
        fail("compile inputs require macOS")
    if platform.machine() != ARCHITECTURE:
        fail(f"compile inputs require an {ARCHITECTURE} build host")
    try:
        IDENTITY.run("xcode-select", "-p")
        swift_version = IDENTITY.run("swift", "--version").splitlines()[0].strip()
        xcode_output = IDENTITY.run("xcodebuild", "-version").splitlines()
        sdk_version = IDENTITY.run("xcrun", "--sdk", "macosx", "--show-sdk-version")
    except (IDENTITY.IdentityError, IndexError) as error:
        fail(f"required build toolchain is unavailable: {error}")
    if not SDK_VERSION_RE.fullmatch(sdk_version):
        fail("could not determine the active macOS SDK version")
    xcode_version = xcode_output[0].strip() if xcode_output else ""
    build_version = ""
    for line in xcode_output[1:]:
        match = re.fullmatch(r"Build version (\S+)", line.strip())
        if match:
            build_version = match.group(1)
            break
    if not swift_version or not xcode_version or not build_version:
        fail("could not record the active Swift and Xcode toolchain")
    return {
        "swiftVersion": swift_version,
        "xcodeVersion": xcode_version,
        "xcodeBuildVersion": build_version,
        "sdkVersion": sdk_version,
        "minimumOSVersion": MINIMUM_OS_VERSION,
    }


def linker_arguments(toolchain):
    return ["-platform_version", "macos", MINIMUM_OS_VERSION, toolchain["sdkVersion"]]


def build_arguments(product, toolchain):
    arguments = [
        "swift",
        "build",
        "-c",
        "release",
        "--product",
        product,
        "--jobs",
        "1",
        "-Xswiftc",
        "-j",
        "-Xswiftc",
        "1",
        "--disable-automatic-resolution",
    ]
    for value in linker_arguments(toolchain):
        arguments.extend(["-Xlinker", value])
    return arguments


def compile_products(repo, toolchain):
    environment = {
        key: value
        for key, value in os.environ.items()
        if key not in GRAPH_ENVIRONMENT_KEYS
    }
    for product in PRODUCTS:
        run_streaming(build_arguments(product, toolchain), repo, environment)


def copy_file(source, destination):
    data = Path(source).read_bytes()
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("xb") as handle:
        handle.write(data)
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(destination, 0o755)


def copy_payload_tree(source, destination):
    source = Path(source)
    for child in sorted(source.iterdir()):
        target = destination / child.name
        if child.is_symlink():
            os.symlink(os.readlink(child), target)
        elif child.is_dir():
            target.mkdir()
            copy_payload_tree(child, target)
        elif child.is_file():
            copy_file(child, target)
        else:
            fail(f"payload contains an unsupported entry: {child}")


def product_architectures(path):
    return IDENTITY.run("xcrun", "lipo", "-archs", str(path)).split()


def macho_build_version(path):
    inspection = IDENTITY.run("xcrun", "otool", "-l", str(path))
    minos = ""
    sdk = ""
    in_build_version = False
    for line in inspection.splitlines():
        fields = line.split()
        if fields[:1] == ["cmd"]:
            in_build_version = fields[1:2] == ["LC_BUILD_VERSION"]
        elif in_build_version and fields[:1] == ["minos"] and len(fields) > 1:
            minos = fields[1]
        elif in_build_version and fields[:1] == ["sdk"] and len(fields) > 1:
            sdk = fields[1]
            in_build_version = False
    if not minos or not sdk:
        fail(f"packaged executable records no build version: {path}")
    return minos, sdk


def linked_libraries(path):
    return IDENTITY.run("xcrun", "otool", "-L", str(path))


def export_products(repo, output, toolchain):
    repo = Path(repo)
    release = repo / ".build/release"
    expected_version = (MINIMUM_OS_VERSION, toolchain["sdkVersion"])
    for product in PRODUCTS:
        source = release / product
        if source.is_symlink() or not source.is_file():
            fail(f"compiled product is missing: {product}")
        if product_architectures(source) != [ARCHITECTURE]:
            fail(f"compiled product is not a thin {ARCHITECTURE} executable: {product}")
        if macho_build_version(source) != expected_version:
            fail(f"compiled product was not linked against the active SDK: {product}")
        copy_file(source, Path(output) / product)
    frameworks = []
    if SPARKLE_LINK in linked_libraries(release / "Fleck"):
        source = repo / SPARKLE_FRAMEWORK
        require_plain_directory(source, "cached Sparkle framework")
        destination = Path(output) / "Sparkle.framework"
        destination.mkdir()
        copy_payload_tree(source, destination)
        frameworks.append(
            {
                "path": "Sparkle.framework",
                "source": SPARKLE_FRAMEWORK,
                "identity": "sparkle",
            }
        )
    return frameworks


def walk_payload(root):
    root = Path(root)
    entries = []

    def visit(relative):
        directory = root / relative if relative else root
        for child in sorted(directory.iterdir()):
            child_relative = f"{relative}/{child.name}" if relative else child.name
            if child.is_symlink():
                entries.append(child_relative)
            elif child.is_dir():
                visit(child_relative)
            elif child.is_file():
                entries.append(child_relative)
            else:
                fail(f"payload contains an unsupported entry: {child_relative}")

    visit("")
    return entries


def inventory_entry(root, relative):
    path = Path(root) / relative
    details = path.lstat()
    if path.is_symlink():
        target = os.readlink(path)
        encoded = target.encode("utf-8")
        return {
            "path": relative,
            "kind": "symlink",
            "target": target,
            "bytes": len(encoded),
            "mode": mode_text(details.st_mode),
            "sha256": sha256_bytes(encoded),
        }
    return {
        "path": relative,
        "kind": "file",
        "bytes": details.st_size,
        "mode": mode_text(details.st_mode),
        "sha256": sha256_file(path),
    }


def build_inventory(root):
    return [inventory_entry(root, relative) for relative in walk_payload(root)]


def write_receipt(path, value):
    data = (json.dumps(value, indent=2, sort_keys=True) + "\n").encode("utf-8")
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o444)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
    except OSError as error:
        fail(f"could not write the compile input receipt: {error}")
    os.chmod(path, 0o444)
    return sha256_bytes(data)


def command_build(args):
    repo = Path(args.repo).resolve()
    output = Path(args.output)
    if not output.is_absolute():
        fail("output directory must be an absolute path")
    parent = output.parent
    if parent.is_symlink() or not parent.is_dir() or parent.resolve() != parent:
        fail("output directory parent must be an existing canonical directory")
    if os.path.lexists(output):
        fail(f"output directory must not already exist: {output}")
    try:
        commit, tree = IDENTITY.source_state(repo)
        version, _ = IDENTITY.product_version(repo)
    except IDENTITY.IdentityError as error:
        fail(str(error))
    toolchain = toolchain_state()
    resolved_bytes, dependencies = pinned_dependencies(repo)
    output.mkdir(mode=0o755)
    try:
        compile_products(repo, toolchain)
        try:
            IDENTITY.source_state(
                repo, {"sourceCommit": commit, "sourceTree": tree}
            )
        except IDENTITY.IdentityError as error:
            fail(str(error))
        require_checkout_agreement(dependencies, dependency_checkouts(repo))
        frameworks = export_products(repo, output, toolchain)
        receipt = {
            "schemaVersion": SCHEMA_VERSION,
            "status": RECEIPT_STATUS,
            "receiptID": str(uuid.uuid4()),
            "createdAt": create_time(),
            "source": {"commit": commit, "tree": tree, "clean": True},
            "productVersion": version,
            "configuration": CONFIGURATION,
            "architecture": ARCHITECTURE,
            "toolchain": toolchain,
            "build": {
                "products": list(PRODUCTS),
                "linkerArguments": linker_arguments(toolchain),
                "enhancedCandidate": False,
                "withoutSparkle": False,
            },
            "dependencies": {
                "packageResolvedSHA256": sha256_bytes(resolved_bytes),
                "verifiedFromCheckouts": True,
                "pins": dependencies,
            },
            "frameworks": frameworks,
            "inventory": build_inventory(output),
        }
        digest = write_receipt(output / RECEIPT_NAME, receipt)
    except BaseException:
        for child in sorted(output.rglob("*"), reverse=True):
            if child.is_symlink() or child.is_file():
                child.unlink()
            else:
                child.rmdir()
        output.rmdir()
        raise
    print(f"Exported compile inputs for Fleck {version} from {commit}")
    print(f"INPUT_ROOT={output}")
    print(f"RECEIPT_SHA256={digest}")


def require_object(value, keys, label):
    if not isinstance(value, dict) or set(value) != set(keys):
        fail(f"input receipt {label} is malformed")
    return value


def require_text(value, label):
    if not isinstance(value, str) or not value:
        fail(f"input receipt {label} must be a nonempty string")
    return value


def validate_source(source, repo):
    require_object(source, ["commit", "tree", "clean"], "source")
    if source["clean"] is not True:
        fail("input receipt does not describe a clean source checkout")
    for key in ("commit", "tree"):
        if not isinstance(source[key], str) or not HEX40_RE.fullmatch(source[key]):
            fail(f"input receipt source {key} is invalid")
    try:
        commit, tree = IDENTITY.source_state(repo)
    except IDENTITY.IdentityError as error:
        fail(str(error))
    if commit != source["commit"] or tree != source["tree"]:
        fail("input receipt source commit or tree does not match this repository")


def validate_dependencies(dependencies, repo):
    require_object(
        dependencies,
        ["packageResolvedSHA256", "verifiedFromCheckouts", "pins"],
        "dependencies",
    )
    if dependencies["verifiedFromCheckouts"] is not True:
        fail("input receipt does not record checkout-verified dependency revisions")
    if not isinstance(dependencies["packageResolvedSHA256"], str) \
            or not HEX64_RE.fullmatch(dependencies["packageResolvedSHA256"]):
        fail("input receipt Package.resolved digest is invalid")
    pins = dependencies["pins"]
    if not isinstance(pins, list):
        fail("input receipt dependency pins are malformed")
    resolved_bytes, local_pins = pinned_dependencies(repo)
    if sha256_bytes(resolved_bytes) != dependencies["packageResolvedSHA256"]:
        fail("input receipt Package.resolved digest does not match this repository")
    if pins != local_pins:
        fail("input receipt dependency revisions do not match Package.resolved")


def validate_toolchain_structure(toolchain):
    require_object(toolchain, TOOLCHAIN_KEYS, "toolchain")
    for key in TOOLCHAIN_KEYS:
        require_text(toolchain[key], f"toolchain {key}")
    if not SWIFT_VERSION_RE.fullmatch(toolchain["swiftVersion"]):
        fail("input receipt Swift version is malformed")
    if not XCODE_VERSION_RE.fullmatch(toolchain["xcodeVersion"]):
        fail("input receipt Xcode version is malformed")
    if not XCODE_BUILD_VERSION_RE.fullmatch(toolchain["xcodeBuildVersion"]):
        fail("input receipt Xcode build version is malformed")
    if not SDK_VERSION_RE.fullmatch(toolchain["sdkVersion"]):
        fail("input receipt SDK version is malformed")
    if toolchain["minimumOSVersion"] != MINIMUM_OS_VERSION:
        fail("input receipt minimum OS version is unsupported")


def validate_products(root, toolchain):
    expected_version = (toolchain["minimumOSVersion"], toolchain["sdkVersion"])
    for product in PRODUCTS:
        path = Path(root) / product
        if product_architectures(path) != [ARCHITECTURE]:
            fail(f"input product is not a thin {ARCHITECTURE} executable: {product}")
        if macho_build_version(path) != expected_version:
            fail(
                f"input product was not linked at macOS {expected_version[0]} "
                f"against the receipted SDK {expected_version[1]}: {product}"
            )


def validate_build(build, toolchain):
    require_object(
        build,
        ["products", "linkerArguments", "enhancedCandidate", "withoutSparkle"],
        "build",
    )
    if build["products"] != list(PRODUCTS):
        fail("input receipt build products are unsupported")
    if build["linkerArguments"] != linker_arguments(toolchain):
        fail("input receipt linker arguments are unsupported")
    if build["enhancedCandidate"] is not False or build["withoutSparkle"] is not False:
        fail("input receipt records a build graph or environment override")


def validate_frameworks(frameworks):
    if not isinstance(frameworks, list):
        fail("input receipt frameworks are malformed")
    paths = []
    for framework in frameworks:
        require_object(framework, ["path", "source", "identity"], "framework")
        path = safe_relative_path(framework["path"], "framework")
        if not path.endswith(".framework"):
            fail(f"input receipt framework path is unsupported: {path}")
        source = safe_relative_path(framework["source"], "framework source")
        if not source.startswith(".build/artifacts/"):
            fail(f"input receipt framework source is unsupported: {source}")
        require_text(framework["identity"], "framework identity")
        paths.append(path)
    if len(set(paths)) != len(paths):
        fail("input receipt repeats a framework path")
    return paths


def validate_inventory(root, inventory, framework_paths):
    root = Path(root).resolve()
    if not isinstance(inventory, list) or not inventory:
        fail("input receipt inventory is empty or malformed")
    entries = []
    seen = set()
    for entry in inventory:
        if not isinstance(entry, dict):
            fail("input receipt inventory entry is malformed")
        kind = entry.get("kind")
        if kind not in ("file", "symlink"):
            fail("input receipt inventory entry has an unsupported kind")
        keys = (
            ["path", "kind", "bytes", "mode", "sha256"]
            if kind == "file"
            else ["path", "kind", "target", "bytes", "mode", "sha256"]
        )
        if set(entry) != set(keys):
            fail("input receipt inventory entry has an unexpected shape")
        relative = safe_relative_path(entry["path"], "input")
        if relative in seen:
            fail(f"input receipt repeats an input path: {relative}")
        seen.add(relative)
        if relative == RECEIPT_NAME:
            fail("input receipt must not inventory itself")
        if relative not in PRODUCTS and not any(
            relative == framework or relative.startswith(framework + "/")
            for framework in framework_paths
        ):
            fail(f"input receipt contains an unexpected input: {relative}")
        candidate = resolve_within(root, relative, "input")
        try:
            details = candidate.lstat()
        except OSError as error:
            fail(f"input is missing or unreadable ({relative}): {error}")
        if not isinstance(entry["bytes"], int) or isinstance(entry["bytes"], bool) \
                or entry["bytes"] < 0:
            fail(f"input receipt byte count is invalid: {relative}")
        if not isinstance(entry["mode"], str) or not re.fullmatch(r"0[0-7]{3}", entry["mode"]):
            fail(f"input receipt mode is invalid: {relative}")
        if not isinstance(entry["sha256"], str) or not HEX64_RE.fullmatch(entry["sha256"]):
            fail(f"input receipt digest is invalid: {relative}")
        if kind == "file":
            if not candidate.is_file() or candidate.is_symlink():
                fail(f"input is missing or is not a regular file: {relative}")
            if details.st_size != entry["bytes"]:
                fail(f"input size does not match the receipt: {relative}")
            if mode_text(details.st_mode) != entry["mode"]:
                fail(f"input mode does not match the receipt: {relative}")
            if sha256_file(candidate) != entry["sha256"]:
                fail(f"input content does not match the receipt: {relative}")
        else:
            if not candidate.is_symlink():
                fail(f"input is missing or is not a symlink: {relative}")
            target = os.readlink(candidate)
            if target != entry["target"]:
                fail(f"input symlink target does not match the receipt: {relative}")
            if not isinstance(entry["target"], str) or not entry["target"] \
                    or entry["target"].startswith("/"):
                fail(f"input symlink target is unsupported: {relative}")
            resolve_within(root, posixpath.normpath(
                posixpath.join(posixpath.dirname(relative), entry["target"])
            ), "input symlink")
            encoded = target.encode("utf-8")
            if len(encoded) != entry["bytes"] or sha256_bytes(encoded) != entry["sha256"]:
                fail(f"input symlink identity does not match the receipt: {relative}")
        entries.append(entry)
    on_disk = [path for path in walk_payload(root) if path != RECEIPT_NAME]
    if on_disk != sorted(seen):
        fail("input directory does not contain exactly the receipted inputs")
    for product in PRODUCTS:
        entry = next((item for item in entries if item["path"] == product), None)
        if entry is None or entry["kind"] != "file":
            fail(f"input receipt is missing the {product} product")
        if not int(entry["mode"], 8) & 0o100:
            fail(f"input receipt product is not executable: {product}")
    return entries


def validate_receipt(receipt, repo, root):
    if not isinstance(receipt, dict):
        fail("input receipt must be a JSON object")
    claimed = ALLOCATED_IDENTITY_KEYS & set(receipt)
    if claimed:
        fail(
            "input receipt must not claim an allocated build identity: "
            + ", ".join(sorted(claimed))
        )
    if set(receipt) != RECEIPT_KEYS:
        fail("input receipt has an unexpected schema")
    if receipt["schemaVersion"] != SCHEMA_VERSION:
        fail("input receipt has an unsupported schema version")
    if receipt["status"] != RECEIPT_STATUS:
        fail("input receipt status is not compile-inputs-not-a-candidate")
    try:
        parsed = uuid.UUID(require_text(receipt["receiptID"], "receiptID"))
    except ValueError:
        fail("input receipt identifier is not a canonical UUID")
    if str(parsed) != receipt["receiptID"] or parsed.version != 4:
        fail("input receipt identifier is not a canonical UUID")
    created = require_text(receipt["createdAt"], "createdAt")
    try:
        dt.datetime.fromisoformat(created.replace("Z", "+00:00"))
    except ValueError:
        fail("input receipt creation time is not ISO-8601")
    try:
        version, _ = IDENTITY.product_version(Path(repo))
    except IDENTITY.IdentityError as error:
        fail(str(error))
    if receipt["productVersion"] != version:
        fail("input receipt product version does not match VERSION")
    if receipt["configuration"] != CONFIGURATION:
        fail("input receipt configuration is not Release")
    if receipt["architecture"] != ARCHITECTURE:
        fail(f"input receipt architecture is not {ARCHITECTURE}")
    validate_toolchain_structure(receipt["toolchain"])
    validate_build(receipt["build"], receipt["toolchain"])
    validate_source(receipt["source"], Path(repo))
    validate_dependencies(receipt["dependencies"], Path(repo))
    framework_paths = validate_frameworks(receipt["frameworks"])
    entries = validate_inventory(root, receipt["inventory"], framework_paths)
    validate_products(root, receipt["toolchain"])
    return entries, framework_paths


def stage_inputs(entries, root, staging):
    root = Path(root).resolve()
    staging = Path(staging)
    if os.path.lexists(staging):
        fail(f"staging directory must not already exist: {staging}")
    staging.mkdir(mode=0o755)
    for entry in entries:
        destination = staging / entry["path"]
        destination.parent.mkdir(parents=True, exist_ok=True)
        source = root / entry["path"]
        if entry["kind"] == "file":
            data = source.read_bytes()
            if sha256_bytes(data) != entry["sha256"]:
                fail(f"input changed while staging: {entry['path']}")
            with destination.open("xb") as handle:
                handle.write(data)
                handle.flush()
                os.fsync(handle.fileno())
            os.chmod(destination, int(entry["mode"], 8))
        else:
            os.symlink(entry["target"], destination)
    return staging


def command_verify(args):
    receipt_path = Path(args.receipt)
    if not receipt_path.is_absolute():
        fail("input receipt path must be absolute")
    if receipt_path.is_symlink() or not receipt_path.is_file() \
            or receipt_path.resolve() != receipt_path:
        fail("input receipt must be an existing canonical non-symlink file")
    if not HEX64_RE.fullmatch(args.receipt_sha256):
        fail("trusted input receipt digest must be 64 lowercase hexadecimal characters")
    try:
        data = receipt_path.read_bytes()
    except OSError as error:
        fail(f"could not read the input receipt: {error}")
    if sha256_bytes(data) != args.receipt_sha256:
        fail("input receipt does not match the supplied transfer digest")
    receipt = read_json_file(receipt_path, "input receipt")
    root = receipt_path.parent
    entries, framework_paths = validate_receipt(receipt, Path(args.repo), root)
    staging = stage_inputs(entries, root, Path(args.staging))
    validate_inventory(staging, entries, framework_paths)
    print(f"Verified compile inputs {receipt['receiptID']} for Fleck {receipt['productVersion']}")
    print(f"STAGED_INPUT_ROOT={staging}")
    for framework in receipt["frameworks"]:
        print(f"STAGED_FRAMEWORK={staging / framework['path']}")


def parser():
    result = argparse.ArgumentParser(
        description="Compile Fleck Release inputs for split-machine packaging"
    )
    sub = result.add_subparsers(dest="command", required=True)
    build = sub.add_parser("build")
    build.add_argument("--repo", required=True)
    build.add_argument("--output", required=True)
    verify = sub.add_parser("verify")
    verify.add_argument("--receipt", required=True)
    verify.add_argument("--receipt-sha256", required=True)
    verify.add_argument("--repo", required=True)
    verify.add_argument("--staging", required=True)
    return result


def main():
    args = parser().parse_args()
    try:
        if args.command == "build":
            command_build(args)
        else:
            command_verify(args)
    except (InputError, IDENTITY.IdentityError) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
