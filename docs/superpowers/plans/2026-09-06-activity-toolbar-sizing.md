# Activity Dismissal and Toolbar Sizing

1. Add focused regression tests for panel-size defaults and migrations, then verify they fail for the expected 640-to-800 behavior.
2. Add hosted-view coverage showing Done clears the sheet's owning presentation state while the parent window stays open, then replace environment dismissal with the required owner closure.
3. Add a responsive toolbar policy test, then replace horizontal scrolling with one adaptive command surface: a full 800-point row and a compact row whose native More menu keeps secondary actions reachable.
4. Run focused FleckCore and FleckApp tests with the installed macOS 26.5 SDK, review the owned diff, and commit the verified patch without pushing.

Constraints: preserve custom saved sizes, screen clamping, title/body font targeting, editor focus, undo, picker cancellation, and all current formatting actions. Do not change tabs, folders, dragging, packaging, installed apps, or GitHub state.
