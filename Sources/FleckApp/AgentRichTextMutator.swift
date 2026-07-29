#if os(macOS)
  import AppKit
  import FleckCore

  enum AgentChecklistFormattingIntent {
    case none
    case normalizePatchedLine
  }

  enum AgentRichTextMutator {
    static func applying(
      _ draft: AgentMutationDraft,
      operation: AgentActivityOperation,
      checklistFormatting: AgentChecklistFormattingIntent? = nil,
      to note: Note,
      preferences: AppPreferences,
      now: Date = Date()
    ) throws -> Note {
      let defaults = NoteTextAppendDefaults(
        fontFamily: preferences.fontFamily,
        fontSize: preferences.fontSize
      )
      let attributed = try attributedText(for: note, defaults: defaults)
      guard utf16Equal(attributed.string, note.body) else {
        throw unavailable()
      }

      let result: NSMutableAttributedString
      if operation == .appendText {
        result = try append(
          draft,
          to: note,
          defaults: defaults
        )
      } else {
        result = try replace(
          draft,
          in: attributed,
          defaults: defaults
        )
      }

      let formatting =
        checklistFormatting
        ?? ((operation == .renameTask || operation == .setTaskState)
          ? .normalizePatchedLine : .none)
      if formatting == .normalizePatchedLine {
        updateChecklistStrike(
          in: result,
          around: draft.patch.range.location
        )
      }

      let richTextRTF = try serialize(result)
      guard
        let decoded = try? NSAttributedString(
          data: richTextRTF,
          options: [.documentType: NSAttributedString.DocumentType.rtf],
          documentAttributes: nil
        ),
        utf16Equal(decoded.string, draft.body)
      else {
        throw unavailable()
      }

      var updated = note
      updated.body = draft.body
      updated.richTextRTF = richTextRTF
      updated.revision += 1
      updated.modifiedAt = now
      return updated
    }

    private static func append(
      _ draft: AgentMutationDraft,
      to note: Note,
      defaults: NoteTextAppendDefaults
    ) throws -> NSMutableAttributedString {
      let separator = note.body.isEmpty ? "" : "\n\n"
      guard
        draft.patch.range
          == NSRange(location: note.body.utf16.count, length: 0),
        draft.patch.beforeText.isEmpty,
        draft.patch.afterText.hasPrefix(separator)
      else {
        throw unavailable()
      }
      let appendedText = String(draft.patch.afterText.dropFirst(separator.count))
      let appended = NoteTextAppender.appending(
        appendedText,
        to: note,
        defaults: defaults
      )
      guard utf16Equal(appended.body, draft.body) else {
        throw unavailable()
      }
      guard
        let attributed = try? NSMutableAttributedString(
          data: appended.richTextRTF,
          options: [.documentType: NSAttributedString.DocumentType.rtf],
          documentAttributes: nil
        )
      else {
        throw unavailable()
      }
      return attributed
    }

    private static func replace(
      _ draft: AgentMutationDraft,
      in source: NSAttributedString,
      defaults: NoteTextAppendDefaults
    ) throws -> NSMutableAttributedString {
      let range = draft.patch.range
      guard
        range.location != NSNotFound,
        range.location >= 0,
        range.length >= 0,
        NSMaxRange(range) <= source.length,
        utf16Equal(
          (source.string as NSString).substring(with: range),
          draft.patch.beforeText
        )
      else {
        throw unavailable()
      }

      let result = NSMutableAttributedString(attributedString: source)
      result.replaceCharacters(
        in: range,
        with: NSAttributedString(
          string: draft.patch.afterText,
          attributes: [.font: defaults.font]
        )
      )
      guard utf16Equal(result.string, draft.body) else {
        throw unavailable()
      }
      return result
    }

    private static func attributedText(
      for note: Note,
      defaults: NoteTextAppendDefaults
    ) throws -> NSAttributedString {
      guard let richTextRTF = note.richTextRTF else {
        return NSAttributedString(
          string: note.body,
          attributes: [.font: defaults.font]
        )
      }
      guard
        let value = try? NSAttributedString(
          data: richTextRTF,
          options: [.documentType: NSAttributedString.DocumentType.rtf],
          documentAttributes: nil
        )
      else {
        throw unavailable()
      }
      return value
    }

    private static func updateChecklistStrike(
      in attributed: NSMutableAttributedString,
      around location: Int
    ) {
      let source = attributed.string as NSString
      guard source.length > 0 else { return }
      let safeLocation = min(max(location, 0), source.length - 1)
      let lineRange = source.lineRange(
        for: NSRange(location: safeLocation, length: 0)
      )
      let rawLine = source.substring(with: lineRange)
        .trimmingCharacters(in: .newlines)
      let indentationCount = rawLine.prefix(while: { $0 == " " }).utf16.count
      let markerLocation = lineRange.location + indentationCount
      guard
        markerLocation + 2 <= attributed.length,
        source.substring(
          with: NSRange(location: markerLocation + 1, length: 1)
        ) == " "
      else { return }
      let marker = source.substring(
        with: NSRange(location: markerLocation, length: 1)
      )
      guard marker == "○" || marker == "●" else { return }

      let contentLocation = markerLocation + 2
      let contentEnd =
        lineRange.location + rawLine.utf16.count
      guard contentEnd >= contentLocation else { return }
      let contentRange = NSRange(
        location: contentLocation,
        length: contentEnd - contentLocation
      )
      if marker == "●" {
        attributed.addAttribute(
          .strikethroughStyle,
          value: NSUnderlineStyle.single.rawValue,
          range: contentRange
        )
      } else {
        attributed.removeAttribute(
          .strikethroughStyle,
          range: contentRange
        )
      }
    }

    private static func serialize(
      _ attributed: NSAttributedString
    ) throws -> Data {
      do {
        return try attributed.data(
          from: NSRange(location: 0, length: attributed.length),
          documentAttributes: [
            .documentType: NSAttributedString.DocumentType.rtf
          ]
        )
      } catch {
        throw unavailable()
      }
    }

    private static func utf16Equal(_ lhs: String, _ rhs: String) -> Bool {
      lhs.utf16.elementsEqual(rhs.utf16)
    }

    private static func unavailable() -> AgentWorkspaceError {
      AgentWorkspaceError(code: .fleckUnavailable)
    }
  }
#endif
