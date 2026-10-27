#if os(macOS)
  import AppKit
  import FleckCore

  enum NoteRichTextCodec {
    private struct RelativeTailIndent: Codable {
      let location: Int
      let length: Int
      let value: Double
    }

    private static let rtfPrefix = Data("{\\rtf1".utf8)
    private static let metadataPrefix = Data("{\\*\\fleckrelativetailsv1 ".utf8)

    private static func maximumEncodedMetadataBytes(for recordCount: Int) -> Int? {
      let (bytes, overflow) = recordCount.multipliedReportingOverflow(by: 128)
      guard !overflow, bytes <= Int.max - 4 else { return nil }
      let groups = (bytes + 4) / 3
      guard groups <= Int.max / 4 else { return nil }
      return groups * 4
    }

    static func encode(_ attributed: NSAttributedString) throws -> Data {
      var data = try attributed.data(
        from: NSRange(location: 0, length: attributed.length),
        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
      )
      let text = attributed.string as NSString
      var records: [RelativeTailIndent] = []
      var location = 0
      while location < text.length {
        let range = text.paragraphRange(for: NSRange(location: location, length: 0))
        if let style = attributed.attribute(.paragraphStyle, at: location, effectiveRange: nil)
          as? NSParagraphStyle, style.tailIndent < 0, style.tailIndent.isFinite
        {
          records.append(RelativeTailIndent(
            location: range.location, length: range.length, value: Double(style.tailIndent)
          ))
        }
        location = NSMaxRange(range)
      }
      guard !records.isEmpty else { return data }
      guard data.starts(with: rtfPrefix) else { throw CocoaError(.fileWriteUnknown) }
      guard let serialized = try? NSAttributedString(
        data: data,
        options: [.documentType: NSAttributedString.DocumentType.rtf],
        documentAttributes: nil
      ) else { return data }
      let serializedText = serialized.string as NSString
      func paragraphParts(_ string: NSString, _ range: NSRange) -> (String, String) {
        var contentsEnd = 0
        string.getParagraphStart(nil, end: nil, contentsEnd: &contentsEnd, for: range)
        return (
          string.substring(with: NSRange(location: range.location, length: contentsEnd - range.location)),
          string.substring(with: NSRange(location: contentsEnd, length: NSMaxRange(range) - contentsEnd))
        )
      }
      let lineEndings = ["\r\n", "\r", "\n", "\u{2029}"]
      var serializedRecords: [RelativeTailIndent] = []
      var sourceLocation = 0
      var serializedLocation = 0
      var recordIndex = 0
      while sourceLocation < text.length {
        guard serializedLocation < serializedText.length else { return data }
        let sourceRange = text.paragraphRange(for: NSRange(location: sourceLocation, length: 0))
        let serializedRange = serializedText.paragraphRange(
          for: NSRange(location: serializedLocation, length: 0)
        )
        let (sourceContent, sourceEnding) = paragraphParts(text, sourceRange)
        let (serializedContent, serializedEnding) = paragraphParts(serializedText, serializedRange)
        guard sourceContent == serializedContent,
          sourceEnding == serializedEnding
            || (lineEndings.contains(sourceEnding) && lineEndings.contains(serializedEnding))
        else { return data }
        if recordIndex < records.count, records[recordIndex].location == sourceRange.location {
          guard serialized.attribute(.paragraphStyle, at: serializedLocation, effectiveRange: nil)
            is NSParagraphStyle
          else { return data }
          serializedRecords.append(RelativeTailIndent(
            location: serializedRange.location,
            length: serializedRange.length,
            value: records[recordIndex].value
          ))
          recordIndex += 1
        }
        sourceLocation = NSMaxRange(sourceRange)
        serializedLocation = NSMaxRange(serializedRange)
      }
      guard serializedLocation == serializedText.length, recordIndex == records.count else {
        return data
      }
      records = serializedRecords
      let encoder = JSONEncoder()
      encoder.outputFormatting = .sortedKeys
      let payload = Data(try encoder.encode(records).base64EncodedString().utf8)
      guard let maximumBytes = maximumEncodedMetadataBytes(for: records.count),
        payload.count <= maximumBytes
      else { throw CocoaError(.fileWriteUnknown) }
      var metadata = metadataPrefix
      metadata.append(payload)
      metadata.append(0x7d)
      data.insert(contentsOf: metadata, at: rtfPrefix.count)
      return data
    }

    static func decode(_ data: Data) throws -> NSAttributedString {
      let attributed = try NSAttributedString(
        data: data,
        options: [.documentType: NSAttributedString.DocumentType.rtf],
        documentAttributes: nil
      )
      let header = rtfPrefix + metadataPrefix
      guard data.starts(with: header) else { return attributed }
      let text = attributed.string as NSString
      var paragraphCount = 0
      var location = 0
      while location < text.length {
        location = NSMaxRange(text.paragraphRange(for: NSRange(location: location, length: 0)))
        paragraphCount += 1
      }
      guard let maximumBytes = maximumEncodedMetadataBytes(for: paragraphCount) else {
        return attributed
      }
      let start = data.startIndex + header.count
      guard let end = data[start...].prefix(maximumBytes + 1).firstIndex(of: 0x7d),
        let payload = Data(base64Encoded: Data(data[start..<end])),
        let records = try? JSONDecoder().decode([RelativeTailIndent].self, from: payload),
        records.count <= paragraphCount
      else { return attributed }
      var priorEnd = 0
      for record in records {
        guard record.value.isFinite, record.value < 0,
          record.location >= priorEnd, record.location < text.length,
          record.length > 0, record.length <= text.length - record.location,
          text.paragraphRange(for: NSRange(location: record.location, length: 0))
            == NSRange(location: record.location, length: record.length),
          attributed.attribute(.paragraphStyle, at: record.location, effectiveRange: nil)
            is NSParagraphStyle
        else { return attributed }
        priorEnd = record.location + record.length
      }
      let result = NSMutableAttributedString(attributedString: attributed)
      for record in records {
        let style = (result.attribute(.paragraphStyle, at: record.location, effectiveRange: nil)
          as! NSParagraphStyle).mutableCopy() as! NSMutableParagraphStyle
        style.tailIndent = CGFloat(record.value)
        result.addAttribute(
          .paragraphStyle, value: style,
          range: NSRange(location: record.location, length: record.length)
        )
      }
      return result
    }
  }

  struct NoteTextAppendResult {
    let body: String
    let richTextRTF: Data
    let insertedSuffix: String
  }

  struct NoteTextAppendDefaults {
    let fontFamily: String
    let fontSize: CGFloat

    init(fontFamily: String = "Avenir Next", fontSize: CGFloat = 17) {
      self.fontFamily = fontFamily
      self.fontSize = fontSize
    }

    var font: NSFont {
      EditorTypography.bodyFont(family: fontFamily, size: fontSize)
    }

    var attributes: [NSAttributedString.Key: Any] {
      EditorTypography.defaultAttributes(family: fontFamily, size: fontSize)
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
      if appended.length > 0 {
        let priorAttributes = appended.attributes(
          at: appended.length - 1,
          effectiveRange: nil
        )
        appended.append(NSAttributedString(string: "\n", attributes: priorAttributes))
        appended.append(NSAttributedString(string: "\n\(text)", attributes: defaults.attributes))
      } else {
        appended.append(NSAttributedString(string: text, attributes: defaults.attributes))
      }
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
        return NSAttributedString(string: note.body, attributes: defaults.attributes)
      }
      return attributed
    }
  }
#endif
