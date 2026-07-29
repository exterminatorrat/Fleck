#if os(macOS)
  import Foundation

  enum ShellArgument {
    static func encode(_ value: String) -> String {
      let safe = CharacterSet.alphanumerics.union(
        CharacterSet(charactersIn: "_@%+=:,./-")
      )
      if value.unicodeScalars.allSatisfy(safe.contains) {
        return value
      }
      return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
  }
#endif
