import Foundation

@main
struct NemotronASRPreflightMain {
  static func main() {
    do {
      try NemotronASRPreflight.run(arguments: CommandLine.arguments)
    } catch {
      FileHandle.standardError.write(Data("preflight-failure:\(error)\n".utf8))
      exit(2)
    }
  }
}
