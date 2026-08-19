import Darwin
import Foundation
import FleckModelEvaluation

@main
struct FleckModelEvaluator {
    static func main() {
        guard CommandLine.arguments.count == 3 else {
            writeError("Usage: fleck-model-eval <input.json> <output.json>\n")
            Darwin.exit(2)
        }

        let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

        do {
            let inputData = try Data(contentsOf: inputURL)
            let input = try JSONDecoder().decode(
                ModelEvaluationRunInput.self,
                from: inputData
            )
            let report = try ModelEvaluationScorer.score(input)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let outputData = try encoder.encode(report)
            try outputData.write(to: outputURL, options: .atomic)
        } catch {
            writeError("fleck-model-eval failed: \(error)\n")
            Darwin.exit(1)
        }
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data(message.utf8))
    }
}
