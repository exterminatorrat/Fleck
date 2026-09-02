import Foundation

public enum JSONLinesCodec {
  public static let maximumLineBytes = 1_048_576

  public static func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let encoded = try encoder.encode(value)
    guard !encoded.contains(0x0A), !encoded.contains(0x0D) else {
      throw CandidateAdapterProtocolError.embeddedNewline
    }
    guard encoded.count <= maximumLineBytes - 1 else {
      throw CandidateAdapterProtocolError.lineTooLarge
    }
    return encoded + Data([0x0A])
  }

  public static func decodeRequest(_ data: Data) throws -> CandidateAdapterRequest {
    try decodeLine(data, as: CandidateAdapterRequest.self)
  }

  public static func decodeEvent(_ data: Data) throws -> CandidateAdapterEvent {
    try decodeLine(data, as: CandidateAdapterEvent.self)
  }

  public static func decodeLine<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
    guard data.count <= maximumLineBytes else {
      throw CandidateAdapterProtocolError.lineTooLarge
    }
    var line = data
    if line.last == 0x0A {
      line.removeLast()
    }
    guard !line.isEmpty else {
      throw CandidateAdapterProtocolError.emptyLine
    }
    guard !line.contains(0x0A), !line.contains(0x0D) else {
      throw CandidateAdapterProtocolError.embeddedNewline
    }
    do {
      return try JSONDecoder().decode(type, from: line)
    } catch let error as CandidateAdapterProtocolError {
      throw error
    } catch {
      throw CandidateAdapterProtocolError.malformedJSON
    }
  }
}
