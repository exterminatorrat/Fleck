import Foundation

@main
struct MakeSilence {
  static func main() throws {
    guard CommandLine.arguments.count == 2 else {
      throw NSError(domain: "silence", code: 2, userInfo: [NSLocalizedDescriptionKey: "usage: silence output"])
    }
    let sampleRate = 16_000
    let sampleCount = sampleRate * 3
    var data = Data("RIFF".utf8)
    appendUInt32LE(&data, UInt32(36 + sampleCount * 2))
    data.append(contentsOf: Data("WAVEfmt ".utf8))
    appendUInt32LE(&data, 16)
    appendUInt16LE(&data, 1)
    appendUInt16LE(&data, 1)
    appendUInt32LE(&data, UInt32(sampleRate))
    appendUInt32LE(&data, UInt32(sampleRate * 2))
    appendUInt16LE(&data, 2)
    appendUInt16LE(&data, 16)
    data.append(contentsOf: Data("data".utf8))
    appendUInt32LE(&data, UInt32(sampleCount * 2))
    data.append(contentsOf: Data(repeating: 0, count: sampleCount * 2))
    try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
  }

  private static func appendUInt16LE(_ data: inout Data, _ value: UInt16) {
    data.append(UInt8(value & 0xff))
    data.append(UInt8(value >> 8))
  }

  private static func appendUInt32LE(_ data: inout Data, _ value: UInt32) {
    data.append(UInt8(value & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
    data.append(UInt8((value >> 16) & 0xff))
    data.append(UInt8(value >> 24))
  }
}
