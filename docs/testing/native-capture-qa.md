# Strict native screenshot capture QA

The strict native screenshot/pixel test is a separate native-QA gate. GitHub-hosted CI runs the ordinary and candidate full graphs with `FLECK_NATIVE_CAPTURE_QA=0`, so that exact permission-gated case is reported as **NOT RUN** there. Every other full-graph selector and assertion remains enabled. Passing CI does not prove the strict capture ran or establish full native screenshot coverage; the gate needs separate native-QA PNG and console-status evidence.

## Run the native gate

From the repository root, run:

```bash
Scripts/run-native-capture-qa.sh
```

The entrypoint sets `FLECK_NATIVE_CAPTURE_QA=1`, selects only `FleckAppTests.hostedGlassAndSolidMenuPanelsCaptureSyntheticChromeAndOpaqueEditor()`, and invokes the committed `Scripts/run-nonempty-swift-tests.sh` runner. It uses the ordinary test graph and needs no model candidate. If `FLECK_TEST_APPKIT_HOST_APP_PATH` is unset, the existing runner uses its normal fresh signed test host. If a caller supplies that variable, the existing runner validates and reuses the immutable host; the QA entrypoint does not replace or modify it.

The checkout must be clean and committed before the command starts. The entrypoint validates full commit and tree object IDs and rejects staged, unstaged, or untracked source changes before creating an output directory or launching the runner. It checks the same commit, tree, and clean state again after the run; a source change or failed Git lookup makes the command fail, even if the test process passed.

The command creates a unique, private output directory with `mktemp -d` under `TMPDIR` (or the system temporary directory when unset), prints the path, and never reuses a fixed output location. To choose a parent directory, set `TMPDIR` to an existing private scratch directory outside the checkout and accepted-build store:

```bash
TMPDIR="/path/to/private-scratch-directory" Scripts/run-native-capture-qa.sh
```

The console receipt is `console.log` in the printed output directory. It records `VERSION`, the source commit and tree, the exact selector, the artifact path, test output, and the runner exit status. On a passing run, the strict test writes synthetic `glass.png` and `solid.png` captures there. A failed permission preflight or test returns nonzero; missing PNGs or a failed/absent status receipt are not a pass. The capture uses synthetic UI content and does not read real notes or bundle model weights.

## Permission prerequisite

macOS Screen Recording permission must be granted through the normal macOS consent flow to the AppKit test host used for the run. The test retains its real `CGPreflightScreenCaptureAccess()` requirement and its actual native capture and pixel-difference assertions. If permission is not granted, the test fails and native QA remains open. The entrypoint does not write TCC state, simulate consent, alter permissions, or launch the Fleck product; a human must approve any macOS permission prompt.

The command's availability is not authorization to run it. Before a native run, obtain owner coordination for a bounded, serialized native-QA slot so no other QA run or source integration can overlap it, and confirm that the human responsible for the test host can grant Screen Recording consent. A clean checkout or a CI result does not reserve that slot or grant OS permission.

The AppKit host runner also accepts only an unset `FLECK_NATIVE_CAPTURE_QA`, `0`, or `1`; an explicitly empty value or any other value fails closed. The dedicated entrypoint always supplies literal `1`. The existing supplemental own-window API probe remains separate and opt-in; it does not replace this strict native gate.

## Evidence boundary

GitHub-hosted Actions is the source of CI evidence. Its named coverage step and job summary disclose that strict native screenshot capture is **NOT RUN** and requires separate native-QA artifact and status-receipt evidence. Do not report CI as strict-capture coverage or claim readiness while this native gate is failed or absent. Native QA evidence and hosted CI evidence are separate; neither advances the accepted-build pointer.
