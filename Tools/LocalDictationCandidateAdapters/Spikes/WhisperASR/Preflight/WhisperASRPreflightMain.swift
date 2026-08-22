import Foundation

@main
struct WhisperASRPreflightMain {
  static func main() {
    do {
      try WhisperASRPreflight.run(arguments: CommandLine.arguments)
    } catch {
      FileHandle.standardError.write(Data("preflight-failure:\(error)\n".utf8))
      exit(2)
    }
  }
}
