# Local dictation routing checklist

Use a packaged Fleck build with Dictation Capsule and local routing enabled. Prepare notes whose titles and body text make each route deterministic, absent, or deliberately ambiguous.

- [ ] Unique auto-file: dictate a clear match and confirm the capture appears once in the expected note; no chooser appears.
- [ ] No match: dictate unrelated content and confirm it is saved once in Inbox with `Saved to Inbox`.
- [ ] Ambiguous route: create two or more plausible matches and confirm `Saved to Inbox`, `Choose note`, and Undo remain visible without the capsule dismissing.
- [ ] Duplicate titles: include duplicate note titles and confirm each menu row shows a distinct context hint; with VoiceOver, confirm each row announces the full title/context and move hint.
- [ ] Keep Inbox: choose `Keep in Inbox`; confirm the chooser clears, the capture remains in Inbox, and the normal saved-dismiss delay resumes.
- [ ] Exact move: choose a note; confirm only this capture moves from Inbox to that note, the destination message is truthful, and no neighboring text moves.
- [ ] Deleted choice: delete one offered note before selecting it; confirm the capsule visibly reports that the dictation is still saved, removes the deleted note from the chooser, and still offers another valid note plus `Keep in Inbox`. Delete every offered note and confirm `Keep in Inbox` remains visible; after a prior move, confirm the capsule offers Undo instead of a nonexistent note.
- [ ] History retry: force or simulate a Dictation History write failure after a move; confirm the capsule visibly names the authoritative saved destination and cleanup state, disables `Keep in Inbox`, and lets the current destination or another valid note be retried. While an alternate move is pending, confirm the capsule immediately names the new destination rather than the previous failure destination.
- [ ] Undo: while the chooser is visible and after a move, confirm Undo remains reachable and reverses the exact receipt-owned capture.
- [ ] New capture: leave a chooser open, start another capture, and confirm the old chooser disappears and cannot move the previous Inbox capture.
- [ ] Disable/re-enable: disable the capsule with a chooser visible, then re-enable it; confirm the still-valid chooser returns for the same capture.
- [ ] Nonactivating behavior: invoke the menu while another app is frontmost; confirm Fleck does not activate and its capsule never becomes key or main.
- [ ] Accessibility: verify Full Keyboard Access, VoiceOver order/labels/hints, Increase Contrast, Reduce Transparency, Reduce Motion, and long or mixed-script titles.

Record the build hash and macOS/device details. Automated suites, Simulator checks, codesigning, and a packaged launch do not prove real-microphone recognition, nonactivation in the user's app mix, or human-speech routing quality; record those as separate hands-on evidence.
