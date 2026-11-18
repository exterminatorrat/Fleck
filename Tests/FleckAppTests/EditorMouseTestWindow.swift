import AppKit
import Testing

/// Supplies the pointer state that accompanies a real click without moving the
/// test runner's system cursor. AppKit tracking can read the live window point
/// independently of the NSEvent it is handling.
@MainActor
final class EditorMouseTestWindow: NSWindow {
  private static var nextMouseEventNumber = 1
  private var syntheticMouseLocation: NSPoint?

  override var mouseLocationOutsideOfEventStream: NSPoint {
    syntheticMouseLocation ?? super.mouseLocationOutsideOfEventStream
  }

  func click(
    _ view: NSView,
    at point: NSPoint,
    clickCount: Int = 1,
    modifiers: NSEvent.ModifierFlags = []
  ) throws {
    try #require(view.window === self)
    try #require(windowNumber > 0)
    drainPendingMouseEvents()
    defer { drainPendingMouseEvents() }

    let windowPoint = view.convert(point, to: nil)
    let previousMouseLocation = syntheticMouseLocation
    syntheticMouseLocation = windowPoint
    defer { syntheticMouseLocation = previousMouseLocation }

    let timestamp = ProcessInfo.processInfo.systemUptime
    let downNumber = Self.nextMouseEventNumber
    Self.nextMouseEventNumber += 2
    let down = try #require(
      NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: windowPoint,
        modifierFlags: modifiers,
        timestamp: timestamp,
        windowNumber: windowNumber,
        context: nil,
        eventNumber: downNumber,
        clickCount: clickCount,
        pressure: 1
      )
    )
    let up = try #require(
      NSEvent.mouseEvent(
        with: .leftMouseUp,
        location: windowPoint,
        modifierFlags: modifiers,
        timestamp: timestamp + 0.01,
        windowNumber: windowNumber,
        context: nil,
        eventNumber: downNumber + 1,
        clickCount: clickCount,
        pressure: 0
      )
    )

    // Dequeue before delivering to the responder so NSApplication.currentEvent
    // describes this gesture, including during AppKit's native selection work.
    // Keep the matching up queued for NSTextView's synchronous tracking loop.
    let application = NSApplication.shared
    application.postEvent(up, atStart: true)
    application.postEvent(down, atStart: true)
    let queuedDown = try #require(
      application.nextEvent(
        matching: .leftMouseDown,
        until: .distantPast,
        inMode: .default,
        dequeue: true
      )
    )
    try #require(queuedDown.windowNumber == windowNumber)
    try #require(queuedDown.window === self)
    try #require(queuedDown.eventNumber == downNumber)
    try #require(application.currentEvent?.eventNumber == downNumber)
    // These tests target the editor responder. Application-level routing can
    // discard synthetic clicks in the shared host before they reach this view.
    view.mouseDown(with: queuedDown)

    // A checklist marker handles its down without starting AppKit tracking.
    // Deliver that click's remaining up to the same responder, rejecting any
    // event that belongs to another window or gesture.
    if let pendingUp = application.nextEvent(
      matching: .leftMouseUp,
      until: .distantPast,
      inMode: .default,
      dequeue: true
    ) {
      try #require(pendingUp.windowNumber == windowNumber)
      try #require(pendingUp.window === self)
      try #require(pendingUp.eventNumber == downNumber + 1)
      view.mouseUp(with: pendingUp)
    }
  }

  private func drainPendingMouseEvents() {
    while NSApplication.shared.nextEvent(
      matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .mouseMoved],
      until: .distantPast,
      inMode: .default,
      dequeue: true
    ) != nil {}
  }
}

@MainActor
func editorCharacterPoint(_ view: NSTextView, at characterIndex: Int) -> NSPoint? {
  guard let window = view.window else { return nil }
  let rect = view.firstRect(
    forCharacterRange: NSRange(location: characterIndex, length: 1),
    actualRange: nil
  )
  guard rect.width > 0 || rect.height > 0 else { return nil }
  return view.convert(
    window.convertPoint(fromScreen: NSPoint(x: rect.midX, y: rect.midY)),
    from: nil
  )
}
