# Accent Checklist Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the completed checklist dot with an accent-filled circle and white checkmark, then draw the checkmark with one short reduced-motion-aware animation.

**Architecture:** Keep `○` and `●` as the persisted checklist source of truth. Add a small Core Graphics renderer and a transient AppKit animation overlay; `ListAwareTextView` owns geometry, drawing, hit testing, and animation activation while `NativeRichTextEditor` explicitly supplies the accent and reduced-motion preference.

**Tech Stack:** Swift 6, macOS AppKit, SwiftUI `NSViewRepresentable`, Core Graphics, Core Animation, Swift Testing.

## Global Constraints

- Preserve the existing plain-text markers: `○` incomplete and `●` complete.
- Preserve content-only strikethrough, one-step undo, selection, indentation, continuation, RTF, Markdown, and accessibility behavior.
- Do not use `NSTextAttachment`, replacement-object characters, or persisted temporary text attributes.
- The completed state must be committed immediately; animation may never delay or reject the edit.
- Use `AppMotion.quickDuration` (`0.10` seconds) for completion motion.
- Reduce Motion must skip the animated overlay and show the final state immediately.
- Invalid accent hex values must fall back to `NSColor.controlAccentColor`.
- Keep all new rendering display-only and remove stale overlay views on repeated toggles.
- Preserve the already-verified tab-color changes in `NotesPanel.swift` and `AppKitEditorTests.swift`.

## File Structure

- Create `Sources/MenuBarNotesApp/ChecklistMarkerDrawing.swift`: vector circle/check paths, static completed-marker drawing, and the transient animation overlay.
- Modify `Sources/MenuBarNotesApp/NativeRichTextEditor.swift`: accent/reduced-motion inputs, shared marker geometry, completed-marker enumeration, custom drawing, hit testing, and animation activation.
- Modify `Sources/MenuBarNotesApp/NotesPanel.swift`: pass the stored accent and SwiftUI Reduce Motion value to the native editor.
- Create `Tests/MenuBarNotesAppTests/ChecklistMarkerDrawingTests.swift`: deterministic vector rendering and overlay policy tests.
- Modify `Tests/MenuBarNotesAppTests/AppKitEditorTests.swift`: real text-layout hit testing plus checklist state/overlay regression tests.

---

### Task 1: Static Accent Checklist Marker

**Files:**
- Create: `Sources/MenuBarNotesApp/ChecklistMarkerDrawing.swift`
- Create: `Tests/MenuBarNotesAppTests/ChecklistMarkerDrawingTests.swift`
- Modify: `Sources/MenuBarNotesApp/NativeRichTextEditor.swift:131-291, 293-530`
- Modify: `Sources/MenuBarNotesApp/NotesPanel.swift:340-370`
- Test: `Tests/MenuBarNotesAppTests/AppKitEditorTests.swift`

**Interfaces:**
- Consumes: `AppPreferences.accentHex: String`, `NotesPanel.reduceMotion: Bool`, `EditorListEngine.parse(_:)`.
- Produces: `ChecklistMarkerDrawing.drawCompleted(in:accentColor:flipped:)`, `ChecklistMarkerDrawing.checkmarkPath(in:flipped:)`, `ListAwareTextView.checklistMarkerRect(for:)`, and `ListAwareTextView.checklistHitRect(for:)`.

- [ ] **Step 1: Add a failing raster-rendering test**

Create `Tests/MenuBarNotesAppTests/ChecklistMarkerDrawingTests.swift`:

```swift
#if os(macOS)
  import AppKit
  import Testing

  @testable import MenuBarNotesApp

  @Test @MainActor func completedChecklistMarkerContainsAccentFillAndWhiteCheck() throws {
    let size = NSSize(width: 24, height: 24)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.clear.setFill()
    NSRect(origin: .zero, size: size).fill()
    ChecklistMarkerDrawing.drawCompleted(
      in: NSRect(x: 3, y: 3, width: 18, height: 18),
      accentColor: NSColor(calibratedRed: 0.12, green: 0.42, blue: 0.92, alpha: 1),
      flipped: false
    )
    image.unlockFocus()

    let representation = try #require(
      image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))
    )
    var accentPixels = 0
    var whitePixels = 0
    for y in 0..<representation.pixelsHigh {
      for x in 0..<representation.pixelsWide {
        guard let color = representation.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
          continue
        }
        if color.blueComponent > 0.70, color.redComponent < 0.40 {
          accentPixels += 1
        }
        if color.redComponent > 0.90,
          color.greenComponent > 0.90,
          color.blueComponent > 0.90,
          color.alphaComponent > 0.50
        {
          whitePixels += 1
        }
      }
    }

    #expect(accentPixels > 80)
    #expect(whitePixels > 3)
  }
#endif
```

- [ ] **Step 2: Run the raster test and verify RED**

Run:

```bash
swift test --filter completedChecklistMarkerContainsAccentFillAndWhiteCheck
```

Expected: compilation fails because `ChecklistMarkerDrawing` does not exist.

- [ ] **Step 3: Implement the vector renderer**

Create `Sources/MenuBarNotesApp/ChecklistMarkerDrawing.swift`:

```swift
#if os(macOS)
  import AppKit
  import QuartzCore

  enum ChecklistMarkerDrawing {
    static func checkmarkPath(in rect: CGRect, flipped: Bool) -> CGPath {
      let elbowY = rect.minY + rect.height * (flipped ? 0.66 : 0.34)
      let rightY = rect.minY + rect.height * (flipped ? 0.32 : 0.68)
      let path = CGMutablePath()
      path.move(
        to: CGPoint(
          x: rect.minX + rect.width * 0.27,
          y: rect.minY + rect.height * (flipped ? 0.49 : 0.51)
        )
      )
      path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.44, y: elbowY))
      path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.74, y: rightY))
      return path
    }

    static func drawCompleted(in rect: NSRect, accentColor: NSColor, flipped: Bool) {
      guard let context = NSGraphicsContext.current?.cgContext else { return }
      context.saveGState()
      context.setFillColor(accentColor.cgColor)
      context.fillEllipse(in: rect)
      context.addPath(checkmarkPath(in: rect, flipped: flipped))
      context.setStrokeColor(NSColor.white.cgColor)
      context.setLineWidth(max(1.35, rect.width * 0.11))
      context.setLineCap(.round)
      context.setLineJoin(.round)
      context.strokePath()
      context.restoreGState()
    }
  }
#endif
```

- [ ] **Step 4: Pass accent and Reduce Motion into the AppKit editor**

In `NativeRichTextEditor`, add:

```swift
let accentColorHex: String
let reduceMotion: Bool
```

In both `makeNSView` and `updateNSView`, configure:

```swift
textView.checklistAccentColor = NSColor(hex: accentColorHex) ?? .controlAccentColor
textView.reduceMotion = reduceMotion
```

Change the existing `NSColor(hex:)` extension from `fileprivate` to internal so the representable and tests continue to resolve colors without duplicating parsing.

In `NotesPanel.editor`, add:

```swift
accentColorHex: appState.preferences.accentHex,
reduceMotion: reduceMotion,
```

immediately before `automaticLists`.

- [ ] **Step 5: Add shared marker geometry and static drawing**

In `ListAwareTextView`, add:

```swift
var checklistAccentColor = NSColor.controlAccentColor {
  didSet { needsDisplay = true }
}
var reduceMotion = false

func checklistMarkerRect(for markerRange: NSRange) -> NSRect? {
  guard let layoutManager, let textContainer,
    markerRange.location != NSNotFound,
    NSMaxRange(markerRange) <= (string as NSString).length
  else { return nil }

  layoutManager.ensureLayout(for: textContainer)
  let glyphRange = layoutManager.glyphRange(
    forCharacterRange: markerRange,
    actualCharacterRange: nil
  )
  guard glyphRange.length > 0 else { return nil }
  let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
    .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
  let diameter = max(10, min(glyphRect.width, glyphRect.height))
  return NSRect(
    x: glyphRect.midX - diameter / 2,
    y: glyphRect.midY - diameter / 2,
    width: diameter,
    height: diameter
  ).integral
}

func checklistHitRect(for markerRange: NSRange) -> NSRect? {
  checklistMarkerRect(for: markerRange)?.insetBy(dx: -4, dy: -3)
}
```

Add the visible completed-marker helper:

```swift
private func completedChecklistMarkerRanges(in dirtyRect: NSRect) -> [NSRange] {
  guard let layoutManager, let textContainer, layoutManager.numberOfGlyphs > 0 else {
    return []
  }
  let containerRect = dirtyRect.offsetBy(
    dx: -textContainerOrigin.x,
    dy: -textContainerOrigin.y
  )
  let glyphRange = layoutManager.glyphRange(
    forBoundingRect: containerRect,
    in: textContainer
  )
  guard glyphRange.length > 0 else { return [] }

  let characterRange = layoutManager.characterRange(
    forGlyphRange: glyphRange,
    actualGlyphRange: nil
  )
  let ns = string as NSString
  let visibleEnd = min(ns.length, NSMaxRange(characterRange))
  var location = min(characterRange.location, ns.length)
  var markerRanges: [NSRange] = []

  while location < visibleEnd {
    let paragraphRange = ns.paragraphRange(
      for: NSRange(location: location, length: 0)
    )
    let paragraph = ns.substring(with: paragraphRange)
      .trimmingCharacters(in: .newlines)
    if let parsed = EditorListEngine.parse(paragraph),
      parsed.style == .checklist,
      parsed.isChecklistComplete
    {
      markerRanges.append(
        NSRange(
          location: paragraphRange.location + (parsed.depth * 4),
          length: 1
        )
      )
    }
    let nextLocation = NSMaxRange(paragraphRange)
    guard nextLocation > location else { break }
    location = nextLocation
  }

  return markerRanges
}
```

Override drawing:

```swift
override func draw(_ dirtyRect: NSRect) {
  super.draw(dirtyRect)
  for markerRange in completedChecklistMarkerRanges(in: dirtyRect) {
    guard let rect = checklistMarkerRect(for: markerRange), rect.intersects(dirtyRect) else {
      continue
    }
    ChecklistMarkerDrawing.drawCompleted(
      in: rect,
      accentColor: checklistAccentColor,
      flipped: isFlipped
    )
  }
}
```

Replace the duplicated marker-rectangle calculation in `mouseDown(with:)` with:

```swift
guard checklistHitRect(for: markerRange)?.contains(point) == true else {
  super.mouseDown(with: event)
  return
}
```

- [ ] **Step 6: Add a real layout/hit-rectangle regression test**

Add to `AppKitEditorTests.swift`:

```swift
@Test @MainActor func checklistHitRectContainsItsRenderedMarker() throws {
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
  textView.font = .systemFont(ofSize: 16)
  textView.string = "○ Task"
  textView.layoutManager?.ensureLayout(for: try #require(textView.textContainer))

  let markerRange = NSRange(location: 0, length: 1)
  let markerRect = try #require(textView.checklistMarkerRect(for: markerRange))
  let hitRect = try #require(textView.checklistHitRect(for: markerRange))

  #expect(hitRect.contains(NSPoint(x: markerRect.midX, y: markerRect.midY)))
  #expect(hitRect.width > markerRect.width)
  #expect(hitRect.height > markerRect.height)
}

@Test @MainActor func clickingChecklistControlUsesSharedHitRect() throws {
  let textView = ListAwareTextView(
    frame: NSRect(x: 0, y: 0, width: 320, height: 160)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  textView.string = "○ Task"
  let container = try #require(textView.textContainer)
  textView.layoutManager?.ensureLayout(for: container)
  let hitRect = try #require(
    textView.checklistHitRect(for: NSRange(location: 0, length: 1))
  )
  let windowPoint = textView.convert(
    NSPoint(x: hitRect.midX, y: hitRect.midY),
    to: nil
  )
  let event = try #require(
    NSEvent.mouseEvent(
      with: .leftMouseDown,
      location: windowPoint,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: 1,
      clickCount: 1,
      pressure: 1
    )
  )

  textView.mouseDown(with: event)

  #expect(textView.string == "● Task")
  #expect(
    textView.textStorage?.attribute(
      .strikethroughStyle,
      at: 2,
      effectiveRange: nil
    ) as? Int == NSUnderlineStyle.single.rawValue
  )
}

@Test @MainActor func completedChecklistRoundTripsWithoutRenderingArtifacts() {
  let textView = ListAwareTextView(frame: .zero)
  textView.string = "● Task"
  textView.textStorage?.addAttribute(
    .strikethroughStyle,
    value: NSUnderlineStyle.single.rawValue,
    range: NSRange(location: 2, length: 4)
  )

  let restored = rtfRoundTrip(textView)

  #expect(restored.string == "● Task")
  #expect(
    restored.textStorage?.attribute(
      .strikethroughStyle,
      at: 2,
      effectiveRange: nil
    ) as? Int == NSUnderlineStyle.single.rawValue
  )
}
```

- [ ] **Step 7: Run focused tests and verify GREEN**

Run:

```bash
swift test --filter completedChecklistMarkerContainsAccentFillAndWhiteCheck
swift test --filter checklistHitRectContainsItsRenderedMarker
swift test --filter clickingChecklistControlUsesSharedHitRect
swift test --filter completedChecklistRoundTripsWithoutRenderingArtifacts
swift test --filter checklistCompletionUndoRestoresMarkerAndStrikethrough
```

Expected: all five tests pass.

- [ ] **Step 8: Commit Task 1**

```bash
git add Sources/MenuBarNotesApp/ChecklistMarkerDrawing.swift \
  Sources/MenuBarNotesApp/NativeRichTextEditor.swift \
  Sources/MenuBarNotesApp/NotesPanel.swift \
  Tests/MenuBarNotesAppTests/ChecklistMarkerDrawingTests.swift \
  Tests/MenuBarNotesAppTests/AppKitEditorTests.swift
git commit -m "feat: draw accent checklist markers"
```

---

### Task 2: Animated Checkmark Completion

**Files:**
- Modify: `Sources/MenuBarNotesApp/ChecklistMarkerDrawing.swift`
- Modify: `Sources/MenuBarNotesApp/NativeRichTextEditor.swift:671-725`
- Modify: `Tests/MenuBarNotesAppTests/ChecklistMarkerDrawingTests.swift`
- Modify: `Tests/MenuBarNotesAppTests/AppKitEditorTests.swift`

**Interfaces:**
- Consumes: `ChecklistMarkerDrawing.checkmarkPath(in:flipped:)`, `ListAwareTextView.checklistMarkerRect(for:)`, `ListAwareTextView.reduceMotion`, and `AppMotion.quickDuration`.
- Produces: `ChecklistCompletionOverlay`, `ListAwareTextView.showChecklistCompletionAnimation(for:)`, and `ListAwareTextView.checklistCompletionOverlayCount`.

- [ ] **Step 1: Add failing animation-policy tests**

Add to `ChecklistMarkerDrawingTests.swift`:

```swift
@Test @MainActor func checklistCompletionOverlayUsesQuickNativeTiming() {
  #expect(ChecklistCompletionOverlay.duration == AppMotion.quickDuration)
}
```

Add to `AppKitEditorTests.swift`:

```swift
@Test @MainActor func reduceMotionSkipsChecklistCompletionOverlay() {
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
  textView.string = "○ Task"
  textView.setSelectedRange(NSRange(location: 2, length: 0))
  textView.reduceMotion = true

  #expect(textView.toggleSelectedChecklist())
  #expect(textView.string == "● Task")
  #expect(textView.checklistCompletionOverlayCount == 0)
}

@Test @MainActor func rapidChecklistToggleDoesNotLeaveStaleOverlay() {
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
  textView.string = "○ Task"
  textView.setSelectedRange(NSRange(location: 2, length: 0))
  textView.reduceMotion = false

  #expect(textView.toggleSelectedChecklist())
  #expect(textView.checklistCompletionOverlayCount <= 1)
  #expect(textView.toggleSelectedChecklist())
  #expect(textView.checklistCompletionOverlayCount == 0)
}
```

- [ ] **Step 2: Run animation tests and verify RED**

Run:

```bash
swift test --filter checklistCompletionOverlayUsesQuickNativeTiming
swift test --filter reduceMotionSkipsChecklistCompletionOverlay
swift test --filter rapidChecklistToggleDoesNotLeaveStaleOverlay
```

Expected: compilation fails because `ChecklistCompletionOverlay` and `checklistCompletionOverlayCount` do not exist.

- [ ] **Step 3: Implement the transient checkmark overlay**

Add to `ChecklistMarkerDrawing.swift`:

```swift
final class ChecklistCompletionOverlay: NSView {
  static let duration = AppMotion.quickDuration
  private let accentColor: NSColor
  private let checkLayer = CAShapeLayer()

  init(frame: NSRect, accentColor: NSColor) {
    self.accentColor = accentColor
    super.init(frame: frame)
    wantsLayer = true
    layer?.backgroundColor = accentColor.cgColor
    layer?.cornerRadius = frame.width / 2
    layer?.masksToBounds = true
    setAccessibilityElement(false)

    checkLayer.frame = bounds
    checkLayer.path = ChecklistMarkerDrawing.checkmarkPath(in: bounds, flipped: false)
    checkLayer.fillColor = NSColor.clear.cgColor
    checkLayer.strokeColor = NSColor.white.cgColor
    checkLayer.lineWidth = max(1.35, bounds.width * 0.11)
    checkLayer.lineCap = .round
    checkLayer.lineJoin = .round
    checkLayer.strokeEnd = 1
    layer?.addSublayer(checkLayer)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  func start(completion: @escaping () -> Void) {
    let animation = CABasicAnimation(keyPath: "strokeEnd")
    animation.fromValue = 0
    animation.toValue = 1
    animation.duration = Self.duration
    animation.timingFunction = CAMediaTimingFunction(
      controlPoints: 0.23, 1.0, 0.32, 1.0
    )

    CATransaction.begin()
    CATransaction.setCompletionBlock(completion)
    checkLayer.add(animation, forKey: "checkmark")
    CATransaction.commit()
  }
}
```

- [ ] **Step 4: Activate animation only after a successful completion**

In `ListAwareTextView`, add:

```swift
private weak var checklistCompletionOverlay: ChecklistCompletionOverlay?

var checklistCompletionOverlayCount: Int {
  subviews.filter { $0 is ChecklistCompletionOverlay }.count
}

private func removeChecklistCompletionOverlay() {
  checklistCompletionOverlay?.removeFromSuperview()
}

private func showChecklistCompletionAnimation(for markerRange: NSRange) {
  removeChecklistCompletionOverlay()
  guard !reduceMotion, let rect = checklistMarkerRect(for: markerRange) else { return }
  let overlay = ChecklistCompletionOverlay(frame: rect, accentColor: checklistAccentColor)
  checklistCompletionOverlay = overlay
  addSubview(overlay)
  overlay.start { [weak overlay] in
    overlay?.removeFromSuperview()
  }
}
```

Refactor `toggleChecklist` so it stores the `replaceText` result:

```swift
let changed = replaceText(
  in: markerRange,
  with: completed ? "●" : "○",
  selecting: selection
) { storage, _ in
  guard contentRange.length > 0 else { return }
  if completed {
    storage.addAttribute(
      .strikethroughStyle,
      value: NSUnderlineStyle.single.rawValue,
      range: contentRange
    )
  } else {
    storage.removeAttribute(.strikethroughStyle, range: contentRange)
  }
}
guard changed else { return false }
if completed {
  showChecklistCompletionAnimation(for: markerRange)
} else {
  removeChecklistCompletionOverlay()
}
return true
```

Keep the existing undo grouping and `registerStrikethroughUndo` call unchanged.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run:

```bash
swift test --filter checklistCompletionOverlayUsesQuickNativeTiming
swift test --filter reduceMotionSkipsChecklistCompletionOverlay
swift test --filter rapidChecklistToggleDoesNotLeaveStaleOverlay
swift test --filter checklistCompletionUndoRestoresMarkerAndStrikethrough
swift test --filter completedChecklistReturnUndoRestoresSuffixFormatting
```

Expected: all tests pass.

- [ ] **Step 6: Commit Task 2**

```bash
git add Sources/MenuBarNotesApp/ChecklistMarkerDrawing.swift \
  Sources/MenuBarNotesApp/NativeRichTextEditor.swift \
  Tests/MenuBarNotesAppTests/ChecklistMarkerDrawingTests.swift \
  Tests/MenuBarNotesAppTests/AppKitEditorTests.swift
git commit -m "feat: animate checklist completion"
```

---

### Task 3: Full Validation and Motion Review

**Files:**
- Modify only if a focused test exposes a checklist-specific defect.
- Test: `Tests/MenuBarNotesAppTests/ChecklistMarkerDrawingTests.swift`
- Test: `Tests/MenuBarNotesAppTests/AppKitEditorTests.swift`

**Interfaces:**
- Consumes: the static renderer and completion overlay from Tasks 1 and 2.
- Produces: a fully validated macOS release build with no stale checklist overlays or persistence regressions.

- [ ] **Step 1: Run the full macOS validation**

Run:

```bash
bash Scripts/validate-macos.sh
```

Expected: every Swift test passes, debug and release builds succeed, and the release executable remains below the script’s 15 MB budget.

- [ ] **Step 2: Run repository hygiene checks**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; only intentional implementation files are modified.

- [ ] **Step 3: Perform a focused code and motion review**

Verify:

- `○` and `●` remain the only persisted checklist markers;
- the custom renderer writes nothing to `NSTextStorage`;
- completion animation starts only after a successful edit;
- Reduce Motion skips the overlay;
- the overlay cannot intercept pointer events;
- rapid toggles remove the previous overlay;
- drawing enumerates visible completed markers rather than all note content;
- the static marker and animation use the same accent and geometry;
- no unrelated editor, list, window, trash, or settings behavior changed.

- [ ] **Step 4: Commit any review-only correction**

If and only if Step 3 finds a checklist-specific defect, add a failing regression test, make the minimal correction, rerun `bash Scripts/validate-macos.sh`, then commit:

```bash
git add Sources/MenuBarNotesApp/ChecklistMarkerDrawing.swift \
  Sources/MenuBarNotesApp/NativeRichTextEditor.swift \
  Sources/MenuBarNotesApp/NotesPanel.swift \
  Tests/MenuBarNotesAppTests/ChecklistMarkerDrawingTests.swift \
  Tests/MenuBarNotesAppTests/AppKitEditorTests.swift
git commit -m "fix: harden checklist completion feedback"
```

If Step 3 finds no defect, do not create an empty commit.
