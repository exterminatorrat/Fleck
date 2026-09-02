# Progress ledger

- 2026-08-31: Created UI-first integration worktree at `fbbdb29424eecebc08c41f4f4fb0df1992f8aa82`.
- 2026-08-31: Provenance confirmed: the visual-polish commit contains the current UI plus the reviewed Fleck Rail and is the newest pill checkpoint.
- 2026-08-31: Compatibility preflight found that accepting pill-side coordinator/shortcut conflicts would regress Wave 3 physical-release and capture-first semantics. Packet requires semantic union rather than side selection.
- 2026-08-31: Fresh final review returned `fix-first`: production processing-backed no-speech lost its no-speech outcome and capture-stage provenance. Bounded Fix 1 owns only coordinator mapping and processing-backed regressions.
- 2026-08-31: Fix 1 RED reproduced `.failed("No speech detected.")` with nil failure provenance on the processing path. The minimal typed mapping now publishes `.noSpeech` and capture-stage provenance; focused 3/3, guarded coordinator 78/78, accessibility 55/55, streaming processor 37/37, release build, package, codesign, arm64, and no-weights gates are green.
