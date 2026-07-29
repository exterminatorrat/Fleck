#if os(macOS)
  import AppKit
  import FleckCore

  struct NoteTextAppendResult {
    let body: String
    let richTextRTF: Data
    let insertedSuffix: String
  }

  struct NoteTextAppendDefaults {
    let fontFamily: String
    let fontSize: CGFloat

    init(fontFamily: String = ".AppleSystemUIFont", fontSize: CGFloat = 15) {
      self.fontFamily = fontFamily
      self.fontSize = fontSize
    }

    var font: NSFont {
      NSFontManager.shared.convert(NSFont.systemFont(ofSize: fontSize), toFamily: fontFamily)
    }
  }

  enum NoteTextAppender {
    static func appending(_ text: String, to note: Note) -> NoteTextAppendResult {
      appending(text, to: note, defaults: NoteTextAppendDefaults())
    }

    static func appending(
      _ text: String,
      to note: Note,
      defaults: NoteTextAppendDefaults
    ) -> NoteTextAppendResult {
      let suffix = (note.body.isEmpty ? "" : "\n\n") + text
      let appended = NSMutableAttributedString(attributedString: attributedText(for: note, defaults: defaults))
      appended.append(NSAttributedString(string: suffix, attributes: [.font: defaults.font]))
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

    private static func attributedText(
      for note: Note,
      defaults: NoteTextAppendDefaults
    ) -> NSAttributedString {
      guard let rtf = note.richTextRTF,
        let attributed = try? NSAttributedString(
          data: rtf,
          options: [.documentType: NSAttributedString.DocumentType.rtf],
          documentAttributes: nil
        )
      else {
        return NSAttributedString(string: note.body, attributes: [.font: defaults.font])
      }
      return attributed
    }
  }
#endif
