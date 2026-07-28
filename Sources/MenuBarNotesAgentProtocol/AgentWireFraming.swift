import Foundation

public enum AgentWireFraming {
  public static let maximumFrameBytes = 1_048_576

  public static func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let payload = try encoder.encode(value)
    guard !payload.isEmpty, payload.count <= maximumFrameBytes else {
      throw AgentWireFramingError.invalidLength
    }
    var length = UInt32(payload.count).bigEndian
    var frame = withUnsafeBytes(of: &length) { Data($0) }
    frame.append(payload)
    return frame
  }

  public static func decodeFrame<T: Decodable>(
    _ type: T.Type,
    from buffer: inout Data
  ) throws -> T? {
    guard buffer.count >= MemoryLayout<UInt32>.size else { return nil }
    let length = buffer.prefix(4).reduce(UInt32.zero) {
      ($0 << 8) | UInt32($1)
    }
    guard length > 0, length <= maximumFrameBytes else {
      throw AgentWireFramingError.invalidLength
    }
    let frameCount = 4 + Int(length)
    guard buffer.count >= frameCount else { return nil }
    let payload = Data(buffer.dropFirst(4).prefix(Int(length)))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(type, from: payload)
    buffer.removeFirst(frameCount)
    return decoded
  }
}

public enum AgentWireFramingError: Error, Equatable {
  case invalidLength
}
