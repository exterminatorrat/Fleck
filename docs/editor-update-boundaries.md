# Editor update and presentation boundaries

This describes the focused refactor of PR #157, reviewed from
`eda5b9cbc25233ee6ef16da0c84009e0d76048ca`. The existing AppKit editor remains
the owner of native input, selection, marked text, and undo.

## External updates have one transaction boundary

`NativeRichTextEditor.applyExternalContentIfNeeded(to:coordinator:)` receives
model content already committed by the app. It resolves RTF and inline-image
projection once, then chooses an incremental edit or a full reload. Both routes
share model-snapshot bookkeeping and viewport restoration. The coordinator
suppresses its user-edit callback during this transaction; undo and later user
edits continue through the normal callback.

An incremental edit is eligible only when it has safe composed-character
boundaries and preserves the surrounding content. Rich-text updates also require
equal attributes in the preserved prefix and suffix. A canonical Unicode
representation change uses the existing reload selection mapper. This accepts
occasional reloads in exchange for retaining every requested formatting change
and the correct UTF-16 selection.

The implementation uses a private `ResolvedContent` value, native
`ListAwareTextView.applyProgrammaticEdit(range:replacement:actionName:)`, and
`NativeEditorScrollView.scheduleScrollRestore(_:revealingCaretIfNeeded:)`.
Callers do not need to coordinate the two replacement routes themselves.

## Presentation work belongs to one change generation

`ListAwareTextView.didChangeText()` normalizes affected list paragraphs, delivers
the native notification, and restores presentation only when the coordinator
has not already refreshed the current text-change generation. Standalone text
views retain the fallback. Composing ink is applied after presentation is ready.
Clearing a presentation invalidates its generation.

A presentation refresh parses the note's list paragraphs once and reuses the
result for checklists and drawn text markers. Marker fonts are cached only for
that pass, keyed by line size within the note's body family. Repainting finds the
dirty slice of ordered marker ranges before requesting glyph geometry. The
drawing operation owns empty-marker opacity; temporary attributes only hide the
native marker and restore the original ink afterward.

## Typography rules remain stateless

`EditorTypography.presetParagraphMetrics(for:size:)` supplies the same immutable
metrics to style application, toolbar recognition, and migration. Recognition
does not construct paragraph styles or measure tab widths. Migration resolves
its target fonts, metrics, and shared tab interval once for each load.

The alternatives considered were a persistent typography/presentation cache and
separate external-edit helpers that each restored scroll state. The per-operation
values avoid cache invalidation state; the common update boundary avoids the
duplicated postconditions that caused the original caret regression. No new
editor framework, dependency, or background worker is involved.

## Verification boundary

Behavioral coverage includes external-edit callback ownership, single-step undo,
formatting outside a replacement, canonical Unicode selections, caret visibility,
typography recognition and migration idempotence, marker rasterization, and
temporary-ink restoration. Editor fixtures must close their windows. Static
selection-fill comparisons use settled Reduce Motion endpoints; separate motion
tests retain animation coverage.

Native compilation, AppKit tests, and visual checks require macOS. Source review
and the reduction in repeated operations do not establish a measured latency,
CPU, or energy improvement; those require profiling the native app.
