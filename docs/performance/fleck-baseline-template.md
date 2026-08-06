# Fleck performance baseline

Status: **TEMPLATE — no baseline measurement captured yet.** Replace bracketed
fields only with observations from the exact QA build and machine. Do not
invent timing, memory, CPU, or disk-write values.

## Scope and safety

- Synthetic datasets: exactly 10-note, 100-note, and 1,000-note workspaces.
- Fixture note IDs and dates are deterministic; titles and bodies contain only
  synthetic text.
- Automated tests use temporary directories and remove them after each run.
- The baseline describes current behavior. It does not optimize saving,
  debounce, hashing, atomicity, recovery, UI, or launch behavior.
- Do not open, copy, or include user note contents. The profile output must not
  be inside `~/Library/Application Support/Fleck/`.

## Environment

| Field | Value |
| --- | --- |
| Measurement status | `[not captured]` |
| Machine/model | `[record machine]` |
| Architecture | `[arm64 / x86_64]` |
| macOS version/build | `[record]` |
| Xcode version | `[record]` |
| Swift version | `[record]` |
| Commit | `[record full SHA]` |
| Build configuration | `Release` |
| QA app/artifact path | `[record exact path]` |
| Output directory | `[record; disposable and outside Fleck Application Support]` |

## Commands

```sh
swift test --disable-automatic-resolution --no-parallel --filter FleckPerformance
bash -n Scripts/profile-fleck-performance.sh
Scripts/profile-fleck-performance.sh "/absolute/path/to/disposable-output"
FLECK_PERFORMANCE_PID=PID Scripts/profile-fleck-performance.sh \
  "/absolute/path/to/disposable-output"
```

Run `shellcheck Scripts/profile-fleck-performance.sh` when `shellcheck` is
installed; record its absence rather than treating it as captured evidence.
Record the exact `Scripts/build-fleck-app.sh` command and the exact manual
`/usr/bin/open -n .build/Fleck.app` command used for the QA app.

## Measurement method and packaged-app boundary

The script builds the release Fleck executable, records host/toolchain/commit
metadata, samples a caller-specified Fleck PID for idle CPU and resident memory,
and records an aggregate `iostat` sample. It never launches or terminates a
process and never reads, copies, moves, or deletes the user's Fleck
Application Support directory.

The current production store has no safe test-root override. Therefore the
packaged app must be launched manually from a disposable macOS account or an
otherwise isolated QA environment. If that boundary cannot be provided, leave
launch, panel presentation, note switching, typing, and save measurements as
`[not captured]`; a build or source review is not runtime evidence.

Use Instruments or another approved macOS measurement tool on the manually
launched QA PID for logical disk writes. The script's aggregate disk sample is
only context and must not be reported as Fleck-only logical writes.

## Panel presentation measurement

The packaged-app loop measures `AX-press-to-accessible-visible`: from the exact
Fleck status-item `AXPress` invocation to the first matching transient panel
window becoming accessibility-visible. This is not pixel-complete and is not
human click latency. It records one cold sample followed by 30 warm samples
from an already-running exact packaged Fleck process, and reports raw samples
plus p50, p95, minimum, and maximum values. It does not use app-side log
polling or activation timing, and never reads or writes Fleck Application
Support or editor data.

Before running it, grant the calling Terminal or agent System Events
Accessibility permission in System Settings → Privacy & Security →
Accessibility, launch the exact packaged Fleck app manually, and record its PID.
The script locates exactly one real Fleck `AXMenuExtra` by iterating every menu
bar of the Fleck application process and requiring title/name `Fleck`, role
`AXMenuBarItem`, and subrole `AXMenuExtra`. Before every sample it checks for a
matching accessible-visible transient window, toggles the exact item only when
needed to normalize the panel closed, and verifies that it is closed. It then
uses one JXA process and `Date.now` to wait for the first matching `AXWindow`
with subrole `AXSystemDialog` or `AXDialog` and sane dimensions. Missing,
ambiguous, or timed-out states fail closed. It does not launch, terminate,
rebuild, signal, or otherwise mutate Fleck.

```sh
bash -n Scripts/measure-fleck-panel-presentation.sh
FLECK_PERFORMANCE_PID=PID Scripts/measure-fleck-panel-presentation.sh \
  "/absolute/path/to/disposable-output"
```

The output directory must already exist, be outside Fleck Application Support,
and not be a symlink. The caller must grant System Events Accessibility to the
Terminal or agent and supply the PID of the already-running exact packaged
Fleck app. Leave the packaged measurement as `[not captured]` until this exact
loop has been run against the accepted QA artifact.

## Results

Record median (p50), p95, and peak where applicable. Use the same run protocol
for the 10-note, 100-note, and 1,000-note fixtures. Values below are blank by
design.

| Measurement | 10-note p50 | 10-note p95 | 100-note p50 | 100-note p95 | 1,000-note p50 | 1,000-note p95 | Peak/notes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Cold launch | `[not captured]` | `[not captured]` | `[not captured]` | `[not captured]` | `[not captured]` | `[not captured]` | `[record]` |
| Warm launch | `[not captured]` | `[not captured]` | `[not captured]` | `[not captured]` | `[not captured]` | `[not captured]` | `[record]` |
| Panel presentation | `[not captured]` | `[not captured]` | `[not captured]` | `[not captured]` | `[not captured]` | `[not captured]` | `[record]` |
| Note switching | `[not captured]` | `[not captured]` | `[not captured]` | `[not captured]` | `[not captured]` | `[not captured]` | `[record]` |
| Typing latency | `[not captured]` | `[not captured]` | `[not captured]` | `[not captured]` | `[not captured]` | `[not captured]` | `[record]` |
| Save duration | `[not captured]` | `[not captured]` | `[not captured]` | `[not captured]` | `[not captured]` | `[not captured]` | `[record]` |
| Logical disk writes | `[not captured]` | `[not captured]` | `[not captured]` | `[not captured]` | `[not captured]` | `[not captured]` | `[record bytes/blocks]` |
| Idle CPU | `[not captured]` | `[not captured]` | `[not captured]` | `[not captured]` | `[not captured]` | `[not captured]` | `[record %]` |
| Resident memory | `[not captured]` | `[not captured]` | `[not captured]` | `[not captured]` | `[not captured]` | `[not captured]` | `[record MB]` |

## Artifact and target checks

| Artifact/resource | Result |
| --- | --- |
| Release executable size | `[not captured]` bytes; target is at or below 15 MB where practical |
| Ordinary idle RSS | `[not captured]` MB; target is below 75 MB |
| QA app signed/packaged | `[not captured]` |
| Logical disk-write tool/output | `[not captured]` |

## Current persistence characterization

`FleckPerformanceCurrentBaselineSaveRewritesUnchangedNoteBodies` records the
current save path rewriting an unchanged `.md` body when another note changes.
This is baseline behavior, not a desired invariant. A later persistence
optimization may deliberately invert this regression test only under a
separately authorized packet and with before/after correctness and performance
evidence.

## Limitations and evidence links

- `[record unverified simulator/device/auth/packaging boundary]`
- `[record whether launch, panel presentation, note switching, typing, save,
  logical disk writes, idle CPU, and resident memory were actually captured]`
- `[link or path to sanitized Instruments/Activity Monitor output]`
- `[record any tool failure, shellcheck absence, or incomplete run]`
