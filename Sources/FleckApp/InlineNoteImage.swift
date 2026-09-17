#if os(macOS)
  import AppKit
  import ImageIO
  import UniformTypeIdentifiers

  enum InlineNoteImageError: Error, Equatable {
    case invalidFile
    case fileTooLarge
    case unsupportedImage
    case importFailed

    var message: String {
      switch self {
      case .invalidFile:
        "Choose an image file."
      case .fileTooLarge:
        "That image is too large to add to a note."
      case .unsupportedImage:
        "That image format is not supported."
      case .importFailed:
        "Fleck could not copy that image into the note library."
      }
    }
  }

  struct InlineNoteImageImport {
    let reference: String
  }

  @MainActor
  final class InlineNoteImageStore {
    static let directoryName = "InlineNoteImages"
    static let maximumFileSize = 100 * 1_024 * 1_024
    static let maximumPixelCount = 100_000_000

    let rootURL: URL
    private let fileManager: FileManager

    init(rootURL: URL, fileManager: FileManager = .default) {
      self.rootURL = rootURL.standardizedFileURL
      self.fileManager = fileManager
    }

    func importImage(at sourceURL: URL) throws -> InlineNoteImageImport {
      let source = sourceURL.standardizedFileURL
      let metadata = try imageMetadata(at: source)
      let fileExtension = preferredExtension(
        sourceExtension: source.pathExtension,
        typeIdentifier: metadata.typeIdentifier
      )
      let destination = rootURL.appendingPathComponent(
        "\(UUID().uuidString.lowercased()).\(fileExtension)",
        isDirectory: false
      )
      let temporary = rootURL.appendingPathComponent(
        ".\(UUID().uuidString.lowercased()).importing",
        isDirectory: false
      )
      do {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        guard !fileManager.fileExists(atPath: destination.path) else {
          throw InlineNoteImageError.importFailed
        }
        try fileManager.copyItem(at: source, to: temporary)
        _ = try imageMetadata(at: temporary)
        try fileManager.moveItem(at: temporary, to: destination)
      } catch let error as InlineNoteImageError {
        try? fileManager.removeItem(at: temporary)
        throw error
      } catch {
        try? fileManager.removeItem(at: temporary)
        throw InlineNoteImageError.importFailed
      }
      let target = destination.absoluteString
        .replacingOccurrences(of: "(", with: "%28")
        .replacingOccurrences(of: ")", with: "%29")
      return InlineNoteImageImport(reference: "![Image](\(target))")
    }

    func isDeclaredImageFile(_ url: URL) -> Bool {
      guard url.isFileURL, !url.pathExtension.isEmpty,
        let type = UTType(filenameExtension: url.pathExtension)
      else { return false }
      return type.conforms(to: .image)
    }

    func projectedContent(from source: NSAttributedString) -> NSAttributedString {
      let result = NSMutableAttributedString(attributedString: source)
      for match in Self.referenceMatches(in: source.string).reversed() {
        let reference = source.attributedSubstring(from: match.range)
        guard let attachment = projectedAttachment(
          for: reference,
          fileURL: match.fileURL
        ) else {
          continue
        }
        result.replaceCharacters(in: match.range, with: attachment)
      }
      return result
    }

    func projectedAttachment(for reference: NSAttributedString) -> NSAttributedString? {
      guard let match = Self.referenceMatches(in: reference.string).first,
        match.range == NSRange(location: 0, length: reference.length)
      else { return nil }
      return projectedAttachment(for: reference, fileURL: match.fileURL)
    }

    private func projectedAttachment(
      for reference: NSAttributedString,
      fileURL: URL
    ) -> NSAttributedString? {
      guard isManagedImageURL(fileURL),
        let metadata = try? imageMetadata(at: fileURL),
        let image = thumbnail(
          at: fileURL,
          originalSize: metadata.pixelSize
      )
      else { return nil }
      let attachment = InlineNoteImageAttachment(
        sourceReference: reference.string,
        image: image,
        originalPixelSize: metadata.pixelSize,
        accessibilityLabel: "Image file \(fileURL.lastPathComponent)"
      )
      var attributes = reference.length > 0
        ? reference.attributes(at: 0, effectiveRange: nil)
        : [:]
      attributes.removeValue(forKey: .attachment)
      attributes.removeValue(forKey: .link)
      attributes[.attachment] = attachment
      return NSAttributedString(string: "\u{fffc}", attributes: attributes)
    }

    func isManagedImageURL(_ url: URL) -> Bool {
      guard url.isFileURL,
        UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil,
        url.deletingLastPathComponent().standardizedFileURL == rootURL,
        url.resolvingSymlinksInPath().deletingLastPathComponent().standardizedFileURL
          == rootURL.resolvingSymlinksInPath().standardizedFileURL
      else { return false }
      let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
      return values?.isRegularFile == true && values?.isSymbolicLink != true
    }

    private struct ImageMetadata {
      let typeIdentifier: String
      let pixelSize: NSSize
    }

    private func imageMetadata(at url: URL) throws -> ImageMetadata {
      guard url.isFileURL else { throw InlineNoteImageError.invalidFile }
      let values: URLResourceValues
      do {
        values = try url.resourceValues(forKeys: [
          .isRegularFileKey,
          .isSymbolicLinkKey,
          .fileSizeKey,
        ])
      } catch {
        throw InlineNoteImageError.invalidFile
      }
      guard values.isRegularFile == true, values.isSymbolicLink != true else {
        throw InlineNoteImageError.invalidFile
      }
      guard let fileSize = values.fileSize, fileSize <= Self.maximumFileSize else {
        throw InlineNoteImageError.fileTooLarge
      }
      guard let source = CGImageSourceCreateWithURL(
        url as CFURL,
        [kCGImageSourceShouldCache: false] as CFDictionary
      ),
        CGImageSourceGetCount(source) > 0,
        let typeIdentifier = CGImageSourceGetType(source) as String?,
        let type = UTType(typeIdentifier),
        type.conforms(to: .image),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
        width > 0,
        height > 0,
        width <= Self.maximumPixelCount / height
      else {
        throw InlineNoteImageError.unsupportedImage
      }
      let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
      let pixelSize = [5, 6, 7, 8].contains(orientation)
        ? NSSize(width: height, height: width)
        : NSSize(width: width, height: height)
      return ImageMetadata(
        typeIdentifier: typeIdentifier,
        pixelSize: pixelSize
      )
    }

    private func thumbnail(at url: URL, originalSize: NSSize) -> NSImage? {
      guard let source = CGImageSourceCreateWithURL(
        url as CFURL,
        [kCGImageSourceShouldCache: false] as CFDictionary
      ),
        let cgImage = CGImageSourceCreateThumbnailAtIndex(
          source,
          0,
          [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 2_048,
          ] as CFDictionary
        )
      else { return nil }
      return NSImage(cgImage: cgImage, size: originalSize)
    }

    private func preferredExtension(
      sourceExtension: String,
      typeIdentifier: String
    ) -> String {
      let value = sourceExtension.lowercased()
      if !value.isEmpty,
        value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }),
        value.count <= 10
      {
        return value
      }
      return UTType(typeIdentifier)?.preferredFilenameExtension ?? "image"
    }

    private struct ReferenceMatch {
      let range: NSRange
      let fileURL: URL
    }

    static func referenceRanges(in text: String) -> [NSRange] {
      referenceMatches(in: text).map(\.range)
    }

    private static func referenceMatches(in text: String) -> [ReferenceMatch] {
      let range = NSRange(location: 0, length: (text as NSString).length)
      return referenceExpression.matches(in: text, range: range).compactMap { match in
        guard let urlRange = Range(match.range(at: 1), in: text),
          let url = URL(string: String(text[urlRange])),
          url.isFileURL
        else { return nil }
        return ReferenceMatch(range: match.range, fileURL: url)
      }
    }

    private static let referenceExpression = try! NSRegularExpression(
      pattern: #"!\[[^\]\r\n]*\]\((file://[^)\r\n]+)\)"#
    )
  }

  @MainActor
  final class InlineNoteImageAttachment: NSTextAttachment {
    nonisolated let sourceReference: String
    nonisolated let originalPixelSize: NSSize

    init(
      sourceReference: String,
      image: NSImage,
      originalPixelSize: NSSize,
      accessibilityLabel: String
    ) {
      self.sourceReference = sourceReference
      self.originalPixelSize = originalPixelSize
      super.init(data: nil, ofType: nil)
      image.accessibilityDescription = accessibilityLabel
      self.image = image
      let cell = NSTextAttachmentCell(imageCell: image)
      cell.setAccessibilityElement(true)
      cell.setAccessibilityLabel(accessibilityLabel)
      attachmentCell = cell
    }

    required init?(coder: NSCoder) {
      sourceReference = ""
      originalPixelSize = .zero
      super.init(coder: coder)
    }

    override func attachmentBounds(
      for textContainer: NSTextContainer?,
      proposedLineFragment lineFrag: NSRect,
      glyphPosition position: NSPoint,
      characterIndex charIndex: Int
    ) -> NSRect {
      guard originalPixelSize.width > 0, originalPixelSize.height > 0 else {
        return .zero
      }
      let availableWidth = max(1, lineFrag.width)
      let scale = min(
        1,
        availableWidth / originalPixelSize.width,
        320 / originalPixelSize.height
      )
      return NSRect(
        x: 0,
        y: 0,
        width: floor(originalPixelSize.width * scale),
        height: floor(originalPixelSize.height * scale)
      )
    }
  }

  enum InlineNoteImageProjection {
    static func expanded(_ display: NSAttributedString) -> NSAttributedString {
      let result = NSMutableAttributedString(attributedString: display)
      var replacements: [(NSRange, NSAttributedString)] = []
      display.enumerateAttribute(
        .attachment,
        in: NSRange(location: 0, length: display.length)
      ) { value, range, _ in
        guard let attachment = value as? InlineNoteImageAttachment else { return }
        var attributes = display.attributes(at: range.location, effectiveRange: nil)
        attributes.removeValue(forKey: .attachment)
        attributes.removeValue(forKey: .link)
        replacements.append((
          range,
          NSAttributedString(
            string: attachment.sourceReference,
            attributes: attributes
          )
        ))
      }
      for (range, sourceReference) in replacements.reversed() {
        result.replaceCharacters(in: range, with: sourceReference)
      }
      return result
    }

    static func sourceRange(
      forDisplayRange range: NSRange,
      in display: NSAttributedString
    ) -> NSRange {
      guard range.location != NSNotFound,
        range.location >= 0,
        NSMaxRange(range) <= display.length
      else { return NSRange(location: 0, length: 0) }
      let start = sourceLocation(forDisplayLocation: range.location, in: display)
      let end = sourceLocation(forDisplayLocation: NSMaxRange(range), in: display)
      return NSRange(location: start, length: max(0, end - start))
    }

    static func displayRange(
      forSourceRange range: NSRange,
      in display: NSAttributedString
    ) -> NSRange {
      let sourceLength = expanded(display).length
      guard range.location != NSNotFound,
        range.location >= 0,
        NSMaxRange(range) <= sourceLength
      else { return NSRange(location: 0, length: 0) }
      if range.length == 0 {
        return NSRange(
          location: displayLocation(
            forSourceLocation: range.location,
            in: display,
            towardEnd: false
          ),
          length: 0
        )
      }
      let start = displayLocation(
        forSourceLocation: range.location,
        in: display,
        towardEnd: false
      )
      let end = displayLocation(
        forSourceLocation: NSMaxRange(range),
        in: display,
        towardEnd: true
      )
      return NSRange(location: start, length: max(0, end - start))
    }

    private static func sourceLocation(
      forDisplayLocation location: Int,
      in display: NSAttributedString
    ) -> Int {
      var delta = 0
      for (range, referenceLength) in attachments(in: display) {
        if location <= range.location { break }
        delta += referenceLength - range.length
      }
      return location + delta
    }

    private static func displayLocation(
      forSourceLocation location: Int,
      in display: NSAttributedString,
      towardEnd: Bool
    ) -> Int {
      var delta = 0
      for (range, referenceLength) in attachments(in: display) {
        let sourceStart = range.location + delta
        let sourceEnd = sourceStart + referenceLength
        if location <= sourceStart { break }
        if location < sourceEnd {
          return range.location + (towardEnd ? range.length : 0)
        }
        delta += referenceLength - range.length
      }
      return location - delta
    }

    private static func attachments(
      in display: NSAttributedString
    ) -> [(NSRange, Int)] {
      var result: [(NSRange, Int)] = []
      display.enumerateAttribute(
        .attachment,
        in: NSRange(location: 0, length: display.length)
      ) { value, range, _ in
        guard let attachment = value as? InlineNoteImageAttachment else { return }
        result.append((range, attachment.sourceReference.utf16.count))
      }
      return result
    }
  }
#endif
