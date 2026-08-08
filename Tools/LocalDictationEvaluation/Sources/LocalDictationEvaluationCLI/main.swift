import Darwin
import Foundation
import LocalDictationEvaluation

@main
struct LocalDictationEvaluationCLI {
  static func main() {
    exit(run(Array(CommandLine.arguments.dropFirst())))
  }

  static func run(_ arguments: [String]) -> Int32 {
    do {
      let command = try Command.parse(arguments)
      switch command {
      case .validateCorpus(let corpusPath, let corpusSchemaPath):
        let corpus = try read(
          EvaluationCorpus.self,
          path: corpusPath,
          schemaPath: corpusSchemaPath
        )
        let issues = EvaluationValidator.validate(corpus: corpus)
        printIssues(issues)
        return issues.isEmpty ? 0 : 2
      case .validateRun(
        let corpusPath,
        let corpusSchemaPath,
        let runPath,
        let runSchemaPath
      ):
        let corpus = try read(
          EvaluationCorpus.self,
          path: corpusPath,
          schemaPath: corpusSchemaPath
        )
        let run = try read(
          CandidateRun.self,
          path: runPath,
          schemaPath: runSchemaPath
        )
        let issues = EvaluationValidator.validate(run: run, against: corpus)
        printIssues(issues)
        return issues.isEmpty ? 0 : 2
      case .report(
        let corpusPath,
        let corpusSchemaPath,
        let runPath,
        let runSchemaPath,
        let gatePath,
        let outputPath
      ):
        let corpus = try read(
          EvaluationCorpus.self,
          path: corpusPath,
          schemaPath: corpusSchemaPath
        )
        let run = try read(
          CandidateRun.self,
          path: runPath,
          schemaPath: runSchemaPath
        )
        let gate = try readGate(path: gatePath)
        let report = try EvaluationReportBuilder.build(
          corpus: corpus,
          run: run,
          gate: gate
        )
        do {
          try EvaluationReportWriter.atomicWrite(
            report.markdown,
            to: URL(fileURLWithPath: outputPath)
          )
        } catch {
          throw FileError(path: outputPath, kind: "write-failed")
        }
        switch report.releaseDecision {
        case .failed, .reviewRequired:
          return 3
        case .passed, .notEligible:
          return 0
        }
      }
    } catch let error as CommandError {
      fputs("argument error: \(error.message)\n", stderr)
      return 2
    } catch let error as FileError {
      fputs("file error: \(error.path) \(error.kind)\n", stderr)
      return 4
    } catch let error as InputError {
      fputs("input error: \(error.path) \(error.kind)\n", stderr)
      return 2
    } catch let error as EvaluationReportError {
      switch error {
      case .invalid(let issues):
        printIssues(issues)
      case .invalidGate(let field):
        fputs("invalid gate field: \(field)\n", stderr)
      }
      return 2
    } catch {
      fputs("internal error\n", stderr)
      return 4
    }
  }

  private static func read<T: Decodable>(
    _ type: T.Type,
    path: String,
    schemaPath: String
  ) throws -> T {
    let data = try readData(path: path)
    let schema = try readData(path: schemaPath)
    do {
      let issues = try StrictJSONSchema.unknownKeyIssues(
        instanceData: data,
        schemaData: schema
      )
      if let issue = issues.first {
        throw InputError(path: path, kind: "unknown-key:\(issue.path)")
      }
    } catch let error as InputError {
      throw error
    } catch {
      throw InputError(path: path, kind: "invalid-json-or-schema")
    }
    do {
      return try JSONDecoder().decode(T.self, from: data)
    } catch {
      throw InputError(path: path, kind: "invalid-json-or-schema")
    }
  }

  private static func readGate(path: String) throws -> EvaluationGate {
    let data = try readData(path: path)
    do {
      return try JSONDecoder().decode(EvaluationGate.self, from: data)
    } catch {
      throw InputError(path: path, kind: "invalid-json-or-schema")
    }
  }

  private static func readData(path: String) throws -> Data {
    do {
      return try Data(contentsOf: URL(fileURLWithPath: path))
    } catch {
      throw FileError(path: path, kind: "read-failed")
    }
  }

  private static func printIssues(_ issues: [EvaluationIssue]) {
    for issue in issues {
      fputs("\(issue.code) \(issue.path)\n", stderr)
    }
  }
}

private enum Command {
  case validateCorpus(corpus: String, corpusSchema: String)
  case validateRun(
    corpus: String,
    corpusSchema: String,
    run: String,
    runSchema: String
  )
  case report(
    corpus: String,
    corpusSchema: String,
    run: String,
    runSchema: String,
    gate: String,
    output: String
  )

  static func parse(_ arguments: [String]) throws -> Command {
    guard let name = arguments.first else {
      throw CommandError("one command is required")
    }
    var values: [String: String] = [:]
    var index = 1
    while index < arguments.count {
      let flag = arguments[index]
      guard flag.hasPrefix("--"), index + 1 < arguments.count else {
        throw CommandError("expected a flag and value")
      }
      guard values[flag] == nil else {
        throw CommandError("duplicate flag \(flag)")
      }
      let value = arguments[index + 1]
      guard !value.hasPrefix("--") else {
        throw CommandError("missing value for \(flag)")
      }
      values[flag] = value
      index += 2
    }
    func require(_ flags: [String]) throws -> [String] {
      guard Set(values.keys) == Set(flags),
        flags.allSatisfy({ values[$0]?.isEmpty == false })
      else {
        throw CommandError("invalid flags for \(name)")
      }
      return flags.compactMap { values[$0] }
    }
    switch name {
    case "validate-corpus":
      let values = try require(["--corpus", "--corpus-schema"])
      return .validateCorpus(corpus: values[0], corpusSchema: values[1])
    case "validate-run":
      let values = try require([
        "--corpus", "--corpus-schema", "--run", "--run-schema"
      ])
      return .validateRun(
        corpus: values[0],
        corpusSchema: values[1],
        run: values[2],
        runSchema: values[3]
      )
    case "report":
      let values = try require([
        "--corpus", "--corpus-schema", "--run", "--run-schema",
        "--gate", "--output"
      ])
      return .report(
        corpus: values[0],
        corpusSchema: values[1],
        run: values[2],
        runSchema: values[3],
        gate: values[4],
        output: values[5]
      )
    default:
      throw CommandError("unknown command")
    }
  }
}

private struct CommandError: Error {
  let message: String
  init(_ message: String) { self.message = message }
}

private struct FileError: Error {
  let path: String
  let kind: String
}

private struct InputError: Error {
  let path: String
  let kind: String
}
