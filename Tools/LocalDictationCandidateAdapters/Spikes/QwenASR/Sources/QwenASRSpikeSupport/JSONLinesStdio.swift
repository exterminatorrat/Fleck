import Foundation
import LocalDictationCandidateProtocol

public final class JSONLinesInput {
  private let handle: FileHandle
  private var finished = false

  public init(handle: FileHandle = .standardInput) {
    self.handle = handle
  }

  public func nextLine() throws -> Data? {
    guard !finished else { return nil }
    var line = Data()
    while true {
      guard let chunk = try handle.read(upToCount: 1), !chunk.isEmpty else {
        finished = true
        return line.isEmpty ? nil : line
      }
      if chunk[chunk.startIndex] == 0x0A {
        return line
      }
      line.append(chunk[chunk.startIndex])
      guard line.count < JSONLinesCodec.maximumLineBytes else {
        throw CandidateAdapterProtocolError.lineTooLarge
      }
    }
  }
}

public final class JSONLinesOutput {
  private let handle: FileHandle

  public init(handle: FileHandle = .standardOutput) {
    self.handle = handle
  }

  public func write(_ event: CandidateAdapterEvent) throws {
    try event.validate()
    try handle.write(contentsOf: JSONLinesCodec.encode(event))
  }
}

public enum SpikeClock {
  public static func milliseconds(_ body: () throws -> Void) rethrows -> Double {
    let start = DispatchTime.now().uptimeNanoseconds
    try body()
    let end = DispatchTime.now().uptimeNanoseconds
    return Double(end - start) / 1_000_000
  }
}
