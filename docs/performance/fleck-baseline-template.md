# Fleck performance baseline

Status: **Synthetic Phase 2 persistence observations captured; packaged-app
measurements remain unrecorded.** Replace bracketed fields only with
observations from the exact QA build and machine. Do not invent timing, memory,
CPU, or disk-write values.

## Scope and safety

- Synthetic datasets: exactly 10-note, 100-note, and 1,000-note workspaces.
- Fixture note IDs and dates are deterministic; titles and bodies contain only
  synthetic text.
- Automated tests use temporary directories and remove them after each run.
- The baseline describes current behavior. The Phase 2 synthetic section below
  characterizes measured live-root content writes before and after the narrowly
  scoped persistence optimization. It does not replace packaged-app evidence
  or optimize debounce, UI, or launch behavior.
- Do not open, copy, or include user note contents. The profile output must not
  be inside `~/Library/Application Support/Fleck/`.

## Environment

| Field | Value |
| --- | --- |
| Measurement status | Synthetic persistence before/after captured; packaged-app measurements not captured |
| Machine/model | MacBookPro17,1 |
| Architecture | arm64 |
| macOS version/build | 26.2 / 25C56 |
| Xcode version | Xcode 26.6 / 17F113 |
| Swift version | Apple Swift 6.3.3 / swift-driver 1.148.6 |
| Commit | `675d0909ee1585820ac270baceae92e22a5f9f2f` plus uncommitted Phase 2 changes |
| Build configuration | Debug SwiftPM tests for synthetic observations |
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

The packaged-app loop measures `AX-press-to-accessible-window`: from the exact
Fleck status-item `AXPress` invocation to the first matching transient panel
window exposed in Fleck's process window list. Window-list membership is the
observed accessibility-exposed criterion; the loop does not require `AXVisible`.
This is not pixel-complete and is not human click latency. It records one cold
sample followed by 30 warm samples from an already-running Fleck process, and
reports raw samples plus p50, p95, minimum, and maximum values. It does not use
app-side log polling or activation timing, and never reads or writes Fleck
Application Support or editor data.

Before running it, grant the calling Terminal or agent System Events
Accessibility permission in System Settings → Privacy & Security →
Accessibility, launch the exact packaged Fleck app manually, and record its PID.
The PID guard validates only a packaged executable path shape
(`Fleck.app/Contents/MacOS/Fleck`); it does not prove that the process is the
accepted build, so retain the launch artifact identity separately.
The script locates exactly one real Fleck `AXMenuExtra` by iterating every menu
bar of the Fleck application process and requiring title/name `Fleck`, role
`AXMenuBarItem`, and subrole `AXMenuExtra`. Before every sample it checks for a
matching sane-size transient window in the process window list, toggles the
exact item only when that window is present to normalize the panel closed, and
verifies that it disappears. It then uses one JXA process and `Date.now` to
wait for the first matching `AXWindow` with subrole `AXSystemDialog` or
`AXDialog` and sane dimensions. Missing, ambiguous, or timed-out states fail
closed; a failed AX transition receives a bounded best-effort close attempt
without replacing the original error. It does not launch, terminate, rebuild,
signal, or otherwise control Fleck's process lifecycle. It intentionally toggles
panel presentation state with AXPress, but does not mutate note/editor or Fleck
Application Support data. Each payload is written through its securely opened
same-directory temporary regular-file handle and atomically published with a
same-directory exclusive `link(2)` followed by unlink of the source; every
existing destination, including a directory substituted immediately before
publication, fails closed. Use a fresh
existing disposable output directory with all three final names absent; the
harness pins its canonical device/inode identity, rejects tab, carriage-return,
and line-feed characters in lexical or resolved paths, and rolls back earlier
app-owned publications if a later publication fails without removing a
caller-owned substitute. Its live directory binding remains authoritative if
the caller renames or replaces the approved pathname: operations continue in
the original directory, and successful outputs remain there rather than being
redirected.

```sh
bash -n Scripts/measure-fleck-panel-presentation.sh
FLECK_PERFORMANCE_PID=PID Scripts/measure-fleck-panel-presentation.sh \
  "/absolute/path/to/disposable-output"
```

The output directory must already exist, be outside Fleck Application Support,
and not be a symlink. The caller must grant System Events Accessibility to the
Terminal or agent, supply the PID of the already-running exact packaged Fleck
app, and retain the artifact identity separately from the path-shape guard.
Leave the packaged measurement as `[not captured]` until this exact loop has
been run against the accepted QA artifact.

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

## Phase 2 persistence optimization: synthetic before/after

This is a deterministic SwiftPM test protocol, not a packaged-app or
host-wide-I/O measurement. It uses the exact 10-, 100-, and 1,000-note
synthetic fixtures, temporary roots outside Fleck Application Support, and one
body-only edit after an initial save. A live-root content write is counted when
the `.md` or `.rtf` file's bytes, modification date, or file identity changes.
`Recovery` copy activity is intentionally excluded and remains present on each
save that has a valid root. No user note content is used.

The before run used exact base `675d0909ee1585820ac270baceae92e22a5f9f2f` in a
disposable archive. The after run used the Phase 2 working tree at the same
base plus its uncommitted changes. These are single-run observations in Debug
SwiftPM tests, so they are comparisons for this fixture/protocol rather than
performance budgets.

| Notes | Before live-root content writes | After live-root content writes | Before initial save ms | After initial save ms | Before initial load ms | After initial load ms | Before changed save ms | After changed save ms |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 | 10 | 1 | 8.919 | 8.499 | 2.782 | 2.223 | 9.768 | 6.579 |
| 100 | 100 | 1 | 36.551 | 29.819 | 11.267 | 11.597 | 85.387 | 47.379 |
| 1,000 | 1,000 | 1 | 336.557 | 321.573 | 182.947 | 108.480 | 762.680 | 473.637 |

In this single synthetic run, the measured initial-save, load, and
changed-note-save timings were lower at every tested scale; the live-root write
count is the deterministic regression signal. This does not claim that all
filesystem writes disappear: valid-root recovery copying,
preferences/manifest replacement, and post-commit maintenance remain separate
work.

## Current persistence characterization

`FleckPerformanceSaveLeavesUnchangedNoteBodiesUntouched` records the new
invariant: a valid-root save that changes another note leaves an unchanged
`.md` body byte-, inode-, and mtime-identical. The base behavior was captured by
the red test before this regression was inverted. `LocalStoreTests` extends the
same observation to changed RTF, RTF removal ordering, metadata-only and
preference-only saves, agent proof saves, deletion/restore, recovery, and
superseded generations.

## Limitations and evidence links

- `[record unverified simulator/device/auth/packaging boundary]`
- `[record whether launch, panel presentation, note switching, typing, save,
  logical disk writes, idle CPU, and resident memory were actually captured]`
- `[link or path to sanitized Instruments/Activity Monitor output]`
- `[record any tool failure, shellcheck absence, or incomplete run]`
