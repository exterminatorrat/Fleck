import Darwin
import Foundation

@main
struct QwenASRPreflightMain {
  static func main() {
    do {
      try QwenASRPreflight.run(arguments: CommandLine.arguments)
    } catch {
      FileHandle.standardError.write(Data("preflight-failure:\(error)\n".utf8))
      Darwin.exit(2)
    }
  }
}
