import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "ci_select_runner", ROOT / "Scripts/ci-select-runner.py"
)
SELECT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SELECT)

PROBE = "Namespace capacity probe"


class FakeClock:
    def __init__(self):
        self.now = 0.0

    def clock(self):
        return self.now

    def sleep(self, seconds):
        self.now += seconds


def run_automatic(states, timeout=120, interval=5):
    fake = FakeClock()
    remaining = list(states)

    def observe():
        return remaining.pop(0) if len(remaining) > 1 else remaining[0]

    selection = SELECT.select_automatic(observe, fake.clock, fake.sleep, timeout, interval)
    return selection, fake.now


class ProbeStateTests(unittest.TestCase):
    def job(self, status, conclusion=None, name=PROBE):
        return {"name": name, "status": status, "conclusion": conclusion}

    def test_missing_or_queued_probe_is_not_started(self):
        self.assertFalse(SELECT.parse_probe_state([], PROBE).started)
        self.assertFalse(SELECT.parse_probe_state([self.job("queued")], PROBE).started)
        self.assertFalse(SELECT.parse_probe_state([self.job("waiting")], PROBE).started)

    def test_running_or_finished_probe_is_started(self):
        self.assertTrue(SELECT.parse_probe_state([self.job("in_progress")], PROBE).started)
        self.assertTrue(
            SELECT.parse_probe_state([self.job("completed", "success")], PROBE).started
        )
        self.assertTrue(
            SELECT.parse_probe_state([self.job("completed", "failure")], PROBE).started
        )

    def test_skipped_or_cancelled_probe_is_unobservable(self):
        for conclusion in ("skipped", "cancelled"):
            self.assertIsNone(
                SELECT.parse_probe_state([self.job("completed", conclusion)], PROBE)
            )

    def test_other_jobs_are_ignored(self):
        jobs = [self.job("in_progress", name="Detect documentation-only changes")]
        self.assertFalse(SELECT.parse_probe_state(jobs, PROBE).started)


class AutomaticSelectionTests(unittest.TestCase):
    started = SELECT.ProbeState(started=True)
    queued = SELECT.ProbeState(started=False)

    def test_probe_that_starts_immediately_keeps_namespace_without_waiting(self):
        selection, elapsed = run_automatic([self.started])
        self.assertEqual(selection.runner, SELECT.NAMESPACE_RUNNER)
        self.assertEqual(elapsed, 0)

    def test_probe_that_starts_late_keeps_namespace(self):
        selection, elapsed = run_automatic([self.queued] * 3 + [self.started])
        self.assertEqual(selection.runner, SELECT.NAMESPACE_RUNNER)
        self.assertEqual(elapsed, 15)

    def test_probe_still_queued_at_timeout_falls_back_to_github_hosted(self):
        selection, elapsed = run_automatic([self.queued])
        self.assertEqual(selection.runner, SELECT.GITHUB_HOSTED_RUNNER)
        self.assertEqual(elapsed, 120)
        self.assertIn("120 seconds", selection.reason)

    def test_unavailable_status_throughout_keeps_namespace(self):
        selection, _ = run_automatic([None])
        self.assertEqual(selection.runner, SELECT.NAMESPACE_RUNNER)

    def test_transient_errors_followed_by_queued_probe_still_fall_back(self):
        selection, _ = run_automatic([None, None, self.queued])
        self.assertEqual(selection.runner, SELECT.GITHUB_HOSTED_RUNNER)


class ManualSelectionTests(unittest.TestCase):
    def test_manual_provider_is_honoured_without_probing(self):
        self.assertEqual(
            SELECT.select_manual("github-hosted").runner, SELECT.GITHUB_HOSTED_RUNNER
        )
        self.assertEqual(SELECT.select_manual("namespace").runner, SELECT.NAMESPACE_RUNNER)
        self.assertEqual(SELECT.select_manual("").runner, SELECT.NAMESPACE_RUNNER)


class CommandLineTests(unittest.TestCase):
    def test_manual_dispatch_writes_outputs_and_summary(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "output"
            summary = Path(directory) / "summary"
            status = SELECT.main(
                [
                    "--event-name", "workflow_dispatch",
                    "--manual-provider", "github-hosted",
                    "--repository", "owner/repo",
                    "--run-id", "1",
                    "--run-attempt", "1",
                    "--probe-job-name", PROBE,
                    "--output", str(output),
                    "--summary", str(summary),
                ]
            )
            self.assertEqual(status, 0)
            self.assertIn("runner=macos-26\n", output.read_text())
            self.assertIn("macos-26", summary.read_text())


if __name__ == "__main__":
    unittest.main()
