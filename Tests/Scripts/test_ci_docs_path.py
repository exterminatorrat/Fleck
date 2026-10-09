import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "Scripts/ci-docs-path.py"
WORKFLOW = ROOT / ".github/workflows/ci.yml"
SPEC = importlib.util.spec_from_file_location("ci_docs_path", HELPER)
CI_DOCS_PATH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CI_DOCS_PATH)


def git(repository, *arguments):
    return subprocess.run(
        ("git", *arguments),
        cwd=repository,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    ).stdout.decode("utf-8").strip()


def job_block(contents, job_id):
    match = re.search(rf"^  {re.escape(job_id)}:\n", contents, re.M)
    if match is None:
        raise AssertionError(f"missing CI job: {job_id}")
    following = re.search(r"^  [A-Za-z0-9_-]+:\n", contents[match.end() :], re.M)
    end = match.end() + following.start() if following else len(contents)
    return contents[match.start() : end]


def gate_script():
    aggregate = job_block(WORKFLOW.read_text(encoding="utf-8"), "macos")
    step = re.search(
        r"^      - name: Require docs-only or full current-source coverage\n",
        aggregate,
        re.M,
    )
    if step is None:
        raise AssertionError("missing final CI gate")
    run = re.search(r"^        run: \|\n", aggregate[step.start() :], re.M)
    if run is None:
        raise AssertionError("missing final CI gate shell")
    lines = aggregate[step.start() + run.end() :].splitlines()
    script = []
    for line in lines:
        if line.startswith("      - name: "):
            break
        if not line:
            script.append("")
        elif line.startswith("          "):
            script.append(line[10:])
        else:
            break
    return "\n".join(script)


GATE_SCRIPT = gate_script()


class GitFixture:
    def __init__(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.parent = Path(self.temporary.name)
        self.repository = self.parent / "repo"
        self.repository.mkdir()
        self.event_path = self.parent / "event.json"
        git(self.repository, "init")
        git(self.repository, "config", "user.name", "CI fixture")
        git(self.repository, "config", "user.email", "ci@example.invalid")
        git(self.repository, "checkout", "-b", "main")
        self.write(
            "README.md",
            "# Fleck\n\nAgent Connector documentation.\n\n[Testing](TESTING.md)\n\n"
            '<img src="Assets/icon.svg" alt="icon">\n',
        )
        self.write("VERSION", "1.0.0-beta.1\n")
        self.write(".github/workflows/ci.yml", "name: CI\n")
        self.write("Package.swift", "let package = true\n")
        self.write("Sources/App.swift", "let app = true\n")
        self.write("TESTING.md", "Testing instructions.\n")
        self.write("Assets/icon.svg", "<svg></svg>\n")
        self.commit("base")
        self.base = git(self.repository, "rev-parse", "HEAD")

    def write(self, relative_path, contents):
        path = self.repository / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(contents, bytes):
            path.write_bytes(contents)
        else:
            path.write_text(contents, encoding="utf-8")

    def commit(self, message):
        git(self.repository, "add", "--all")
        git(self.repository, "commit", "-m", message)

    def merge(self, changes=None, deletions=(), rename=None, empty_commit=False):
        git(self.repository, "checkout", "-b", "feature")
        for relative_path, contents in (changes or {}).items():
            self.write(relative_path, contents)
        for relative_path in deletions:
            (self.repository / relative_path).unlink()
        if rename is not None:
            source, destination = rename
            (self.repository / destination).parent.mkdir(parents=True, exist_ok=True)
            git(self.repository, "mv", source, destination)
        git(self.repository, "add", "--all")
        git(self.repository, "commit", "--allow-empty", "-m", "feature")
        head = git(self.repository, "rev-parse", "HEAD")
        git(self.repository, "checkout", "main")
        git(self.repository, "merge", "--no-ff", "--no-edit", "feature")
        source_commit = git(self.repository, "rev-parse", "HEAD")
        self.event_path.write_text(
            json.dumps({"pull_request": {"base": {"sha": self.base}, "head": {"sha": head}}}),
            encoding="utf-8",
        )
        return head, source_commit

    def classify(self, event_name="pull_request"):
        source_commit = git(self.repository, "rev-parse", "HEAD")
        return CI_DOCS_PATH.classify(
            self.repository,
            event_name,
            self.event_path,
            source_commit,
        )

    def close(self):
        self.temporary.cleanup()


class CIDocsPathTests(unittest.TestCase):
    def fixture(self):
        fixture = GitFixture()
        self.addCleanup(fixture.close)
        return fixture

    def gate(self, identity, route, **overrides):
        docs = route == "docs"
        environment = os.environ.copy()
        environment.update(
            {
                "GITHUB_SHA": identity["source_commit"],
                "DETECTOR_RESULT": "success",
                "ROUTE": route,
                "DETECTED_COMMIT": identity["source_commit"],
                "DETECTED_TREE": identity["source_tree"],
                "DETECTED_VERSION": identity["product_version"],
                "DETECTED_WORKFLOW_SHA256": identity["workflow_sha256"],
                "DOCS_RESULT": "success" if docs else "skipped",
                "DOCS_COMMIT": identity["source_commit"] if docs else "",
                "DOCS_TREE": identity["source_tree"] if docs else "",
                "DOCS_VERSION": identity["product_version"] if docs else "",
                "DOCS_WORKFLOW_SHA256": identity["workflow_sha256"] if docs else "",
                "INITIAL_RESULT": "skipped" if docs else "success",
                "VALIDATION_RESULT": "skipped" if docs else "success",
                "ENHANCED_RESULT": "skipped" if docs else "success",
                "INITIAL_COMMIT": "" if docs else identity["source_commit"],
                "VALIDATION_COMMIT": "" if docs else identity["source_commit"],
                "INITIAL_TREE": "" if docs else identity["source_tree"],
                "VALIDATION_TREE": "" if docs else identity["source_tree"],
                "INITIAL_VERSION": "" if docs else identity["product_version"],
                "VALIDATION_VERSION": "" if docs else identity["product_version"],
            }
        )
        environment.update(overrides)
        return subprocess.run(
            ("/bin/bash", "-c", GATE_SCRIPT),
            cwd=ROOT,
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def test_a_readme_only_change_classifies_and_passes_docs_gate_locally(self):
        fixture = self.fixture()
        fixture.merge(
            changes={
                "README.md": "# Fleck\n\nUpdated Agent Connector documentation.\n\n"
                "[Testing](TESTING.md)\n\n<img src=\"Assets/icon.svg\">\n"
            }
        )
        route, identity = fixture.classify()
        self.assertEqual(route, "docs")
        CI_DOCS_PATH.validate_documentation(
            fixture.repository,
            identity["source_commit"],
            identity,
        )
        self.assertEqual(self.gate(identity, route).returncode, 0)

    def test_b_source_change_uses_full_gate(self):
        fixture = self.fixture()
        fixture.merge(changes={"Sources/App.swift": "let app = false\n"})
        route, identity = fixture.classify()
        self.assertEqual(route, "full")
        self.assertEqual(self.gate(identity, route).returncode, 0)

    def test_c_mixed_readme_and_source_change_uses_full_gate(self):
        fixture = self.fixture()
        fixture.merge(
            changes={
                "README.md": "# Fleck\n\nUpdated Agent Connector documentation.\n",
                "Sources/App.swift": "let app = false\n",
            }
        )
        route, identity = fixture.classify()
        self.assertEqual(route, "full")
        self.assertEqual(self.gate(identity, route).returncode, 0)

    def test_d_workflow_and_configuration_changes_use_full_route(self):
        for path in (".github/workflows/ci.yml", "Package.swift"):
            with self.subTest(path=path):
                fixture = self.fixture()
                fixture.merge(changes={path: "changed configuration\n"})
                route, _ = fixture.classify()
                self.assertEqual(route, "full")

    def test_e_invalid_readme_fails_validation_and_docs_gate(self):
        fixture = self.fixture()
        fixture.merge(changes={"README.md": "# Fleck\n\nUpdated docs.\n"})
        route, identity = fixture.classify()
        self.assertEqual(route, "docs")
        with self.assertRaises(CI_DOCS_PATH.ValidationError):
            CI_DOCS_PATH.validate_documentation(
                fixture.repository,
                identity["source_commit"],
                identity,
            )
        self.assertNotEqual(
            self.gate(identity, route, DOCS_RESULT="failure").returncode,
            0,
        )

    def test_f_full_route_fails_when_any_original_job_fails(self):
        fixture = self.fixture()
        fixture.merge(changes={"Sources/App.swift": "let app = false\n"})
        route, identity = fixture.classify()
        for job in ("INITIAL_RESULT", "VALIDATION_RESULT", "ENHANCED_RESULT"):
            with self.subTest(job=job):
                self.assertNotEqual(
                    self.gate(identity, route, **{job: "failure"}).returncode,
                    0,
                )

    def test_readme_renames_deletions_and_other_paths_require_full(self):
        cases = (
            {"rename": ("README.md", "docs/README.md")},
            {"deletions": ("README.md",)},
            {"rename": ("Sources/App.swift", "README.md")},
        )
        for arguments in cases:
            with self.subTest(arguments=arguments):
                fixture = self.fixture()
                if arguments.get("rename") == ("Sources/App.swift", "README.md"):
                    (fixture.repository / "README.md").unlink()
                    git(fixture.repository, "add", "--all")
                    git(fixture.repository, "commit", "-m", "remove README before rename")
                    fixture.base = git(fixture.repository, "rev-parse", "HEAD")
                fixture.merge(**arguments)
                route, _ = fixture.classify()
                self.assertEqual(route, "full")

    def test_nul_delimited_names_are_not_interpreted_by_a_shell(self):
        fixture = self.fixture()
        filename = "Sources/odd\tname\n'\"$(touch sentinel).swift"
        fixture.merge(changes={filename: "let odd = true\n"})
        route, _ = fixture.classify()
        self.assertEqual(route, "full")
        self.assertFalse((fixture.repository / "sentinel").exists())

    def test_malformed_empty_and_unrecognized_diffs_default_to_full(self):
        for output in (
            b"",
            b"M\0README.md",
            b"Z\0README.md\0",
            b"R100\0README.md\0",
            b"M\0README.md\0M\0",
            b"M\0README.md\0M\0README.md\0",
        ):
            with self.subTest(output=output):
                self.assertEqual(CI_DOCS_PATH.classify_name_status(output), "full")
        self.assertEqual(CI_DOCS_PATH.classify_name_status(b"M\0README.md\0"), "docs")

    def test_unknown_events_missing_history_and_empty_changes_default_to_full(self):
        fixture = self.fixture()
        fixture.merge(empty_commit=True)
        route, identity = fixture.classify()
        self.assertEqual(route, "full")
        self.assertEqual(self.gate(identity, route).returncode, 0)
        self.assertEqual(fixture.classify("push")[0], "full")
        self.assertEqual(fixture.classify("workflow_dispatch")[0], "full")
        event = {"pull_request": {"base": {"sha": "f" * 40}, "head": {"sha": "0" * 40}}}
        fixture.event_path.write_text(json.dumps(event), encoding="utf-8")
        self.assertEqual(fixture.classify()[0], "full")
        fixture.event_path.write_text("not json", encoding="utf-8")
        self.assertEqual(fixture.classify()[0], "full")

    def test_docs_validation_rejects_source_and_workflow_fingerprint_drift(self):
        fixture = self.fixture()
        fixture.merge(
            changes={"README.md": "# Fleck\n\nAgent Connector documentation update.\n"}
        )
        route, identity = fixture.classify()
        self.assertEqual(route, "docs")
        for key, value in (
            ("source_commit", "0" * 40),
            ("source_tree", "0" * 40),
            ("product_version", "9.9.9"),
            ("workflow_sha256", "0" * 64),
        ):
            with self.subTest(key=key):
                expected = dict(identity, **{key: value})
                with self.assertRaises(CI_DOCS_PATH.ValidationError):
                    CI_DOCS_PATH.validate_documentation(
                        fixture.repository,
                        identity["source_commit"],
                        expected,
                    )

    def test_docs_and_full_gates_fail_closed_for_skipped_cancelled_and_missing_jobs(self):
        fixture = self.fixture()
        fixture.merge(changes={"README.md": "# Fleck\n\nAgent Connector update.\n"})
        docs_route, docs_identity = fixture.classify()
        self.assertEqual(docs_route, "docs")
        for overrides in (
            {"DETECTOR_RESULT": "failure"},
            {"DETECTOR_RESULT": "cancelled"},
            {"DOCS_RESULT": "cancelled"},
            {"DOCS_RESULT": "skipped"},
            {"INITIAL_RESULT": "success"},
            {"ROUTE": "unknown"},
            {"DETECTED_COMMIT": ""},
            {"DETECTED_TREE": ""},
            {"DETECTED_VERSION": ""},
            {"DETECTED_WORKFLOW_SHA256": ""},
            {"DOCS_COMMIT": ""},
            {"DOCS_TREE": ""},
            {"DOCS_VERSION": ""},
            {"DOCS_WORKFLOW_SHA256": ""},
        ):
            with self.subTest(overrides=overrides):
                self.assertNotEqual(
                    self.gate(docs_identity, docs_route, **overrides).returncode,
                    0,
                )

        full_fixture = self.fixture()
        full_fixture.merge(changes={"Sources/App.swift": "let app = false\n"})
        _, full_identity = full_fixture.classify()
        for overrides in (
            {"DETECTOR_RESULT": "skipped"},
            {"DETECTOR_RESULT": "cancelled"},
            {"DOCS_RESULT": "success"},
            {"INITIAL_RESULT": "skipped"},
            {"VALIDATION_RESULT": "cancelled"},
            {"ENHANCED_RESULT": "skipped"},
            {"INITIAL_COMMIT": ""},
            {"VALIDATION_TREE": ""},
            {"INITIAL_VERSION": ""},
            {"DETECTED_WORKFLOW_SHA256": "invalid"},
            {"INITIAL_COMMIT": "0" * 40},
            {"VALIDATION_TREE": "0" * 40},
            {"INITIAL_VERSION": "9.9.9"},
        ):
            with self.subTest(overrides=overrides):
                self.assertNotEqual(
                    self.gate(full_identity, "full", **overrides).returncode,
                    0,
                )

    def test_readme_requires_valid_local_markdown_and_html_references(self):
        fixture = self.fixture()
        fixture.merge(
            changes={
                "README.md": "# Fleck\n\nAgent Connector\n\n[broken](missing.md)\n"
            }
        )
        with self.assertRaises(CI_DOCS_PATH.ValidationError):
            CI_DOCS_PATH.validate_readme(fixture.repository)

        fixture.write(
            "README.md",
            "# Fleck\n\nAgent Connector\n\n<img src=\"missing.svg\">\n",
        )
        with self.assertRaises(CI_DOCS_PATH.ValidationError):
            CI_DOCS_PATH.validate_readme(fixture.repository)

    def test_readme_rejects_binary_conflicts_and_legacy_terms(self):
        fixture = self.fixture()
        for contents in (
            b"\0",
            b"\xff",
            b"Agent Connector\n<<<<<<< HEAD\n",
            b"Agent Connector\nThe MenuBar" b"Notes app\n",
            b"Agent Connector\nA command bridge\n",
        ):
            with self.subTest(contents=contents):
                fixture.write("README.md", contents)
                with self.assertRaises(CI_DOCS_PATH.ValidationError):
                    CI_DOCS_PATH.validate_readme(fixture.repository)

    def test_cli_writes_route_and_pinned_source_outputs(self):
        fixture = self.fixture()
        fixture.merge(
            changes={"README.md": "# Fleck\n\nAgent Connector documentation update.\n"}
        )
        source_commit = git(fixture.repository, "rev-parse", "HEAD")
        output = fixture.parent / "github-output.txt"
        result = subprocess.run(
            (
                sys.executable,
                "-B",
                str(HELPER),
                "classify",
                "--repository",
                str(fixture.repository),
                "--event-name",
                "pull_request",
                "--event-file",
                str(fixture.event_path),
                "--source-commit",
                source_commit,
                "--output",
                str(output),
            ),
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr.decode("utf-8"))
        values = dict(line.split("=", 1) for line in output.read_text().splitlines())
        self.assertEqual(values["route"], "docs")
        self.assertEqual(values["source_commit"], source_commit)
        identity = CI_DOCS_PATH.repository_identity(fixture.repository, source_commit)
        self.assertEqual(values["workflow_sha256"], identity["workflow_sha256"])
        validation_output = fixture.parent / "validation-output.txt"
        validation = subprocess.run(
            (
                sys.executable,
                "-B",
                str(HELPER),
                "validate",
                "--repository",
                str(fixture.repository),
                "--source-commit",
                source_commit,
                "--expected-commit",
                identity["source_commit"],
                "--expected-tree",
                identity["source_tree"],
                "--expected-version",
                identity["product_version"],
                "--expected-workflow-sha256",
                identity["workflow_sha256"],
                "--output",
                str(validation_output),
            ),
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(validation.returncode, 0, validation.stderr.decode("utf-8"))
        validated = dict(
            line.split("=", 1) for line in validation_output.read_text().splitlines()
        )
        self.assertEqual(validated, identity)

    def test_workflow_keeps_docs_gate_narrow_and_full_jobs_required(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("  pull_request:\n", workflow)
        self.assertNotIn("paths-ignore:", workflow)
        self.assertIn("permissions:\n  contents: read\n", workflow)
        detector = job_block(workflow, "detect-changes")
        docs = job_block(workflow, "docs-validation")
        build = job_block(workflow, "macos-build")
        validation = job_block(workflow, "macos-validation")
        enhanced = job_block(workflow, "macos-enhanced")
        aggregate = job_block(workflow, "macos")
        checkout = "de0fac2e4500dabe0009e67214ff5f5447ce83dd"
        for block in (detector, docs):
            self.assertIn(f"uses: actions/checkout@{checkout}", block)
            self.assertIn("persist-credentials: false", block)
            self.assertIn("fetch-depth: 0", block)
            self.assertIn("ref: ${{ github.sha }}", block)
        self.assertIn("python3 -B Scripts/ci-docs-path.py classify", detector)
        self.assertIn("python3 -B Scripts/ci-docs-path.py validate", docs)
        self.assertIn("workflow_sha256", detector)
        self.assertIn("DETECTED_WORKFLOW_SHA256", docs)
        for block in (build, validation, enhanced):
            self.assertIn("needs.detect-changes.result == 'success'", block)
            self.assertIn("outputs.route == 'full'", block)
        for forbidden in ("swift", "xcodebuild", "brew install", "package", "sign"):
            self.assertNotIn(forbidden, docs.casefold())
        self.assertIn("name: macOS build and tests", aggregate)
        self.assertIn("if: ${{ always() }}", aggregate)
        self.assertIn("DOCS_WORKFLOW_SHA256", aggregate)
        self.assertIn("test \"$DETECTED_COMMIT\" = \"$GITHUB_SHA\"", aggregate)
        self.assertIn("python3 -B -m unittest discover -s Tests/Scripts -p test_ci_docs_path.py", build)


if __name__ == "__main__":
    unittest.main()
