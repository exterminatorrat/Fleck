import concurrent.futures
import hashlib
import importlib.util
import json
import os
import plistlib
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
import uuid
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "Scripts/fleck-build-identity.py"
SPEC = importlib.util.spec_from_file_location("fleck_build_identity", TOOL)
identity = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(identity)


def git(repo, *arguments):
    return subprocess.run(
        ["git", "-C", str(repo), *arguments],
        check=True,
        text=True,
        capture_output=True,
    ).stdout.strip()


class RepositoryFixture:
    def __init__(self, root):
        self.repo = root / "repo"
        self.repo.mkdir()
        self.accepted = self.repo / ".identity-test" / "accepted"
        self.database = self.repo / ".identity-test" / "identities.sqlite3"
        self.accepted.mkdir(parents=True)
        git(self.repo, "init", "-q")
        git(self.repo, "config", "user.email", "fixture@example.invalid")
        git(self.repo, "config", "user.name", "Build identity fixture")
        (self.repo / ".gitignore").write_text(".build/\n.identity-test/\n", encoding="utf-8")
        (self.repo / "base.txt").write_text("accepted\n", encoding="utf-8")
        git(self.repo, "add", ".")
        git(self.repo, "commit", "-qm", "Accepted base")
        self.accepted_commit = git(self.repo, "rev-parse", "HEAD")
        self.accepted_tree = git(self.repo, "rev-parse", "HEAD^{tree}")
        validator = self.accepted / "check-accepted-build.py"
        validator.write_text(
            "#!/usr/bin/env python3\n"
            "import argparse, pathlib, sys\n"
            "p=argparse.ArgumentParser(); p.add_argument('manifest'); "
            "p.add_argument('--artifact-root'); p.add_argument('--repo'); "
            "p.add_argument('--repo-mode'); a=p.parse_args(); "
            "sys.exit(0 if pathlib.Path(a.repo, '.git').exists() else 1)\n",
            encoding="utf-8",
        )
        validator.chmod(validator.stat().st_mode | stat.S_IXUSR)
        validator_bytes = validator.read_bytes()
        self.manifest = {
            "schemaVersion": 1,
            "registryStatus": "active",
            "latestAcceptedRecordID": "fixture-accepted",
            "records": [{
                "id": "fixture-accepted",
                "status": "latestAccepted",
                "source": {"commit": self.accepted_commit, "tree": self.accepted_tree},
            }],
            "supportFiles": [{
                "relativePath": "check-accepted-build.py",
                "sha256": hashlib.sha256(validator_bytes).hexdigest(),
                "size": len(validator_bytes),
            }],
        }
        self.write_manifest()
        (self.repo / "VERSION").write_text("1.0.0-beta.1\n", encoding="utf-8")
        (self.repo / "CHANGELOG.md").write_text(
            "# Changelog\n\n## [1.0.0-beta.1] - 2026-09-11\n", encoding="utf-8"
        )
        (self.repo / ".fleck-build-identity-test-fixture").write_text(
            "fleck-build-identity-test-fixture-v1\n", encoding="utf-8"
        )
        self.write_baseline()
        scripts = self.repo / "Scripts"
        scripts.mkdir()
        for name in (
            "build-fleck-app.sh",
            "build-parakeet-test-app.sh",
            "build-pre-astra-corrected-build.sh",
        ):
            shutil.copy2(ROOT / "Scripts" / name, scripts / name)
        shutil.copy2(ROOT / "Scripts/fleck-build-identity.py", scripts / "fleck-build-identity.py")
        sources = self.repo / "Sources"
        sources.mkdir()
        (sources / "Hidden.swift").write_text("let hidden = false\n", encoding="utf-8")
        git(self.repo, "add", ".")
        git(self.repo, "commit", "-qm", "Candidate source")

    @property
    def manifest_hash(self):
        return hashlib.sha256((self.accepted / "manifest.json").read_bytes()).hexdigest()

    def write_manifest(self):
        data = json.dumps(self.manifest, indent=2, sort_keys=True) + "\n"
        (self.accepted / "manifest.json").write_text(data, encoding="utf-8")
        digest = hashlib.sha256(data.encode()).hexdigest()
        (self.accepted / "manifest.sha256").write_text(f"{digest}  manifest.json\n", encoding="utf-8")

    def write_baseline(self, **changes):
        baseline = {
            "schemaVersion": 1,
            "canonicalManifestSHA256": self.manifest_hash,
            "selectedRecordID": "fixture-accepted",
            "acceptedSourceCommit": self.accepted_commit,
            "acceptedSourceTree": self.accepted_tree,
            "requiredRegistryStatus": "active",
        }
        baseline.update(changes)
        (self.repo / "BuildBaseline.json").write_text(
            json.dumps(baseline, indent=2) + "\n", encoding="utf-8"
        )

    def begin(self, flavor="development", mode="local", nested_token=None):
        capture = self.repo / ".build" / f"{flavor}-{uuid.uuid4()}.json"
        arguments = mock.Mock(
            repo=str(self.repo),
            flavor=flavor,
            configuration="Debug",
            capture=str(capture),
            mode=mode,
            test_accepted_root=str(self.accepted) if mode == "local" else None,
            test_database=str(self.database) if mode == "local" else None,
            nested_token=nested_token,
        )
        with mock.patch.dict(
            os.environ, {"FLECK_BUILD_IDENTITY_TEST_FIXTURE": "1"}, clear=False
        ):
            identity.command_begin(arguments)
        return capture


class BuildIdentityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve()

    def tearDown(self):
        self.temporary.cleanup()

    def fixture(self):
        return RepositoryFixture(self.root)

    def test_version_and_bundle_number_transitions(self):
        repo = self.root / "version"
        repo.mkdir()
        for value, numeric in [
            ("1.0.0-beta.1", "1.0.0"),
            ("1.0.1-beta.1", "1.0.1"),
            ("1.0.1-beta.2", "1.0.1"),
            ("1.1.0-beta.1", "1.1.0"),
            ("1.1.0", "1.1.0"),
        ]:
            (repo / "VERSION").write_text(value + "\n", encoding="utf-8")
            self.assertEqual(identity.product_version(repo), (value, numeric))
        self.assertEqual(identity.bundle_version(1), "1.0.0")
        self.assertEqual(identity.bundle_version(100), "1.0.99")
        self.assertEqual(identity.bundle_version(101), "1.1.0")
        self.assertEqual(identity.bundle_version(10_001), "2.0.0")
        self.assertEqual(identity.bundle_version(99_990_000), "9999.99.99")
        with self.assertRaises(identity.IdentityError):
            identity.bundle_version(99_990_001)

    def test_artifact_name_and_plist_names_come_from_one_capture(self):
        fixture = self.fixture()
        capture_path = fixture.begin()
        capture = identity.load_capture(capture_path)
        expected = f"Fleck {capture['productVersion']} Build {capture['buildNumber']}"
        self.assertEqual(identity.artifact_name(capture), expected)
        values = identity.plist_values(capture)
        self.assertEqual(values["CFBundleName"], expected)
        self.assertEqual(values["CFBundleDisplayName"], expected)
        self.assertEqual(values["FleckBuildLabel"], expected)
        identity.release_guard(capture)

    def test_result_file_is_immutable_exact_and_bound_to_published_app(self):
        fixture = self.fixture()
        capture_path = fixture.begin()
        capture = identity.load_capture(capture_path)
        name = identity.artifact_name(capture)
        app = fixture.repo / ".build" / f"{name}.app"
        plist = app / "Contents" / "Info.plist"
        plist.parent.mkdir(parents=True)
        with plist.open("wb") as handle:
            plistlib.dump(identity.plist_values(capture), handle)
        results = fixture.repo / ".build" / "results"
        results.mkdir()
        result = results / "development.json"

        ownership = identity.write_result(capture, app, result)
        self.assertRegex(ownership, r"^[0-9]+:[0-9]+$")
        self.assertEqual(
            json.loads(result.read_text(encoding="utf-8")),
            {"appPath": str(app), "buildID": capture["buildID"]},
        )
        self.assertEqual(identity.read_result(fixture.repo, result, "development"), app)
        before = result.read_bytes()
        with self.assertRaises(identity.IdentityError):
            identity.write_result(capture, app, result)
        self.assertEqual(result.read_bytes(), before)
        identity.release_guard(capture)

    def test_result_reader_binds_uuid_metadata_flavor_and_publication_root(self):
        fixture = self.fixture()
        capture_path = fixture.begin()
        capture = identity.load_capture(capture_path)
        name = identity.artifact_name(capture)
        app = fixture.repo / ".build" / f"{name}.app"
        plist = app / "Contents" / "Info.plist"
        plist.parent.mkdir(parents=True)
        with plist.open("wb") as handle:
            plistlib.dump(identity.plist_values(capture), handle)
        result = fixture.repo / ".build" / "result.json"
        identity.write_result(capture, app, result)

        with self.assertRaisesRegex(identity.IdentityError, "publication root"):
            identity.read_result(fixture.repo, result, "parakeet")
        value = json.loads(result.read_text(encoding="utf-8"))
        value["buildID"] = str(uuid.uuid4())
        result.write_text(json.dumps(value), encoding="utf-8")
        with self.assertRaisesRegex(identity.IdentityError, "does not match"):
            identity.read_result(fixture.repo, result, "development")
        identity.release_guard(capture)

    def test_owned_result_removal_preserves_a_substituted_destination(self):
        fixture = self.fixture()
        capture_path = fixture.begin()
        capture = identity.load_capture(capture_path)
        name = identity.artifact_name(capture)
        app = fixture.repo / ".build" / f"{name}.app"
        plist = app / "Contents" / "Info.plist"
        plist.parent.mkdir(parents=True)
        with plist.open("wb") as handle:
            plistlib.dump(identity.plist_values(capture), handle)
        result = fixture.repo / ".build" / "result.json"
        ownership = identity.write_result(capture, app, result)
        replacement = fixture.repo / ".build" / "replacement"
        replacement.write_text("replacement sentinel\n", encoding="utf-8")
        replacement.replace(result)

        with self.assertRaisesRegex(identity.IdentityError, "substituted"):
            identity.remove_owned_result(fixture.repo, result, ownership)
        self.assertEqual(result.read_text(encoding="utf-8"), "replacement sentinel\n")
        result.unlink()
        second = fixture.repo / ".build" / "second.json"
        second_ownership = identity.write_result(capture, app, second)
        identity.remove_owned_result(fixture.repo, second, second_ownership)
        self.assertFalse(os.path.lexists(second))
        identity.release_guard(capture)

    def test_result_path_rejects_outside_existing_and_symlinked_destinations(self):
        fixture = self.fixture()
        build = fixture.repo / ".build"
        build.mkdir()
        results = build / "results"
        results.mkdir()
        outside = self.root / "outside.json"
        existing = results / "existing.json"
        existing.write_text("sentinel\n", encoding="utf-8")
        target = build / "target"
        target.mkdir()
        link = build / "linked"
        link.symlink_to(target, target_is_directory=True)

        for rejected in (
            Path("relative.json"),
            outside,
            existing,
            link / "result.json",
        ):
            with self.subTest(path=rejected):
                with self.assertRaises(identity.IdentityError):
                    identity.validate_result_path(fixture.repo, rejected)
        self.assertEqual(existing.read_text(encoding="utf-8"), "sentinel\n")

    def test_failed_result_verification_leaves_no_success_result(self):
        fixture = self.fixture()
        capture_path = fixture.begin()
        capture = identity.load_capture(capture_path)
        name = identity.artifact_name(capture)
        app = fixture.repo / ".build" / f"{name}.app"
        plist = app / "Contents" / "Info.plist"
        plist.parent.mkdir(parents=True)
        values = identity.plist_values(capture)
        values["FleckBuildID"] = str(uuid.uuid4())
        with plist.open("wb") as handle:
            plistlib.dump(values, handle)
        result = fixture.repo / ".build" / "failed-result.json"

        with self.assertRaises(identity.IdentityError):
            identity.write_result(capture, app, result)
        self.assertFalse(os.path.lexists(result))
        identity.release_guard(capture)

    def test_rejects_missing_and_malformed_version_and_baseline(self):
        repo = self.root / "invalid"
        repo.mkdir()
        with self.assertRaises(identity.IdentityError):
            identity.product_version(repo)
        for invalid in ("1.0", "01.0.0", "1.0.0-beta.01", "v1.0.0"):
            (repo / "VERSION").write_text(invalid, encoding="utf-8")
            with self.assertRaises(identity.IdentityError):
                identity.product_version(repo)
        (repo / "BuildBaseline.json").write_text("{}", encoding="utf-8")
        with self.assertRaises(identity.IdentityError):
            identity.load_baseline(repo)

    def test_allocator_serializes_concurrent_unique_allocations(self):
        database = self.root / "identities.sqlite3"
        data = {
            "buildDate": "2026-09-11T00:00:00Z",
            "sourceCommit": "a" * 40,
            "sourceTree": "b" * 40,
            "productVersion": "1.0.0-beta.1",
            "flavor": "development",
            "configuration": "Debug",
        }
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
            allocated = list(executor.map(lambda _: identity.allocate(database, data), range(24)))
        numbers = [item[0] for item in allocated]
        build_ids = [item[1] for item in allocated]
        self.assertEqual(sorted(numbers), list(range(1, 25)))
        self.assertEqual(len(set(build_ids)), 24)
        for value in build_ids:
            self.assertEqual(str(uuid.UUID(value)), value)

    def test_same_source_unfinished_attempts_have_distinct_identity_and_gap(self):
        fixture = self.fixture()
        first = fixture.begin()
        first_value = identity.load_capture(first)
        identity.release_guard(first_value)
        second = fixture.begin()
        second_value = identity.load_capture(second)
        identity.release_guard(second_value)
        self.assertEqual(first_value["sourceCommit"], second_value["sourceCommit"])
        self.assertEqual(second_value["buildNumber"], first_value["buildNumber"] + 1)
        self.assertNotEqual(first_value["buildID"], second_value["buildID"])

    def test_failed_finish_releases_guard_and_burns_build_number(self):
        fixture = self.fixture()
        failed_path = fixture.begin()
        failed = identity.load_capture(failed_path)
        plist_path = self.root / "failed-finish.plist"
        with plist_path.open("wb") as handle:
            plistlib.dump(identity.plist_values(failed), handle)
        hidden_source = fixture.repo / "Sources/Hidden.swift"
        git(fixture.repo, "update-index", "--assume-unchanged", "Sources/Hidden.swift")
        hidden_source.write_text("let hidden = true\n", encoding="utf-8")
        with self.assertRaisesRegex(identity.IdentityError, "assume-unchanged"):
            identity.command_finish(mock.Mock(capture=str(failed_path), plist=str(plist_path)))
        identity.release_guard(failed)
        git(fixture.repo, "update-index", "--no-assume-unchanged", "Sources/Hidden.swift")
        git(fixture.repo, "checkout", "--", "Sources/Hidden.swift")

        next_path = fixture.begin()
        next_capture = identity.load_capture(next_path)
        self.assertEqual(next_capture["buildNumber"], failed["buildNumber"] + 1)
        identity.release_guard(next_capture)

    def test_stamp_verify_and_copy_preserve_full_identity(self):
        fixture = self.fixture()
        capture_path = fixture.begin()
        capture = identity.load_capture(capture_path)
        plist_path = self.root / "Info.plist"
        with plist_path.open("wb") as handle:
            plistlib.dump({"CFBundleIdentifier": "com.harryjin.fleck"}, handle)
        value = identity.read_plist(plist_path)
        value.update(identity.plist_values(capture))
        identity.write_plist(plist_path, value)
        actual = identity.verify_plist(capture, plist_path)
        self.assertEqual(actual["CFBundleShortVersionString"], "1.0.0")
        self.assertEqual(actual["FleckVersion"], "1.0.0-beta.1")
        copied = self.root / "extracted.plist"
        shutil.copy2(plist_path, copied)
        self.assertEqual(identity.read_plist(copied), actual)
        info = identity.info_text(capture, actual["CFBundleIdentifier"])
        self.assertIn(f"Build ID: {capture['buildID']}", info)
        self.assertIn(f"Source commit: {capture['sourceCommit']}", info)
        self.assertNotIn(str(fixture.repo), info)
        identity.release_guard(capture)

    def test_corrected_repack_retains_input_identity_and_gets_new_identity(self):
        fixture = self.fixture()
        inner_path = fixture.begin("parakeet")
        inner = identity.load_capture(inner_path)
        identity.release_guard(inner)
        outer_path = fixture.begin("corrected")
        outer = identity.load_capture(outer_path)
        arguments = mock.Mock(
            capture=str(outer_path),
            input_build_id=inner["buildID"],
            input_manifest_sha256="c" * 64,
        )
        identity.command_augment(arguments)
        augmented = identity.load_capture(outer_path)
        self.assertNotEqual(augmented["buildID"], inner["buildID"])
        self.assertEqual(augmented["inputBuildID"], inner["buildID"])
        self.assertEqual(identity.plist_values(augmented)["FleckInputManifestSHA256"], "c" * 64)
        identity.release_guard(augmented)

    def test_guard_is_fail_fast_and_allows_only_corrected_parakeet_nesting(self):
        fixture = self.fixture()
        outer_path = fixture.begin("corrected")
        outer = identity.load_capture(outer_path)
        with self.assertRaises(identity.IdentityError):
            fixture.begin("development")
        nested_path = fixture.begin("parakeet", nested_token=outer["guardToken"])
        nested = identity.load_capture(nested_path)
        self.assertFalse(nested["ownsGuard"])
        identity.release_guard(nested)
        with self.assertRaises(identity.IdentityError):
            fixture.begin("development", nested_token=outer["guardToken"])
        identity.release_guard(outer)

    def test_corrupt_or_unwritable_allocator_fails_without_fallback(self):
        database = self.root / "corrupt.sqlite3"
        database.write_bytes(b"not sqlite")
        data = {
            "buildDate": "2026-09-11T00:00:00Z", "sourceCommit": "a" * 40,
            "sourceTree": "b" * 40, "productVersion": "1.0.0-beta.1",
            "flavor": "development", "configuration": "Debug",
        }
        with self.assertRaises(identity.IdentityError):
            identity.allocate(database, data)
        blocker = self.root / "file-parent"
        blocker.write_text("not a directory", encoding="utf-8")
        with self.assertRaises(identity.IdentityError):
            identity.allocate(blocker / "database.sqlite3", data)

    def test_local_begin_rejects_dirty_moving_and_unrelated_source(self):
        fixture = self.fixture()
        (fixture.repo / "dirty.txt").write_text("dirty", encoding="utf-8")
        with self.assertRaisesRegex(identity.IdentityError, "dirty"):
            fixture.begin()
        (fixture.repo / "dirty.txt").unlink()
        capture_path = fixture.begin()
        capture = identity.load_capture(capture_path)
        (fixture.repo / "base.txt").write_text("moved\n", encoding="utf-8")
        with self.assertRaisesRegex(identity.IdentityError, "dirty"):
            identity.source_state(fixture.repo, capture)
        git(fixture.repo, "checkout", "--", "base.txt")
        (fixture.repo / "moved.txt").write_text("new committed source\n", encoding="utf-8")
        git(fixture.repo, "add", "moved.txt")
        git(fixture.repo, "commit", "-qm", "Move source during packaging")
        with self.assertRaisesRegex(identity.IdentityError, "changed"):
            identity.source_state(fixture.repo, capture)
        identity.release_guard(capture)
        unrelated = subprocess.run(
            ["git", "-C", str(fixture.repo), "commit-tree", fixture.accepted_tree],
            check=True,
            text=True,
            input="Unrelated accepted source\n",
            capture_output=True,
        ).stdout.strip()
        fixture.manifest["records"][0]["source"]["commit"] = unrelated
        fixture.write_manifest()
        fixture.write_baseline(
            canonicalManifestSHA256=fixture.manifest_hash,
            acceptedSourceCommit=unrelated,
        )
        git(fixture.repo, "add", "BuildBaseline.json")
        git(fixture.repo, "commit", "-qm", "Unrelated pin")
        with self.assertRaises(identity.IdentityError):
            fixture.begin()

    def test_source_rejects_assume_unchanged_and_skip_worktree_flags(self):
        fixture = self.fixture()
        hidden_source = fixture.repo / "Sources/Hidden.swift"
        for flag, clear_flag in (
            ("--assume-unchanged", "--no-assume-unchanged"),
            ("--skip-worktree", "--no-skip-worktree"),
        ):
            git(fixture.repo, "update-index", flag, "Sources/Hidden.swift")
            hidden_source.write_text(f"let hidden = \"{flag}\"\n", encoding="utf-8")
            with self.assertRaisesRegex(
                identity.IdentityError, "assume-unchanged or skip-worktree"
            ):
                identity.source_state(fixture.repo)
            git(fixture.repo, "update-index", clear_flag, "Sources/Hidden.swift")
            git(fixture.repo, "checkout", "--", "Sources/Hidden.swift")

    def test_registry_missing_inactive_and_changed_fail_closed(self):
        fixture = self.fixture()
        baseline = identity.load_baseline(fixture.repo)
        missing = self.root / "missing"
        with self.assertRaises(identity.IdentityError):
            identity.registry_state(fixture.repo, missing, baseline)
        fixture.manifest["registryStatus"] = "inactive"
        fixture.write_manifest()
        fixture.write_baseline(canonicalManifestSHA256=fixture.manifest_hash)
        baseline = identity.load_baseline(fixture.repo)
        with self.assertRaisesRegex(identity.IdentityError, "not active"):
            identity.registry_state(fixture.repo, fixture.accepted, baseline)
        fixture.manifest["registryStatus"] = "active"
        fixture.write_manifest()
        with self.assertRaisesRegex(identity.IdentityError, "changed"):
            identity.registry_state(fixture.repo, fixture.accepted, baseline)
        (fixture.accepted / "manifest.json").write_text("{malformed", encoding="utf-8")
        malformed_digest = hashlib.sha256(b"{malformed").hexdigest()
        (fixture.accepted / "manifest.sha256").write_text(
            f"{malformed_digest}  manifest.json\n", encoding="utf-8"
        )
        baseline["canonicalManifestSHA256"] = malformed_digest
        with self.assertRaisesRegex(identity.IdentityError, "malformed"):
            identity.registry_state(fixture.repo, fixture.accepted, baseline)

    def test_replaced_exit_zero_validator_is_rejected_before_execution(self):
        fixture = self.fixture()
        baseline = identity.load_baseline(fixture.repo)
        validator = fixture.accepted / "check-accepted-build.py"
        validator.write_text("#!/usr/bin/env python3\nimport sys\nsys.exit(0)\n", encoding="utf-8")
        with self.assertRaisesRegex(identity.IdentityError, "authenticated support record"):
            identity.registry_state(fixture.repo, fixture.accepted, baseline)

    def test_mid_build_registry_mutation_fails_finish(self):
        fixture = self.fixture()
        capture_path = fixture.begin()
        capture = identity.load_capture(capture_path)
        plist_path = self.root / "registry-mutation.plist"
        with plist_path.open("wb") as handle:
            plistlib.dump(identity.plist_values(capture), handle)
        manifest_path = fixture.accepted / "manifest.json"
        manifest_path.write_bytes(manifest_path.read_bytes() + b" ")
        with self.assertRaises(identity.IdentityError):
            identity.command_finish(mock.Mock(capture=str(capture_path), plist=str(plist_path)))
        identity.release_guard(capture)

    def test_registry_fixture_is_read_only_across_begin_and_finish(self):
        fixture = self.fixture()
        before = {
            path.relative_to(fixture.accepted): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in fixture.accepted.iterdir()
        }
        capture_path = fixture.begin()
        capture = identity.load_capture(capture_path)
        plist_path = self.root / "Info.plist"
        with plist_path.open("wb") as handle:
            plistlib.dump(identity.plist_values(capture), handle)
        identity.command_finish(mock.Mock(capture=str(capture_path), plist=str(plist_path)))
        identity.release_guard(capture)
        after = {
            path.relative_to(fixture.accepted): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in fixture.accepted.iterdir()
        }
        self.assertEqual(before, after)

    def test_ci_mode_labels_candidate_and_refuses_corrected_handoff(self):
        fixture = self.fixture()
        with mock.patch.dict(os.environ, {"CI": "true", "GITHUB_ACTIONS": "true"}, clear=False):
            capture_path = fixture.begin(mode="ci-unverified")
            capture = identity.load_capture(capture_path)
            self.assertEqual(capture["baselineRegistryStatus"], "ci-unverified")
            self.assertEqual(capture["candidateStatus"], "CI unverified - not a handoff candidate")
            identity.release_guard(capture)
            with self.assertRaisesRegex(identity.IdentityError, "forbidden"):
                fixture.begin(flavor="corrected", mode="ci-unverified")

    def test_registry_injection_is_fixture_only_and_confined(self):
        self.assertEqual(
            identity.DEFAULT_ACCEPTED_ROOT,
            Path.home() / "Fleck-builds/accepted",
        )
        self.assertEqual(
            identity.DEFAULT_DATABASE,
            Path.home() / "Fleck-builds/build-metadata/identities.sqlite3",
        )
        fixture = self.fixture()
        arguments = mock.Mock(
            repo=str(fixture.repo),
            flavor="development",
            configuration="Debug",
            capture=str(fixture.repo / ".build/rejected.json"),
            mode="local",
            test_accepted_root=str(self.root / "arbitrary-accepted"),
            test_database=str(self.root / "arbitrary.sqlite3"),
            nested_token=None,
        )
        with self.assertRaisesRegex(identity.IdentityError, "test environment"):
            identity.command_begin(arguments)
        with mock.patch.dict(
            os.environ, {"FLECK_BUILD_IDENTITY_TEST_FIXTURE": "1"}, clear=False
        ):
            with self.assertRaisesRegex(identity.IdentityError, "\.identity-test"):
                identity.command_begin(arguments)
        help_text = subprocess.run(
            [str(TOOL), "begin", "--help"], check=True, text=True, capture_output=True
        ).stdout
        self.assertNotIn("--accepted-root", help_text)
        self.assertNotIn("--database ", help_text)

    def test_ci_checkout_preserves_accepted_source_ancestry(self):
        workflow = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
        checkout = workflow.index("uses: actions/checkout@")
        fetch = workflow.index("fetch-depth: 0", checkout)
        first_step_after_checkout = workflow.index("- name:", checkout)
        self.assertLess(fetch, first_step_after_checkout)
        self.assertIn('PYTHONDONTWRITEBYTECODE: "1"', workflow)
        self.assertIn("python3 -B -m unittest", workflow)
        self.assertIn("python3 -B Scripts/fleck-build-identity.py check", workflow)

    def test_python_test_preflight_does_not_leave_hidden_source_state(self):
        fixture = self.fixture()
        helper = fixture.repo / "Scripts/fleck-build-identity.py"
        import_code = (
            "import importlib.util; "
            f"s=importlib.util.spec_from_file_location('fixture_identity', {str(helper)!r}); "
            "m=importlib.util.module_from_spec(s); s.loader.exec_module(m)"
        )
        environment = os.environ.copy()
        environment.pop("PYTHONDONTWRITEBYTECODE", None)
        subprocess.run(
            [sys.executable, "-X", "pycache_prefix=", "-c", import_code],
            check=True,
            env=environment,
        )
        cache = helper.parent / "__pycache__"
        self.assertTrue(cache.is_dir())
        with self.assertRaisesRegex(identity.IdentityError, "dirty"):
            identity.source_state(fixture.repo)
        shutil.rmtree(cache)
        subprocess.run(
            [sys.executable, "-B", "-X", "pycache_prefix=", "-c", import_code],
            check=True,
            env=environment,
        )
        self.assertFalse(cache.exists())
        identity.source_state(fixture.repo)

    def test_check_requires_version_changelog_baseline_and_ordered_hooks(self):
        fixture = self.fixture()
        version, baseline = identity.check_repo(fixture.repo)
        self.assertEqual(version, "1.0.0-beta.1")
        self.assertEqual(baseline["selectedRecordID"], "fixture-accepted")
        script = fixture.repo / "Scripts/build-fleck-app.sh"
        script.write_text('"$identity_tool" begin\n"$identity_tool" finish\n', encoding="utf-8")
        with self.assertRaises(identity.IdentityError):
            identity.check_repo(fixture.repo)


if __name__ == "__main__":
    unittest.main()
