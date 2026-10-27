import CFNetwork
import CFleckEventHTTP
import Darwin
import Foundation

struct AgentEventHTTPHeader: Equatable, Sendable {
  let name: String
  let value: String
}

struct AgentEventHTTPResponse: Equatable, Sendable {
  let statusCode: Int
  let body: Data
  let retryAfterSeconds: TimeInterval?

  init(statusCode: Int, body: Data, retryAfterSeconds: TimeInterval? = nil) {
    self.statusCode = statusCode
    self.body = body
    self.retryAfterSeconds = retryAfterSeconds
  }
}

enum AgentEventHTTPTransportError: Error, Equatable {
  case invalidRequest
  case cancelled
  case timedOut
  case busy
  case transportFailure
}

struct AgentEventHTTPResolvedAddress: Equatable, Sendable {
  let family: Int32
  let numericAddress: String
}

struct AgentEventHTTPTransport: Sendable {
  struct Endpoint: Equatable, Sendable {
    let url: String
    let host: String
    let resolverHost: String
    let port: UInt16
    let requestTarget: String
  }

  static let maximumRequestBodyBytes = 1_024
  static let maximumResponseBodyBytes = 65_536
  static let maximumRetryAfterHeaderBytes = Int(FLECK_EVENT_HTTP_MAX_RETRY_AFTER_VALUE_BYTES)
  static let maximumRetryAfterSeconds = 900
  static let maximumTotalDurationMilliseconds: UInt32 = 10_000
  static let maximumResolutionDurationMilliseconds: UInt64 = 3_000
  static let maximumConcurrentRequests = 1

  func post(
    callbackURL: String,
    headers: [AgentEventHTTPHeader],
    body: Data
  ) async throws -> AgentEventHTTPResponse {
    let endpoint = try Self.parseEndpoint(callbackURL)
    try Self.validateHeaders(headers)
    try Self.validateBody(body)

    let deadline =
      DispatchTime.now().uptimeNanoseconds
      + UInt64(Self.maximumTotalDurationMilliseconds) * 1_000_000
    let cancellation = AgentEventHTTPCancellationFlag()
    let workerPool = AgentEventHTTPWorkerPool.shared
    guard workerPool.reserve() else { throw AgentEventHTTPTransportError.busy }

    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        workerPool.queue.addOperation {
          defer { workerPool.release() }
          do {
            guard !cancellation.isCancelled else {
              throw AgentEventHTTPTransportError.cancelled
            }
            guard let initialRemaining = Self.remainingMilliseconds(until: deadline) else {
              throw AgentEventHTTPTransportError.timedOut
            }
            let rawAddresses = try Self.resolve(
              host: endpoint.resolverHost,
              deadline: deadline,
              cancellation: cancellation
            )
            let addresses = try Self.validateResolvedAddresses(rawAddresses)
            guard let pinnedAddress = addresses.first else {
              throw AgentEventHTTPTransportError.invalidRequest
            }
            guard !cancellation.isCancelled else {
              throw AgentEventHTTPTransportError.cancelled
            }
            guard let remaining = Self.remainingMilliseconds(until: deadline) else {
              throw AgentEventHTTPTransportError.timedOut
            }
            let response = try Self.perform(
              endpoint: endpoint,
              pin: pinnedAddress,
              headers: headers,
              body: body,
              timeoutMilliseconds: min(initialRemaining, remaining),
              cancellation: cancellation
            )
            guard !cancellation.isCancelled else {
              throw AgentEventHTTPTransportError.cancelled
            }
            continuation.resume(returning: response)
          } catch {
            continuation.resume(throwing: error)
          }
        }
      }
    } onCancel: {
      cancellation.cancel()
    }
  }

  static func parseEndpoint(_ callbackURL: String) throws -> Endpoint {
    let canonicalURL: String
    do {
      canonicalURL = try AgentEventSubscriptionIdentity.canonicalCallbackURL(callbackURL)
    } catch {
      throw AgentEventHTTPTransportError.invalidRequest
    }
    guard canonicalURL == callbackURL,
      let components = URLComponents(string: callbackURL),
      let host = components.host,
      let resolverHost = resolverHost(for: host)
    else {
      throw AgentEventHTTPTransportError.invalidRequest
    }

    let port = components.port ?? 443
    guard (1...65_535).contains(port), let port = UInt16(exactly: port) else {
      throw AgentEventHTTPTransportError.invalidRequest
    }
    let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
    let requestTarget = path + (components.percentEncodedQuery.map { "?\($0)" } ?? "")
    guard requestTarget.utf8.count <= 2_048,
      curlParserAgrees(
        url: callbackURL,
        host: host,
        port: port,
        requestTarget: requestTarget
      )
    else {
      throw AgentEventHTTPTransportError.invalidRequest
    }

    return Endpoint(
      url: callbackURL,
      host: host,
      resolverHost: resolverHost,
      port: port,
      requestTarget: requestTarget
    )
  }

  static func curlParserAgrees(
    url: String,
    host: String,
    port: UInt16,
    requestTarget: String
  ) -> Bool {
    withCStringPointers([url, host, requestTarget]) { pointers in
      fleck_event_http_validate_url(pointers[0], pointers[1], port, pointers[2]) == 1
    }
  }

  static func validateHeaders(_ headers: [AgentEventHTTPHeader]) throws {
    let allowedNames: Set<String> = [
      "content-type", "webhook-id", "webhook-timestamp", "webhook-signature",
      "x-mcp-subscription-id",
    ]
    guard headers.count == allowedNames.count else {
      throw AgentEventHTTPTransportError.invalidRequest
    }

    var names = Set<String>()
    var totalBytes = 0
    for header in headers {
      let nameBytes = Array(header.name.utf8)
      let valueBytes = Array(header.value.utf8)
      guard allowedNames.contains(header.name), names.insert(header.name).inserted,
        (1...1_024).contains(valueBytes.count),
        nameBytes.allSatisfy({ (97...122).contains($0) || $0 == 45 }),
        valueBytes.allSatisfy({ (32...126).contains($0) })
      else {
        throw AgentEventHTTPTransportError.invalidRequest
      }
      totalBytes += nameBytes.count + valueBytes.count + 4
      guard totalBytes <= 2_048 else { throw AgentEventHTTPTransportError.invalidRequest }

      switch header.name {
      case "content-type":
        guard header.value == "application/json" else {
          throw AgentEventHTTPTransportError.invalidRequest
        }
      case "webhook-id":
        guard isValidWebhookID(header.value) else {
          throw AgentEventHTTPTransportError.invalidRequest
        }
      case "webhook-timestamp":
        guard isValidWebhookTimestamp(header.value) else {
          throw AgentEventHTTPTransportError.invalidRequest
        }
      case "webhook-signature":
        guard isValidWebhookSignature(header.value) else {
          throw AgentEventHTTPTransportError.invalidRequest
        }
      case "x-mcp-subscription-id":
        guard isValidSubscriptionID(header.value) else {
          throw AgentEventHTTPTransportError.invalidRequest
        }
      default:
        throw AgentEventHTTPTransportError.invalidRequest
      }
    }
    guard names == allowedNames else { throw AgentEventHTTPTransportError.invalidRequest }
  }

  static func validateBody(_ body: Data) throws {
    guard body.count <= maximumRequestBodyBytes else {
      throw AgentEventHTTPTransportError.invalidRequest
    }
  }

  static func parseRetryAfter(_ value: [UInt8], responseTime: TimeInterval) -> TimeInterval? {
    guard responseTime.isFinite, !value.isEmpty,
      value.allSatisfy({ (0x20...0x7e).contains($0) })
    else {
      return nil
    }

    if value.allSatisfy({ (0x30...0x39).contains($0) }) {
      var seconds: UInt64 = 0
      for byte in value {
        let (scaled, multiplyOverflow) = seconds.multipliedReportingOverflow(by: 10)
        let (sum, additionOverflow) = scaled.addingReportingOverflow(UInt64(byte - 0x30))
        guard !multiplyOverflow, !additionOverflow else { return nil }
        seconds = sum
      }
      return TimeInterval(min(seconds, UInt64(maximumRetryAfterSeconds)))
    }

    let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    let months = [
      "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]
    guard value.count == 29,
      value[3] == 0x2c, value[4] == 0x20, value[7] == 0x20, value[11] == 0x20,
      value[16] == 0x20, value[19] == 0x3a, value[22] == 0x3a, value[25] == 0x20,
      value[26] == 0x47, value[27] == 0x4d, value[28] == 0x54,
      let weekday = weekdays.firstIndex(of: String(decoding: value[0..<3], as: UTF8.self)),
      let monthIndex = months.firstIndex(of: String(decoding: value[8..<11], as: UTF8.self))
    else {
      return nil
    }

    func integer(_ range: Range<Int>) -> Int? {
      var result = 0
      for byte in value[range] {
        guard (0x30...0x39).contains(byte) else { return nil }
        result = result * 10 + Int(byte - 0x30)
      }
      return result
    }

    guard let day = integer(5..<7), let year = integer(12..<16), year > 0,
      let hour = integer(17..<19), let minute = integer(20..<22),
      let second = integer(23..<25)
    else {
      return nil
    }
    let month = monthIndex + 1
    let leapYear = year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
    let daysInMonth = [31, leapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    guard (1...daysInMonth[month - 1]).contains(day), (0...23).contains(hour),
      (0...59).contains(minute), (0...59).contains(second)
    else {
      return nil
    }

    let adjustedYear = year - (month <= 2 ? 1 : 0)
    let era = adjustedYear / 400
    let yearOfEra = adjustedYear - era * 400
    let adjustedMonth = month + (month > 2 ? -3 : 9)
    let dayOfYear = (153 * adjustedMonth + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    let daysSinceEpoch = era * 146_097 + dayOfEra - 719_468
    let weekdayNumber = ((daysSinceEpoch + 4) % 7 + 7) % 7
    guard weekdayNumber == weekday else { return nil }
    let timestamp =
      TimeInterval(daysSinceEpoch) * 86_400
      + TimeInterval(hour * 3_600 + minute * 60 + second)
    let delay = timestamp - responseTime
    guard delay.isFinite else { return nil }
    return min(max(delay, 0), TimeInterval(maximumRetryAfterSeconds))
  }

  static func validateResolvedAddresses(_ addresses: [Data]) throws
    -> [AgentEventHTTPResolvedAddress]
  {
    guard !addresses.isEmpty, addresses.count <= 32 else {
      throw AgentEventHTTPTransportError.invalidRequest
    }
    return try addresses.map { try validateResolvedAddress($0) }
  }

  private static func validateResolvedAddress(_ data: Data) throws -> AgentEventHTTPResolvedAddress
  {
    guard data.count >= 2 else { throw AgentEventHTTPTransportError.invalidRequest }
    let family = Int32(data[1])
    switch family {
    case AF_INET:
      guard data.count == MemoryLayout<sockaddr_in>.size else {
        throw AgentEventHTTPTransportError.invalidRequest
      }
      let address = data.withUnsafeBytes { $0.loadUnaligned(as: sockaddr_in.self) }
      guard Int(address.sin_len) == data.count, Int32(address.sin_family) == AF_INET,
        address.sin_port == 0,
        let offset = MemoryLayout<sockaddr_in>.offset(of: \.sin_addr)
      else {
        throw AgentEventHTTPTransportError.invalidRequest
      }
      let bytes = Data(data[offset..<(offset + MemoryLayout<in_addr>.size)])
      guard isPublicAddress(family: AF_INET, bytes: bytes) else {
        throw AgentEventHTTPTransportError.invalidRequest
      }
      return AgentEventHTTPResolvedAddress(
        family: AF_INET,
        numericAddress: try numericIPv4(address.sin_addr)
      )
    case AF_INET6:
      guard data.count == MemoryLayout<sockaddr_in6>.size else {
        throw AgentEventHTTPTransportError.invalidRequest
      }
      let address = data.withUnsafeBytes { $0.loadUnaligned(as: sockaddr_in6.self) }
      guard Int(address.sin6_len) == data.count, Int32(address.sin6_family) == AF_INET6,
        address.sin6_port == 0, address.sin6_scope_id == 0, address.sin6_flowinfo == 0,
        let offset = MemoryLayout<sockaddr_in6>.offset(of: \.sin6_addr)
      else {
        throw AgentEventHTTPTransportError.invalidRequest
      }
      let bytes = Data(data[offset..<(offset + MemoryLayout<in6_addr>.size)])
      guard isPublicAddress(family: AF_INET6, bytes: bytes) else {
        throw AgentEventHTTPTransportError.invalidRequest
      }
      return AgentEventHTTPResolvedAddress(
        family: AF_INET6,
        numericAddress: try numericIPv6(address.sin6_addr)
      )
    default:
      throw AgentEventHTTPTransportError.invalidRequest
    }
  }

  private static func isPublicAddress(family: Int32, bytes: Data) -> Bool {
    bytes.withUnsafeBytes { rawBuffer in
      fleck_event_http_is_public_address(
        family,
        rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
        rawBuffer.count
      ) == 1
    }
  }

  private static func numericIPv4(_ address: in_addr) throws -> String {
    var address = address
    var output = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
    guard inet_ntop(AF_INET, &address, &output, socklen_t(output.count)) != nil else {
      throw AgentEventHTTPTransportError.invalidRequest
    }
    return string(from: output)
  }

  private static func numericIPv6(_ address: in6_addr) throws -> String {
    var address = address
    var output = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
    guard inet_ntop(AF_INET6, &address, &output, socklen_t(output.count)) != nil else {
      throw AgentEventHTTPTransportError.invalidRequest
    }
    return string(from: output).lowercased()
  }

  private static func resolverHost(for urlHost: String) -> String? {
    let bytes = Array(urlHost.utf8)
    guard !bytes.isEmpty, bytes.count <= 255, bytes.allSatisfy({ (33...126).contains($0) }) else {
      return nil
    }

    if urlHost.first == "[", urlHost.last == "]" {
      let address = String(urlHost.dropFirst().dropLast())
      guard !address.contains("%"), let numeric = canonicalIPv6(address), numeric == address else {
        return nil
      }
      return address
    }
    guard !urlHost.contains(":"), !urlHost.hasSuffix(".") else { return nil }
    if let numeric = canonicalIPv4(urlHost) { return numeric }
    if looksLikeNumericAddress(urlHost) { return nil }

    let labels = urlHost.split(separator: ".", omittingEmptySubsequences: false)
    guard urlHost.utf8.count <= 253, !labels.isEmpty else { return nil }
    for label in labels {
      let value = Array(label.utf8)
      guard (1...63).contains(value.count),
        value.first != 45, value.last != 45,
        value.allSatisfy({
          (97...122).contains($0) || (48...57).contains($0) || $0 == 45
        })
      else {
        return nil
      }
    }
    return urlHost
  }

  private static func looksLikeNumericAddress(_ host: String) -> Bool {
    let bytes = Array(host.utf8)
    guard bytes.contains(where: { (48...57).contains($0) }) else { return false }
    return host.hasPrefix("0x")
      || bytes.allSatisfy({ (48...57).contains($0) || $0 == 46 })
      || bytes.allSatisfy({
        (48...57).contains($0) || (97...102).contains($0) || $0 == 46
      })
  }

  private static func canonicalIPv4(_ value: String) -> String? {
    var address = in_addr()
    guard value.withCString({ inet_pton(AF_INET, $0, &address) }) == 1 else { return nil }
    var output = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
    guard inet_ntop(AF_INET, &address, &output, socklen_t(output.count)) != nil else { return nil }
    let normalized = string(from: output)
    return normalized == value ? normalized : nil
  }

  private static func canonicalIPv6(_ value: String) -> String? {
    var address = in6_addr()
    guard value.withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 else { return nil }
    var output = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
    guard inet_ntop(AF_INET6, &address, &output, socklen_t(output.count)) != nil else { return nil }
    return string(from: output).lowercased()
  }

  private static func string(from output: [CChar]) -> String {
    String(decoding: output.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
  }

  private static func isValidWebhookID(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    return (1...128).contains(bytes.count)
      && bytes.allSatisfy {
        (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
          || $0 == 95 || $0 == 45 || $0 == 58
      }
  }

  private static func isValidWebhookTimestamp(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    guard (1...19).contains(bytes.count), bytes.allSatisfy({ (48...57).contains($0) }),
      bytes.count == 1 || bytes[0] != 48,
      let timestamp = Int64(value), timestamp >= 0
    else {
      return false
    }
    return String(timestamp) == value
  }

  private static func isValidWebhookSignature(_ value: String) -> Bool {
    let signatures = value.split(separator: " ", omittingEmptySubsequences: false)
    guard (1...2).contains(signatures.count), value.utf8.count <= 95 else { return false }
    return signatures.allSatisfy { signature in
      guard signature.hasPrefix("v1,") else { return false }
      let encoded = String(signature.dropFirst(3))
      guard let bytes = Data(base64Encoded: encoded), bytes.count == 32 else { return false }
      return bytes.base64EncodedString() == encoded
    }
  }

  private static func isValidSubscriptionID(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    return bytes.count == 68
      && value.hasPrefix("evt_")
      && bytes.dropFirst(4).allSatisfy {
        (48...57).contains($0) || (97...102).contains($0)
      }
  }

  private static func remainingMilliseconds(until deadline: UInt64) -> UInt32? {
    let now = DispatchTime.now().uptimeNanoseconds
    guard now < deadline else { return nil }
    let remaining = deadline - now
    let milliseconds = (remaining + 999_999) / 1_000_000
    return UInt32(min(milliseconds, UInt64(maximumTotalDurationMilliseconds)))
  }

  private static func resolve(
    host: String,
    deadline: UInt64,
    cancellation: AgentEventHTTPCancellationFlag
  ) throws -> [Data] {
    guard !cancellation.isCancelled else { throw AgentEventHTTPTransportError.cancelled }
    let hostObject = CFHostCreateWithName(kCFAllocatorDefault, host as CFString).takeRetainedValue()
    let callbackState = AgentEventHTTPHostCallbackState()
    let clientInfo = Unmanaged.passUnretained(callbackState).toOpaque()
    var clientContext = CFHostClientContext(
      version: 0,
      info: clientInfo,
      retain: nil,
      release: nil,
      copyDescription: nil
    )
    guard let ownerRunLoop = CFRunLoopGetCurrent() else {
      throw AgentEventHTTPTransportError.transportFailure
    }
    let runLoopMode = CFRunLoopMode.defaultMode!
    let mode = runLoopMode.rawValue
    var clientInstalled = false
    var scheduled = false
    var started = false

    do {
      guard CFHostSetClient(hostObject, agentEventHTTPHostCallback, &clientContext) else {
        throw AgentEventHTTPTransportError.transportFailure
      }
      clientInstalled = true
      CFHostScheduleWithRunLoop(hostObject, ownerRunLoop, mode)
      scheduled = true
      guard CFHostStartInfoResolution(hostObject, .addresses, nil) else {
        throw AgentEventHTTPTransportError.transportFailure
      }
      started = true

      let now = DispatchTime.now().uptimeNanoseconds
      let resolutionDeadline = min(
        deadline,
        now + maximumResolutionDurationMilliseconds * 1_000_000
      )
      while !callbackState.completed {
        guard !cancellation.isCancelled else { throw AgentEventHTTPTransportError.cancelled }
        let current = DispatchTime.now().uptimeNanoseconds
        guard current < resolutionDeadline else { throw AgentEventHTTPTransportError.timedOut }
        let remainingSeconds = Double(resolutionDeadline - current) / 1_000_000_000
        _ = CFRunLoopRunInMode(runLoopMode, min(0.05, remainingSeconds), true)
      }
      guard !callbackState.failed else { throw AgentEventHTTPTransportError.transportFailure }
      guard !cancellation.isCancelled else { throw AgentEventHTTPTransportError.cancelled }
      var hasBeenResolved = DarwinBoolean(false)
      guard
        let addresses = CFHostGetAddressing(hostObject, &hasBeenResolved)?.takeUnretainedValue(),
        hasBeenResolved.boolValue
      else {
        throw AgentEventHTTPTransportError.transportFailure
      }
      let rawAddresses = try copyResolverAddresses(addresses)
      tearDownHost(
        hostObject,
        runLoop: ownerRunLoop,
        mode: mode,
        started: started,
        scheduled: scheduled,
        clientInstalled: clientInstalled
      )
      started = false
      scheduled = false
      clientInstalled = false
      withExtendedLifetime(callbackState) {}
      withExtendedLifetime(hostObject) {}
      return rawAddresses
    } catch {
      tearDownHost(
        hostObject,
        runLoop: ownerRunLoop,
        mode: mode,
        started: started,
        scheduled: scheduled,
        clientInstalled: clientInstalled
      )
      withExtendedLifetime(callbackState) {}
      withExtendedLifetime(hostObject) {}
      throw error
    }
  }

  private static func tearDownHost(
    _ host: CFHost,
    runLoop: CFRunLoop,
    mode: CFString,
    started: Bool,
    scheduled: Bool,
    clientInstalled: Bool
  ) {
    if started { CFHostCancelInfoResolution(host, .addresses) }
    if scheduled { CFHostUnscheduleFromRunLoop(host, runLoop, mode) }
    if clientInstalled { _ = CFHostSetClient(host, nil, nil) }
  }

  static func copyResolverAddresses(_ addresses: CFArray) throws -> [Data] {
    let count = CFArrayGetCount(addresses)
    guard count > 0, count <= 32 else { throw AgentEventHTTPTransportError.invalidRequest }
    var copies: [Data] = []
    copies.reserveCapacity(count)
    for index in 0..<count {
      guard let value = CFArrayGetValueAtIndex(addresses, index) else {
        throw AgentEventHTTPTransportError.invalidRequest
      }
      let cfValue = Unmanaged<CFTypeRef>.fromOpaque(value).takeUnretainedValue()
      guard CFGetTypeID(cfValue) == CFDataGetTypeID() else {
        throw AgentEventHTTPTransportError.invalidRequest
      }
      let data = Unmanaged<CFData>.fromOpaque(value).takeUnretainedValue()
      let length = CFDataGetLength(data)
      guard length > 0, length <= MemoryLayout<sockaddr_in6>.size,
        let bytes = CFDataGetBytePtr(data)
      else {
        throw AgentEventHTTPTransportError.invalidRequest
      }
      copies.append(Data(bytes: bytes, count: length))
    }
    return copies
  }

  private static func perform(
    endpoint: Endpoint,
    pin: AgentEventHTTPResolvedAddress,
    headers: [AgentEventHTTPHeader],
    body: Data,
    timeoutMilliseconds: UInt32,
    cancellation: AgentEventHTTPCancellationFlag
  ) throws -> AgentEventHTTPResponse {
    var responseBody = Data(count: maximumResponseBodyBytes)
    var responseBodyLength = 0
    var statusCode: Int64 = 0
    var retryAfterValue = [UInt8](repeating: 0, count: maximumRetryAfterHeaderBytes)
    var retryAfterValueLength = 0
    let result = withCStringPointers([
      endpoint.url, endpoint.host, endpoint.requestTarget, pin.numericAddress,
    ]) {
      urlPointers in
      withCStringHeaders(headers) { cHeaders in
        body.withUnsafeBytes { bodyBytes in
          responseBody.withUnsafeMutableBytes { responseBytes in
            retryAfterValue.withUnsafeMutableBufferPointer { retryAfterBytes in
              fleck_event_http_post(
                urlPointers[0],
                urlPointers[1],
                endpoint.port,
                urlPointers[2],
                urlPointers[3],
                bodyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                body.count,
                cHeaders.baseAddress,
                cHeaders.count,
                timeoutMilliseconds,
                agentEventHTTPIsCancelled,
                Unmanaged.passUnretained(cancellation).toOpaque(),
                responseBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                responseBytes.count,
                &responseBodyLength,
                &statusCode,
                retryAfterBytes.baseAddress,
                retryAfterBytes.count,
                &retryAfterValueLength
              )
            }
          }
        }
      }
    }
    guard result == FLECK_EVENT_HTTP_SUCCESS else {
      if cancellation.isCancelled || result == FLECK_EVENT_HTTP_CANCELLED {
        throw AgentEventHTTPTransportError.cancelled
      }
      if result == FLECK_EVENT_HTTP_INVALID_REQUEST {
        throw AgentEventHTTPTransportError.invalidRequest
      }
      throw AgentEventHTTPTransportError.transportFailure
    }
    guard (0...maximumResponseBodyBytes).contains(responseBodyLength) else {
      throw AgentEventHTTPTransportError.transportFailure
    }
    guard (0...maximumRetryAfterHeaderBytes).contains(retryAfterValueLength) else {
      throw AgentEventHTTPTransportError.transportFailure
    }
    responseBody.removeSubrange(responseBodyLength..<responseBody.count)
    let responseTime = Date().timeIntervalSince1970
    let retryAfterSeconds = Self.parseRetryAfter(
      Array(retryAfterValue.prefix(retryAfterValueLength)),
      responseTime: responseTime
    )
    return AgentEventHTTPResponse(
      statusCode: Int(statusCode),
      body: responseBody,
      retryAfterSeconds: retryAfterSeconds
    )
  }

  private static func withCStringPointers<T>(
    _ values: [String],
    operation: ([UnsafePointer<CChar>]) -> T
  ) -> T {
    var pointers: [UnsafePointer<CChar>] = []
    func visit(_ index: Int) -> T {
      guard index < values.count else { return operation(pointers) }
      return values[index].withCString { pointer in
        pointers.append(pointer)
        defer { pointers.removeLast() }
        return visit(index + 1)
      }
    }
    return visit(0)
  }

  private static func withCStringHeaders<T>(
    _ headers: [AgentEventHTTPHeader],
    operation: (UnsafeBufferPointer<FleckEventHTTPHeader>) -> T
  ) -> T {
    var cHeaders: [FleckEventHTTPHeader] = []
    func visit(_ index: Int) -> T {
      guard index < headers.count else {
        return cHeaders.withUnsafeBufferPointer(operation)
      }
      let header = headers[index]
      return header.name.withCString { name in
        header.value.withCString { value in
          cHeaders.append(FleckEventHTTPHeader(name: name, value: value))
          defer { cHeaders.removeLast() }
          return visit(index + 1)
        }
      }
    }
    return visit(0)
  }
}

private final class AgentEventHTTPWorkerPool: @unchecked Sendable {
  static let shared = AgentEventHTTPWorkerPool()

  let queue: OperationQueue
  private let lock = NSLock()
  private var activeRequests = 0

  private init() {
    queue = OperationQueue()
    queue.maxConcurrentOperationCount = AgentEventHTTPTransport.maximumConcurrentRequests
    queue.qualityOfService = .utility
  }

  func reserve() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard activeRequests < AgentEventHTTPTransport.maximumConcurrentRequests else { return false }
    activeRequests += 1
    return true
  }

  func release() {
    lock.lock()
    activeRequests -= 1
    lock.unlock()
  }
}

private final class AgentEventHTTPCancellationFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false

  var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled
  }

  func cancel() {
    lock.lock()
    cancelled = true
    lock.unlock()
  }
}

private final class AgentEventHTTPHostCallbackState {
  var completed = false
  var failed = false
}

private func agentEventHTTPHostCallback(
  _ host: CFHost,
  _ typeInfo: CFHostInfoType,
  _ error: UnsafePointer<CFStreamError>?,
  _ clientInfo: UnsafeMutableRawPointer?
) {
  guard typeInfo == .addresses, let clientInfo else { return }
  let state = Unmanaged<AgentEventHTTPHostCallbackState>.fromOpaque(clientInfo)
    .takeUnretainedValue()
  state.failed = error.map { $0.pointee.domain != 0 || $0.pointee.error != 0 } ?? false
  state.completed = true
  _ = host
}

private func agentEventHTTPIsCancelled(_ context: UnsafeMutableRawPointer?) -> Int32 {
  guard let context else { return 1 }
  let cancellation = Unmanaged<AgentEventHTTPCancellationFlag>.fromOpaque(context)
    .takeUnretainedValue()
  return cancellation.isCancelled ? 1 : 0
}
