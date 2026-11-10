import re
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/ci.yml"

ORIGINAL_JOBS = (
    "detect-changes",
    "macos-build",
    "macos-validation",
    "docs-validation",
    "macos",
    "macos-enhanced",
    "own-window-capture-probe",
    "folder-navigator-diagnostic",
    "folder-navigator-diagnostic-enhanced",
    "ordinary-test-diagnostic",
)
QUALIFICATION_JOB = "namespace-qualification"

NATIVE_PROVIDER_RUNS_ON = (
    "${{ github.event_name == 'workflow_dispatch' && "
    "inputs.native_runner_provider == 'namespace' && "
    "'namespace-profile-fleck' || 'macos-26' }}"
)
EXPECTED_RUNS_ON = {
    "detect-changes": "namespace-profile-fleck",
    "macos-build": NATIVE_PROVIDER_RUNS_ON,
    "macos-validation": NATIVE_PROVIDER_RUNS_ON,
    "docs-validation": "namespace-profile-fleck",
    "macos": "namespace-profile-fleck",
    "macos-enhanced": NATIVE_PROVIDER_RUNS_ON,
    "own-window-capture-probe": "macos-26",
    "folder-navigator-diagnostic": "macos-26",
    "folder-navigator-diagnostic-enhanced": "macos-26",
    "ordinary-test-diagnostic": NATIVE_PROVIDER_RUNS_ON,
    QUALIFICATION_JOB: "namespace-profile-fleck",
}

ORIGINAL_CONDITIONS = {
    "detect-changes": (
        "${{ github.event_name != 'workflow_dispatch' || "
        "inputs.ordinary_test_diagnostic_selector == '' }}"
    ),
    "macos-build": (
        "${{ needs.detect-changes.result == 'success' && "
        "needs.detect-changes.outputs.route == 'full' }}"
    ),
    "macos-validation": (
        "${{ needs.detect-changes.result == 'success' && "
        "needs.detect-changes.outputs.route == 'full' }}"
    ),
    "docs-validation": "${{ needs.detect-changes.outputs.route == 'docs' }}",
    "macos": (
        "${{ always() && (github.event_name != 'workflow_dispatch' || "
        "inputs.ordinary_test_diagnostic_selector == '') }}"
    ),
    "macos-enhanced": (
        "${{ needs.detect-changes.result == 'success' && "
        "needs.detect-changes.outputs.route == 'full' }}"
    ),
    "own-window-capture-probe": (
        "${{ github.event_name == 'workflow_dispatch' && "
        "inputs.own_window_capture_probe }}"
    ),
    "folder-navigator-diagnostic": (
        "${{ github.event_name == 'workflow_dispatch' && "
        "inputs.folder_navigator_probe }}"
    ),
    "folder-navigator-diagnostic-enhanced": (
        "${{ github.event_name == 'workflow_dispatch' && "
        "inputs.folder_navigator_probe }}"
    ),
    "ordinary-test-diagnostic": (
        "${{ github.event_name == 'workflow_dispatch' && "
        "inputs.ordinary_test_diagnostic_selector != '' }}"
    ),
}


def job_block(contents, job_id):
    match = re.search(rf"^  {re.escape(job_id)}:\n", contents, re.M)
    if match is None:
        raise AssertionError(f"missing CI job: {job_id}")
    following = re.search(r"^  [A-Za-z0-9_-]+:\n", contents[match.end() :], re.M)
    end = match.end() + following.start() if following else len(contents)
    return contents[match.start() : end]


def job_if(contents, job_id):
    block = job_block(contents, job_id)
    match = re.search(r"^    if: (.+)$", block, re.M)
    if match is None:
        raise AssertionError(f"missing if for CI job: {job_id}")
    return match.group(1)


def job_runs_on(contents, job_id):
    block = job_block(contents, job_id)
    match = re.search(r"^    runs-on: (.+)$", block, re.M)
    if match is None:
        raise AssertionError(f"missing runs-on for CI job: {job_id}")
    return match.group(1)


def reduce_qualification_guard(condition):
    for guard in (
        "!inputs.namespace_qualification_only && ",
        " && !inputs.namespace_qualification_only",
    ):
        if guard in condition:
            return condition.replace(guard, "", 1)
    raise AssertionError(f"missing qualification guard: {condition}")


def normalized_expression(condition):
    expression = condition.removeprefix("${{").removesuffix("}}").strip()
    while expression.startswith("(") and expression.endswith(")"):
        expression = expression[1:-1].strip()
    return expression


def input_block(contents, input_id):
    match = re.search(rf"^      {re.escape(input_id)}:\n", contents, re.M)
    if match is None:
        raise AssertionError(f"missing workflow_dispatch input: {input_id}")
    following = re.search(
        r"^(?:      [A-Za-z0-9_-]+:|    [A-Za-z0-9_-]+:|\S)",
        contents[match.end() :],
        re.M,
    )
    end = match.end() + following.start() if following else len(contents)
    return contents[match.start() : end]


class NamespaceQualificationWorkflowTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.contents = WORKFLOW.read_text(encoding="utf-8")
        jobs = re.search(r"^jobs:\n", cls.contents, re.M)
        if jobs is None:
            raise AssertionError("missing jobs section")
        cls.job_ids = re.findall(
            r"^  ([a-z0-9-]+):\n", cls.contents[jobs.end() :], re.M
        )
        cls.qualification = job_block(cls.contents, QUALIFICATION_JOB)

    def test_dispatch_input_is_boolean_default_false(self):
        block = input_block(self.contents, "namespace_qualification_only")
        self.assertIn("required: false", block)
        self.assertIn("type: boolean", block)
        self.assertIn("default: false", block)

    def test_native_runner_provider_input_is_choice_with_exact_options(self):
        block = input_block(self.contents, "native_runner_provider")
        self.assertIn("required: false", block)
        self.assertIn("type: choice", block)
        self.assertIn("default: github-hosted", block)
        options = re.findall(r"^          - (\S+)$", block, re.M)
        self.assertEqual(options, ["github-hosted", "namespace"])

    def test_native_runner_provider_maps_three_heavy_and_one_focused_job(self):
        for job_id in (
            "macos-build",
            "macos-validation",
            "macos-enhanced",
            "ordinary-test-diagnostic",
        ):
            with self.subTest(job=job_id):
                runs_on = job_runs_on(self.contents, job_id)
                self.assertEqual(runs_on, NATIVE_PROVIDER_RUNS_ON)
                self.assertIn(
                    "github.event_name == 'workflow_dispatch'", runs_on
                )
                self.assertIn(
                    "inputs.native_runner_provider == 'namespace'", runs_on
                )
                self.assertIn("'namespace-profile-fleck'", runs_on)
                self.assertIn("|| 'macos-26'", runs_on)
        namespace_jobs = [
            job_id
            for job_id in ORIGINAL_JOBS
            if job_runs_on(self.contents, job_id) == NATIVE_PROVIDER_RUNS_ON
        ]
        self.assertEqual(
            namespace_jobs,
            [
                "macos-build",
                "macos-validation",
                "macos-enhanced",
                "ordinary-test-diagnostic",
            ],
        )
        for job_id in ORIGINAL_JOBS:
            with self.subTest(job=job_id):
                self.assertNotIn(
                    "namespace-profile-exterminatorrat",
                    job_runs_on(self.contents, job_id),
                )

    def test_all_other_runs_on_values_are_unchanged(self):
        for job_id, expected in EXPECTED_RUNS_ON.items():
            with self.subTest(job=job_id):
                self.assertEqual(job_runs_on(self.contents, job_id), expected)

    def test_job_inventory_preserves_existing_jobs(self):
        self.assertEqual(
            set(self.job_ids), set(ORIGINAL_JOBS) | {QUALIFICATION_JOB}
        )
        self.assertEqual(len(self.job_ids), len(set(self.job_ids)))

    def test_every_original_job_skips_qualification_runs(self):
        for job_id in ORIGINAL_JOBS:
            with self.subTest(job=job_id):
                condition = job_if(self.contents, job_id)
                self.assertIn("!inputs.namespace_qualification_only", condition)
                self.assertTrue(
                    condition.startswith(
                        "${{ !inputs.namespace_qualification_only && "
                    )
                    or condition.endswith(
                        " && !inputs.namespace_qualification_only }}"
                    ),
                    condition,
                )

    def test_default_mode_reduces_to_previous_gate(self):
        for job_id, previous in ORIGINAL_CONDITIONS.items():
            with self.subTest(job=job_id):
                reduced = reduce_qualification_guard(
                    job_if(self.contents, job_id)
                )
                self.assertEqual(
                    normalized_expression(reduced),
                    normalized_expression(previous),
                )

    def test_qualification_job_is_the_only_dispatch_route(self):
        condition = job_if(self.contents, QUALIFICATION_JOB)
        self.assertIn("github.event_name == 'workflow_dispatch'", condition)
        self.assertIn("inputs.namespace_qualification_only", condition)
        self.assertNotIn("!", condition)

    def test_qualification_job_uses_exact_runner_and_timeout(self):
        self.assertIn(
            "runs-on: namespace-profile-fleck\n", self.qualification
        )
        self.assertNotIn("namespace-profile-exterminatorrat", self.qualification)
        self.assertNotIn("macos-26", self.qualification)
        timeouts = re.findall(
            r"^    timeout-minutes: (\d+)$", self.qualification, re.M
        )
        self.assertEqual(timeouts, ["5"])

    def test_qualification_job_has_no_requires_or_checkout(self):
        self.assertNotRegex(self.qualification, r"(?m)^    needs:")
        self.assertNotIn("actions/checkout", self.qualification)
        self.assertNotIn("uses:", self.qualification)
        self.assertNotIn("secrets.", self.qualification)
        self.assertIn("permissions:\n      contents: read\n", self.qualification)
        self.assertNotIn("contents: write", self.qualification)

    def test_qualification_job_reports_bounded_metadata(self):
        for expected in (
            "$GITHUB_SHA",
            "$RUNNER_OS",
            "$RUNNER_ARCH",
            "$RUNNER_NAME",
            "sw_vers",
            "uname -m",
            "xcodebuild -version",
            "swift --version",
            "xcrun --show-sdk-version",
            "xcrun --show-sdk-path",
            'launchctl print "gui/$(id -u)" >/dev/null 2>&1',
            "sudo -n -l /usr/bin/pmset -a displaysleep 0 sleep 0",
            "pmset permission query",
            "command -v brew",
            "brew --version",
            "command -v rg",
            "rg --version",
            'HOMEBREW_NO_AUTO_UPDATE: "1"',
        ):
            with self.subTest(expected=expected):
                self.assertIn(expected, self.qualification)

    def test_brew_version_captures_output_without_head_pipeline(self):
        self.assertIn('brew_version="$(brew --version)"', self.qualification)
        self.assertIn(r"${brew_version%%$'\n'*}", self.qualification)
        self.assertNotIn("brew --version | head", self.qualification)

    def test_qualification_job_fails_clearly_off_macos_arm64(self):
        for expected in (
            '"$RUNNER_OS" != "macOS"',
            '"$RUNNER_ARCH" != "ARM64"',
            '"$(uname -s)" != "Darwin"',
            '"$(uname -m)" != "arm64"',
            "qualification requires macOS arm64",
            "exit 1",
        ):
            with self.subTest(expected=expected):
                self.assertIn(expected, self.qualification)

    def test_qualification_job_is_metadata_only(self):
        for forbidden in (
            "actions/checkout",
            "git ",
            "brew install",
            "brew upgrade",
            "brew update",
            "brew tap",
            "npm ",
            "pip install",
            "swift build",
            "swift test",
            "swift run",
            "swift package",
            "xcodebuild build",
            "xcodebuild test",
            "xcodebuild clean",
            "sudo -n pmset",
            "pmset sleepnow",
            "pmset -g",
            "pmset -b",
            "pmset -c",
            "printenv",
            "set -x",
            "security ",
            "dscl",
            "dseditgroup",
            "whoami",
            "id -un",
            "osascript",
            "launchctl load",
            "launchctl bootstrap",
            "launchctl bootout",
            "launchctl kickstart",
            "curl ",
            "wget ",
            "defaults write",
        ):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, self.qualification)
        for line in self.qualification.splitlines():
            stripped = line.strip()
            with self.subTest(line=stripped):
                self.assertFalse(stripped.startswith("pmset "), stripped)
                self.assertFalse(stripped.startswith("sudo -n pmset "), stripped)

    def test_concurrency_isolates_qualification_runs(self):
        match = re.search(r"^  group: (.+)$", self.contents, re.M)
        self.assertIsNotNone(match)
        group = match.group(1)
        self.assertIn(
            "inputs.namespace_qualification_only && 'namespace-qualification-'",
            group,
        )
        self.assertIn("'focused-'", group)
        self.assertIn("github.event.pull_request.number || github.ref", group)
        self.assertIn(
            "cancel-in-progress: ${{ github.event_name == 'pull_request' }}",
            self.contents,
        )

    def test_native_provider_concurrency_is_separate_from_queued_github_runs(self):
        match = re.search(r"^  group: (.+)$", self.contents, re.M)
        self.assertIsNotNone(match)
        self.assertEqual(
            match.group(1),
            "ci-${{ github.event_name == 'workflow_dispatch' && "
            "inputs.namespace_qualification_only && 'namespace-qualification-' || "
            "github.event_name == 'workflow_dispatch' && "
            "inputs.ordinary_test_diagnostic_selector != '' && 'focused-' || "
            "github.event_name == 'workflow_dispatch' && "
            "inputs.native_runner_provider == 'namespace' && 'namespace-native-' || '' }}"
            "${{ github.event.pull_request.number || github.ref }}",
        )

    def test_normal_run_conditions_retain_previous_behavior(self):
        self.assertIn(
            "github.event_name != 'workflow_dispatch' || "
            "inputs.ordinary_test_diagnostic_selector == ''",
            job_if(self.contents, "detect-changes"),
        )
        self.assertIn("always()", job_if(self.contents, "macos"))
        self.assertIn(
            "needs.detect-changes.result == 'success'",
            job_if(self.contents, "macos-build"),
        )
        self.assertIn(
            "needs.detect-changes.outputs.route == 'full'",
            job_if(self.contents, "macos-validation"),
        )
        self.assertIn(
            "needs.detect-changes.outputs.route == 'full'",
            job_if(self.contents, "macos-enhanced"),
        )
        self.assertIn(
            "needs.detect-changes.outputs.route == 'docs'",
            job_if(self.contents, "docs-validation"),
        )
        self.assertIn(
            "inputs.own_window_capture_probe",
            job_if(self.contents, "own-window-capture-probe"),
        )
        for job_id in (
            "folder-navigator-diagnostic",
            "folder-navigator-diagnostic-enhanced",
        ):
            with self.subTest(job=job_id):
                self.assertIn(
                    "inputs.folder_navigator_probe", job_if(self.contents, job_id)
                )
        self.assertIn(
            "inputs.ordinary_test_diagnostic_selector != ''",
            job_if(self.contents, "ordinary-test-diagnostic"),
        )


if __name__ == "__main__":
    unittest.main()
