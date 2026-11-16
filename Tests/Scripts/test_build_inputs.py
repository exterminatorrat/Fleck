import contextlib
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
import uuid
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.dont_write_bytecode = True

TOOLCHAIN = {
    "swiftVersion": "Swift version 6.0.3 (swift-6.0.3-RELEASE)",
    "xcodeVersion": "Xcode 26.0",
    "xcodeBuildVersion": "26A335",
    "sdkVersion": "26.0",
    "minimumOSVersion": "14.0",
}

PRODUCER_TOOLCHAIN = {
    "swiftVersion": "Swift version 6.4.2 (swift-6.4.2-RELEASE)",
    "xcodeVersion": "Xcode 27.2",
    "xcodeBuildVersion": "27B52",
    "sdkVersion": "27.2",
    "minimumOSVersion": "14.0",
}


def load_inputs():
    spec = importlib.util.spec_from_file_location(
        "fleck_build_inputs", ROOT / "Scripts/fleck-build-inputs.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


inputs = load_inputs()


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def linked_version(toolchain=TOOLCHAIN):
    return (toolchain["minimumOSVersion"], toolchain["sdkVersion"])


def build_patches(fixture):
    return (
        mock.patch.object(inputs, "toolchain_state", return_value=dict(TOOLCHAIN)),
        mock.patch.object(
            inputs, "compile_products", side_effect=fixture.fabricate_products
        ),
        mock.patch.object(inputs, "product_architectures", return_value=["arm64"]),
        mock.patch.object(inputs, "macho_build_version", return_value=linked_version()),
        mock.patch.object(inputs, "linked_libraries", return_value=""),
    )


class CompileInputFixture:
    def __init__(self, root):
        self.root = Path(root).resolve()
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.git("init", "-q")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "user.name", "Fleck compile input fixture")
        (self.repo / "VERSION").write_text("1.8.14-beta.1\n", encoding="utf-8")
        (self.repo / ".gitignore").write_text(".build/\n", encoding="utf-8")
        self.checkouts = self.make_checkouts()
        self.write_resolved()
        self.git("add", ".")
        self.git("commit", "-qm", "Compile input fixture")
        self.output = self.root / "inputs"

    def git(self, *arguments, cwd=None):
        subprocess.run(
            ["git", "-C", str(cwd or self.repo), *arguments],
            check=True,
            capture_output=True,
            text=True,
        )

    def revision(self, path):
        return subprocess.run(
            ["git", "-C", str(path), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

    def make_checkouts(self):
        checkouts = {}
        for name, url in (
            ("eventsource", "https://github.com/mattt/eventsource.git"),
            ("swift-log", "https://github.com/apple/swift-log.git"),
        ):
            path = self.repo / ".build/checkouts" / name
            path.mkdir(parents=True)
            (path / "Package.swift").write_text(
                "// swift-tools-version:6.0\n", encoding="utf-8"
            )
            self.git("init", "-q", cwd=path)
            self.git("config", "user.email", "fixture@example.invalid", cwd=path)
            self.git("config", "user.name", "Fleck compile input fixture", cwd=path)
            self.git("remote", "add", "origin", url, cwd=path)
            self.git("add", ".", cwd=path)
            self.git("commit", "-qm", name, cwd=path)
            checkouts[name] = {"url": url, "revision": self.revision(path)}
        return checkouts

    def pins(self):
        return [
            {
                "identity": name,
                "kind": "remoteSourceControl",
                "location": data["url"],
                "state": {"revision": data["revision"], "version": "1.0.0"},
            }
            for name, data in sorted(self.checkouts.items())
        ]

    def write_resolved(self, pins=None):
        (self.repo / "Package.resolved").write_text(
            json.dumps(
                {
                    "originHash": "0" * 64,
                    "pins": self.pins() if pins is None else pins,
                    "version": 3,
                },
                indent=2,
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )

    def fabricate_products(self, repo, toolchain):
        release = Path(repo) / ".build/release"
        release.mkdir(parents=True, exist_ok=True)
        for product in inputs.PRODUCTS:
            binary = release / product
            binary.write_bytes(f"fixture {product} binary\n".encode())
            binary.chmod(0o755)

    def build(self):
        with contextlib.ExitStack() as stack:
            for patch in build_patches(self):
                stack.enter_context(patch)
            inputs.command_build(
                SimpleNamespace(repo=str(self.repo), output=str(self.output))
            )

    def inventory(self):
        return [
            entry
            for entry in inputs.build_inventory(self.output)
            if entry["path"] != inputs.RECEIPT_NAME
        ]

    def receipt_path(self):
        return self.output / inputs.RECEIPT_NAME

    def receipt(self):
        return json.loads(self.receipt_path().read_bytes())

    def rewrite(self, mutate):
        receipt = self.receipt()
        mutate(receipt)
        path = self.receipt_path()
        path.chmod(0o644)
        path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        path.chmod(0o444)
        return digest(path)

    def verify(
        self, sha=None, staging=None, receipt_path=None,
        architectures=None, build_version=None,
    ):
        path = Path(receipt_path or self.receipt_path())
        staging = Path(staging or self.root / "staging")
        with mock.patch.object(
            inputs, "product_architectures", return_value=list(architectures or ["arm64"])
        ), mock.patch.object(
            inputs, "macho_build_version", return_value=build_version or linked_version()
        ):
            inputs.command_verify(
                SimpleNamespace(
                    receipt=str(path),
                    receipt_sha256=sha or digest(path),
                    repo=str(self.repo),
                    staging=str(staging),
                )
            )
        return staging

    def add_framework(self, link_target="Versions/Current/Sparkle"):
        framework = self.output / "Sparkle.framework"
        framework.mkdir()
        (framework / "Versions/B").mkdir(parents=True)
        (framework / "Versions/B/Sparkle").write_bytes(b"fixture sparkle binary\n")
        os.symlink("B", framework / "Versions/Current")
        os.symlink(link_target, framework / "Sparkle")
        return framework

    def producer_toolchain_receipt(self):
        toolchain = dict(PRODUCER_TOOLCHAIN)
        return self.rewrite(
            lambda receipt: (
                receipt.__setitem__("toolchain", toolchain),
                receipt["build"].__setitem__(
                    "linkerArguments", inputs.linker_arguments(toolchain)
                ),
            )
        )

    def signed_framework_receipt(self):
        self.add_framework()
        return self.rewrite(
            lambda receipt: (
                receipt.__setitem__(
                    "frameworks",
                    [
                        {
                            "path": "Sparkle.framework",
                            "source": inputs.SPARKLE_FRAMEWORK,
                            "identity": "sparkle",
                        }
                    ],
                ),
                receipt.__setitem__("inventory", self.inventory()),
            )
        )


class CompileInputTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="fleck-compile-inputs-")
        self.fixture = CompileInputFixture(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()

    def test_build_writes_immutable_receipt_without_claiming_an_identity(self):
        self.fixture.build()
        path = self.fixture.receipt_path()
        self.assertTrue(path.is_file())
        self.assertEqual(path.stat().st_mode & 0o777, 0o444)
        receipt = self.fixture.receipt()
        self.assertEqual(set(receipt), inputs.RECEIPT_KEYS)
        self.assertEqual(receipt["status"], inputs.RECEIPT_STATUS)
        self.assertEqual(receipt["configuration"], "Release")
        self.assertEqual(receipt["architecture"], "arm64")
        self.assertEqual(receipt["build"]["products"], inputs.PRODUCTS)
        self.assertFalse(receipt["build"]["enhancedCandidate"])
        self.assertFalse(receipt["build"]["withoutSparkle"])
        self.assertEqual(receipt["dependencies"]["verifiedFromCheckouts"], True)
        self.assertEqual(
            [item["identity"] for item in receipt["dependencies"]["pins"]],
            sorted(self.fixture.checkouts),
        )
        self.assertEqual(
            {item["path"] for item in receipt["inventory"]},
            set(inputs.PRODUCTS),
        )
        for claimed in ("buildID", "buildNumber", "candidateStatus"):
            self.assertNotIn(claimed, receipt)
        staged = self.fixture.verify()
        self.assertEqual(
            {path.name for path in staged.iterdir()}, set(inputs.PRODUCTS)
        )
        self.assertEqual((staged / "Fleck").read_bytes(),
                         (self.fixture.output / "Fleck").read_bytes())

    def test_compile_products_locks_jobs_and_drops_graph_overrides(self):
        recorded = []

        def record(arguments, cwd, environment=None):
            recorded.append((list(arguments), dict(environment or {})))
            return ""

        environment = {
            "FLECK_ENHANCED_CANDIDATE": "1",
            "FLECK_BUILD_WITHOUT_SPARKLE": "1",
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        }
        with mock.patch.object(inputs, "run_streaming", side_effect=record), \
                mock.patch.dict(os.environ, environment, clear=True):
            inputs.compile_products(self.fixture.repo, dict(TOOLCHAIN))
        self.assertEqual(len(recorded), len(inputs.PRODUCTS))
        for (arguments, child_environment), product in zip(recorded, inputs.PRODUCTS):
            self.assertEqual(arguments[:4], ["swift", "build", "-c", "release"])
            self.assertEqual(arguments[arguments.index("--product") + 1], product)
            self.assertEqual(arguments[arguments.index("--jobs") + 1], "1")
            self.assertIn("--disable-automatic-resolution", arguments)
            flag = arguments.index("-Xswiftc")
            self.assertEqual(arguments[flag:flag + 4], ["-Xswiftc", "-j", "-Xswiftc", "1"])
            for value in inputs.linker_arguments(TOOLCHAIN):
                self.assertIn(value, arguments)
            for override in ("FLECK_ENHANCED_CANDIDATE", "FLECK_BUILD_WITHOUT_SPARKLE"):
                self.assertNotIn(override, child_environment)
            self.assertIn("PATH", child_environment)

    def test_compile_products_streams_compiler_output(self):
        calls = []

        def record(arguments, cwd=None, env=None):
            calls.append((list(arguments), cwd, env))
            return SimpleNamespace(returncode=0)

        with mock.patch.object(inputs.subprocess, "run", side_effect=record):
            inputs.compile_products(self.fixture.repo, dict(TOOLCHAIN))
        self.assertEqual(len(calls), len(inputs.PRODUCTS))
        for arguments, cwd, env in calls:
            self.assertEqual(arguments[:4], ["swift", "build", "-c", "release"])
            self.assertEqual(cwd, str(self.fixture.repo))
            self.assertIsNotNone(env)

    def test_streaming_compile_failure_reports_the_exit_status(self):
        with mock.patch.object(
            inputs.subprocess, "run", return_value=SimpleNamespace(returncode=65)
        ):
            with self.assertRaisesRegex(inputs.InputError, "exit status 65"):
                inputs.run_streaming(["swift", "build"], self.fixture.repo, {})

    def test_build_rejects_dirty_source_and_existing_output(self):
        (self.fixture.repo / "VERSION").write_text("1.8.14-beta.2\n", encoding="utf-8")
        with self.assertRaisesRegex(inputs.InputError, "dirty"):
            self.fixture.build()
        self.fixture.git("checkout", "--", "VERSION")
        self.fixture.output.mkdir()
        with self.assertRaisesRegex(inputs.InputError, "must not already exist"):
            self.fixture.build()

    def test_build_rejects_dependency_revision_drift(self):
        self.fixture.write_resolved(
            pins=[
                {
                    "identity": pin["identity"],
                    "kind": pin["kind"],
                    "location": pin["location"],
                    "state": {**pin["state"], "revision": "0" * 40},
                }
                for pin in self.fixture.pins()
            ]
        )
        self.fixture.git("add", ".")
        self.fixture.git("commit", "-qm", "Drifted lockfile")
        with self.assertRaisesRegex(inputs.InputError, "does not match Package.resolved"):
            self.fixture.build()
        self.assertFalse(self.fixture.output.exists())

    def test_build_rejects_a_checkout_that_is_not_in_the_lockfile(self):
        stray = self.fixture.repo / ".build/checkouts/stray"
        stray.mkdir()
        self.fixture.git("init", "-q", cwd=stray)
        self.fixture.git("config", "user.email", "fixture@example.invalid", cwd=stray)
        self.fixture.git("config", "user.name", "Fleck compile input fixture", cwd=stray)
        self.fixture.git("remote", "add", "origin", "https://example.invalid/stray.git", cwd=stray)
        (stray / "README.md").write_text("stray\n", encoding="utf-8")
        self.fixture.git("add", ".", cwd=stray)
        self.fixture.git("commit", "-qm", "stray", cwd=stray)
        with self.assertRaisesRegex(inputs.InputError, "unexpected dependency checkout"):
            self.fixture.build()

    def test_receipt_digest_must_match_the_trusted_transfer_hash(self):
        self.fixture.build()
        with self.assertRaisesRegex(inputs.InputError, "transfer digest"):
            self.fixture.verify(sha="0" * 64)

    def test_tampered_input_is_rejected(self):
        self.fixture.build()
        (self.fixture.output / "Fleck").write_bytes(b"tampered\n")
        with self.assertRaisesRegex(inputs.InputError, "does not match the receipt"):
            self.fixture.verify()

    def test_missing_input_is_rejected(self):
        self.fixture.build()
        (self.fixture.output / "fleck-agent").unlink()
        with self.assertRaisesRegex(inputs.InputError, "missing or unreadable"):
            self.fixture.verify()

    def test_unexpected_input_is_rejected(self):
        self.fixture.build()
        (self.fixture.output / "extra.bin").write_bytes(b"unexpected\n")
        with self.assertRaisesRegex(inputs.InputError, "exactly the receipted inputs"):
            self.fixture.verify()

    def test_mode_drift_is_rejected(self):
        self.fixture.build()
        (self.fixture.output / "Fleck").chmod(0o644)
        with self.assertRaisesRegex(inputs.InputError, "mode does not match the receipt"):
            self.fixture.verify()

    def test_symlink_in_place_of_a_product_is_rejected(self):
        self.fixture.build()
        target = self.fixture.output / "Fleck"
        payload = target.read_bytes()
        target.unlink()
        os.symlink(self.fixture.output / "fleck-agent", target)
        with self.assertRaisesRegex(inputs.InputError, "not a regular file"):
            self.fixture.verify()
        target.unlink()
        target.write_bytes(payload)

    def test_source_identity_drift_is_rejected(self):
        self.fixture.build()
        sha = self.fixture.rewrite(
            lambda receipt: receipt["source"].__setitem__("commit", "1" * 40)
        )
        with self.assertRaisesRegex(inputs.InputError, "does not match this repository"):
            self.fixture.verify(sha)

    def test_tree_drift_is_rejected(self):
        self.fixture.build()
        sha = self.fixture.rewrite(
            lambda receipt: receipt["source"].__setitem__("tree", "0" * 40)
        )
        with self.assertRaisesRegex(inputs.InputError, "does not match this repository"):
            self.fixture.verify(sha)

    def test_version_drift_is_rejected(self):
        self.fixture.build()
        sha = self.fixture.rewrite(
            lambda receipt: receipt.__setitem__("productVersion", "9.9.9-beta.1")
        )
        with self.assertRaisesRegex(inputs.InputError, "does not match VERSION"):
            self.fixture.verify(sha)

    def test_configuration_drift_is_rejected(self):
        self.fixture.build()
        sha = self.fixture.rewrite(
            lambda receipt: receipt.__setitem__("configuration", "Debug")
        )
        with self.assertRaisesRegex(inputs.InputError, "not Release"):
            self.fixture.verify(sha)

    def test_architecture_drift_is_rejected(self):
        self.fixture.build()
        sha = self.fixture.rewrite(
            lambda receipt: receipt.__setitem__("architecture", "x86_64")
        )
        with self.assertRaisesRegex(inputs.InputError, "architecture"):
            self.fixture.verify(sha)

    def test_producer_toolchain_differences_are_accepted(self):
        self.fixture.build()
        staged = self.fixture.verify(
            self.fixture.producer_toolchain_receipt(),
            build_version=linked_version(PRODUCER_TOOLCHAIN),
        )
        self.assertEqual(
            {path.name for path in staged.iterdir()}, set(inputs.PRODUCTS)
        )

    def test_malformed_producer_metadata_is_rejected(self):
        cases = (
            ("swiftVersion", "6.4.2", "Swift version is malformed"),
            ("swiftVersion", "Swift version 6.4.2-RELEASE", "Swift version is malformed"),
            ("xcodeVersion", "Xcode 27", "Xcode version is malformed"),
            ("xcodeBuildVersion", "27-2", "Xcode build version is malformed"),
            ("xcodeBuildVersion", "27B52b1", "Xcode build version is malformed"),
            ("sdkVersion", "27", "SDK version is malformed"),
            ("sdkVersion", "SDK27.2", "SDK version is malformed"),
            ("minimumOSVersion", "13.0", "minimum OS version is unsupported"),
        )
        for key, value, message in cases:
            with self.subTest(key=key, value=value):
                temporary = tempfile.TemporaryDirectory(prefix="fleck-compile-inputs-")
                self.addCleanup(temporary.cleanup)
                fixture = CompileInputFixture(temporary.name)
                fixture.build()
                sha = fixture.rewrite(
                    lambda receipt, key=key, value=value: receipt["toolchain"].__setitem__(
                        key, value
                    )
                )
                with self.assertRaisesRegex(inputs.InputError, message):
                    fixture.verify(sha)

    def test_binary_sdk_mismatch_is_rejected(self):
        self.fixture.build()
        with self.assertRaisesRegex(inputs.InputError, "receipted SDK 27.2"):
            self.fixture.verify(
                self.fixture.producer_toolchain_receipt(), build_version=linked_version()
            )

    def test_binary_minimum_os_mismatch_is_rejected(self):
        self.fixture.build()
        with self.assertRaisesRegex(inputs.InputError, "linked at macOS 14.0"):
            self.fixture.verify(sha=None, build_version=("15.0", TOOLCHAIN["sdkVersion"]))

    def test_fat_binary_is_rejected(self):
        self.fixture.build()
        with self.assertRaisesRegex(inputs.InputError, "thin arm64 executable"):
            self.fixture.verify(architectures=["arm64", "x86_64"])

    def test_dependency_drift_is_rejected(self):
        self.fixture.build()
        sha = self.fixture.rewrite(
            lambda receipt: receipt["dependencies"]["pins"][0].__setitem__(
                "revision", "2" * 40
            )
        )
        with self.assertRaisesRegex(inputs.InputError, "do not match Package.resolved"):
            self.fixture.verify(sha)

    def test_allocated_identity_claim_is_rejected(self):
        self.fixture.build()
        sha = self.fixture.rewrite(
            lambda receipt: receipt.__setitem__("buildID", str(uuid.uuid4()))
        )
        with self.assertRaisesRegex(
            inputs.InputError, "must not claim an allocated build identity"
        ):
            self.fixture.verify(sha)

    def test_enhanced_graph_override_is_rejected(self):
        self.fixture.build()
        sha = self.fixture.rewrite(
            lambda receipt: receipt["build"].__setitem__("enhancedCandidate", True)
        )
        with self.assertRaisesRegex(inputs.InputError, "graph or environment override"):
            self.fixture.verify(sha)

    def test_framework_payload_with_symlinks_is_accepted_and_staged(self):
        self.fixture.build()
        sha = self.fixture.signed_framework_receipt()
        staged = self.fixture.verify(sha)
        framework = staged / "Sparkle.framework"
        self.assertTrue((framework / "Sparkle").is_symlink())
        self.assertEqual(os.readlink(framework / "Sparkle"), "Versions/Current/Sparkle")
        self.assertEqual(os.readlink(framework / "Versions/Current"), "B")
        self.assertEqual(
            (framework / "Sparkle").read_bytes(), b"fixture sparkle binary\n"
        )

    def test_symlink_escape_is_rejected(self):
        self.fixture.build()
        framework = self.fixture.add_framework()
        (framework / "Sparkle").unlink()
        os.symlink("../../outside", framework / "Sparkle")
        sha = self.fixture.rewrite(
            lambda receipt: (
                receipt.__setitem__(
                    "frameworks",
                    [
                        {
                            "path": "Sparkle.framework",
                            "source": inputs.SPARKLE_FRAMEWORK,
                            "identity": "sparkle",
                        }
                    ],
                ),
                receipt.__setitem__("inventory", self.fixture.inventory()),
            )
        )
        with self.assertRaisesRegex(inputs.InputError, "escapes the input directory"):
            self.fixture.verify(sha)

    def test_absolute_symlink_target_is_rejected(self):
        self.fixture.build()
        framework = self.fixture.add_framework()
        (framework / "Sparkle").unlink()
        os.symlink("/usr/bin/true", framework / "Sparkle")
        sha = self.fixture.rewrite(
            lambda receipt: (
                receipt.__setitem__(
                    "frameworks",
                    [
                        {
                            "path": "Sparkle.framework",
                            "source": inputs.SPARKLE_FRAMEWORK,
                            "identity": "sparkle",
                        }
                    ],
                ),
                receipt.__setitem__("inventory", self.fixture.inventory()),
            )
        )
        with self.assertRaisesRegex(inputs.InputError, "escapes the input directory"):
            self.fixture.verify(sha)

    def test_parent_directory_escape_in_inventory_is_rejected(self):
        self.fixture.build()
        sha = self.fixture.rewrite(
            lambda receipt: receipt["inventory"].append(
                {
                    "path": "../Fleck",
                    "kind": "file",
                    "bytes": 1,
                    "mode": "0755",
                    "sha256": "0" * 64,
                }
            )
        )
        with self.assertRaisesRegex(inputs.InputError, "normalized relative path"):
            self.fixture.verify(sha)

    def test_staging_refuses_an_existing_directory(self):
        self.fixture.build()
        staging = self.fixture.root / "staging"
        staging.mkdir()
        with self.assertRaisesRegex(inputs.InputError, "must not already exist"):
            self.fixture.verify(staging=staging)

    def test_staged_copy_is_rehashed(self):
        self.fixture.build()
        entries = inputs.validate_inventory(
            self.fixture.output,
            self.fixture.receipt()["inventory"],
            [],
        )
        original = inputs.sha256_file
        calls = []

        def tracking(path):
            value = original(path)
            calls.append((Path(path), value))
            return value

        staging = self.fixture.root / "staging"
        with mock.patch.object(inputs, "sha256_file", side_effect=tracking):
            inputs.stage_inputs(entries, self.fixture.output, staging)
            inputs.validate_inventory(staging, entries, [])
        staged_paths = {path for path, _ in calls if staging in path.parents}
        self.assertEqual(staged_paths, {staging / name for name in inputs.PRODUCTS})
        for name in inputs.PRODUCTS:
            self.assertEqual(
                digest(staging / name), digest(self.fixture.output / name)
            )

    def test_cli_verify_rejects_a_wrong_transfer_digest(self):
        self.fixture.build()
        staged = self.fixture.root / "cli-staging"
        result = subprocess.run(
            [
                sys.executable,
                "-B",
                str(ROOT / "Scripts/fleck-build-inputs.py"),
                "verify",
                "--receipt",
                str(self.fixture.receipt_path()),
                "--receipt-sha256",
                "0" * 64,
                "--repo",
                str(self.fixture.repo),
                "--staging",
                str(staged),
            ],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("does not match the supplied transfer digest", result.stderr)
        self.assertFalse(staged.exists())


class PackagerParserTests(unittest.TestCase):
    def packager(self):
        return ROOT / "Scripts/build-fleck-app.sh"

    def run_packager(self, *arguments):
        return subprocess.run(
            ["bash", str(self.packager()), *arguments],
            capture_output=True,
            text=True,
        )

    def test_unknown_flag_is_rejected(self):
        result = self.run_packager("--bogus")
        self.assertEqual(result.returncode, 2)
        self.assertIn("usage:", result.stderr)

    def test_prebuilt_inputs_requires_a_trusted_digest(self):
        result = self.run_packager("--prebuilt-inputs", "/tmp/receipt.json")
        self.assertEqual(result.returncode, 2)
        self.assertIn("usage:", result.stderr)

    def test_trusted_digest_requires_prebuilt_inputs(self):
        result = self.run_packager("--input-receipt-sha256", "0" * 64)
        self.assertEqual(result.returncode, 2)
        self.assertIn("usage:", result.stderr)

    def test_duplicate_result_file_is_rejected(self):
        result = self.run_packager(
            "--result-file", "/tmp/first.json", "--result-file", "/tmp/second.json"
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("usage:", result.stderr)

    def test_missing_option_value_is_rejected(self):
        result = self.run_packager("--result-file")
        self.assertEqual(result.returncode, 2)
        self.assertIn("usage:", result.stderr)


if __name__ == "__main__":
    unittest.main()
