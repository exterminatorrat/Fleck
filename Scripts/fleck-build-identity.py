#!/usr/bin/env python3
import argparse
import datetime as dt
import hashlib
import json
import os
import plistlib
import re
import sqlite3
import subprocess
import sys
import uuid
from pathlib import Path


DEFAULT_ACCEPTED_ROOT = Path.home() / "Fleck-builds/accepted"
DEFAULT_DATABASE = Path.home() / "Fleck-builds/build-metadata/identities.sqlite3"
VERSION_RE = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$"
)
HEX40_RE = re.compile(r"^[0-9a-f]{40}$")
HEX64_RE = re.compile(r"^[0-9a-f]{64}$")


class IdentityError(Exception):
    pass


def fail(message):
    raise IdentityError(message)


def run(*args, cwd=None):
    result = subprocess.run(args, cwd=cwd, text=True, capture_output=True)
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        fail(f"command failed ({' '.join(map(str, args))}): {detail}")
    return result.stdout.strip()


def read_json(path, label):
    try:
        with Path(path).open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        fail(f"could not read {label}: {error}")


def atomic_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{uuid.uuid4()}.tmp")
    try:
        with temporary.open("x", encoding="utf-8") as handle:
            json.dump(value, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except OSError as error:
        temporary.unlink(missing_ok=True)
        fail(f"could not write capture: {error}")


def product_version(repo):
    try:
        value = (repo / "VERSION").read_text(encoding="utf-8").strip()
    except (OSError, UnicodeError) as error:
        fail(f"could not read VERSION: {error}")
    match = VERSION_RE.fullmatch(value)
    if not match:
        fail(f"VERSION is not a supported semantic version: {value!r}")
    prerelease = match.group(4)
    if prerelease:
        for part in prerelease.split("."):
            if part.isdigit() and len(part) > 1 and part.startswith("0"):
                fail(f"VERSION contains a zero-padded prerelease number: {value!r}")
    return value, ".".join(match.groups()[:3])


def load_baseline(repo):
    baseline = read_json(repo / "BuildBaseline.json", "BuildBaseline.json")
    required = {
        "schemaVersion",
        "canonicalManifestSHA256",
        "selectedRecordID",
        "acceptedSourceCommit",
        "acceptedSourceTree",
        "requiredRegistryStatus",
    }
    if set(baseline) != required or baseline["schemaVersion"] != 1:
        fail("BuildBaseline.json has an unsupported schema")
    if not HEX64_RE.fullmatch(baseline["canonicalManifestSHA256"]):
        fail("BuildBaseline.json has an invalid canonical manifest digest")
    if not HEX40_RE.fullmatch(baseline["acceptedSourceCommit"]):
        fail("BuildBaseline.json has an invalid accepted source commit")
    if not HEX40_RE.fullmatch(baseline["acceptedSourceTree"]):
        fail("BuildBaseline.json has an invalid accepted source tree")
    if baseline["requiredRegistryStatus"] != "active":
        fail("BuildBaseline.json must require an active registry")
    if not isinstance(baseline["selectedRecordID"], str) or not baseline["selectedRecordID"]:
        fail("BuildBaseline.json has an invalid selected record ID")
    return baseline


def source_state(repo, expected=None):
    repo = Path(repo).resolve()
    try:
        top = Path(run("git", "-C", repo, "rev-parse", "--show-toplevel")).resolve()
    except IdentityError:
        raise
    if top != repo:
        fail("repository path is not its owning Git worktree")
    index_entries = run("git", "-C", repo, "ls-files", "-v", "-z")
    hidden = []
    for entry in index_entries.split("\0"):
        if not entry:
            continue
        tag = entry[0]
        if tag == "S" or tag.islower():
            hidden.append(entry[2:])
    if hidden:
        fail(
            "source index contains assume-unchanged or skip-worktree paths: "
            + ", ".join(hidden)
        )
    status = run(
        "git", "-C", repo, "status", "--porcelain=v1", "--untracked-files=all",
        "--ignore-submodules=none"
    )
    if status:
        fail("source worktree is dirty; packaging requires exclusive clean-source ownership")
    commit = run("git", "-C", repo, "rev-parse", "HEAD^{commit}")
    tree = run("git", "-C", repo, "rev-parse", "HEAD^{tree}")
    if not HEX40_RE.fullmatch(commit) or not HEX40_RE.fullmatch(tree):
        fail("could not capture full source commit and tree")
    if expected and (commit != expected["sourceCommit"] or tree != expected["sourceTree"]):
        fail("source commit or tree changed during packaging")
    return commit, tree


def registry_state(repo, accepted_root, baseline):
    repo = Path(repo).resolve()
    accepted_root = Path(accepted_root).resolve()
    manifest_path = accepted_root / "manifest.json"
    sidecar_path = accepted_root / "manifest.sha256"
    validator = accepted_root / "check-accepted-build.py"
    try:
        manifest_bytes = manifest_path.read_bytes()
        sidecar = sidecar_path.read_text(encoding="utf-8").split()
    except (OSError, UnicodeError) as error:
        fail(f"canonical accepted registry is missing or unreadable: {error}")
    digest = hashlib.sha256(manifest_bytes).hexdigest()
    if not sidecar or sidecar[0] != digest:
        fail("canonical accepted registry sidecar does not match manifest.json")
    if digest != baseline["canonicalManifestSHA256"]:
        fail("canonical accepted registry changed from the pinned manifest")
    try:
        manifest = json.loads(manifest_bytes)
    except (UnicodeError, json.JSONDecodeError) as error:
        fail(f"canonical accepted registry is malformed: {error}")
    if manifest.get("registryStatus") != baseline["requiredRegistryStatus"]:
        fail("canonical accepted registry is not active")
    if manifest.get("latestAcceptedRecordID") != baseline["selectedRecordID"]:
        fail("canonical accepted registry selected record does not match the pin")
    records = manifest.get("records")
    if not isinstance(records, list):
        fail("canonical accepted registry records are malformed")
    record = next((item for item in records if item.get("id") == baseline["selectedRecordID"]), None)
    if not isinstance(record, dict):
        fail("pinned accepted record is missing")
    source = record.get("source")
    if not isinstance(source, dict) or source.get("commit") != baseline["acceptedSourceCommit"] \
            or source.get("tree") != baseline["acceptedSourceTree"]:
        fail("pinned accepted record source does not match BuildBaseline.json")
    support_files = manifest.get("supportFiles")
    if not isinstance(support_files, list):
        fail("canonical accepted registry support files are malformed")
    validator_records = [
        item for item in support_files
        if isinstance(item, dict) and item.get("relativePath") == "check-accepted-build.py"
    ]
    if len(validator_records) != 1:
        fail("canonical accepted registry must authenticate exactly one preserved validator")
    validator_record = validator_records[0]
    expected_size = validator_record.get("size")
    expected_digest = validator_record.get("sha256")
    if not isinstance(expected_size, int) or isinstance(expected_size, bool) or expected_size < 1 \
            or not isinstance(expected_digest, str) or not HEX64_RE.fullmatch(expected_digest):
        fail("canonical accepted registry validator authentication is malformed")
    if not validator.is_file() or validator.is_symlink():
        fail("preserved accepted-build validator is missing or unsafe")
    try:
        validator_bytes = validator.read_bytes()
    except OSError as error:
        fail(f"preserved accepted-build validator is unreadable: {error}")
    if len(validator_bytes) != expected_size \
            or hashlib.sha256(validator_bytes).hexdigest() != expected_digest:
        fail("preserved accepted-build validator does not match its authenticated support record")
    result = subprocess.run(
        [
            sys.executable, "-", str(manifest_path),
            "--artifact-root", str(accepted_root),
            "--repo", str(repo),
            "--repo-mode", "reachable",
        ],
        input=validator_bytes,
        capture_output=True,
    )
    if result.returncode:
        detail = (result.stderr or result.stdout).decode("utf-8", errors="replace").strip()
        fail(f"authenticated accepted-build validator failed: {detail}")
    return {
        "baselineManifestSHA256": digest,
        "baselineRecordID": baseline["selectedRecordID"],
        "baselineRegistryStatus": manifest["registryStatus"],
    }


def bundle_version(number):
    if number < 1:
        fail("build number must be at least 1")
    first = 1 + (number - 1) // 10000
    if first > 9999:
        fail("build number exceeds the four-digit first CFBundleVersion component")
    return f"{first}.{((number - 1) // 100) % 100}.{(number - 1) % 100}"


def allocate(database, data):
    database = Path(database)
    try:
        database.parent.mkdir(parents=True, exist_ok=True)
        connection = sqlite3.connect(database, timeout=30, isolation_level=None)
        try:
            connection.execute("PRAGMA busy_timeout=30000")
            connection.execute("PRAGMA synchronous=FULL")
            connection.execute("BEGIN IMMEDIATE")
            connection.execute(
                "CREATE TABLE IF NOT EXISTS build_identities ("
                "number INTEGER PRIMARY KEY AUTOINCREMENT, build_id TEXT NOT NULL UNIQUE, "
                "began_at TEXT NOT NULL, source_commit TEXT NOT NULL, source_tree TEXT NOT NULL, "
                "product_version TEXT NOT NULL, flavor TEXT NOT NULL, configuration TEXT NOT NULL)"
            )
            build_id = str(uuid.uuid4())
            cursor = connection.execute(
                "INSERT INTO build_identities "
                "(build_id, began_at, source_commit, source_tree, product_version, flavor, configuration) "
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
                (
                    build_id, data["buildDate"], data["sourceCommit"], data["sourceTree"],
                    data["productVersion"], data["flavor"], data["configuration"],
                ),
            )
            number = cursor.lastrowid
            bundle_version(number)
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()
    except (OSError, sqlite3.Error) as error:
        fail(f"build identity allocator is corrupt or unwritable: {error}")
    return number, build_id


def guard_path(repo):
    return repo / ".build" / ".fleck-packaging-operation.lock"


def acquire_guard(repo, flavor, nested_token):
    lock = guard_path(repo)
    lock.parent.mkdir(parents=True, exist_ok=True)
    if nested_token:
        owner = read_json(lock / "owner.json", "packaging operation guard")
        if owner.get("token") != nested_token or owner.get("flavor") != "corrected" \
                or flavor != "parakeet":
            fail("invalid nested corrected-to-Parakeet packaging handoff")
        return nested_token, False
    token = str(uuid.uuid4())
    try:
        lock.mkdir()
        with (lock / "owner.json").open("x", encoding="utf-8") as handle:
            json.dump({"token": token, "flavor": flavor, "pid": os.getpid()}, handle)
            handle.write("\n")
    except FileExistsError:
        fail(f"another packaging operation owns this worktree build root: {lock}")
    except OSError as error:
        try:
            lock.rmdir()
        except OSError:
            pass
        fail(f"could not acquire packaging operation guard: {error}")
    return token, True


def release_guard(capture):
    if not capture.get("ownsGuard"):
        return
    lock = Path(capture["guardPath"])
    owner_path = lock / "owner.json"
    owner = read_json(owner_path, "packaging operation guard")
    if owner.get("token") != capture.get("guardToken"):
        fail("refusing to release a packaging operation guard owned by another process")
    try:
        owner_path.unlink()
        lock.rmdir()
    except OSError as error:
        fail(f"could not release packaging operation guard: {error}")


def load_capture(path):
    capture = read_json(path, "build identity capture")
    if capture.get("schemaVersion") != 1:
        fail("build identity capture has an unsupported schema")
    return capture


def artifact_name(capture):
    version = capture.get("productVersion")
    number = capture.get("buildNumber")
    if not isinstance(version, str) or not VERSION_RE.fullmatch(version) \
            or not isinstance(number, int) or number < 1:
        fail("build identity capture cannot produce an artifact name")
    return f"Fleck {version} Build {number}"


def plist_values(capture):
    name = artifact_name(capture)
    values = {
        "CFBundleDisplayName": name,
        "CFBundleName": name,
        "CFBundleShortVersionString": capture["numericProductVersion"],
        "CFBundleVersion": capture["bundleVersion"],
        "FleckVersion": capture["productVersion"],
        "FleckBuildNumber": str(capture["buildNumber"]),
        "FleckBuildID": capture["buildID"],
        "FleckBuildDate": capture["buildDate"],
        "FleckSourceCommit": capture["sourceCommit"],
        "FleckSourceTree": capture["sourceTree"],
        "FleckBuildFlavor": capture["flavor"],
        "FleckBuildConfiguration": capture["configuration"],
        "FleckBuildLabel": name,
        "FleckCandidateStatus": capture["candidateStatus"],
        "FleckBaselineManifestSHA256": capture["baselineManifestSHA256"],
        "FleckBaselineRecordID": capture["baselineRecordID"],
        "FleckBaselineRegistryStatus": capture["baselineRegistryStatus"],
    }
    if capture.get("inputBuildID"):
        values["FleckInputBuildID"] = capture["inputBuildID"]
    if capture.get("inputManifestSHA256"):
        values["FleckInputManifestSHA256"] = capture["inputManifestSHA256"]
    return values


def read_plist(path):
    try:
        with Path(path).open("rb") as handle:
            return plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as error:
        fail(f"could not read bundle plist: {error}")


def write_plist(path, value):
    try:
        with Path(path).open("wb") as handle:
            plistlib.dump(value, handle, fmt=plistlib.FMT_XML, sort_keys=False)
    except OSError as error:
        fail(f"could not stamp bundle plist: {error}")


def verify_plist(capture, path, source_only=False):
    actual = read_plist(path)
    expected = plist_values(capture)
    if source_only:
        keys = [
            "CFBundleShortVersionString", "FleckVersion", "FleckSourceCommit", "FleckSourceTree",
            "FleckBaselineManifestSHA256", "FleckBaselineRecordID", "FleckBaselineRegistryStatus",
        ]
    else:
        keys = list(expected)
    for key in keys:
        if actual.get(key) != expected[key]:
            fail(f"bundle plist {key} does not match captured build identity")
    if source_only:
        identity_keys = [
            "FleckBuildNumber", "CFBundleVersion", "FleckBuildID", "FleckBuildDate",
            "FleckBuildFlavor", "FleckBuildConfiguration", "FleckCandidateStatus",
        ]
        if any(not isinstance(actual.get(key), str) or not actual[key] for key in identity_keys):
            fail("input bundle plist has an incomplete packaged build identity")
        if not actual["FleckBuildNumber"].isdigit() or not re.fullmatch(
            r"[1-9][0-9]{0,3}\.[0-9]{1,2}\.[0-9]{1,2}", actual["CFBundleVersion"]
        ):
            fail("input bundle plist has malformed numeric build metadata")
        try:
            parsed = uuid.UUID(actual["FleckBuildID"])
        except ValueError:
            fail("input bundle plist FleckBuildID is not a canonical UUID")
        if str(parsed) != actual["FleckBuildID"]:
            fail("input bundle plist FleckBuildID is not a canonical UUID")
    else:
        try:
            uuid.UUID(actual["FleckBuildID"])
        except (KeyError, ValueError, AttributeError):
            fail("bundle plist FleckBuildID is not a canonical UUID")
    return actual


def check_repo(repo):
    version, _ = product_version(repo)
    baseline = load_baseline(repo)
    try:
        changelog = (repo / "CHANGELOG.md").read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        fail(f"could not read CHANGELOG.md: {error}")
    if not re.search(rf"^## \[{re.escape(version)}\] - \d{{4}}-\d{{2}}-\d{{2}}$", changelog, re.M):
        fail("CHANGELOG.md has no dated heading matching VERSION")
    scripts = {
        "Scripts/build-fleck-app.sh": ("begin", "stamp", "finish", "release"),
        "Scripts/build-parakeet-test-app.sh": ("begin", "stamp", "finish", "release"),
        "Scripts/build-pre-astra-corrected-build.sh": (
            "begin", "verify --source-only", "augment", "stamp", "finish", "release"
        ),
    }
    for relative, hooks in scripts.items():
        try:
            source = (repo / relative).read_text(encoding="utf-8")
        except (OSError, UnicodeError) as error:
            fail(f"could not read {relative}: {error}")
        if '"$identity_tool" release' not in source:
            fail(f"{relative} is missing build-identity release cleanup")
        cursor = 0
        for hook in (hook for hook in hooks if hook != "release"):
            marker = f"$identity_tool\" {hook}"
            index = source.find(marker, cursor)
            if index < 0:
                fail(f"{relative} is missing ordered build-identity hook: {hook}")
            cursor = index + len(marker)
        stamp_index = source.find('$identity_tool" stamp')
        if relative == "Scripts/build-fleck-app.sh":
            if not source.find("swift build") < stamp_index < source.find("codesign --force"):
                fail("build-fleck-app.sh must stamp after compilation and before signing")
        elif relative == "Scripts/build-parakeet-test-app.sh":
            comparison_index = source.find('for exact_pair in')
            signing_index = source.find('readonly designated_requirement=')
            if not comparison_index < stamp_index < signing_index:
                fail("Parakeet packaging must stamp after source comparisons and before signing")
        else:
            builder_index = source.find('FLECK_BUILD_IDENTITY_NESTED_TOKEN=')
            finish_index = source.find('$identity_tool" finish')
            publication_index = source.find("renamex_np(")
            if not source.find('$identity_tool" begin') < builder_index < stamp_index \
                    < finish_index < publication_index:
                fail("corrected packaging identity hooks are not ordered around build and publication")
    return version, baseline


def test_injection(args, repo):
    accepted_value = getattr(args, "test_accepted_root", None)
    database_value = getattr(args, "test_database", None)
    if not accepted_value and not database_value:
        return None
    if not accepted_value or not database_value:
        fail("test accepted root and test database must be injected together")
    if os.environ.get("FLECK_BUILD_IDENTITY_TEST_FIXTURE") != "1":
        fail("build identity fixture injection requires its explicit test environment")
    marker = repo / ".fleck-build-identity-test-fixture"
    try:
        marker_value = marker.read_text(encoding="utf-8").strip()
    except (OSError, UnicodeError) as error:
        fail(f"build identity fixture marker is missing: {error}")
    if marker_value != "fleck-build-identity-test-fixture-v1":
        fail("build identity fixture marker is invalid")
    run("git", "-C", repo, "ls-files", "--error-unmatch", marker.relative_to(repo))
    fixture_root = (repo / ".identity-test").resolve()
    accepted_root = Path(accepted_value).resolve()
    database = Path(database_value).resolve()
    if accepted_root != fixture_root / "accepted" or fixture_root not in database.parents:
        fail("test build identity state must stay below the fixture's .identity-test directory")
    return accepted_root, database


def command_begin(args):
    repo = Path(args.repo).resolve()
    capture_path = Path(args.capture).resolve()
    token = None
    owns_guard = False
    try:
        token, owns_guard = acquire_guard(repo, args.flavor, args.nested_token)
        version, numeric = product_version(repo)
        baseline = load_baseline(repo)
        commit, tree = source_state(repo)
        run("git", "-C", repo, "merge-base", "--is-ancestor", baseline["acceptedSourceCommit"], commit)
        injected = test_injection(args, repo)
        if args.mode == "ci-unverified":
            if injected:
                fail("test accepted-registry injection is unavailable in ci-unverified mode")
            if args.flavor == "corrected":
                fail("corrected handoff packaging is forbidden in ci-unverified mode")
            if os.environ.get("CI") != "true" or os.environ.get("GITHUB_ACTIONS") != "true":
                fail("ci-unverified mode requires the hosted CI environment")
            registry = {
                "baselineManifestSHA256": baseline["canonicalManifestSHA256"],
                "baselineRecordID": baseline["selectedRecordID"],
                "baselineRegistryStatus": "ci-unverified",
            }
            status = "CI unverified - not a handoff candidate"
            database = repo / ".build/build-metadata/ci-identities.sqlite3"
        else:
            accepted_root, database = injected or (DEFAULT_ACCEPTED_ROOT, DEFAULT_DATABASE)
            registry = registry_state(repo, accepted_root, baseline)
            status = (
                "Test fixture - not a handoff candidate"
                if injected else "Candidate - not accepted"
            )
        data = {
            "schemaVersion": 1,
            "productVersion": version,
            "numericProductVersion": numeric,
            "buildDate": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
            "sourceCommit": commit,
            "sourceTree": tree,
            "flavor": args.flavor,
            "configuration": args.configuration,
            "candidateStatus": status,
            **registry,
        }
        number, build_id = allocate(database, data)
        data.update({
            "buildNumber": number,
            "bundleVersion": bundle_version(number),
            "buildID": build_id,
            "mode": args.mode,
            "acceptedRoot": str(accepted_root if args.mode == "local" else DEFAULT_ACCEPTED_ROOT),
            "guardPath": str(guard_path(repo)),
            "guardToken": token,
            "ownsGuard": owns_guard,
            "repo": str(repo),
        })
        atomic_json(capture_path, data)
    except Exception:
        if owns_guard and token:
            try:
                release_guard({
                    "ownsGuard": True,
                    "guardPath": str(guard_path(repo)),
                    "guardToken": token,
                })
            except Exception:
                pass
        raise


def command_augment(args):
    capture = load_capture(args.capture)
    try:
        parsed = uuid.UUID(args.input_build_id)
    except ValueError:
        fail("input build ID is not a canonical UUID")
    if str(parsed) != args.input_build_id.lower() or not HEX64_RE.fullmatch(args.input_manifest_sha256):
        fail("input build identity or manifest digest is malformed")
    capture["inputBuildID"] = str(parsed)
    capture["inputManifestSHA256"] = args.input_manifest_sha256
    atomic_json(args.capture, capture)


def command_finish(args):
    capture = load_capture(args.capture)
    repo = Path(capture["repo"])
    source_state(repo, capture)
    if capture["mode"] == "local":
        baseline = load_baseline(repo)
        current = registry_state(repo, Path(capture["acceptedRoot"]), baseline)
        for key, value in current.items():
            if capture.get(key) != value:
                fail("accepted registry changed during packaging")
    verify_plist(capture, args.plist)


def validate_result_path(repo, value):
    repo = Path(repo).resolve()
    build_root = repo / ".build"
    result = Path(value)
    if not result.is_absolute():
        fail("result file path must be absolute")
    try:
        result.relative_to(build_root)
    except ValueError:
        fail("result file must be inside the owning worktree .build directory")
    if result == build_root:
        fail("result file must be below the owning worktree .build directory")
    current = result.parent
    while True:
        if not current.exists() or current.is_symlink() or not current.is_dir() \
                or current.resolve() != current:
            fail("result file parent must be an existing canonical non-symlink directory")
        if current == build_root:
            break
        if build_root not in current.parents:
            fail("result file must be inside the owning worktree .build directory")
        current = current.parent
    if os.path.lexists(result):
        fail("result file destination must not already exist")
    return result


def read_result(repo_value, result_value, flavor):
    repo = Path(repo_value).resolve()
    build_root = repo / ".build"
    result = Path(result_value)
    if not result.is_absolute():
        fail("result file path must be absolute")
    try:
        result.relative_to(build_root)
    except ValueError:
        fail("result file must be inside the owning worktree .build directory")
    if result.is_symlink() or not result.is_file() or result.resolve() != result:
        fail("result file must be an existing canonical non-symlink file")
    try:
        value = json.loads(result.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail("build result is not valid JSON")
    if not isinstance(value, dict) or set(value) != {"appPath", "buildID"} \
            or not all(isinstance(value[key], str) and value[key] for key in value):
        fail("build result must contain exactly nonempty appPath and buildID strings")
    try:
        parsed_build_id = uuid.UUID(value["buildID"])
    except ValueError:
        fail("build result contains an invalid build ID")
    if str(parsed_build_id) != value["buildID"]:
        fail("build result contains a noncanonical build ID")
    app = Path(value["appPath"])
    if not app.is_absolute() or app.is_symlink() or not app.is_dir() or app.resolve() != app:
        fail("build result app must be an absolute canonical non-symlink directory")
    expected_parent = build_root if flavor == "development" else build_root / "parakeet-test"
    if app.parent != expected_parent:
        fail(f"build result app is outside the {flavor} publication root")
    plist = read_plist(app / "Contents/Info.plist")
    version = plist.get("FleckVersion")
    number = plist.get("FleckBuildNumber")
    if not isinstance(version, str) or not VERSION_RE.fullmatch(version) \
            or not isinstance(number, str) or not re.fullmatch(r"[1-9][0-9]*", number):
        fail("build result app has invalid version or build metadata")
    name = f"Fleck {version} Build {number}"
    if app.name != name + ".app" \
            or plist.get("CFBundleName") != name \
            or plist.get("CFBundleDisplayName") != name \
            or plist.get("FleckBuildLabel") != name \
            or plist.get("FleckBuildFlavor") != flavor:
        fail("build result app name and metadata do not agree")
    if plist.get("FleckBuildID") != value["buildID"]:
        fail("build result build ID does not match the app plist")
    return app


def remove_owned_result(repo_value, result_value, identity):
    repo = Path(repo_value).resolve()
    build_root = repo / ".build"
    result = Path(result_value)
    if not re.fullmatch(r"[0-9]+:[0-9]+", identity):
        fail("build result ownership identity is invalid")
    if not result.is_absolute():
        fail("result file path must be absolute")
    try:
        result.relative_to(build_root)
    except ValueError:
        fail("result file must be inside the owning worktree .build directory")
    expected = tuple(int(value) for value in identity.split(":"))
    if not os.path.lexists(result):
        return
    if result.is_symlink() or not result.is_file() or result.resolve() != result:
        fail("refusing to remove an unsafe build result")
    current = result.lstat()
    if (current.st_dev, current.st_ino) != expected:
        fail("refusing to remove a substituted build result")
    result.unlink()
    directory = os.open(result.parent, os.O_RDONLY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)


def write_result(capture, app_value, result_value):
    repo = Path(capture["repo"]).resolve()
    result = validate_result_path(repo, result_value)
    app = Path(app_value)
    if not app.is_absolute() or app.is_symlink() or not app.is_dir() or app.resolve() != app:
        fail("published app path must be an absolute canonical non-symlink directory")
    try:
        app.relative_to(repo / ".build")
    except ValueError:
        fail("published app path must be inside the owning worktree .build directory")
    if app.name != artifact_name(capture) + ".app":
        fail("published app name does not match captured build identity")
    verify_plist(capture, app / "Contents/Info.plist")
    payload = {"appPath": str(app), "buildID": capture["buildID"]}
    temporary = result.parent / f".{result.name}.{uuid.uuid4()}.tmp"
    published = False
    created_identity = None
    try:
        with temporary.open("x", encoding="utf-8") as handle:
            json.dump(payload, handle, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        created = temporary.stat()
        created_identity = (created.st_dev, created.st_ino)
        os.link(temporary, result)
        published = True
        temporary.unlink()
        directory = os.open(result.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
        return f"{created_identity[0]}:{created_identity[1]}"
    except OSError as error:
        if published and created_identity:
            try:
                current = result.lstat()
                if not result.is_symlink() \
                        and (current.st_dev, current.st_ino) == created_identity:
                    result.unlink()
            except OSError:
                pass
        temporary.unlink(missing_ok=True)
        fail(f"could not write immutable build result: {error}")


def info_text(capture, bundle_identifier):
    fields = [
        ("Product version", capture["productVersion"]),
        ("Build number", str(capture["buildNumber"])),
        ("Bundle version", capture["bundleVersion"]),
        ("Build ID", capture["buildID"]),
        ("Build date (UTC)", capture["buildDate"]),
        ("Source commit", capture["sourceCommit"]),
        ("Source tree", capture["sourceTree"]),
        ("Flavor", capture["flavor"]),
        ("Configuration", capture["configuration"]),
        ("Candidate status", capture["candidateStatus"]),
        ("Baseline manifest SHA-256", capture["baselineManifestSHA256"]),
        ("Baseline record", capture["baselineRecordID"]),
        ("Baseline registry status", capture["baselineRegistryStatus"]),
    ]
    if capture.get("inputBuildID"):
        fields.append(("Input build ID", capture["inputBuildID"]))
    if capture.get("inputManifestSHA256"):
        fields.append(("Input app manifest SHA-256", capture["inputManifestSHA256"]))
    fields.append(("Bundle identifier", bundle_identifier))
    return "\n".join(f"{label}: {value}" for label, value in fields)


def parser():
    result = argparse.ArgumentParser(description="Allocate and verify Fleck package identities")
    sub = result.add_subparsers(dest="command", required=True)
    check = sub.add_parser("check")
    check.add_argument("--repo", default=Path(__file__).resolve().parent.parent)
    begin = sub.add_parser("begin")
    begin.add_argument("--repo", required=True)
    begin.add_argument("--flavor", required=True, choices=("development", "parakeet", "corrected"))
    begin.add_argument("--configuration", required=True)
    begin.add_argument("--capture", required=True)
    begin.add_argument("--mode", choices=("local", "ci-unverified"), default="local")
    begin.add_argument("--test-accepted-root")
    begin.add_argument("--test-database")
    begin.add_argument("--nested-token")
    stamp = sub.add_parser("stamp")
    stamp.add_argument("--capture", required=True)
    stamp.add_argument("--plist", required=True)
    verify = sub.add_parser("verify")
    verify.add_argument("--capture", required=True)
    verify.add_argument("--plist", required=True)
    verify.add_argument("--source-only", action="store_true")
    finish = sub.add_parser("finish")
    finish.add_argument("--capture", required=True)
    finish.add_argument("--plist", required=True)
    augment = sub.add_parser("augment")
    augment.add_argument("--capture", required=True)
    augment.add_argument("--input-build-id", required=True)
    augment.add_argument("--input-manifest-sha256", required=True)
    release = sub.add_parser("release")
    release.add_argument("--capture", required=True)
    field = sub.add_parser("field")
    field.add_argument("--capture", required=True)
    field.add_argument("name")
    info = sub.add_parser("info")
    info.add_argument("--capture", required=True)
    info.add_argument("--bundle-identifier", required=True)
    name = sub.add_parser("name")
    name.add_argument("--capture", required=True)
    result_path = sub.add_parser("validate-result-path")
    result_path.add_argument("--repo", required=True)
    result_path.add_argument("--result-file", required=True)
    write = sub.add_parser("write-result")
    write.add_argument("--capture", required=True)
    write.add_argument("--app", required=True)
    write.add_argument("--result-file", required=True)
    read = sub.add_parser("read-result")
    read.add_argument("--repo", required=True)
    read.add_argument("--result-file", required=True)
    read.add_argument("--flavor", required=True, choices=("development", "parakeet"))
    remove = sub.add_parser("remove-owned-result")
    remove.add_argument("--repo", required=True)
    remove.add_argument("--result-file", required=True)
    remove.add_argument("--identity", required=True)
    return result


def main():
    args = parser().parse_args()
    if args.command == "check":
        version, baseline = check_repo(Path(args.repo).resolve())
        print(f"VERSION={version}")
        print(f"BASELINE_MANIFEST_SHA256={baseline['canonicalManifestSHA256']}")
    elif args.command == "begin":
        command_begin(args)
    elif args.command == "stamp":
        capture = load_capture(args.capture)
        plist = read_plist(args.plist)
        plist.update(plist_values(capture))
        write_plist(args.plist, plist)
        verify_plist(capture, args.plist)
    elif args.command == "verify":
        verify_plist(load_capture(args.capture), args.plist, args.source_only)
    elif args.command == "finish":
        command_finish(args)
    elif args.command == "augment":
        command_augment(args)
    elif args.command == "release":
        release_guard(load_capture(args.capture))
    elif args.command == "field":
        capture = load_capture(args.capture)
        if args.name not in capture:
            fail(f"capture field is absent: {args.name}")
        print(capture[args.name])
    elif args.command == "info":
        print(info_text(load_capture(args.capture), args.bundle_identifier))
    elif args.command == "name":
        print(artifact_name(load_capture(args.capture)))
    elif args.command == "validate-result-path":
        validate_result_path(args.repo, args.result_file)
    elif args.command == "write-result":
        print(write_result(load_capture(args.capture), args.app, args.result_file))
    elif args.command == "read-result":
        print(read_result(args.repo, args.result_file, args.flavor))
    elif args.command == "remove-owned-result":
        remove_owned_result(args.repo, args.result_file, args.identity)


if __name__ == "__main__":
    try:
        main()
    except IdentityError as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
