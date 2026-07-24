import Foundation

public enum MarkdownEditing {
    public enum ListStyle: Sendable {
        case bullets
        case numbers
    }

    public static func togglingList(in text: String, style: ListStyle) -> String {
        let lines = text.components(separatedBy: "\n")
        let allFormatted = !lines.isEmpty && lines.allSatisfy { line in
            switch style {
            case .bullets:
                line.hasPrefix("- ")
            case .numbers:
                line.range(of: #"^\d+\. "#, options: .regularExpression) != nil
            }
        }

        return lines.enumerated().map { index, line in
            if allFormatted {
                switch style {
                case .bullets:
                    return String(line.dropFirst(2))
                case .numbers:
                    return line.replacingOccurrences(
                        of: #"^\d+\. "#,
                        with: "",
                        options: .regularExpression
                    )
                }
            }

            switch style {
            case .bullets:
                return "- \(line)"
            case .numbers:
                return "\(index + 1). \(line)"
            }
        }.joined(separator: "\n")
    }
}
