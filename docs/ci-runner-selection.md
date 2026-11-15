# CI runner selection

Required macOS CI normally runs on the Namespace runner profile
`namespace-profile-fleck`. When Namespace has no macOS capacity, jobs stay
queued and the pull request waits. The `CI` workflow detects this and runs the
macOS jobs on GitHub-hosted `macos-26` instead.

## How it works

For `push` and `pull_request` events, two jobs start together:

| Job | Runner | Purpose |
| --- | --- | --- |
| `Namespace capacity probe` | `namespace-profile-fleck` | Does nothing except start. Its start time shows whether Namespace has capacity. |
| `Select CI runner` | `ubuntu-latest` | Polls the probe job through the Actions API for up to 120 seconds. |

`Select CI runner` publishes one runner label:

- The probe started within 120 seconds: `namespace-profile-fleck`.
- The probe is still queued after 120 seconds: `macos-26`, with a workflow
  warning and a step summary that names the reason.
- The Actions API could not be read: `namespace-profile-fleck`, the previous
  behavior, so a selector fault never blocks CI.

`detect-changes` runs on the selected runner and passes the label to
`macos-build`, `macos-validation`, `macos-enhanced`, `docs-validation` and
`macos`. Each of them falls back to `namespace-profile-fleck` when the label is
empty.

A probe left queued during an outage starts later and exits at once. It does
not affect any result, but the workflow run stays open until it finishes.

## Manual runs

`workflow_dispatch` skips the probe. The `native_runner_provider` input decides
directly: `namespace` (default) or `github-hosted`. The focused
`ordinary-test-diagnostic` job keeps its own manual routing.

## Changing the behavior

- The decision logic is in `Scripts/ci-select-runner.py`. Its tests are in
  `Tests/Scripts/test_ci_select_runner.py`.
- The probe window and poll interval are the `--timeout-seconds` and
  `--interval-seconds` arguments of the `Choose Namespace or GitHub-hosted
  macOS` step in `.github/workflows/ci.yml`.
- The workflow contract is checked by
  `Tests/Scripts/test_ci_namespace_qualification.py` and
  `Scripts/test-nonempty-swift-test-runners.sh`. Both must change with the
  workflow.

## Limits

- GitHub-hosted macOS minutes and queue time are separate from Namespace and
  can be limited too.
- A Namespace outage shorter than 120 seconds is not detected.
- The selection is made once per run. A rerun of failed jobs reuses the earlier
  label; rerun the whole workflow to select again.
