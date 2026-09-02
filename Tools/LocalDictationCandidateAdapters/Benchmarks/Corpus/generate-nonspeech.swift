import Foundation
import Darwin

private enum GeneratorError: Error, CustomStringConvertible {
  case usage
  case unsafeDestination
  case destinationMissing
  case destinationNotEmpty
  case outputExists(String)

  var description: String {
    switch self {
    case .usage:
      return "usage: generate-nonspeech.swift ABSOLUTE_EMPTY_DESTINATION"
    case .unsafeDestination:
      return "destination must be an absolute local directory that is not a symlink"
    case .destinationMissing:
      return "destination must already exist as an empty directory"
    case .destinationNotEmpty:
      return "destination must be empty"
    case .outputExists(let name):
      return "refusing to overwrite output: \(name)"
    }
  }
}

private struct PythonRandom {
  private static let stateCount = 624
  private static let period = 397
  private static let matrixA: UInt32 = 0x9908B0DF

  private var state = [UInt32](repeating: 0, count: stateCount)
  private var index = stateCount

  init(seed: UInt32) {
    var state = [UInt32](repeating: 0, count: Self.stateCount)
    state[0] = 19_650_218
    for i in 1..<Self.stateCount {
      state[i] = 1_812_433_253 &* (state[i - 1] ^ (state[i - 1] >> 30)) &+ UInt32(i)
    }

    var i = 1
    var j = 0
    var remaining = max(Self.stateCount, 1)
    while remaining > 0 {
      state[i] = (state[i] ^ ((state[i - 1] ^ (state[i - 1] >> 30)) &* 1_664_525)) &+ seed &+ UInt32(j)
      i += 1
      j += 1
      if i >= Self.stateCount {
        state[0] = state[Self.stateCount - 1]
        i = 1
      }
      if j >= 1 {
        j = 0
      }
      remaining -= 1
    }

    remaining = Self.stateCount - 1
    while remaining > 0 {
      state[i] = (state[i] ^ ((state[i - 1] ^ (state[i - 1] >> 30)) &* 1_566_083_941)) &- UInt32(i)
      i += 1
      if i >= Self.stateCount {
        state[0] = state[Self.stateCount - 1]
        i = 1
      }
      remaining -= 1
    }
    state[0] = 0x80000000
    self.state = state
    self.index = Self.stateCount
  }

  mutating func uniform(_ lower: Double, _ upper: Double) -> Float {
    Float(lower + (upper - lower) * nextDouble())
  }

  private mutating func nextDouble() -> Double {
    let high = UInt64(nextUInt32() >> 5)
    let low = UInt64(nextUInt32() >> 6)
    return Double(high * 67_108_864 + low) / 9_007_199_254_740_992.0
  }

  private mutating func nextUInt32() -> UInt32 {
    if index >= Self.stateCount {
      var i = 0
      while i < Self.stateCount {
        let y = (state[i] & 0x80000000) | (state[(i + 1) % Self.stateCount] & 0x7FFFFFFF)
        state[i] = state[(i + Self.period) % Self.stateCount] ^ (y >> 1) ^ ((y & 1) == 0 ? 0 : Self.matrixA)
        i += 1
      }
      index = 0
    }

    var value = state[index]
    index += 1
    value ^= value >> 11
    value ^= (value << 7) & 0x9D2C5680
    value ^= (value << 15) & 0xEFC60000
    value ^= value >> 18
    return value
  }
}

private func appendUInt16LE(_ data: inout Data, _ value: UInt16) {
  data.append(UInt8(value & 0xFF))
  data.append(UInt8(value >> 8))
}

private func appendUInt32LE(_ data: inout Data, _ value: UInt32) {
  data.append(UInt8(value & 0xFF))
  data.append(UInt8((value >> 8) & 0xFF))
  data.append(UInt8((value >> 16) & 0xFF))
  data.append(UInt8(value >> 24))
}

private func appendASCII(_ data: inout Data, _ value: String) {
  data.append(contentsOf: value.utf8)
}

private func waveData(samples: [Float]) -> Data {
  let sampleBytes = samples.count * MemoryLayout<Float>.size
  var data = Data(capacity: sampleBytes + 58)
  appendASCII(&data, "RIFF")
  appendUInt32LE(&data, UInt32(sampleBytes + 50))
  appendASCII(&data, "WAVE")
  appendASCII(&data, "fmt ")
  appendUInt32LE(&data, 18)
  appendUInt16LE(&data, 3)
  appendUInt16LE(&data, 1)
  appendUInt32LE(&data, 16_000)
  appendUInt32LE(&data, 64_000)
  appendUInt16LE(&data, 4)
  appendUInt16LE(&data, 32)
  appendUInt16LE(&data, 0)
  appendASCII(&data, "fact")
  appendUInt32LE(&data, 4)
  appendUInt32LE(&data, UInt32(samples.count))
  appendASCII(&data, "data")
  appendUInt32LE(&data, UInt32(sampleBytes))
  for sample in samples {
    appendUInt32LE(&data, sample.bitPattern)
  }
  return data
}

private func outputURLs(in destination: URL) -> [URL] {
  [
    destination.appendingPathComponent("silence-5s.wav"),
    destination.appendingPathComponent("white-noise-low-5s.wav"),
    destination.appendingPathComponent("white-noise-medium-5s.wav"),
    destination.appendingPathComponent("impulse-train-5s.wav"),
    destination.appendingPathComponent("alternating-silence-noise-10s.wav"),
  ]
}

private func validateDestination(_ path: String) throws -> URL {
  guard path.hasPrefix("/"), !path.contains("://"), path != "/" else {
    throw GeneratorError.unsafeDestination
  }

  let fileManager = FileManager.default
  var isDirectory = ObjCBool(false)
  guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
    throw GeneratorError.destinationMissing
  }
  let attributes = try fileManager.attributesOfItem(atPath: path)
  guard attributes[.type] as? FileAttributeType != .typeSymbolicLink, isDirectory.boolValue else {
    throw GeneratorError.unsafeDestination
  }

  let destination = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
  guard destination.resolvingSymlinksInPath().isFileURL else {
    throw GeneratorError.unsafeDestination
  }
  guard try fileManager.contentsOfDirectory(atPath: destination.path).isEmpty else {
    throw GeneratorError.destinationNotEmpty
  }
  return destination
}

private func generate() throws {
  guard CommandLine.arguments.count == 2 else {
    throw GeneratorError.usage
  }
  let destination = try validateDestination(CommandLine.arguments[1])
  let fileManager = FileManager.default
  let urls = outputURLs(in: destination)
  for url in urls where fileManager.fileExists(atPath: url.path) || (try? fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeSymbolicLink {
    throw GeneratorError.outputExists(url.lastPathComponent)
  }

  let stage = destination.appendingPathComponent(".nonspeech-staging-\(UUID().uuidString)", isDirectory: true)
  try fileManager.createDirectory(at: stage, withIntermediateDirectories: false)
  var published: [URL] = []
  do {
    var random = PythonRandom(seed: 0xF1EC2026)
    let silence = [Float](repeating: 0, count: 80_000)
    let lowNoise = (0..<80_000).map { _ in random.uniform(-0.01, 0.01) }
    let mediumNoise = (0..<80_000).map { _ in random.uniform(-0.05, 0.05) }
    var impulseTrain = silence
    for index in stride(from: 0, to: impulseTrain.count, by: 8_000) {
      impulseTrain[index] = 0.25
    }
    var alternating = [Float](repeating: 0, count: 160_000)
    for index in 32_000..<(32_000 + 48_000) {
      alternating[index] = random.uniform(-0.02, 0.02)
    }
    for index in 112_000..<160_000 {
      alternating[index] = random.uniform(-0.02, 0.02)
    }

    let samples = [silence, lowNoise, mediumNoise, impulseTrain, alternating]
    for (index, url) in urls.enumerated() {
      try waveData(samples: samples[index]).write(
        to: stage.appendingPathComponent(url.lastPathComponent),
        options: .atomic
      )
    }
    for url in urls {
      let staged = stage.appendingPathComponent(url.lastPathComponent)
      guard !fileManager.fileExists(atPath: url.path) else {
        throw GeneratorError.outputExists(url.lastPathComponent)
      }
      try fileManager.moveItem(at: staged, to: url)
      published.append(url)
    }
    try fileManager.removeItem(at: stage)
  } catch {
    for url in published {
      try? fileManager.removeItem(at: url)
    }
    try? fileManager.removeItem(at: stage)
    throw error
  }
}

@main
private struct GenerateNonspeech {
  static func main() {
    do {
      try generate()
    } catch {
      FileHandle.standardError.write(Data("generate-nonspeech: \(error)\n".utf8))
      exit(2)
    }
  }
}
