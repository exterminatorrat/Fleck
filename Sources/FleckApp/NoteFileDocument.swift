#if os(macOS)
  import SwiftUI
  import UniformTypeIdentifiers

  struct NoteFileDocument: FileDocument {
    static let markdownContentType = UTType(filenameExtension: "md") ?? .plainText
    static let readableContentTypes: [UTType] = [.plainText, markdownContentType, .rtf]

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
