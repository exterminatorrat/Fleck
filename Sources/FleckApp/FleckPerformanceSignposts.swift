import OSLog

internal enum FleckPerformanceSignposts {
  static let subsystem = "com.harryjin.fleck"
  static let category = "performance"
  static let signposter = OSSignposter(
    subsystem: subsystem,
    category: category
  )

  static let launch = StaticString("launch")
  static let snapshotLoad = StaticString("snapshot-load")
  static let searchQuery = StaticString("search-query")
  static let noteSwitch = StaticString("note-switch")
  static let noteSwitchState = StaticString("note-switch-state")
  static let editorChange = StaticString("editor-change")
  static let editorSerialization = StaticString("editor-serialization")
  static let editorLayout = StaticString("editor-layout")
  static let editorMount = StaticString("editor-mount")
  static let snapshotPreparation = StaticString("snapshot-preparation")
  static let snapshotSave = StaticString("snapshot-save")
  static let agentCommit = StaticString("agent-commit")
  static let panelPresentation = StaticString("panel-presentation")
}
