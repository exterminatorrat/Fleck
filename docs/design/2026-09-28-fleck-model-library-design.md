# Fleck Model Library — Design

Date: 2026-09-28
Status: Approved for implementation; design only, not a model release.

## Decision and intent

Give local models their own full-width **Models** window, reached from a Models entry under Voice & Writing in Settings. Reproduce the *information architecture and interactions* of the supplied Superwhisper references: searchable, filterable model table; pinned rows; hover and selected-row treatments; and an expansive model detail view. Use Fleck's native typography, semantic themes, icon vocabulary, and accessibility behavior rather than copying another product's artwork, brand colors, or window chrome.

The current Dictation Settings page remains the home for capture, modifier key, microphone, recognition language, experience, history, and privacy. Its compact readiness indicator remains available there. The modifier control may also be linked from Shortcuts, but must have one authoritative setting, not duplicated switches. Model-installation controls leave Dictation Settings and live in Models. A small link from Dictation to Models is enough to connect the two tasks.

The reviewed development source for this proposal is `39d349dd5532316cc322eae90f6916fdeb5d3daa` (tree `c913743d91f4684953e17e9819967b9ab644298c`), descended from the accepted source `dd5c3e2d027d6adde6ad79a3f7d91cc1c9d33e21` and the designated development source `baf7f7885b64fcde4d3caec23dbbad7ca361b586`. Its explicit feature delta includes the accumulated versioning, editor, banner, capsule, dictionary, palette, and Settings work. An uncommitted `1.3.2-beta.1` Dictation model-card prototype exists in the isolated worktree; it is not this design and must be deliberately reconciled rather than silently accepted or discarded. The canonical accepted registry and running Build 101 are unaffected by this document.

## Window and navigation

- Settings → Models opens one dedicated, resizable Models window without the regular Settings sidebar. Prefer an approximately 1100-point default width; validate a minimum around 900 points against real table content rather than forcing the existing 840-point Settings frame to carry every column. Reopening focuses the existing Models window instead of making duplicates.
- The Models window has a persistent top search field, a provider filter initially labeled **All providers**, and an **All / Voice / Cleanup** type filter. The provider menu lists only creators represented by *admitted, visible* entries; the initial development inventory is NVIDIA and Google. Provider is the upstream creator, while the exact converted artifact and its distributor are separately attributed in details.
- With no detail open, show the full-width table. Opening a row keeps search, filters, scroll position, and a compact model list on the left; the right side becomes the detail view. **Back to models** restores the full table and its previous position. Escape closes the detail before closing the window; opening a row does not select a runtime engine.
- The public build must not leak development-only entries. If no optional models are admitted, keep a useful empty state: “No optional local models are available in this build. Dictation still uses its built-in local paths.” Do not populate filters with unavailable or speculative providers.

```text
Models                                          [Search models              ] [Filters]
[All providers ▾] [All | Voice | Cleanup]
☆  Model name                     Type       Speed / Accuracy     Size     Action
☆  Parakeet TDT 0.6B v2           Voice      see evidence rule   464 MB   Download
☆  Gemma 3 1B                     Cleanup    see evidence rule   772 MB   Download

When a row is open:
[Search models] [Filters]       │  [‹ Back to models]  [model name]       [☆]
[compact filtered model list]  │  Short description and current install state
                               │  Type · Verified capabilities · Speed · Accuracy
                               │  Download and disk size · Requirements · Attribution
                               │  [Install / Cancel / Repair / Update / Remove]
```

The diagram describes structure, not final copy, typography, colors, scores, or artifact availability. Show the size from the currently admitted signed descriptor, rounded consistently in decimal MB. The signed Parakeet and Gemma manifests presently specify 464,413,247 and 771,863,021 download bytes respectively; do not reuse a reference screenshot's size for a different conversion.

## Table and detail behavior

| Element | Contract |
| --- | --- |
| Star | Toggles a locally persisted pin for this model's role and stable model ID. Pinned entries sort first, then by model name; starring **only organizes the list**. It never installs, activates, or prefers an engine. Preserve the pin across a revision update of the same model ID. |
| Identity | Use a restrained model/family icon, name, and verified language badge. The row's type icon distinguishes voice recognition from language-model cleanup; its text label remains available to VoiceOver. No borrowed provider logos without appropriate asset rights. |
| Hover and selection | A full-row, subtle semantic hover fill and a stronger selected-detail fill, analogous to the current Dictionary list. Pointer and keyboard activation open details; hover, keyboard focus, pin, and open-for-details are distinct states. A selected row does not mean the model is active. |
| Speed / Accuracy | Keep two visually separate slots like the reference, with readable text equivalents. A segment bar may render only when its value passes the evidence rule below. Otherwise show **Not rated**, not empty bars that suggest a zero score. |
| Size and action | Show download size before installation and a stateful Download/Cancel/Repair/Update/Remove control at the trailing edge. An installed row shows Installed and a Remove affordance; a repair state exposes Repair, not Download. Confirm removal and explain the fallback before deleting an installed model. |
| Search and filters | Search visible model name, creator, and type without affecting pin or installation. Provider and type filters intersect with search; preserve those choices when opening and closing a detail. The model-name header toggles A–Z/Z–A, with pinned rows first in either order. A zero-result state offers **Clear filters**. |
| Detail | Put the short, accurate purpose first: Parakeet transcribes voice; Gemma cleans captured text. Then Type, verified Specs, Speed, Accuracy, Download size, installed footprint, hardware/language requirements, exact artifact/conversion attribution, license/terms, and the current installation action. Keep the primary action anchored and reachable at enlarged text sizes without covering content. |

All models in this library are local. Omit Cloud/Offline as a table column and do not imply account, billing, or remote inference. A small “On this Mac” explanation in the library introduction or details is sufficient. Apple Speech and faithful local cleanup remain fallback paths explained in Dictation and relevant model details, not fake downloadable entries in the optional-model table.

## Truthful metadata and benchmarks

The two currently admitted development candidates are **Parakeet TDT 0.6B v2**, a FluidInference Core ML conversion of NVIDIA's model, and **Gemma 3 1B**, an mlx-community MLX conversion of Google's model. Their current signed configurations declare English support on arm64. Neither is a public option merely because it appears in a developer build. Parakeet's distribution approval and attribution requirements, and Gemma's separate Terms of Use, remain release gates.

- **Specs** represent evidenced capabilities only: role, supported languages, local execution, and verified resource/format facts where useful. Do not label the present candidates multilingual, long-context, or “fast” without a supported capability or benchmark. Use a text label beside any capability icon.
- **Speed** must name a published source, exact model/conversion revision, hardware, task, and unit. Voice speed might be real-time factor; cleanup speed might be tokens per second. These are not interchangeable. A score bar needs a documented type-specific normalization range and a citation available from the detail view.
- **Accuracy** likewise requires a task-appropriate published measure and dataset: word error rate for recognition versus a stated, defensible language-quality measure for cleanup. A generic language-model score must not be relabeled “cleanup accuracy.” Compare or sort ratings only within the same type and methodology.
- Until suitable evidence is reviewed, both fields display **Not rated** for a model, including in the table. The design includes the slots now so the table structure can grow without fabricating scores. If only one model in a type has a valid score, show the sourced measure in details but do not pretend a relative five-step comparison exists.
- Sizes, languages, compatibility, and installer phases come from the admitted descriptor and installer state. The UI cannot make a model available merely by naming it in a list. Show an unsupported-machine or failed-verification reason and recovery where the installer provides one.

## Installation and activation are different

The current runtime automatically uses a healthy installed Parakeet for recognition and a healthy installed Gemma for cleanup; otherwise it falls back. The model browser preserves that policy for this design. The detail action may say **Install** and explain “Fleck uses this automatically while installed and healthy.” Avoid Superwhisper's **Use in all modes** wording, which Fleck cannot currently honor. Pinned, selected-for-details, installed, healthy, and actively used are separate states in data and accessibility copy. Do not add an engine preference or promise manual switching under this design.

Installation, download progress, verification, start/calibration, cancellation, repair, update, removal, and failure reuse the existing admitted-model lifecycle. State changes update both the row and the detail; a lost or unsupported admission removes the candidate from public view without leaving a dead selected detail. Before installation, show the exact source, applicable license/terms, and required local storage. Removing the installed candidate returns to the existing fallback; do not claim that pinning or viewing a different row changes capture behavior.

Today's installer admits at most one recommended candidate per role. The future list needs an admission-backed inventory keyed by role and stable model ID before multiple Parakeet variants can appear simultaneously. That inventory is an implementation prerequisite, **not** authorization to expose unreleased variants or invent rows. Future variants must independently pass signed identity, hardware, language, capacity, license, and release gates.

## Visual, input, and accessibility acceptance

- Keep Fleck's semantic palette in light and dark modes, including Monochrome, high contrast, Reduce Transparency, and enlarged text. Use compact rows and restrained full-row highlights rather than nested cards, copied logos, ornamental score bars, or branded gradients.
- At the normal window width, the full table fits its star, identity, type, ratings, size, and action columns with no horizontal clipping. In details mode the compact list and detail remain side by side. At the validated narrow/enlarged-text breakpoint, collapse to a single-column detail with a clear Back control instead of truncating actions or benchmarks.
- Tab order: search → provider → type → sortable table/header → row and pin/action controls → detail and its primary action. Up/Down navigates rows, Return opens details, Space toggles the focused star or button, and Escape backs out without changing the runtime. Do not let a row's click target swallow its pin or install control.
- VoiceOver identifies model name, creator, type, pin state, installation state, download size, rating with source or “Not rated,” and the consequences of each action. Hover-only affordances also have keyboard and accessibility paths. Progress announces percentage and phase; failures include a concrete recovery action.
- Verify real admitted and no-candidate builds at normal and minimum width, accessibility text, keyboard-only and VoiceOver navigation, filter/search/pin persistence, installed/failure/removal states, all relevant semantic themes, and the status of the unchanged Dictation capture controls. Use fixture-only screenshots for review; do not present a hosted fixture as a packaged or accepted build.

## Boundaries

This document specifies the Models information architecture, truthful metadata rules, and interactions. The full-width window and table/detail structure are approved for implementation. It does not implement the new window, persist pins, introduce benchmark scores, change capture/runtime policy, publish any model, move the accepted-build pointer, or authorize a package, launch, push, PR, or merge. The existing uncommitted Dictation prototype remains separate and must be preserved while implementation uses the approved design.
