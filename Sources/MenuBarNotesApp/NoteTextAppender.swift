#if os(macOS)
  import AppKit
  import MenuBarNotesCore

  struct NoteTextAppendResult {
    let body: String
    let richTextRTF: Data
    let insertedSuffix: String
  }

  enum NoteTextAppender {
    static func appending(_ text: String, to note: Note) -> NoteTextAppendResult {
      let suffix = (note.body.isEmpty ? "" : "\n\n") + text
      let appended = NSMutableAttributedString(attributedString: attributedText(for: note))
      appended.append(NSAttributedString(string: suffix))
      let rtf = try! appended.data(
        from: NSRange(location: 0, length: appended.length),
        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
      )
      return NoteTextAppendResult(
        body: note.body + suffix,
        richTextRTF: rtf,
        insertedSuffix: suffix
      )
    }

    private static func attributedText(for note: Note) -> NSAttributedString {
      guard let rtf = note.richTextRTF,
        let attributed = try? NSAttributedString(
          data: rtf,
          options: [.documentType: NSAttributedString.DocumentType.rtf],
          documentAttributes: nil
        )
      else {
        return NSAttributedString(string: note.body)
      }
      return attributed
    }
  }
#endif
