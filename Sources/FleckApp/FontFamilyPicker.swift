#if os(macOS)
  import AppKit
  import FleckCore
  import SwiftUI

  /// A picker never derives its editing target from the search field's focus.
  @MainActor
  final class FontPickerTarget: NSObject {
    let note: Note
    let isTitle: Bool
    let undoManager: UndoManager?
    let range: NSRange
    private weak var textView: NSTextView?
    private var invalidated = false

    init?(note: Note, isTitle: Bool, commands: EditorCommands) {
      guard isTitle || commands.textView != nil else { return nil }
      self.note = note
      self.isTitle = isTitle
      textView = commands.textView
      undoManager = commands.textView?.undoManager
      range = commands.textView?.selectedRange() ?? NSRange(location: 0, length: 0)
      super.init()
      if !isTitle, let storage = textView?.textStorage {
        NotificationCenter.default.addObserver(self, selector: #selector(invalidate), name: NSTextStorage.didProcessEditingNotification, object: storage)
      }
    }

    var label: String { isTitle ? "Title" : range.length == 0 ? "New text" : "Selected text" }

    @objc private func invalidate() { invalidated = true }

    func isValid(note: Note?, isEditorVisible: Bool, commands: EditorCommands) -> Bool {
      guard !invalidated, isEditorVisible, note == self.note else { return false }
      return isTitle || (textView != nil && commands.textView === textView && textView?.selectedRange() == range)
    }

    @discardableResult
    func apply(_ family: String, note: Note?, isEditorVisible: Bool, commands: EditorCommands, titleMutation: (String) -> Void) -> Bool {
      guard isValid(note: note, isEditorVisible: isEditorVisible, commands: commands) else { return false }
      invalidated = true
      routeFontFamilyAction(family: family, isTitleFocused: isTitle, titleMutation: titleMutation, bodyMutation: { family in
        if let textView {
          textView.window?.makeFirstResponder(textView)
          textView.setSelectedRange(range)
        }
        commands.applyFontFamily(family)
      })
      return true
    }
  }

  struct FontFamilyPicker: NSViewControllerRepresentable {
    let currentFamily: String?
    let isMixed: Bool
    let targetLabel: String
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    func makeNSViewController(context: Context) -> FontFamilyPickerController {
      FontFamilyPickerController(currentFamily: currentFamily, isMixed: isMixed, targetLabel: targetLabel, onCommit: onCommit, onCancel: onCancel)
    }

    func updateNSViewController(_ controller: FontFamilyPickerController, context: Context) {
      controller.onCommit = onCommit
      controller.onCancel = onCancel
    }
  }

  @MainActor
  final class FontFamilyPickerController: NSViewController, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let searchField = NSSearchField()
    private let table = FontFamilyTableView()
    private let emptyLabel = NSTextField(labelWithString: "No matching fonts")
    private let clearButton = NSButton(title: "Clear search", target: nil, action: nil)
    private let installedFamilies = NSFontManager.shared.availableFontFamilies
    private var rows: [String] = []
    private let currentFamily: String?
    private let isMixed: Bool
    private let targetLabel: String
    var onCommit: (String) -> Void
    var onCancel: () -> Void

    init(currentFamily: String?, isMixed: Bool, targetLabel: String, onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
      self.currentFamily = currentFamily
      self.isMixed = isMixed
      self.targetLabel = targetLabel
      self.onCommit = onCommit
      self.onCancel = onCancel
      super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func displayName(_ family: String) -> String {
      family.hasPrefix(".") ? "System" : family
    }

    static func families(from installed: [String], query: String) -> [String] {
      let families = [".AppleSystemUIFont"] + Set(installed.filter { !$0.hasPrefix(".") }).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
      let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
      return families.filter { query.isEmpty || displayName($0).localizedStandardContains(query) }
    }

    override func loadView() {
      view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 320))
      preferredContentSize = view.frame.size
      searchField.placeholderString = "Search fonts"
      searchField.setAccessibilityLabel("Search fonts")
      searchField.delegate = self
      searchField.sendsSearchStringImmediately = true
      let context = NSTextField(labelWithString: "Applying to \(targetLabel)")
      context.font = .systemFont(ofSize: 11)
      context.textColor = .secondaryLabelColor
      let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("family"))
      column.width = 250
      table.addTableColumn(column)
      table.headerView = nil
      table.rowHeight = 30
      table.dataSource = self
      table.delegate = self
      table.target = self
      table.action = #selector(commitSelection)
      table.onReturn = { [weak self] in self?.commitSelection() }
      table.setAccessibilityLabel("Font families")
      let scroll = NSScrollView()
      scroll.documentView = table
      scroll.hasVerticalScroller = true
      scroll.drawsBackground = false
      clearButton.target = self
      clearButton.action = #selector(clearSearch)
      clearButton.bezelStyle = .inline
      let empty = NSStackView(views: [emptyLabel, clearButton])
      empty.orientation = .vertical
      let list = NSView()
      for child in [scroll, empty] {
        child.translatesAutoresizingMaskIntoConstraints = false
        list.addSubview(child)
      }
      NSLayoutConstraint.activate([
        scroll.leadingAnchor.constraint(equalTo: list.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: list.trailingAnchor),
        scroll.topAnchor.constraint(equalTo: list.topAnchor), scroll.bottomAnchor.constraint(equalTo: list.bottomAnchor),
        empty.centerXAnchor.constraint(equalTo: list.centerXAnchor), empty.centerYAnchor.constraint(equalTo: list.centerYAnchor),
      ])
      let stack = NSStackView(views: [searchField, context, list])
      stack.orientation = .vertical
      stack.alignment = .leading
      stack.spacing = 8
      stack.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(stack)
      NSLayoutConstraint.activate([
        stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
        stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 12), stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
        searchField.widthAnchor.constraint(equalTo: stack.widthAnchor), list.widthAnchor.constraint(equalTo: stack.widthAnchor),
      ])
      reloadRows()
    }

    override func viewDidAppear() {
      super.viewDidAppear()
      view.window?.makeFirstResponder(searchField)
    }

    func controlTextDidChange(_ notification: Notification) { reloadRows() }

    private func reloadRows() {
      rows = Self.families(from: installedFamilies, query: searchField.stringValue)
      table.reloadData()
      let selected = !isMixed ? rows.firstIndex(of: currentFamily ?? "") : nil
      table.selectRowIndexes(rows.isEmpty ? [] : IndexSet(integer: selected ?? 0), byExtendingSelection: false)
      emptyLabel.superview?.isHidden = !rows.isEmpty
      if table.selectedRow >= 0 { table.scrollRowToVisible(table.selectedRow) }
    }

    @objc private func clearSearch() {
      searchField.stringValue = ""
      reloadRows()
      view.window?.makeFirstResponder(searchField)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
      let family = rows[row]
      let name = NSTextField(labelWithString: Self.displayName(family))
      name.lineBreakMode = .byTruncatingTail
      name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      let sample = NSTextField(labelWithString: "Aa")
      sample.font = EditorTypography.bodyFont(family: family, size: 17)
      let selected = !isMixed && (currentFamily == family || (family == ".AppleSystemUIFont" && currentFamily?.hasPrefix(".") == true))
      let check = NSTextField(labelWithString: selected ? "✓" : "")
      check.widthAnchor.constraint(equalToConstant: 14).isActive = true
      let cell = NSStackView(views: [check, name, sample])
      cell.spacing = 6
      cell.setAccessibilityElement(true)
      cell.setAccessibilityLabel(Self.displayName(family))
      cell.setAccessibilityValue(selected ? "Current font" : "")
      return cell
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
      switch selector {
      case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.moveUp(_:)):
        guard !rows.isEmpty else { return true }
        let step = selector == #selector(NSResponder.moveDown(_:)) ? 1 : -1
        let row = min(max(table.selectedRow + step, 0), rows.count - 1)
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
        return true
      case #selector(NSResponder.insertNewline(_:)):
        commitSelection()
        return true
      case #selector(NSResponder.cancelOperation(_:)):
        cancelOperation(nil)
        return true
      default: return false
      }
    }

    @objc func commitSelection() {
      guard rows.indices.contains(table.selectedRow) else { return }
      onCommit(rows[table.selectedRow])
    }

    override func cancelOperation(_ sender: Any?) { onCancel() }
  }

  private final class FontFamilyTableView: NSTableView {
    var onReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
      if event.keyCode == 36 || event.keyCode == 76 {
        onReturn?()
      } else {
        super.keyDown(with: event)
      }
    }
  }

#endif
