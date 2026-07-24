#if os(macOS)
  import SwiftUI
  import UniformTypeIdentifiers

  extension UTType {
    /// Markdown does not have a built-in `UTType.markdown` member on every supported SDK.
    static let markdownText = UTType(importedAs: "net.daringfireball.markdown")
  }

  struct NoteFileDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText, .markdownText, .rtf]

    var data: Data

    init(data: Data = Data()) {
      self.data = data
    }

    init(configuration: ReadConfiguration) throws {
      data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
      FileWrapper(regularFileWithContents: data)
    }
  }
#endif
