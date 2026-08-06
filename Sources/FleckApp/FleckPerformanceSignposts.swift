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
  static let snapshotSave = StaticString("snapshot-save")
  static let panelPresentation = StaticString("panel-presentation")
}
