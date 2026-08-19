import Foundation

public struct PCM16Wave: Sendable {
  public let sampleRate: Int
  public let channels: Int
  public let samples: [Float]

  public init(sampleRate: Int, channels: Int, samples: [Float]) {
    self.sampleRate = sampleRate
    self.channels = channels
    self.samples = samples
  }
}

public enum WaveReaderError: Error, Equatable, CustomStringConvertible {
  case truncated
  case invalidContainer
  case missingFormat
  case missingSamples
  case unsupportedFormat
  case unsupportedChannels
  case unsupportedBitDepth
  case sampleRateMismatch(expected: Int, actual: Int)

  public var description: String {
    switch self {
    case .truncated: return "truncated-wav"
    case .invalidContainer: return "invalid-wav-container"
    case .missingFormat: return "missing-wav-format"
    case .missingSamples: return "missing-wav-samples"
    case .unsupportedFormat: return "unsupported-wav-format"
    case .unsupportedChannels: return "unsupported-wav-channels"
    case .unsupportedBitDepth: return "unsupported-wav-bit-depth"
    case .sampleRateMismatch(let expected, let actual):
      return "sample-rate-mismatch-expected-\(expected)-actual-\(actual)"
    }
  }
}

public enum WaveReader {
  public static func read(_ url: URL, expectedSampleRate: Int? = nil) throws -> PCM16Wave {
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    guard data.count >= 12 else { throw WaveReaderError.truncated }
    guard data[0..<4] == Data("RIFF".utf8), data[8..<12] == Data("WAVE".utf8) else {
      throw WaveReaderError.invalidContainer
    }

    var offset = 12
    var audioFormat: UInt16?
    var channels: UInt16?
    var sampleRate: UInt32?
    var blockAlign: UInt16?
    var bitsPerSample: UInt16?
    var sampleBytes: Data?

    while offset + 8 <= data.count {
      let chunkID = data[offset..<(offset + 4)]
      let chunkSize = Int(try readUInt32LE(data, at: offset + 4))
      offset += 8
      guard chunkSize >= 0, offset + chunkSize <= data.count else {
        throw WaveReaderError.truncated
      }
      if chunkID == Data("fmt ".utf8) {
        guard chunkSize >= 16 else { throw WaveReaderError.truncated }
        audioFormat = try readUInt16LE(data, at: offset)
        channels = try readUInt16LE(data, at: offset + 2)
        sampleRate = try readUInt32LE(data, at: offset + 4)
        blockAlign = try readUInt16LE(data, at: offset + 12)
        bitsPerSample = try readUInt16LE(data, at: offset + 14)
      } else if chunkID == Data("data".utf8) {
        sampleBytes = Data(data[offset..<(offset + chunkSize)])
      }
      offset += chunkSize + (chunkSize & 1)
    }

    guard let audioFormat, let channels, let sampleRate, let blockAlign, let bitsPerSample else {
      throw WaveReaderError.missingFormat
    }
    guard let sampleBytes, !sampleBytes.isEmpty else { throw WaveReaderError.missingSamples }
    guard channels > 0, channels <= 2 else { throw WaveReaderError.unsupportedChannels }
    guard let expectedSampleRate else {
      return try decode(
        sampleBytes: sampleBytes,
        audioFormat: audioFormat,
        channels: channels,
        sampleRate: sampleRate,
        blockAlign: blockAlign,
        bitsPerSample: bitsPerSample
      )
    }
    guard Int(sampleRate) == expectedSampleRate else {
      throw WaveReaderError.sampleRateMismatch(expected: expectedSampleRate, actual: Int(sampleRate))
    }
    return try decode(
      sampleBytes: sampleBytes,
      audioFormat: audioFormat,
      channels: channels,
      sampleRate: sampleRate,
      blockAlign: blockAlign,
      bitsPerSample: bitsPerSample
    )
  }

  private static func decode(
    sampleBytes: Data,
    audioFormat: UInt16,
    channels: UInt16,
    sampleRate: UInt32,
    blockAlign: UInt16,
    bitsPerSample: UInt16
  ) throws -> PCM16Wave {
    guard audioFormat == 1 || audioFormat == 3 else { throw WaveReaderError.unsupportedFormat }
    let bytesPerSample = Int(bitsPerSample / 8)
    guard (audioFormat == 1 && bitsPerSample == 16) || (audioFormat == 3 && bitsPerSample == 32) else {
      throw WaveReaderError.unsupportedBitDepth
    }
    guard Int(blockAlign) == Int(channels) * bytesPerSample,
      sampleBytes.count % Int(blockAlign) == 0
    else {
      throw WaveReaderError.truncated
    }

    let channelCount = Int(channels)
    let frameCount = sampleBytes.count / Int(blockAlign)
    var samples = [Float](repeating: 0, count: frameCount)
    for frame in 0..<frameCount {
      let frameOffset = frame * Int(blockAlign)
      var total: Float = 0
      for channel in 0..<channelCount {
        let sampleOffset = frameOffset + channel * bytesPerSample
        if audioFormat == 1 {
          let value = Int16(bitPattern: try readUInt16LE(sampleBytes, at: sampleOffset))
          total += Float(value) / 32_768
        } else {
          let bits = try readUInt32LE(sampleBytes, at: sampleOffset)
          total += Float(bitPattern: bits)
        }
      }
      samples[frame] = total / Float(channelCount)
    }
    return PCM16Wave(sampleRate: Int(sampleRate), channels: channelCount, samples: samples)
  }

  private static func readUInt16LE(_ data: Data, at offset: Int) throws -> UInt16 {
    guard offset >= 0, offset + 2 <= data.count else { throw WaveReaderError.truncated }
    return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
  }

  private static func readUInt32LE(_ data: Data, at offset: Int) throws -> UInt32 {
    guard offset >= 0, offset + 4 <= data.count else { throw WaveReaderError.truncated }
    return UInt32(data[offset])
      | (UInt32(data[offset + 1]) << 8)
      | (UInt32(data[offset + 2]) << 16)
      | (UInt32(data[offset + 3]) << 24)
  }
}
