import AppKit

@MainActor
func diagActivation(_ tag: String, window: NSWindow?) {
  let front = NSWorkspace.shared.frontmostApplication
  let menuOwner = NSWorkspace.shared.menuBarOwningApplication
  var lines: [String] = []
  lines.append("[DIAG \(tag)] appActive=\(NSApp.isActive) hidden=\(NSApp.isHidden) policy=\(NSApp.activationPolicy().rawValue) selfPID=\(ProcessInfo.processInfo.processIdentifier)")
  lines.append("[DIAG \(tag)] front=\(front?.bundleIdentifier ?? "nil")/\(front?.localizedName ?? "nil") pid=\(front?.processIdentifier ?? -1) menuOwner=\(menuOwner?.bundleIdentifier ?? "nil")/\(menuOwner?.localizedName ?? "nil")")
  if let window {
    lines.append("[DIAG \(tag)] window key=\(window.isKeyWindow) main=\(window.isMainWindow) visible=\(window.isVisible) canKey=\(window.canBecomeKey) occl=\(window.occlusionState.rawValue) level=\(window.level.rawValue) appKeyIsWindow=\(NSApp.keyWindow === window) firstResponder=\(window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil")")
  }
  lines.append("[DIAG \(tag)] appKey=\(NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "nil") appMain=\(NSApp.mainWindow.map { String(describing: type(of: $0)) } ?? "nil")")
  for w in NSApp.windows where w.isVisible {
    lines.append("[DIAG \(tag)]  win \(type(of: w)) key=\(w.isKeyWindow) level=\(w.level.rawValue) frame=\(w.frame) parent=\(w.parent != nil)")
  }
  let regular = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
    .map { "\($0.localizedName ?? "?")(\($0.processIdentifier))\($0.isActive ? "*" : "")" }
  lines.append("[DIAG \(tag)] regularApps=\(regular.joined(separator: ","))")
  print(lines.joined(separator: "\n"))
}

