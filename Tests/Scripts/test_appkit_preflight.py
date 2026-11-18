import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
RUNNER = (ROOT / "Scripts/run-swift-tests-with-appkit-host.sh").read_text()
VALIDATION = RUNNER[
    RUNNER.index('readonly preflight_regex='):RUNNER.index('prebuilt_mode=0')
]
EXECUTION = RUNNER[RUNNER.index('readonly list_output='):]
TARGET = "FleckAppTests.doubleClickSelectsTheWordUnderThePointer(usePlainTextView:)"
SELECTOR = r"^FleckAppTests\.doubleClick.*$"
MOCK_HOST = r'''
launch_host() {
  local phase="$1"
  shift
  printf '%s\t%s\n' "$phase" "$*" >> "$state_dir/trace"
  if [[ "$phase" = list ]]; then
    printf '%s\n' "$FIXTURE_IDENTIFIERS"
    return 0
  fi
  if [[ "$phase" = "${FIXTURE_FAIL_PHASE:-}" ]]; then
    printf '%s\n' '✘ Test run with 1 test in 0 suites failed after 0.001 seconds with 1 issue.'
    return 37
  fi
  if [[ "$phase" = "${FIXTURE_EMPTY_PHASE:-}" ]]; then
    printf '%s\n' '✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.'
    return 0
  fi
  printf '%s\n' '✔ Test run with 1 test in 0 suites passed after 0.001 seconds.'
}
'''


class AppKitPreflightTests(unittest.TestCase):
    def run_fixture(self, preflight=None, fail_phase="", empty_phase="", request="^.+$"):
        # Execute the runner's actual validation and post-build phase code. Only
        # LaunchServices is replaced, so these controls also run without macOS.
        with tempfile.TemporaryDirectory(prefix="fleck-preflight-") as directory:
            env = os.environ.copy()
            env.pop("FLECK_TEST_APPKIT_PREFLIGHT_SELECTOR", None)
            env.update(
                state_dir=directory,
                identifier_regex=request,
                FIXTURE_IDENTIFIERS=f"{TARGET}\nFleckCoreTests.unrelated()",
                FIXTURE_FAIL_PHASE=fail_phase,
                FIXTURE_EMPTY_PHASE=empty_phase,
            )
            if preflight is not None:
                env["FLECK_TEST_APPKIT_PREFLIGHT_SELECTOR"] = preflight
            result = subprocess.run(
                ["/bin/bash", "-c", "set -euo pipefail\n" + MOCK_HOST + VALIDATION + EXECUTION],
                env=env, text=True, capture_output=True,
            )
            trace = Path(directory, "trace")
            calls = [line.split("\t", 1) for line in trace.read_text().splitlines()] if trace.exists() else []
            return result, calls

    def test_unset_preflight_preserves_single_full_run(self):
        result, calls = self.run_fixture()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([phase for phase, _ in calls], ["list", "run"])
        self.assertEqual(calls[-1][1], "--filter ^.+$ --no-parallel")

    def test_unset_preflight_preserves_focused_request(self):
        result, calls = self.run_fixture(request=r"^FleckCoreTests\.unrelated\(\)$")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([phase for phase, _ in calls], ["list", "run"])
        self.assertEqual(
            calls[-1][1], r"--filter ^(FleckCoreTests\.unrelated\(\)/) --no-parallel",
        )
        self.assertIn("matched test count: 1", result.stdout)

    def test_passing_preflight_reuses_list_and_keeps_full_filter(self):
        result, calls = self.run_fixture(SELECTOR)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([phase for phase, _ in calls], ["list", "preflight", "run"])
        self.assertIn(r"doubleClickSelectsTheWordUnderThePointer\(usePlainTextView:\)/", calls[1][1])
        self.assertNotIn("unrelated", calls[1][1])
        self.assertEqual(calls[-1][1], "--filter ^.+$ --no-parallel")
        self.assertIn("matched test count: 1", result.stdout)
        self.assertIn("matched test count: 2", result.stdout)

    def test_failing_preflight_propagates_and_stops_full_run(self):
        result, calls = self.run_fixture(SELECTOR, fail_phase="preflight")
        self.assertEqual(result.returncode, 37)
        self.assertEqual([phase for phase, _ in calls], ["list", "preflight"])

    def test_zero_match_preflight_stops_before_execution(self):
        result, calls = self.run_fixture(r"^FleckAppTests\.missing\(\)$")
        self.assertEqual(result.returncode, 3)
        self.assertEqual([phase for phase, _ in calls], ["list"])
        self.assertIn("matched zero tests", result.stderr)

    def test_invalid_or_unbounded_preflight_fails_before_listing(self):
        for selector in ("", "unanchored", "^[$", "^.+$", "^.*$", "^" + "a" * 160 + "$"):
            with self.subTest(selector=selector):
                result, calls = self.run_fixture(selector)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(calls, [])

    def test_preflight_cannot_replace_a_focused_request(self):
        result, calls = self.run_fixture(SELECTOR, request=SELECTOR)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(calls, [])

    def test_preflight_keeps_nonempty_completion_gate(self):
        result, calls = self.run_fixture(SELECTOR, empty_phase="preflight")
        self.assertEqual(result.returncode, 1)
        self.assertEqual([phase for phase, _ in calls], ["list", "preflight"])
        self.assertIn("without a final non-empty passing test summary", result.stderr)

    def test_passing_preflight_does_not_mask_full_run_failure(self):
        result, calls = self.run_fixture(SELECTOR, fail_phase="run")
        self.assertEqual(result.returncode, 37)
        self.assertEqual([phase for phase, _ in calls], ["list", "preflight", "run"])


if __name__ == "__main__":
    unittest.main()
