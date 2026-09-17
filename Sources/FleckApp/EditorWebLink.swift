#if os(macOS)
  import AppKit
  import Darwin
  import FleckCore
  import SwiftUI

  enum EditorWebLink {
    static func validatedURL(_ text: String) -> URL? {
      guard !text.isEmpty,
        text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
        !text.contains(where: \.isWhitespace),
        let components = URLComponents(string: text),
        let scheme = components.scheme?.lowercased(),
        scheme == "https" || scheme == "http",
        let host = components.host, isValidHost(host),
        let url = components.url
      else { return nil }
      return url
    }

    private static func isValidHost(_ host: String) -> Bool {
      if host.hasPrefix("["), host.hasSuffix("]") {
        var parsed = in6_addr()
        return String(host.dropFirst().dropLast()).withCString {
          inet_pton(AF_INET6, $0, &parsed) == 1
        }
      }
      let labels = host.split(separator: ".", omittingEmptySubsequences: false)
      guard labels.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 63 }) else { return false }
      return labels.allSatisfy { label in
        guard let first = label.unicodeScalars.first,
          let last = label.unicodeScalars.last,
          CharacterSet.alphanumerics.contains(first),
          CharacterSet.alphanumerics.contains(last)
        else { return false }
        return label.unicodeScalars.allSatisfy {
          CharacterSet.alphanumerics.contains($0) || $0 == "-"
        }
      }
    }
  }

  @MainActor
  final class EditorNoteLinkTarget: NSObject {
    private enum PermitState {
      case captured
      case pickerBlocked(generation: UInt64)
      case validated(blockedGeneration: UInt64, applyGeneration: UInt64)
      case consumed
      case invalidated
    }

    let noteID: UUID
    let noteRevision: UInt64
    let range: NSRange
    private weak var textView: NSTextView?
    private weak var storage: NSTextStorage?
    private let expectedText: NSAttributedString
    private let capturedSessionGeneration: UInt64
    private var permitState = PermitState.captured

    init?(note: Note, range: NSRange, commands: EditorCommands) {
      guard commands.canPerformBodyCommand, let textView = commands.textView,
        let storage = textView.textStorage,
        range.location != NSNotFound, range.location >= 0,
        NSMaxRange(range) <= storage.length
      else { return nil }
      noteID = note.id
      noteRevision = note.revision
      self.range = range
      expectedText = storage.attributedSubstring(from: range)
      capturedSessionGeneration = commands.editorSessionGeneration
      self.textView = textView
      self.storage = storage
      super.init()
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(invalidate),
        name: NSTextStorage.didProcessEditingNotification,
        object: storage
      )
    }

    func capturePickerBlock(commands: EditorCommands) -> Bool {
      guard case .captured = permitState,
        commands.areBodyCommandsBlocked,
        let textView, let storage,
        commands.textView === textView, textView.textStorage === storage,
        commands.editorSessionGeneration == capturedSessionGeneration &+ 1
      else {
        permitState = .invalidated
        return false
      }
      permitState = .pickerBlocked(generation: commands.editorSessionGeneration)
      return true
    }

    func isValidAfterPickerDismissal(
      note: Note?,
      isEditorVisible: Bool,
      commands: EditorCommands
    ) -> Bool {
      let blockedGeneration: UInt64
      switch permitState {
      case .pickerBlocked(let generation):
        blockedGeneration = generation
      case .validated(let generation, _):
        blockedGeneration = generation
      case .captured, .consumed, .invalidated:
        permitState = .invalidated
        return false
      }
      guard isEditorVisible,
        note?.id == noteID, note?.revision == noteRevision,
        let textView, let storage,
        commands.textView === textView, textView.textStorage === storage,
        commands.areBodyCommandsBlocked,
        commands.editorSessionGeneration == blockedGeneration,
        range.location >= 0, NSMaxRange(range) <= storage.length,
        storage.attributedSubstring(from: range).isEqual(to: expectedText)
      else {
        permitState = .invalidated
        return false
      }
      permitState = .validated(
        blockedGeneration: blockedGeneration,
        applyGeneration: blockedGeneration &+ 1
      )
      return true
    }

    @discardableResult
    func apply(label: String, targetNoteID: UUID, commands: EditorCommands) -> Bool {
      guard case .validated(_, let applyGeneration) = permitState else {
        permitState = .invalidated
        return false
      }
      permitState = .consumed
      guard commands.editorSessionGeneration == applyGeneration,
        commands.canPerformBodyCommand,
        let textView, let storage,
        commands.textView === textView, textView.textStorage === storage,
        range.location >= 0, NSMaxRange(range) <= storage.length,
        storage.attributedSubstring(from: range).isEqual(to: expectedText)
      else { return false }
      return commands.insertNoteLink(
        replacing: range,
        label: label,
        targetNoteID: targetNoteID,
        expectedTextView: textView,
        expectedStorage: storage
      )
    }

    func cancel() { permitState = .invalidated }

    @objc private func invalidate() { permitState = .invalidated }
  }

  @MainActor
  final class EditorWebLinkTarget: NSObject {
    let noteID: UUID
    let noteRevision: UInt64
    let range: NSRange
    let existingURL: URL?
    let existingDisplayText: String
    private weak var textView: NSTextView?
    private weak var storage: NSTextStorage?
    private let capturedSelection: NSRange
    private let sessionGeneration: UInt64
    private var invalidated = false

    init?(note: Note, commands: EditorCommands) {
      guard commands.canPerformBodyCommand, let textView = commands.textView,
        let storage = textView.textStorage
      else { return nil }
      let selection = textView.selectedRange()
      guard selection.location != NSNotFound, selection.location >= 0,
        NSMaxRange(selection) <= storage.length
      else { return nil }
      guard !NoteLinkParser.links(in: textView.string).contains(where: { link in
        selection.length == 0
          ? selection.location >= link.range.location && selection.location < NSMaxRange(link.range)
          : NSIntersectionRange(link.range, selection).length > 0
      }) else { return nil }

      var targetRange = selection
      var targetURL: URL?
      if selection.length == 0, selection.location < storage.length {
        var effectiveRange = NSRange(location: 0, length: 0)
        let value = storage.attribute(
          .link,
          at: selection.location,
          longestEffectiveRange: &effectiveRange,
          in: NSRange(location: 0, length: storage.length)
        )
        if let url = Self.webURL(from: value) {
          targetRange = effectiveRange
          targetURL = url
        }
      } else if selection.length > 0, selection.location < storage.length {
        var effectiveRange = NSRange(location: 0, length: 0)
        let value = storage.attribute(
          .link,
          at: selection.location,
          longestEffectiveRange: &effectiveRange,
          in: NSRange(location: 0, length: storage.length)
        )
        if NSIntersectionRange(effectiveRange, selection) == selection,
          let url = Self.webURL(from: value)
        {
          targetRange = effectiveRange
          targetURL = url
        }
      }

      guard !EditorCommands.containsAttachment(in: targetRange, storage: storage) else {
        return nil
      }
      noteID = note.id
      noteRevision = note.revision
      range = targetRange
      capturedSelection = selection
      sessionGeneration = commands.editorSessionGeneration
      existingURL = targetURL
      existingDisplayText = targetRange.length > 0
        ? storage.attributedSubstring(from: targetRange).string
        : ""
      self.textView = textView
      self.storage = storage
      super.init()
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(invalidate),
        name: NSTextStorage.didProcessEditingNotification,
        object: storage
      )
    }

    var isEditingExistingLink: Bool { existingURL != nil }

    func isValid(
      note: Note?,
      isEditorVisible: Bool,
      commands: EditorCommands
    ) -> Bool {
      guard !invalidated, isEditorVisible,
        note?.id == noteID, note?.revision == noteRevision,
        let textView, let storage,
        commands.textView === textView, textView.textStorage === storage,
        commands.editorSessionGeneration == sessionGeneration,
        commands.canPerformBodyCommand,
        textView.selectedRange() == capturedSelection,
        range.location >= 0, NSMaxRange(range) <= storage.length
      else { return false }
      return true
    }

    func cancel() { invalidated = true }

    @discardableResult
    func apply(
      urlText: String,
      displayText: String?,
      note: Note?,
      isEditorVisible: Bool,
      commands: EditorCommands
    ) -> Bool {
      guard let url = EditorWebLink.validatedURL(urlText),
        isValid(note: note, isEditorVisible: isEditorVisible, commands: commands),
        let textView, let storage
      else { return false }
      let applied = commands.applyWebLink(
        url: url,
        range: range,
        displayText: displayText,
        expectedTextView: textView,
        expectedStorage: storage
      )
      if applied { invalidated = true }
      return applied
    }

    @discardableResult
    func remove(
      note: Note?,
      isEditorVisible: Bool,
      commands: EditorCommands
    ) -> Bool {
      guard existingURL != nil,
        isValid(note: note, isEditorVisible: isEditorVisible, commands: commands),
        let textView, let storage
      else { return false }
      let removed = commands.removeWebLink(
        range: range,
        expectedTextView: textView,
        expectedStorage: storage
      )
      if removed { invalidated = true }
      return removed
    }

    @objc private func invalidate() { invalidated = true }

    private static func webURL(from value: Any?) -> URL? {
      if let url = value as? URL {
        return EditorWebLink.validatedURL(url.absoluteString)
      }
      if let string = value as? String {
        return EditorWebLink.validatedURL(string)
      }
      return nil
    }
  }

  struct EditorWebLinkPopover: View {
    let target: EditorWebLinkTarget
    let onApply: (String, String?) -> Bool
    let onRemove: () -> Bool
    let onCancel: () -> Void
    @State private var urlText: String
    @State private var displayText: String
    @State private var validationMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field { case url, display }

    init(
      target: EditorWebLinkTarget,
      onApply: @escaping (String, String?) -> Bool,
      onRemove: @escaping () -> Bool,
      onCancel: @escaping () -> Void
    ) {
      self.target = target
      self.onApply = onApply
      self.onRemove = onRemove
      self.onCancel = onCancel
      _urlText = State(initialValue: target.existingURL?.absoluteString ?? "https://")
      _displayText = State(initialValue: target.existingDisplayText)
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 10) {
        Text(target.isEditingExistingLink ? "Edit Web Link" : "Add Web Link")
          .font(.headline)
        TextField("URL", text: $urlText)
          .focused($focusedField, equals: .url)
          .accessibilityLabel("Web link URL")
        if !target.isEditingExistingLink {
          TextField("Display text (optional)", text: $displayText)
            .focused($focusedField, equals: .display)
            .accessibilityLabel("Web link display text")
        }
        if let validationMessage {
          Text(validationMessage)
            .font(.caption)
            .foregroundStyle(.red)
            .accessibilityLabel("Web link error: \(validationMessage)")
        }
        HStack {
          if target.isEditingExistingLink {
            Button("Remove", role: .destructive) {
              if onRemove() { onCancel() }
            }
          }
          Spacer()
          Button("Cancel", action: onCancel)
          Button("Apply") {
            guard EditorWebLink.validatedURL(urlText) != nil else {
              validationMessage = "Enter an absolute http or https URL with a host."
              return
            }
            if onApply(urlText, displayText.isEmpty ? nil : displayText) {
              onCancel()
            } else {
              validationMessage = "The editing target changed. Open Web Link again."
            }
          }
          .keyboardShortcut(.defaultAction)
        }
      }
      .frame(width: 320)
      .padding(12)
      .onAppear { focusedField = .url }
    }
  }
#endif
