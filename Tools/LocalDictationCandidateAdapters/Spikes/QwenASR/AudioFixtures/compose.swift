import Foundation

@main
struct ComposeOfficialAudio {
  static func main() throws {
    guard CommandLine.arguments.count == 4 else {
      throw NSError(domain: "compose", code: 2, userInfo: [NSLocalizedDescriptionKey: "usage: compose input-a input-b output"])
    }
    let first = try WaveReader.read(URL(fileURLWithPath: CommandLine.arguments[1]))
    let second = try WaveReader.read(URL(fileURLWithPath: CommandLine.arguments[2]))
    guard first.sampleRate == second.sampleRate, first.channels == 1, second.channels == 1 else {
      throw NSError(domain: "compose", code: 3, userInfo: [NSLocalizedDescriptionKey: "fixtures must be mono with the same sample rate"])
    }
    try writeWave(
      samples: first.samples + second.samples,
      sampleRate: first.sampleRate,
      to: URL(fileURLWithPath: CommandLine.arguments[3])
    )
  }

  private static func writeWave(samples: [Float], sampleRate: Int, to url: URL) throws {
    var data = Data("RIFF".utf8)
    appendUInt32LE(&data, UInt32(36 + samples.count * 2))
    data.append(contentsOf: Data("WAVEfmt ".utf8))
    appendUInt32LE(&data, 16)
    appendUInt16LE(&data, 1)
    appendUInt16LE(&data, 1)
    appendUInt32LE(&data, UInt32(sampleRate))
    appendUInt32LE(&data, UInt32(sampleRate * 2))
    appendUInt16LE(&data, 2)
    appendUInt16LE(&data, 16)
    data.append(contentsOf: Data("data".utf8))
    appendUInt32LE(&data, UInt32(samples.count * 2))
    for sample in samples {
      let clipped = max(-1, min(0.999969, sample))
      appendUInt16LE(&data, UInt16(bitPattern: Int16(clipped * 32_768)))
    }
    try data.write(to: url, options: .atomic)
  }

  private static func appendUInt16LE(_ data: inout Data, _ value: UInt16) {
    data.append(UInt8(value & 0xff))
    data.append(UInt8(value >> 8))
  }

  private static func appendUInt32LE(_ data: inout Data, _ value: UInt32) {
    data.append(UInt8(value & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
    data.append(UInt8((value >> 16) & 0xff))
    data.append(UInt8((value >> 24) & 0xff))
  }
}
