import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "Scripts/validate-perf-prebuilt.py"
SWIFT_VERSION = "Swift version 6.4.0 (swift-6.4-RELEASE)"
SDK_VERSION = "27.4"


def git(repo, *arguments):
    return subprocess.run(
        ["git", "-C", str(repo), *arguments],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class PrebuiltFixture:
    def __init__(self, parent):
        self.repo = parent / "repo"
        self.repo.mkdir()
        (self.repo / ".gitignore").write_text(".build/\n", encoding="utf-8")
        scripts = self.repo / "Scripts"
        scripts.mkdir()
        shutil.copy2(ROOT / "Scripts/run-swift-tests-with-appkit-host.sh", scripts)
        shutil.copy2(ROOT / "Scripts/validate-perf-prebuilt.py", scripts)
        support = self.repo / "Tests/Support"
        support.mkdir(parents=True)
        shutil.copy2(ROOT / "Tests/Support/AppKitTestMain.swift", support)
        git(self.repo, "init", "-q")
        git(self.repo, "config", "user.email", "fixture@example.invalid")
        git(self.repo, "config", "user.name", "Performance receipt fixture")
        git(self.repo, "add", ".")
        git(self.repo, "commit", "-qm", "Fixture source")

        self.products = self.repo / ".build/out/Products"
        self.executables = {}
        for configuration in ("Debug", "Release"):
            executable = (
                self.products
                / configuration
                / "FleckPerformanceTests.xctest/Contents/MacOS/FleckPerformanceTests"
            )
            executable.parent.mkdir(parents=True)
            executable.write_bytes(f"{configuration} test bundle\n".encode())
            executable.chmod(0o755)
            self.executables[configuration.lower()] = executable

        self.receipt_path = parent / "perf-prebuilt.json"
        self.tool = scripts / "validate-perf-prebuilt.py"

    def receipt(self, configuration="debug", **changes):
        wrapper = self.repo / "Scripts/run-swift-tests-with-appkit-host.sh"
        harness = self.repo / "Tests/Support/AppKitTestMain.swift"
        executable = self.executables[configuration]
        value = {
            "schemaVersion": 1,
            "packageRoot": str(self.repo),
            "sourceCommit": git(self.repo, "rev-parse", "HEAD"),
            "sourceTree": git(self.repo, "rev-parse", "HEAD^{tree}"),
            "configuration": configuration,
            "buildSystem": "swiftbuild",
            "testabilityEnabled": True,
            "swiftVersion": SWIFT_VERSION,
            "sdkVersion": SDK_VERSION,
            "harnessSHA256": digest(harness),
            "bootstrapWrapperSHA256": digest(wrapper),
            "testBundleExecutableSHA256": digest(executable),
        }
        value.update(changes)
        self.receipt_path.write_text(json.dumps(value), encoding="utf-8")
        return value

    def invoke(
        self,
        *,
        receipt_path=None,
        package_root=None,
        configuration="debug",
        swift_version=SWIFT_VERSION,
        sdk_version=SDK_VERSION,
        scratch_path="",
        environment=None,
    ):
        receipt_path = str(receipt_path or self.receipt_path)
        package_root = str(package_root or self.repo)
        env = os.environ.copy()
        env.update({
            "FLECK_PERF_RUN": "1",
            "FLECK_TEST_SWIFT_TARGET": "FleckPerformanceTests",
            "FLECK_TEST_SWIFT_BUILD_SYSTEM": "swiftbuild",
            "FLECK_TEST_SWIFT_CONFIGURATION": configuration,
            "FLECK_PERF_PREBUILT_RECEIPT": receipt_path,
        })
        env.pop("FLECK_ENHANCED_CANDIDATE", None)
        env.pop("FLECK_BUILD_WITHOUT_SPARKLE", None)
        for key, value in (environment or {}).items():
            if value is None:
                env.pop(key, None)
            else:
                env[key] = value
        return subprocess.run(
            [
                "python3",
                "-B",
                str(self.tool),
                "--receipt",
                receipt_path,
                "--package-root",
                package_root,
                "--configuration",
                configuration,
                "--swift-version",
                swift_version,
                "--sdk-version",
                sdk_version,
                "--scratch-path",
                scratch_path,
            ],
            check=False,
            capture_output=True,
            text=True,
            env=env,
        )


class ValidatePerfPrebuiltTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="fleck-prebuilt-test-")
        self.parent = Path(self.temporary.name).resolve()
        self.fixture = PrebuiltFixture(self.parent)

    def tearDown(self):
        self.temporary.cleanup()

    def assert_rejected(self, **arguments):
        result = self.fixture.invoke(**arguments)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertNotIn(str(self.parent), result.stderr)
        self.assertTrue(result.stderr.startswith("error: "), result.stderr)
        return result.stderr

    def test_valid_debug_and_release_receipts_print_only_the_fixed_products_path(self):
        for configuration in ("debug", "release"):
            with self.subTest(configuration=configuration):
                self.fixture.receipt(configuration)
                result = self.fixture.invoke(configuration=configuration)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(
                    result.stdout,
                    str(self.fixture.products / configuration.capitalize()) + "\n",
                )
                self.assertEqual(result.stderr, "")

    def test_receipt_schema_and_source_identity_are_strict(self):
        invalid_receipts = (
            {"schemaVersion": 2},
            {"sourceCommit": "a" * 40},
            {"sourceTree": "b" * 40},
            {"packageRoot": str(self.parent)},
            {"harnessSHA256": "0" * 64},
            {"bootstrapWrapperSHA256": "1" * 64},
            {"testBundleExecutableSHA256": "2" * 64},
            {"buildSystem": "xcode"},
            {"configuration": "release"},
            {"testabilityEnabled": False},
            {"testabilityEnabled": 1},
            {"untrustedBundlePath": "/private/arbitrary.app"},
        )
        for change in invalid_receipts:
            with self.subTest(change=change):
                self.fixture.receipt(**change)
                self.assert_rejected()

        self.fixture.receipt()
        self.fixture.receipt_path.write_text(
            '{"schemaVersion":1,"schemaVersion":1}', encoding="utf-8"
        )
        self.assert_rejected()
        self.fixture.receipt_path.write_text("{invalid", encoding="utf-8")
        self.assert_rejected()
        missing_field = self.fixture.receipt()
        missing_field.pop("testabilityEnabled")
        self.fixture.receipt_path.write_text(json.dumps(missing_field), encoding="utf-8")
        self.assert_rejected()

    def test_dirty_and_changed_source_are_rejected(self):
        self.fixture.receipt()
        source = self.fixture.repo / "Tests/Support/AppKitTestMain.swift"
        source.write_text(source.read_text(encoding="utf-8") + "\n// changed\n", encoding="utf-8")
        self.assert_rejected()
        source.write_text(source.read_text(encoding="utf-8").replace("\n// changed\n", "\n"), encoding="utf-8")
        self.assert_rejected(environment={"FLECK_TEST_SWIFT_TARGET": "WrongTarget"})

        (self.fixture.repo / "untracked.txt").write_text("dirty\n", encoding="utf-8")
        self.assert_rejected()

    def test_receipt_and_package_root_paths_must_be_canonical_and_regular(self):
        self.fixture.receipt()
        missing_receipt = self.parent / "missing.json"
        self.assert_rejected(receipt_path=missing_receipt)

        receipt_link = self.parent / "receipt-link.json"
        receipt_link.symlink_to(self.fixture.receipt_path)
        self.assert_rejected(receipt_path=receipt_link)

        self.assert_rejected(receipt_path="relative-receipt.json")
        noncanonical_receipt = f"{self.parent}/./{self.fixture.receipt_path.name}"
        self.assert_rejected(receipt_path=noncanonical_receipt)

        repo_link = self.parent / "repo-link"
        repo_link.symlink_to(self.fixture.repo, target_is_directory=True)
        self.assert_rejected(package_root=repo_link)

    def test_fixed_products_bundle_must_exist_without_symlinks_and_match_hash(self):
        self.fixture.receipt()
        executable = self.fixture.executables["debug"]
        executable.unlink()
        self.assert_rejected()

        executable.write_bytes(b"wrong bytes\n")
        executable.chmod(0o755)
        self.assert_rejected()

        self.fixture.receipt()
        executable.chmod(0o644)
        self.assert_rejected()

        executable.chmod(0o755)
        bundle = executable.parents[2]
        moved_bundle = bundle.with_name("moved-test-bundle")
        bundle.rename(moved_bundle)
        bundle.symlink_to(moved_bundle, target_is_directory=True)
        self.fixture.receipt()
        self.assert_rejected()

        bundle.unlink()
        moved_bundle.rename(bundle)
        moved_executable = self.parent / "moved-test-executable"
        executable.rename(moved_executable)
        executable.symlink_to(moved_executable)
        self.fixture.receipt()
        self.assert_rejected()

    def test_toolchain_configuration_graph_target_and_scratch_must_match(self):
        self.fixture.receipt()
        self.assert_rejected(swift_version="Swift version 9.0")
        self.assert_rejected(sdk_version="99.0")
        self.assert_rejected(configuration="optimized")
        self.assert_rejected(scratch_path="/tmp/scratch")
        self.assert_rejected(environment={"FLECK_PERF_SWIFT_VERSION": "Swift version 5.0"})

        restrictions = (
            {"FLECK_PERF_RUN": "0"},
            {"FLECK_PERF_RUN": None},
            {"FLECK_TEST_SWIFT_TARGET": "OtherTests"},
            {"FLECK_TEST_SWIFT_TARGET": None},
            {"FLECK_TEST_SWIFT_BUILD_SYSTEM": "native"},
            {"FLECK_TEST_SWIFT_BUILD_SYSTEM": None},
            {"FLECK_TEST_SWIFT_CONFIGURATION": "release"},
            {"FLECK_ENHANCED_CANDIDATE": "1"},
            {"FLECK_BUILD_WITHOUT_SPARKLE": "1"},
            {"FLECK_PERF_PREBUILT_RECEIPT": "/different/receipt.json"},
            {"FLECK_TEST_SWIFT_CONFIGURATION": None},
        )
        for change in restrictions:
            with self.subTest(change=change):
                self.assert_rejected(environment=change)

    def test_products_directory_symlink_is_rejected(self):
        self.fixture.receipt()
        products = self.fixture.products / "Debug"
        outside = self.parent / "external-products"
        shutil.copytree(products, outside)
        shutil.rmtree(products)
        products.symlink_to(outside, target_is_directory=True)
        self.assert_rejected()


if __name__ == "__main__":
    unittest.main()
