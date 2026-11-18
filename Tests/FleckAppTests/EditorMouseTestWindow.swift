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

  /// Wait before computing a hit point: a newly ordered window's AppKit frame
  /// can precede the WindowServer frame used to convert posted mouse events.
  func prepareForClick() async throws {
    try #require(windowNumber > 0)
    try #require(isVisible)
    let primaryHeight = try #require(NSScreen.screens.first).frame.height
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(5))
    while clock.now < deadline {
      let expected = CGRect(
        x: frame.minX, y: primaryHeight - frame.maxY,
        width: frame.width, height: frame.height
      )
      if let actual = windowServerFrame(),
        abs(actual.minX - expected.minX) < 1,
        abs(actual.minY - expected.minY) < 1,
        abs(actual.width - expected.width) < 1,
        abs(actual.height - expected.height) < 1
      {
        contentView?.layoutSubtreeIfNeeded()
        return
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    try #require(
      Bool(false),
      "WindowServer did not receive editor frame: AppKit=\(frame), Quartz=\(String(describing: windowServerFrame())), primaryHeight=\(primaryHeight)"
    )
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
    try #require(down.locationInWindow == windowPoint)
    try #require(up.locationInWindow == windowPoint)

    // Dequeue before delivering to the responder so NSApplication.currentEvent
    // describes this gesture, including during AppKit's native selection work.
    // Keep the matching up queued for NSTextView's synchronous tracking loop.
    let application = NSApplication.shared
    application.postEvent(up, atStart: true)
    // Validate the queued up before dequeuing down, so peeking cannot replace
    // the down event as NSApplication.currentEvent during native selection.
    let queuedUp = try #require(
      application.nextEvent(
        matching: .leftMouseUp,
        until: .distantPast,
        inMode: .default,
        dequeue: false
      )
    )
    try #require(queuedUp.window === self)
    try #require(queuedUp.eventNumber == downNumber + 1)
    try requireClickGeometry(of: queuedUp, in: view, at: point, windowPoint: windowPoint)
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
    try requireClickGeometry(of: queuedDown, in: view, at: point, windowPoint: windowPoint)
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
      try requireClickGeometry(of: pendingUp, in: view, at: point, windowPoint: windowPoint)
      view.mouseUp(with: pendingUp)
    }
  }

  private func windowServerFrame() -> CGRect? {
    let windows = CGWindowListCopyWindowInfo(
      [.optionIncludingWindow], CGWindowID(windowNumber)
    ) as? [[String: Any]]
    guard let bounds = windows?.first?[kCGWindowBounds as String] as? NSDictionary else {
      return nil
    }
    return CGRect(dictionaryRepresentation: bounds)
  }

  private func requireClickGeometry(
    of event: NSEvent,
    in view: NSView,
    at point: NSPoint,
    windowPoint: NSPoint
  ) throws {
    let received = event.locationInWindow
    let receivedViewPoint = view.convert(received, from: nil)
    let diagnostic = "event=\(event.type) number=\(event.eventNumber) "
      + "expectedWindowPoint=\(windowPoint) receivedWindowPoint=\(received) "
      + "expectedViewPoint=\(point) receivedViewPoint=\(receivedViewPoint) "
      + "expectedScreenPoint=\(convertPoint(toScreen: windowPoint)) "
      + "receivedScreenPoint=\(convertPoint(toScreen: received)) "
      + "windowFrame=\(frame) viewFrame=\(view.frame) viewBounds=\(view.bounds) "
      + "windowServerFrame=\(String(describing: windowServerFrame())) "
      + "screenFrames=\(NSScreen.screens.map(\.frame))"
    try #require(received == windowPoint, "\(diagnostic)")
    try #require(receivedViewPoint == point, "\(diagnostic)")
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
