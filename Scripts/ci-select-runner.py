#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys
import time
from dataclasses import dataclass

NAMESPACE_RUNNER = "namespace-profile-fleck"
GITHUB_HOSTED_RUNNER = "macos-26"
STARTED_STATUSES = frozenset({"in_progress"})
STARTED_CONCLUSIONS = frozenset({"success", "failure"})
UNOBSERVABLE_CONCLUSIONS = frozenset({"skipped", "cancelled"})


@dataclass(frozen=True)
class Selection:
    runner: str
    reason: str
    fallback: bool = False


@dataclass(frozen=True)
class ProbeState:
    started: bool


def select_manual(provider):
    if provider == "github-hosted":
        return Selection(GITHUB_HOSTED_RUNNER, "manual dispatch selected GitHub-hosted")
    return Selection(NAMESPACE_RUNNER, "manual dispatch selected Namespace")


def parse_probe_state(jobs, probe_job_name):
    for job in jobs:
        if job.get("name") != probe_job_name:
            continue
        status = job.get("status")
        conclusion = job.get("conclusion")
        if status == "completed" and conclusion in UNOBSERVABLE_CONCLUSIONS:
            return None
        started = status in STARTED_STATUSES or (
            status == "completed" and conclusion in STARTED_CONCLUSIONS
        )
        return ProbeState(started=started)
    return ProbeState(started=False)


def select_automatic(observe, clock, sleep, timeout_seconds, interval_seconds):
    deadline = clock() + timeout_seconds
    observed = False
    while True:
        state = observe()
        if state is not None:
            observed = True
            if state.started:
                return Selection(NAMESPACE_RUNNER, "Namespace started the capacity probe")
        if clock() >= deadline:
            break
        sleep(interval_seconds)
    if not observed:
        return Selection(
            NAMESPACE_RUNNER,
            "probe status was unavailable, so the default Namespace runner is kept",
        )
    return Selection(
        GITHUB_HOSTED_RUNNER,
        f"Namespace did not start the capacity probe within {timeout_seconds} seconds",
        fallback=True,
    )


def fetch_jobs(repository, run_id, run_attempt):
    completed = subprocess.run(
        (
            "gh",
            "api",
            "--paginate",
            f"repos/{repository}/actions/runs/{run_id}/attempts/{run_attempt}/jobs",
            "--jq",
            ".jobs[] | {name, status, conclusion}",
        ),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        return None
    return [json.loads(line) for line in completed.stdout.decode().splitlines() if line]


def write_outputs(path, selection):
    with open(path, "a", encoding="utf-8") as handle:
        handle.write(f"runner={selection.runner}\n")
        handle.write(f"reason={selection.reason}\n")


def announce(selection, summary_path):
    line = f"Runner selected: {selection.runner} ({selection.reason})"
    print(line)
    if selection.fallback:
        print(f"::warning title=Namespace fallback::{line}")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as handle:
            handle.write(f"### CI runner selection\n\n{line}\n")


def parse_arguments(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--event-name", required=True)
    parser.add_argument("--manual-provider", default="")
    parser.add_argument("--repository", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--run-attempt", required=True)
    parser.add_argument("--probe-job-name", required=True)
    parser.add_argument("--timeout-seconds", type=int, default=120)
    parser.add_argument("--interval-seconds", type=int, default=5)
    parser.add_argument("--output", required=True)
    parser.add_argument("--summary", default="")
    return parser.parse_args(argv)


def main(argv):
    arguments = parse_arguments(argv)
    if arguments.event_name == "workflow_dispatch":
        selection = select_manual(arguments.manual_provider)
    else:

        def observe():
            jobs = fetch_jobs(arguments.repository, arguments.run_id, arguments.run_attempt)
            if jobs is None:
                return None
            return parse_probe_state(jobs, arguments.probe_job_name)

        selection = select_automatic(
            observe,
            time.monotonic,
            time.sleep,
            arguments.timeout_seconds,
            arguments.interval_seconds,
        )
    write_outputs(arguments.output, selection)
    announce(selection, arguments.summary)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
