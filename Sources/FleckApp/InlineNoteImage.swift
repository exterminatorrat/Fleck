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

  struct InlineNoteImageReference: Equatable, Sendable {
    static let transformTitlePrefix = "fleck:"
    static let maximumDimension = 20_000.0

    let altText: String
    let urlText: String
    let titleText: String?
    let transform: InlineImageTransform?

    var url: URL? {
      URL(string: urlText)
    }

    var text: String {
      guard let titleText else { return "![\(altText)](\(urlText))" }
      return "![\(altText)](\(urlText) \"\(titleText)\")"
    }

    func replacingTransform(_ transform: InlineImageTransform?) -> InlineNoteImageReference? {
      guard let transform else {
        return InlineNoteImageReference(
          altText: altText,
          urlText: urlText,
          titleText: nil,
          transform: nil
        )
      }
      guard let title = Self.title(for: transform),
        let persisted = Self.transform(fromTitle: title)
      else { return nil }
      return InlineNoteImageReference(
        altText: altText,
        urlText: urlText,
        titleText: title,
        transform: persisted
      )
    }

    struct Match {
      let range: NSRange
      let reference: InlineNoteImageReference
    }

    static func parse(_ text: String) -> InlineNoteImageReference? {
      let matches = matches(in: text)
      let whole = NSRange(location: 0, length: (text as NSString).length)
      guard matches.count == 1, matches[0].range == whole else { return nil }
      return matches[0].reference
    }

    static func matches(in text: String) -> [Match] {
      let source = text as NSString
      let whole = NSRange(location: 0, length: source.length)
      return expression.matches(in: text, range: whole).compactMap { match in
        let urlText = source.substring(with: match.range(at: 2))
        guard let url = URL(string: urlText), url.isFileURL else { return nil }
        let titleRange = match.range(at: 3)
        let titleText = titleRange.location == NSNotFound
          ? nil
          : source.substring(with: titleRange)
        let parsedTransform: InlineImageTransform?
        if let titleText {
          guard let parsed = transform(fromTitle: titleText) else { return nil }
          parsedTransform = parsed
        } else {
          parsedTransform = nil
        }
        return Match(
          range: match.range,
          reference: InlineNoteImageReference(
            altText: source.substring(with: match.range(at: 1)),
            urlText: urlText,
            titleText: titleText,
            transform: parsedTransform
          )
        )
      }
    }

    static func title(for transform: InlineImageTransform) -> String? {
      guard transform.isValid,
        let width = persistedDimension(transform.size.width),
        let height = persistedDimension(transform.size.height),
        let degrees = persistedDegrees(transform.rotationDegrees)
      else { return nil }
      return "\(transformTitlePrefix)\(width)x\(height)@\(degrees)"
    }

    static func transform(fromTitle title: String) -> InlineImageTransform? {
      guard title.hasPrefix(transformTitlePrefix) else { return nil }
      let body = title.dropFirst(transformTitlePrefix.count)
      guard let sizeMark = body.firstIndex(of: "x"),
        let rotationMark = body.lastIndex(of: "@"),
        sizeMark < rotationMark
      else { return nil }
      let widthText = body[..<sizeMark]
      let heightText = body[body.index(after: sizeMark)..<rotationMark]
      let degreesText = body[body.index(after: rotationMark)...]
      guard let width = parsedNumber(widthText),
        let height = parsedNumber(heightText),
        let degrees = parsedNumber(degreesText),
        width > 0,
        height > 0,
        width <= maximumDimension,
        height <= maximumDimension,
        degrees >= 0,
        degrees < 360
      else { return nil }
      return InlineImageTransform(
        size: CGSize(width: width, height: height),
        rotationDegrees: degrees
      )
    }

    private static func persistedDimension(_ value: CGFloat) -> String? {
      let dimension = Double(value)
      guard dimension.isFinite, dimension > 0, dimension <= maximumDimension else { return nil }
      let hundredths = Int((dimension * 100).rounded())
      guard hundredths > 0 else { return nil }
      return decimalText(hundredths)
    }

    private static func persistedDegrees(_ value: Double) -> String? {
      guard value.isFinite, value >= 0, value < 360 else { return nil }
      return decimalText(Int((value * 100).rounded()) % 36_000)
    }

    private static func decimalText(_ hundredths: Int) -> String {
      let whole = hundredths / 100
      let fraction = hundredths % 100
      guard fraction != 0 else { return String(whole) }
      guard fraction % 10 != 0 else { return "\(whole).\(fraction / 10)" }
      return "\(whole).\(fraction < 10 ? "0" : "")\(fraction)"
    }

    private static func parsedNumber(_ text: Substring) -> Double? {
      guard !text.isEmpty, text.count <= 12 else { return nil }
      var digits = 0
      var dots = 0
      for scalar in text.unicodeScalars {
        if scalar.value >= 48, scalar.value <= 57 {
          digits += 1
        } else if scalar == "." {
          dots += 1
          guard dots == 1, digits > 0 else { return nil }
        } else {
          return nil
        }
      }
      guard digits > 0, text.last != "." else { return nil }
      return Double(text)
    }

    private static let expression = try! NSRegularExpression(
      pattern: #"!\[([^\]\r\n]*)\]\((file://[^)\s\r\n]+)(?:[ \t]+"([^"\r\n]*)")?\)"#
    )
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
      for match in InlineNoteImageReference.matches(in: source.string).reversed() {
        let reference = source.attributedSubstring(from: match.range)
        guard let attachment = projectedAttachment(
          for: reference,
          reference: match.reference
        ) else {
          continue
        }
        result.replaceCharacters(in: match.range, with: attachment)
      }
      return result
    }

    func projectedAttachment(for reference: NSAttributedString) -> NSAttributedString? {
      guard let parsed = InlineNoteImageReference.parse(reference.string) else { return nil }
      return projectedAttachment(for: reference, reference: parsed)
    }

    private func projectedAttachment(
      for source: NSAttributedString,
      reference: InlineNoteImageReference
    ) -> NSAttributedString? {
      guard let fileURL = reference.url,
        isManagedImageURL(fileURL),
        let metadata = try? imageMetadata(at: fileURL),
        let image = thumbnail(
          at: fileURL,
          originalSize: metadata.pixelSize
        )
      else { return nil }
      let attachment = InlineNoteImageAttachment(
        sourceReference: reference.text,
        image: image,
        originalPixelSize: metadata.pixelSize,
        accessibilityLabel: "Image file \(fileURL.lastPathComponent)"
      )
      var attributes = source.length > 0
        ? source.attributes(at: 0, effectiveRange: nil)
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

    static func referenceRanges(in text: String) -> [NSRange] {
      InlineNoteImageReference.matches(in: text).map(\.range)
    }
  }

  @MainActor
  final class InlineNoteImageAttachment: NSTextAttachment {
    nonisolated static let maximumRenderedEdge: CGFloat = 2_048

    nonisolated let sourceReference: String
    nonisolated let originalPixelSize: NSSize
    nonisolated let reference: InlineNoteImageReference?
    nonisolated let displayTransform: InlineImageTransform?
    nonisolated let imageAccessibilityLabel: String
    let originalImage: NSImage

    init(
      sourceReference: String,
      image: NSImage,
      originalPixelSize: NSSize,
      accessibilityLabel: String
    ) {
      let parsed = InlineNoteImageReference.parse(sourceReference)
      self.sourceReference = sourceReference
      self.originalPixelSize = originalPixelSize
      self.reference = parsed
      self.displayTransform = parsed?.transform
      self.imageAccessibilityLabel = accessibilityLabel
      self.originalImage = image
      super.init(data: nil, ofType: nil)
      install(image: image)
    }

    private init(
      reference: InlineNoteImageReference,
      image: NSImage,
      originalPixelSize: NSSize,
      accessibilityLabel: String
    ) {
      self.sourceReference = reference.text
      self.originalPixelSize = originalPixelSize
      self.reference = reference
      self.displayTransform = reference.transform
      self.imageAccessibilityLabel = accessibilityLabel
      self.originalImage = image
      super.init(data: nil, ofType: nil)
      install(image: image)
    }

    required init?(coder: NSCoder) {
      sourceReference = ""
      originalPixelSize = .zero
      reference = nil
      displayTransform = nil
      imageAccessibilityLabel = ""
      originalImage = NSImage(size: .zero)
      super.init(coder: coder)
    }

    private func install(image: NSImage) {
      image.accessibilityDescription = imageAccessibilityLabel
      guard let displayTransform else {
        self.image = image
        return
      }
      let rendered = Self.renderedImage(original: image, transform: displayTransform)
      rendered.accessibilityDescription = imageAccessibilityLabel
      self.image = rendered
    }

    func replacingTransform(_ transform: InlineImageTransform?) -> InlineNoteImageAttachment? {
      guard let reference, let next = reference.replacingTransform(transform) else { return nil }
      return InlineNoteImageAttachment(
        reference: next,
        image: originalImage,
        originalPixelSize: originalPixelSize,
        accessibilityLabel: imageAccessibilityLabel
      )
    }

    nonisolated func effectiveTransform(fitting bounds: NSRect) -> InlineImageTransform {
      guard let displayTransform, displayTransform.isValid else {
        return InlineImageTransform(
          size: CGSize(width: max(0, bounds.width), height: max(0, bounds.height))
        )
      }
      let envelope = displayTransform.rotatedSize
      guard envelope.width > 0, envelope.height > 0, bounds.width > 0 else {
        return displayTransform
      }
      return displayTransform.fitting(availableWidth: bounds.width)
    }

    static func renderedImage(
      original: NSImage,
      transform: InlineImageTransform?
    ) -> NSImage {
      guard let transform, transform.isValid else { return original }
      let envelope = transform.rotatedSize
      guard envelope.width > 0, envelope.height > 0 else { return original }
      let scale = min(2, maximumRenderedEdge / max(envelope.width, envelope.height))
      let rasterSize = CGSize(
        width: max(1, (envelope.width * scale).rounded(.up)),
        height: max(1, (envelope.height * scale).rounded(.up))
      )
      guard let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
          data: nil,
          width: Int(rasterSize.width),
          height: Int(rasterSize.height),
          bitsPerComponent: 8,
          bytesPerRow: 0,
          space: space,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
      else { return original }
      context.translateBy(x: 0, y: rasterSize.height)
      context.scaleBy(x: 1, y: -1)
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
      InlineNoteImageRendering.draw(
        image: original,
        transform: transform,
        in: NSRect(origin: .zero, size: rasterSize)
      )
      NSGraphicsContext.restoreGraphicsState()
      guard let raster = context.makeImage() else { return original }
      return NSImage(cgImage: raster, size: envelope)
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
      guard let displayTransform, displayTransform.isValid else {
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
      let envelope = displayTransform.rotatedSize
      let scale = min(1, availableWidth / envelope.width)
      return NSRect(
        x: 0,
        y: 0,
        width: min(envelope.width * scale, availableWidth),
        height: envelope.height * scale
      )
    }
  }

  @MainActor
  private enum InlineNoteImageRendering {
    static func draw(image: NSImage, transform: InlineImageTransform?, in frame: NSRect) {
      guard frame.width > 0, frame.height > 0 else { return }
      guard let transform, transform.isValid else {
        image.draw(
          in: frame,
          from: .zero,
          operation: .sourceOver,
          fraction: 1,
          respectFlipped: true,
          hints: nil
        )
        return
      }
      let envelope = transform.rotatedSize
      guard envelope.width > 0, envelope.height > 0 else { return }
      let scale = min(frame.width / envelope.width, frame.height / envelope.height)
      let content = NSRect(
        x: frame.midX - transform.size.width * scale / 2,
        y: frame.midY - transform.size.height * scale / 2,
        width: transform.size.width * scale,
        height: transform.size.height * scale
      )
      NSGraphicsContext.saveGraphicsState()
      let rotation = NSAffineTransform()
      rotation.translateX(by: frame.midX, yBy: frame.midY)
      rotation.rotate(byDegrees: CGFloat(transform.rotationDegrees))
      rotation.translateX(by: -frame.midX, yBy: -frame.midY)
      rotation.concat()
      image.draw(
        in: content,
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: nil
      )
      NSGraphicsContext.restoreGraphicsState()
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
