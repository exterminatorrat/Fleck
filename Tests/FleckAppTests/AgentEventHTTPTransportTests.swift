import CFleckEventHTTPTestSupport
import Darwin
import Foundation
import FleckMCPFixtureSupport
import Testing

@testable import FleckApp

@Suite(.serialized)
struct AgentEventHTTPTransportTests {
  @Test func retryAfterParserAcceptsBoundedSecondsAndCanonicalIMFFixdate() {
    let responseTime = 784_111_700.0
    #expect(parseRetryAfterHeader("0", responseTime: responseTime) == 0)
    #expect(parseRetryAfterHeader("00042", responseTime: responseTime) == 42)
    #expect(parseRetryAfterHeader("900", responseTime: responseTime) == 900)
    #expect(parseRetryAfterHeader("901", responseTime: responseTime) == 900)
    #expect(
      parseRetryAfterHeader(String(UInt64.max), responseTime: responseTime) == 900)
    #expect(
      parseRetryAfterHeader("Sun, 06 Nov 1994 08:49:37 GMT", responseTime: responseTime) == 77)
    #expect(
      parseRetryAfterHeader("Sun, 06 Nov 1994 08:49:37 GMT", responseTime: 784_111_837) == 0)
    #expect(
      parseRetryAfterHeader("Sun, 06 Nov 1994 08:49:37 GMT", responseTime: 784_110_876) == 900)
    #expect(
      parseRetryAfterHeader("Tue, 29 Feb 2000 00:00:00 GMT", responseTime: 0) == 900)
    #expect(
      AgentEventHTTPResponse(statusCode: 200, body: Data()).retryAfterSeconds == nil)
    #expect(
      AgentEventHTTPResponse(statusCode: 429, body: Data(), retryAfterSeconds: 12)
        .retryAfterSeconds == 12)
  }

  @Test func retryAfterParserRejectsMalformedNumbersDatesAndReferences() {
    for value in [
      "", "+1", "-1", "1.5", "1e3", " 1", "1 ", "١",
      "18446744073709551616",
      "Mon, 06 Nov 1994 08:49:37 GMT",
      "Sun, 31 Feb 1994 08:49:37 GMT",
      "Sun, 06 Nov 1994 08:49:60 GMT",
      "Sunday, 06-Nov-94 08:49:37 GMT",
      "Sun Nov  6 08:49:37 1994",
      "Sun, 6 Nov 1994 08:49:37 GMT",
      "Sun, 06 Nov 1994 08:49:37 UTC",
      "Sun, 06 Nov 1994 08:49:37 +0000",
    ] {
      #expect(parseRetryAfterHeader(value, responseTime: 784_111_700) == nil)
    }
    #expect(parseRetryAfterHeader("1", responseTime: .infinity) == nil)
    #expect(parseRetryAfterHeader("1", responseTime: .nan) == nil)
    #expect(
      parseRetryAfterHeader("Sun, 06 Nov 1994 08:49:37 GMT", responseTime: -.infinity) == nil)
  }

  @Test func nativeRetryAfterCallbacksUseOnlyOneCompletedFinalBlock() throws {
    let callbacks = try #require(FleckEventHTTPTestResponseCallbacksCreate())
    defer { FleckEventHTTPTestResponseCallbacksDestroy(callbacks) }

    for line in [
      "HTTP/1.1 103 Early Hints\r\n",
      "Retry-After: 5\r\n",
      "\r\n",
      "HTTP/1.1 429 Too Many Requests\r\n",
      "rEtRy-AfTeR:\t 000900 \t\r\n",
      "\r\n",
    ] {
      _ = feedResponseHeader(callbacks, line)
    }
    #expect(nativeRetryAfterValue(callbacks) == "000900")

    let noFinalHint = try #require(FleckEventHTTPTestResponseCallbacksCreate())
    defer { FleckEventHTTPTestResponseCallbacksDestroy(noFinalHint) }
    for line in [
      "HTTP/1.1 100 Continue\r\n",
      "Retry-After: 2\r\n",
      "\r\n",
      "HTTP/1.1 204 No Content\r\n",
      "\r\n",
    ] {
      _ = feedResponseHeader(noFinalHint, line)
    }
    #expect(nativeRetryAfterValue(noFinalHint) == nil)

    let duplicateFinal = try #require(FleckEventHTTPTestResponseCallbacksCreate())
    defer { FleckEventHTTPTestResponseCallbacksDestroy(duplicateFinal) }
    for line in [
      "HTTP/1.1 200 OK\r\n",
      "Retry-After: 1\r\n",
      "\r\n",
      "HTTP/1.1 201 Created\r\n",
      "Retry-After: 2\r\n",
      "\r\n",
    ] {
      _ = feedResponseHeader(duplicateFinal, line)
    }
    #expect(nativeRetryAfterValue(duplicateFinal) == nil)

    let invalidStatus = try #require(FleckEventHTTPTestResponseCallbacksCreate())
    defer { FleckEventHTTPTestResponseCallbacksDestroy(invalidStatus) }
    for line in [
      "HTTP/1.1 600 Invalid Status\r\n",
      "Retry-After: 2\r\n",
      "\r\n",
      "HTTP/1.1 200 OK\r\n",
      "Retry-After: 3\r\n",
      "\r\n",
    ] {
      _ = feedResponseHeader(invalidStatus, line)
    }
    #expect(nativeRetryAfterValue(invalidStatus) == nil)
  }

  @Test func nativeRetryAfterIMFFixdateFlowsIntoSwiftParser() throws {
    let callbacks = try #require(FleckEventHTTPTestResponseCallbacksCreate())
    defer { FleckEventHTTPTestResponseCallbacksDestroy(callbacks) }
    for line in [
      "HTTP/1.1 429 Too Many Requests\r\n",
      "Retry-After: Sun, 06 Nov 1994 08:49:37 GMT\r\n",
      "\r\n",
    ] {
      _ = feedResponseHeader(callbacks, line)
    }

    let capturedValue = try #require(nativeRetryAfterValue(callbacks))
    #expect(capturedValue == "Sun, 06 Nov 1994 08:49:37 GMT")
    #expect(parseRetryAfterHeader(capturedValue, responseTime: 784_111_700) == 77)
    #expect(parseRetryAfterHeader(capturedValue, responseTime: 784_111_837) == 0)
    #expect(parseRetryAfterHeader(capturedValue, responseTime: 784_110_876) == 900)
  }

  @Test func nativeRetryAfterCallbacksRejectMalformedAndIncompleteHints() throws {
    let malformedLines = [
      ["Retry-After: 1\r\n", "retry-after: 2\r\n"],
      ["Retry-After: 1\r\n", " \t2\r\n"],
      ["Retry-After : 1\r\n"],
      ["Retry-After\r\n"],
      ["Retry-After:\t \r\n"],
      ["Retry-After: 1\u{1}2\r\n"],
      ["Retry-After: 1\t2\r\n"],
      ["Retry-After: 1\r2\r\n"],
      ["Retry-After: 1\n2\r\n"],
      ["Retry-After: 1\u{00e9}2\r\n"],
      ["Retry-After: \(String(repeating: "1", count: 1_025))\r\n"],
      ["Retry-After: 1"],
    ]
    for lines in malformedLines {
      let callbacks = try #require(FleckEventHTTPTestResponseCallbacksCreate())
      defer { FleckEventHTTPTestResponseCallbacksDestroy(callbacks) }
      _ = feedResponseHeader(callbacks, "HTTP/1.1 429 Too Many Requests\r\n")
      for line in lines { _ = feedResponseHeader(callbacks, line) }
      _ = feedResponseHeader(callbacks, "\r\n")
      #expect(nativeRetryAfterValue(callbacks) == nil)
    }

    let incompleteBlock = try #require(FleckEventHTTPTestResponseCallbacksCreate())
    defer { FleckEventHTTPTestResponseCallbacksDestroy(incompleteBlock) }
    _ = feedResponseHeader(incompleteBlock, "HTTP/1.1 429 Too Many Requests\r\n")
    _ = feedResponseHeader(incompleteBlock, "Retry-After: 5\r\n")
    #expect(nativeRetryAfterValue(incompleteBlock) == nil)
  }

  @Test func nativeRetryAfterCallbacksIgnoreTrailersAndIsolateRequests() throws {
    let callbacks = try #require(FleckEventHTTPTestResponseCallbacksCreate())
    defer { FleckEventHTTPTestResponseCallbacksDestroy(callbacks) }
    for line in [
      "HTTP/1.1 429 Too Many Requests\r\n",
      "Retry-After: 8\r\n",
      "\r\n",
    ] {
      _ = feedResponseHeader(callbacks, line)
    }
    #expect(feedResponseBody(callbacks, Array("body".utf8)) == 4)
    _ = feedResponseHeader(callbacks, "Retry-After: 99\r\n")
    #expect(nativeRetryAfterValue(callbacks) == "8")

    let trailerOnly = try #require(FleckEventHTTPTestResponseCallbacksCreate())
    defer { FleckEventHTTPTestResponseCallbacksDestroy(trailerOnly) }
    _ = feedResponseHeader(trailerOnly, "HTTP/1.1 429 Too Many Requests\r\n")
    _ = feedResponseHeader(trailerOnly, "\r\n")
    _ = feedResponseBody(trailerOnly, Array("body".utf8))
    _ = feedResponseHeader(trailerOnly, "Retry-After: 99\r\n")
    #expect(nativeRetryAfterValue(trailerOnly) == nil)

    let otherRequest = try #require(FleckEventHTTPTestResponseCallbacksCreate())
    defer { FleckEventHTTPTestResponseCallbacksDestroy(otherRequest) }
    _ = feedResponseHeader(otherRequest, "HTTP/1.1 204 No Content\r\n")
    _ = feedResponseHeader(otherRequest, "\r\n")
    #expect(nativeRetryAfterValue(otherRequest) == nil)
    #expect(nativeRetryAfterValue(callbacks) == "8")
  }

  @Test func nativeRetryAfterHeaderCapCountsAllBlocksAndTrailers() throws {
    let callbacks = try #require(FleckEventHTTPTestResponseCallbacksCreate())
    defer { FleckEventHTTPTestResponseCallbacksDestroy(callbacks) }
    let lines = [
      "HTTP/1.1 103 Early Hints\r\n",
      "\r\n",
      "HTTP/1.1 429 Too Many Requests\r\n",
      "Retry-After: 7\r\n",
      "\r\n",
    ]
    for line in lines { _ = feedResponseHeader(callbacks, line) }
    _ = feedResponseBody(callbacks, Array("x".utf8))

    let remaining = 16_384 - lines.reduce(0) { $0 + $1.utf8.count }
    let prefix = "X-Trailer: "
    let trailer = prefix + String(repeating: "x", count: remaining - prefix.utf8.count - 2) + "\r\n"
    #expect(feedResponseHeader(callbacks, trailer) == remaining)
    #expect(feedResponseHeader(callbacks, "x") == 0)
    #expect(nativeRetryAfterValue(callbacks) == nil)
  }

  @Test func failedAndCancelledNativeRequestsClearRetryAfterOutput() throws {
    let oversizedBody = Data(repeating: 0x7b, count: 1_025)
    let signature = try makeSignature(body: Data(#"{}"#.utf8))
    let failed = performNativeRequest(
      callbackURL: "https://hook.example/hook",
      certificatePath: "",
      loopbackPort: 0,
      body: oversizedBody,
      signature: signature
    )
    #expect(failed.result != 0)
    #expect(failed.responseRetryAfterBytes == 0)
    #expect(failed.opensocketCalls == 0)

    let cancellation = NativeCancellationHandle(
      try #require(FleckEventHTTPTestCancellationCreate()))
    defer { cancellation.destroy() }
    cancellation.cancel()
    let body = Data(#"{"type":"synthetic"}"#.utf8)
    let cancelled = performNativeRequest(
      callbackURL: "https://hook.example/hook",
      certificatePath: "",
      loopbackPort: 0,
      body: body,
      signature: try makeSignature(body: body),
      cancellation: cancellation.pointer
    )
    #expect(cancelled.result != 0)
    #expect(cancelled.responseRetryAfterBytes == 0)
    #expect(cancelled.opensocketCalls == 0)
    #expect(cancelled.preRequestCalls == 0)
  }

  @Test func acceptsCanonicalSubscriptionIDHeader() throws {
    try AgentEventHTTPTransport.validateHeaders([
      AgentEventHTTPHeader(name: "content-type", value: "application/json"),
      AgentEventHTTPHeader(
        name: "webhook-id",
        value: "msg_verification_00000000-0000-4000-8000-000000000001"
      ),
      AgentEventHTTPHeader(name: "webhook-timestamp", value: "1729000000"),
      AgentEventHTTPHeader(
        name: "webhook-signature",
        value: "v1,\(Data(repeating: 0, count: 32).base64EncodedString())"
      ),
      AgentEventHTTPHeader(
        name: "x-mcp-subscription-id",
        value: "evt_\(String(repeating: "a", count: 64))"
      ),
    ])
  }

  @Test func respectsApprovedResolverAndConcurrencyBounds() {
    #expect(AgentEventHTTPTransport.maximumResolutionDurationMilliseconds == 3_000)
    #expect(AgentEventHTTPTransport.maximumConcurrentRequests == 1)
  }

  @Test func signatureValidatorsAcceptBoundedKeyOverlapAndRejectMalformedValues() throws {
    let signature = try AgentEventWebhookSigner.sign(
      id: "evt_overlap",
      timestamp: Date(timeIntervalSince1970: 1_729_000_000),
      body: Data("{}".utf8),
      currentSecret: Data(repeating: 7, count: 32),
      previousSecret: Data(repeating: 8, count: 32)
    )
    let overlap = signature.webhookSignature
    let single = String(try #require(overlap.split(separator: " ").first))
    func headers(_ value: String) -> [AgentEventHTTPHeader] {
      [
        .init(name: "content-type", value: "application/json"),
        .init(name: "webhook-id", value: signature.webhookID),
        .init(name: "webhook-timestamp", value: signature.webhookTimestamp),
        .init(name: "webhook-signature", value: value),
        .init(name: "x-mcp-subscription-id", value: "evt_\(String(repeating: "a", count: 64))"),
      ]
    }

    for valid in [single, overlap] {
      try AgentEventHTTPTransport.validateHeaders(headers(valid))
      #expect(valid.withCString { FleckEventHTTPTestValidateSignature($0) } == 1)
    }
    for invalid in [
      "", " " + single, single + " ", single + "  " + single,
      single + "\t" + single, overlap + " " + single,
      single + " v1,", "v2," + String(single.dropFirst(3)),
      "v1," + String(repeating: "A", count: 42) + "B=",
    ] {
      #expect(throws: AgentEventHTTPTransportError.invalidRequest) {
        try AgentEventHTTPTransport.validateHeaders(headers(invalid))
      }
      #expect(invalid.withCString { FleckEventHTTPTestValidateSignature($0) } == 0)
    }
  }

  @Test func fixturePortReadHasFiniteDeadline() {
    let pipe = Pipe()
    let start = DispatchTime.now().uptimeNanoseconds
    let line = LocalTLSFixture.readLine(from: pipe.fileHandleForReading, timeoutSeconds: 0.05)
    let elapsed = DispatchTime.now().uptimeNanoseconds - start
    try? pipe.fileHandleForReading.close()
    try? pipe.fileHandleForWriting.close()

    #expect(line == nil)
    #expect(elapsed < 1_000_000_000)
  }

  @Test func libcurlInitializationGateOrdersFirstUseAndFailure() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let directoryRoot = try OwnedMCPFixtureRoot.create(kind: .eventHTTPTransport)
    let directory = directoryRoot.url
    var mayCleanupDirectory = true
    defer {
      if mayCleanupDirectory {
        do { try directoryRoot.cleanup() }
        catch { Issue.record("The owned libcurl probe root could not be cleaned: \(error)") }
      } else {
        Issue.record("The libcurl probe root is preserved because child termination was not confirmed")
      }
    }

    let sdk = try captureProcess(
      executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
      arguments: ["--sdk", "macosx", "--show-sdk-path"],
      timeoutSeconds: 10
    )
    guard sdk.terminationObserved else {
      mayCleanupDirectory = false
      throw HTTPFixtureError.processDidNotStop
    }
    #expect(sdk.status == 0)
    let probeURL = directory.appendingPathComponent("curl-init-probe")
    let compile = try captureProcess(
      executable: URL(fileURLWithPath: "/usr/bin/clang"),
      arguments: [
        "-std=c11", "-Wall", "-Wextra", "-Wpedantic", "-Werror", "-Wconversion",
        "-Wsign-conversion", "-Wshadow", "-Wstrict-prototypes", "-Wmissing-prototypes",
        "-DFLECK_EVENT_HTTP_INIT_PROBE=1", "-isysroot",
        sdk.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
        "-I", repositoryRoot.appendingPathComponent("Sources/CFleckEventHTTP/include").path,
        "-I",
        repositoryRoot.appendingPathComponent("Tests/CFleckEventHTTPTestSupport/include").path,
        repositoryRoot.appendingPathComponent(
          "Tests/CFleckEventHTTPTestSupport/FleckEventHTTPTestSupport.c"
        ).path,
        "-lcurl", "-framework", "CFNetwork", "-framework", "CoreFoundation", "-pthread",
        "-o", probeURL.path,
      ],
      timeoutSeconds: 20
    )
    guard compile.terminationObserved else {
      mayCleanupDirectory = false
      throw HTTPFixtureError.processDidNotStop
    }
    print("libcurl probe compile: status=\(compile.status)\n\(compile.stdout)\(compile.stderr)")
    #expect(compile.status == 0)
    guard compile.status == 0 else { throw HTTPFixtureError.processFailed }

    for scenario in ["--validate-init-failure", "--post-init-failure", "--concurrent-first-use"] {
      let probe = try captureProcess(
        executable: probeURL,
        arguments: [scenario],
        timeoutSeconds: 10
      )
      guard probe.terminationObserved else {
        mayCleanupDirectory = false
        throw HTTPFixtureError.processDidNotStop
      }
      print(
        "libcurl probe \(scenario): status=\(probe.status) timeout=\(probe.timedOut)\n\(probe.stdout)\(probe.stderr)"
      )
      #expect(!probe.timedOut)
      #expect(probe.status == 0)
    }
  }

  @Test func canonicalURLAndCurlParserAgreementPreserveEncodedTarget() throws {
    let callbackURL = "https://example.com/a%2Fb?tenant=a%2Fb"
    let endpoint = try AgentEventHTTPTransport.parseEndpoint(callbackURL)

    #expect(endpoint.url == callbackURL)
    #expect(endpoint.host == "example.com")
    #expect(endpoint.port == 443)
    #expect(endpoint.requestTarget == "/a%2Fb?tenant=a%2Fb")
    #expect(
      AgentEventHTTPTransport.curlParserAgrees(
        url: callbackURL,
        host: endpoint.host,
        port: endpoint.port,
        requestTarget: endpoint.requestTarget
      )
    )
    #expect(
      !AgentEventHTTPTransport.curlParserAgrees(
        url: callbackURL,
        host: endpoint.host,
        port: endpoint.port,
        requestTarget: "/a/b?tenant=a%2Fb"
      )
    )

    let encodedSlash = try AgentEventHTTPTransport.parseEndpoint("https://example.com/a%2Fb")
    let pathSlash = try AgentEventHTTPTransport.parseEndpoint("https://example.com/a/b")
    #expect(encodedSlash.requestTarget != pathSlash.requestTarget)

    let ipv4Endpoint = try AgentEventHTTPTransport.parseEndpoint("https://8.8.8.8:8443/hook")
    #expect(ipv4Endpoint.resolverHost == "8.8.8.8")
    #expect(ipv4Endpoint.port == 8443)
    let ipv6Endpoint = try AgentEventHTTPTransport.parseEndpoint(
      "https://[2001:4860:4860::8888]:8443/hook")
    #expect(ipv6Endpoint.resolverHost == "2001:4860:4860::8888")
    #expect(ipv6Endpoint.port == 8443)
  }

  @Test func rejectsUnsafeCallbackURLsAndCallerControlledHeaders() throws {
    for callbackURL in [
      "http://example.com/hook",
      "https://user@example.com/hook",
      "https://example.com/hook#fragment",
      "https://example.com./hook",
      "https://2130706433/hook",
      "https://127.1/hook",
      "https://0177.0.0.1/hook",
      "https://0x7f000001/hook",
      "https://1.2.3.999/hook",
      "https://[fe80::1%25en0]/hook",
      "https://example.com/%2/hook",
      "HTTPS://Example.COM:443/hook",
    ] {
      #expect(throws: AgentEventHTTPTransportError.invalidRequest) {
        try AgentEventHTTPTransport.parseEndpoint(callbackURL)
      }
    }

    let validHeaders = [
      AgentEventHTTPHeader(name: "content-type", value: "application/json"),
      AgentEventHTTPHeader(name: "webhook-id", value: "evt_123"),
      AgentEventHTTPHeader(name: "webhook-timestamp", value: "1729000000"),
      AgentEventHTTPHeader(
        name: "webhook-signature",
        value: "v1,\(Data(repeating: 0, count: 32).base64EncodedString())"
      ),
      AgentEventHTTPHeader(
        name: "x-mcp-subscription-id",
        value: "evt_\(String(repeating: "a", count: 64))"
      ),
    ]
    try AgentEventHTTPTransport.validateHeaders(validHeaders)

    for invalidHeaders in [
      [
        validHeaders[0], validHeaders[1], validHeaders[2], validHeaders[3],
        AgentEventHTTPHeader(name: "webhook-id", value: "evt_other"),
      ],
      [
        validHeaders[0], validHeaders[1], validHeaders[2], validHeaders[3],
        AgentEventHTTPHeader(name: "host", value: "attacker.example"),
      ],
      [
        validHeaders[0], validHeaders[1], validHeaders[2], validHeaders[3],
        AgentEventHTTPHeader(name: "content-length", value: "0"),
      ],
      [
        validHeaders[0], validHeaders[1], validHeaders[2], validHeaders[3],
        AgentEventHTTPHeader(name: "authorization", value: "Bearer synthetic"),
      ],
      [
        validHeaders[0], validHeaders[1], validHeaders[2], validHeaders[3],
        AgentEventHTTPHeader(name: "connection", value: "keep-alive"),
      ],
      [
        AgentEventHTTPHeader(name: "content-type", value: "application/json\r\nHost: attacker"),
        validHeaders[1], validHeaders[2], validHeaders[3], validHeaders[4],
      ],
      [
        validHeaders[0], validHeaders[1], validHeaders[2],
        AgentEventHTTPHeader(name: "webhook-signature", value: "v1,abc\u{00}def"), validHeaders[4],
      ],
      [
        validHeaders[0], validHeaders[1], validHeaders[2],
        AgentEventHTTPHeader(
          name: "webhook-signature", value: String(repeating: "x", count: 1_025)), validHeaders[4],
      ],
      [
        validHeaders[1], validHeaders[2], validHeaders[3], validHeaders[4],
        AgentEventHTTPHeader(name: "x-mcp-subscription-id", value: validHeaders[4].value),
      ],
      [
        validHeaders[0], validHeaders[1], validHeaders[2], validHeaders[3],
        AgentEventHTTPHeader(
          name: "x-mcp-subscription-id", value: "evt_\(String(repeating: "A", count: 64))"),
      ],
      [
        validHeaders[0], validHeaders[1], validHeaders[2], validHeaders[3],
        AgentEventHTTPHeader(name: "x-mcp-subscription-id", value: "evt_short"),
      ],
      [
        validHeaders[0], validHeaders[1], validHeaders[2], validHeaders[3],
        AgentEventHTTPHeader(name: "X-MCP-Subscription-Id", value: validHeaders[4].value),
      ],
      Array(validHeaders.dropLast()),
      validHeaders + [
        AgentEventHTTPHeader(name: "x-mcp-subscription-id", value: validHeaders[4].value)
      ],
    ] {
      #expect(throws: AgentEventHTTPTransportError.invalidRequest) {
        try AgentEventHTTPTransport.validateHeaders(invalidHeaders)
      }
    }

    #expect(throws: AgentEventHTTPTransportError.invalidRequest) {
      try AgentEventHTTPTransport.validateBody(Data(repeating: 0x7b, count: 1_025))
    }
    try AgentEventHTTPTransport.validateBody(Data(repeating: 0x7b, count: 1_024))
  }

  @Test func validatesEverySyntheticResolverAddressAndRejectsMalformedLayouts() throws {
    let accepted = try AgentEventHTTPTransport.validateResolvedAddresses([
      resolverIPv4("8.8.8.8"),
      resolverIPv4("1.1.1.1"),
      resolverIPv6("2001:4860:4860::8888"),
    ])
    #expect(accepted.count == 3)
    #expect(accepted.map(\.family) == [AF_INET, AF_INET, AF_INET6])
    #expect(accepted.first?.numericAddress == "8.8.8.8")

    let adjacentPublic = try AgentEventHTTPTransport.validateResolvedAddresses([
      resolverIPv6("3fff:1000::1"),
    ])
    #expect(adjacentPublic.count == 1)

    for forbidden in [
      "0.0.0.0", "10.1.2.3", "100.64.0.1", "127.0.0.1", "169.254.1.1",
      "172.31.1.1", "192.0.0.1", "192.0.2.1", "192.88.99.1", "192.168.1.1",
      "198.18.0.1", "198.51.100.1", "203.0.113.1", "224.0.0.1", "240.0.0.1",
      "255.255.255.255",
    ] {
      #expect(throws: AgentEventHTTPTransportError.invalidRequest) {
        try AgentEventHTTPTransport.validateResolvedAddresses([resolverIPv4(forbidden)])
      }
    }

    for forbidden in [
      "::", "::1", "::ffff:8.8.8.8", "64:ff9b::808:808", "2001::1", "2001:db8::1",
      "2002:808:808::", "fc00::1", "fe80::1", "ff02::1",
      "3fff::1", "3fff:0fff:ffff:ffff:ffff:ffff:ffff:ffff",
      "3ffe::", "3ffe:ffff:ffff:ffff:ffff:ffff:ffff:ffff",
    ] {
      #expect(throws: AgentEventHTTPTransportError.invalidRequest) {
        try AgentEventHTTPTransport.validateResolvedAddresses([resolverIPv6(forbidden)])
      }
    }

    #expect(throws: AgentEventHTTPTransportError.invalidRequest) {
      try AgentEventHTTPTransport.validateResolvedAddresses([
        resolverIPv4("8.8.8.8"), resolverIPv4("127.0.0.1"),
      ])
    }
    #expect(throws: AgentEventHTTPTransportError.invalidRequest) {
      try AgentEventHTTPTransport.validateResolvedAddresses([
        resolverIPv4("8.8.8.8"), resolverIPv6("3fff::1"),
      ])
    }
    #expect(throws: AgentEventHTTPTransportError.invalidRequest) {
      try AgentEventHTTPTransport.validateResolvedAddresses([])
    }
    #expect(throws: AgentEventHTTPTransportError.invalidRequest) {
      try AgentEventHTTPTransport.validateResolvedAddresses([Data([0, 0])])
    }

    var malformedLength = resolverIPv4("8.8.8.8")
    malformedLength[0] = 1
    #expect(throws: AgentEventHTTPTransportError.invalidRequest) {
      try AgentEventHTTPTransport.validateResolvedAddresses([malformedLength])
    }

    let scopedAddress = resolverIPv6("2001:4860:4860::8888", scopeID: 1)
    #expect(throws: AgentEventHTTPTransportError.invalidRequest) {
      try AgentEventHTTPTransport.validateResolvedAddresses([scopedAddress])
    }
  }

  @Test func rejectsMixedResolverArraysBeforeAssumingCFDataValues() throws {
    let values: [AnyObject] = [
      resolverIPv4("8.8.8.8") as NSData,
      "not resolver data" as NSString,
    ]
    let addresses = values as CFArray

    #expect(throws: AgentEventHTTPTransportError.invalidRequest) {
      try AgentEventHTTPTransport.copyResolverAddresses(addresses)
    }
  }

  @Test func curlPinsThePublicSockaddrThenUsesTestOnlyLoopbackTLS() throws {
    let certificate = try SyntheticTLSCertificate.make(hostname: "hook.example")
    let fixture = try LocalTLSFixture(certificate: certificate)
    defer { fixture.remove() }
    let body = Data([0x7b, 0x00, 0xff, 0x7d])
    let signature = try makeSignature(body: body)

    let result = performNativeRequest(
      callbackURL: fixture.callbackURL(path: "/hook/a%2Fb?tenant=a%2Fb"),
      certificatePath: certificate.certificateURL.path,
      loopbackPort: fixture.port,
      body: body,
      signature: signature
    )
    let request = try #require(fixture.events.first { $0["kind"] as? String == "request" })

    #expect(result.result == 0)
    #expect(result.opensocketCalls == 1)
    #expect(result.pinMatches == 1)
    #expect(result.socketsCreated == 1)
    #expect(result.preRequestCalls == 1)
    #expect(result.statusCode == 202)
    #expect(
      fixture.events.contains {
        $0["kind"] as? String == "sni" && $0["name"] as? String == "hook.example"
      })
    #expect(request["target"] as? String == "/hook/a%2Fb?tenant=a%2Fb")
    #expect(request["host"] as? String == "hook.example:\(fixture.port)")
    #expect(request["body_hex"] as? String == body.map { String(format: "%02x", $0) }.joined())
    let receivedHeaders = try #require(request["headers"] as? [String: String])
    #expect(receivedHeaders["content-type"] == "application/json")
    #expect(receivedHeaders["webhook-id"] == signature.webhookID)
    #expect(receivedHeaders["webhook-timestamp"] == signature.webhookTimestamp)
    #expect(receivedHeaders["webhook-signature"] == signature.webhookSignature)
    #expect(
      receivedHeaders["x-mcp-subscription-id"]
        == "evt_\(String(repeating: "a", count: 64))"
    )
  }

  @Test func nativeFixtureRejectsInvalidSubscriptionIDBeforeOpeningSocket() throws {
    let certificate = try SyntheticTLSCertificate.make(hostname: "hook.example")
    let fixture = try LocalTLSFixture(certificate: certificate)
    defer { fixture.remove() }
    let body = Data(#"{"type":"synthetic"}"#.utf8)
    let signature = try makeSignature(body: body)
    let result = performNativeRequest(
      callbackURL: fixture.callbackURL(),
      certificatePath: certificate.certificateURL.path,
      loopbackPort: fixture.port,
      body: body,
      signature: signature,
      subscriptionID: "evt_\(String(repeating: "A", count: 64))"
    )

    #expect(result.result != 0)
    #expect(result.opensocketCalls == 0)
    #expect(result.socketsCreated == 0)
    #expect(fixture.httpByteCount == 0)
  }

  @Test func wrongHostnameAndUntrustedCertificateSendNoHTTPBytes() throws {
    let trustedCertificate = try SyntheticTLSCertificate.make(hostname: "hook.example")
    let wrongHostnameFixture = try LocalTLSFixture(certificate: trustedCertificate)
    defer { wrongHostnameFixture.remove() }
    let body = Data(#"{"type":"synthetic"}"#.utf8)
    let signature = try makeSignature(body: body)
    let wrongHostname = performNativeRequest(
      callbackURL: wrongHostnameFixture.callbackURL(hostname: "wrong.example"),
      certificatePath: trustedCertificate.certificateURL.path,
      loopbackPort: wrongHostnameFixture.port,
      body: body,
      signature: signature
    )
    #expect(wrongHostname.result != 0)
    #expect(wrongHostnameFixture.httpByteCount == 0)

    let untrustedCertificate = try SyntheticTLSCertificate.make(hostname: "hook.example")
    let untrustedFixture = try LocalTLSFixture(certificate: untrustedCertificate)
    defer { untrustedFixture.remove() }
    let untrusted = performNativeRequest(
      callbackURL: untrustedFixture.callbackURL(),
      certificatePath: trustedCertificate.certificateURL.path,
      loopbackPort: untrustedFixture.port,
      body: body,
      signature: signature
    )
    #expect(untrusted.result != 0)
    #expect(untrustedFixture.httpByteCount == 0)
  }

  @Test func immutablePinRejectsMismatchedCurlDestinationBeforeCreatingSocket() throws {
    let certificate = try SyntheticTLSCertificate.make(hostname: "hook.example")
    let url = "https://hook.example:4443/hook"
    let body = Data(#"{"type":"synthetic"}"#.utf8)
    let signature = try makeSignature(body: body)
    let result = performNativeRequest(
      callbackURL: url,
      certificatePath: certificate.certificateURL.path,
      loopbackPort: 1,
      body: body,
      signature: signature,
      pinnedAddress: "93.184.216.34",
      resolveAddress: "93.184.215.14"
    )

    #expect(result.result != 0)
    #expect(result.opensocketCalls == 1)
    #expect(result.pinMatches == 0)
    #expect(result.socketsCreated == 0)
    #expect(result.pinRejected == 1)
  }

  @Test func hostileProxyEnvironmentCannotChangePinnedDestination() throws {
    let certificate = try SyntheticTLSCertificate.make(hostname: "hook.example")
    let fixture = try LocalTLSFixture(certificate: certificate)
    defer { fixture.remove() }
    let body = Data(#"{"type":"synthetic"}"#.utf8)
    let signature = try makeSignature(body: body)
    let result = performNativeRequest(
      callbackURL: fixture.callbackURL(),
      certificatePath: certificate.certificateURL.path,
      loopbackPort: fixture.port,
      body: body,
      signature: signature,
      flags: 1
    )

    #expect(result.result == 0)
    #expect(result.pinMatches == 1)
    #expect(result.socketsCreated == 1)
    #expect(fixture.events.contains { $0["kind"] as? String == "request" })
  }

  @Test func peerResetDoesNotChangeSIGPIPEDisposition() throws {
    let certificate = try SyntheticTLSCertificate.make(hostname: "hook.example")
    let fixture = try LocalTLSFixture(
      certificate: certificate,
      configuration: .init(resetAfterRequest: true)
    )
    defer { fixture.remove() }
    let body = Data(#"{"type":"synthetic"}"#.utf8)
    let signature = try makeSignature(body: body)
    let signalStateBefore = FleckEventHTTPTestSIGPIPEFingerprint()
    #expect(signalStateBefore != 0)

    let result = performNativeRequest(
      callbackURL: fixture.callbackURL(),
      certificatePath: certificate.certificateURL.path,
      loopbackPort: fixture.port,
      body: body,
      signature: signature
    )

    #expect(result.result != 0)
    #expect(result.opensocketCalls == 1)
    #expect(result.pinMatches == 1)
    #expect(result.socketsCreated == 1)
    #expect(fixture.httpByteCount > 0)
    #expect(FleckEventHTTPTestSIGPIPEFingerprint() == signalStateBefore)
  }

  @Test func redirectsAreNotFollowedAndAltSvcCannotChangeFreshAttemptPin() throws {
    let certificate = try SyntheticTLSCertificate.make(hostname: "hook.example")
    let redirectFixture = try LocalTLSFixture(
      certificate: certificate,
      configuration: .init(
        maximumConnections: 2,
        responseStatus: 302,
        responseHeaders: ["Location": "/redirected"]
      )
    )
    defer { redirectFixture.remove() }
    let body = Data(#"{"type":"synthetic"}"#.utf8)
    let signature = try makeSignature(body: body)
    let redirected = performNativeRequest(
      callbackURL: redirectFixture.callbackURL(),
      certificatePath: certificate.certificateURL.path,
      loopbackPort: redirectFixture.port,
      body: body,
      signature: signature
    )
    #expect(redirected.result == 0)
    #expect(redirected.statusCode == 302)
    #expect(redirected.opensocketCalls == 1)
    #expect(redirectFixture.events.filter { $0["kind"] as? String == "request" }.count == 1)

    let altServiceFixture = try LocalTLSFixture(
      certificate: certificate,
      configuration: .init(
        maximumConnections: 2,
        responseHeaders: ["Alt-Svc": "h2=\"93.184.216.35:{PORT}\"; ma=3600"]
      )
    )
    defer { altServiceFixture.remove() }
    let first = performNativeRequest(
      callbackURL: altServiceFixture.callbackURL(),
      certificatePath: certificate.certificateURL.path,
      loopbackPort: altServiceFixture.port,
      body: body,
      signature: signature,
      pinnedAddress: "93.184.216.34"
    )
    let second = performNativeRequest(
      callbackURL: altServiceFixture.callbackURL(),
      certificatePath: certificate.certificateURL.path,
      loopbackPort: altServiceFixture.port,
      body: body,
      signature: signature,
      pinnedAddress: "93.184.215.14"
    )

    #expect(first.result == 0)
    #expect(second.result == 0)
    #expect(first.pinMatches == 1)
    #expect(second.pinMatches == 1)
    #expect(second.opensocketCalls == 1)
    #expect(altServiceFixture.events.filter { $0["kind"] as? String == "request" }.count == 2)
  }

  @Test func cancellationAtFinalGateAndStalledTransfersAreBounded() async throws {
    let certificate = try SyntheticTLSCertificate.make(hostname: "hook.example")
    let body = Data(#"{"type":"synthetic"}"#.utf8)
    let signature = try makeSignature(body: body)

    let preRequestFixture = try LocalTLSFixture(certificate: certificate)
    defer { preRequestFixture.remove() }
    let cancelled = performNativeRequest(
      callbackURL: preRequestFixture.callbackURL(),
      certificatePath: certificate.certificateURL.path,
      loopbackPort: preRequestFixture.port,
      body: body,
      signature: signature,
      flags: 2
    )
    #expect(cancelled.result != 0)
    #expect(cancelled.preRequestCalls == 1)
    #expect(preRequestFixture.httpByteCount == 0)

    let stalledTLSFixture = try LocalTLSFixture(
      certificate: certificate,
      configuration: .init(stallBeforeTLSMilliseconds: 1_000)
    )
    defer { stalledTLSFixture.remove() }
    let stalledTLS = performNativeRequest(
      callbackURL: stalledTLSFixture.callbackURL(),
      certificatePath: certificate.certificateURL.path,
      loopbackPort: stalledTLSFixture.port,
      body: body,
      signature: signature,
      timeoutMilliseconds: 250
    )
    #expect(stalledTLS.result != 0)
    #expect(stalledTLSFixture.httpByteCount == 0)

    let stalledResponseFixture = try LocalTLSFixture(
      certificate: certificate,
      configuration: .init(stallAfterRequestMilliseconds: 2_000)
    )
    defer { stalledResponseFixture.remove() }
    let cancellation = NativeCancellationHandle(
      try #require(FleckEventHTTPTestCancellationCreate()))
    defer { cancellation.destroy() }
    let task = Task.detached {
      performNativeRequest(
        callbackURL: stalledResponseFixture.callbackURL(),
        certificatePath: certificate.certificateURL.path,
        loopbackPort: stalledResponseFixture.port,
        body: body,
        signature: signature,
        cancellation: cancellation.pointer
      )
    }
    do {
      _ = try await stalledResponseFixture.waitForRequest()
    } catch {
      cancellation.cancel()
      _ = await task.value
      throw error
    }
    cancellation.cancel()
    let result = await task.value
    #expect(result.result != 0)
    #expect(result.preRequestCalls == 1)
  }

  @Test func responseHeaderAndBodyLimitsAbortBoundedTransfer() throws {
    let certificate = try SyntheticTLSCertificate.make(hostname: "hook.example")
    let body = Data(#"{"type":"synthetic"}"#.utf8)
    let signature = try makeSignature(body: body)

    let largeHeadersFixture = try LocalTLSFixture(
      certificate: certificate,
      configuration: .init(
        responseHeaders: ["X-Large": String(repeating: "x", count: 17_000)]
      )
    )
    defer { largeHeadersFixture.remove() }
    let largeHeaders = performNativeRequest(
      callbackURL: largeHeadersFixture.callbackURL(),
      certificatePath: certificate.certificateURL.path,
      loopbackPort: largeHeadersFixture.port,
      body: body,
      signature: signature
    )
    #expect(largeHeaders.result != 0)
    #expect(largeHeadersFixture.events.contains { $0["kind"] as? String == "request" })

    let largeBodyFixture = try LocalTLSFixture(
      certificate: certificate,
      configuration: .init(responseBodyBytes: 65_537)
    )
    defer { largeBodyFixture.remove() }
    let largeBody = performNativeRequest(
      callbackURL: largeBodyFixture.callbackURL(),
      certificatePath: certificate.certificateURL.path,
      loopbackPort: largeBodyFixture.port,
      body: body,
      signature: signature
    )
    #expect(largeBody.result != 0)
    #expect(largeBody.responseBodyBytes <= 65_536)
  }
}

private struct NativeObservation: Sendable {
  let result: Int32
  let curlCode: Int32
  let opensocketCalls: UInt32
  let pinMatches: UInt32
  let socketsCreated: UInt32
  let preRequestCalls: UInt32
  let pinRejected: UInt32
  let statusCode: Int
  let responseBodyBytes: UInt64
  let responseRetryAfterBytes: UInt64
}

private func performNativeRequest(
  callbackURL: String,
  certificatePath: String,
  loopbackPort: UInt16,
  body: Data,
  signature: AgentEventWebhookSignature,
  pinnedAddress: String = "93.184.216.34",
  resolveAddress: String? = nil,
  timeoutMilliseconds: UInt32 = 2_000,
  flags: UInt32 = 0,
  subscriptionID: String = "evt_\(String(repeating: "a", count: 64))",
  cancellation: OpaquePointer? = nil
) -> NativeObservation {
  let resolvedAddress = resolveAddress ?? pinnedAddress
  let values = [
    callbackURL,
    pinnedAddress,
    resolvedAddress,
    certificatePath,
    signature.webhookID,
    signature.webhookTimestamp,
    signature.webhookSignature,
    subscriptionID,
  ]

  return withCStringPointers(values) { pointers in
    body.withUnsafeBytes { bodyBytes in
      var request = FleckEventHTTPTestRequest(
        url: pointers[0],
        pin_address: pointers[1],
        resolve_address: pointers[2],
        certificate_path: pointers[3],
        body: bodyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
        body_length: body.count,
        webhook_id: pointers[4],
        webhook_timestamp: pointers[5],
        webhook_signature: pointers[6],
        subscription_id: pointers[7],
        loopback_port: loopbackPort,
        timeout_ms: timeoutMilliseconds,
        flags: flags,
        cancellation: cancellation
      )
      var observation = FleckEventHTTPTestObservation()
      let result = FleckEventHTTPTestPerform(&request, &observation)
      let native = NativeObservation(
        result: result,
        curlCode: observation.curl_code,
        opensocketCalls: observation.opensocket_calls,
        pinMatches: observation.pin_matches,
        socketsCreated: observation.sockets_created,
        preRequestCalls: observation.pre_request_calls,
        pinRejected: observation.pin_rejected,
        statusCode: Int(observation.status_code),
        responseBodyBytes: observation.response_body_bytes,
        responseRetryAfterBytes: observation.response_retry_after_bytes
      )
      return native
    }
  }
}

private func parseRetryAfterHeader(
  _ value: String,
  responseTime: TimeInterval
) -> TimeInterval? {
  AgentEventHTTPTransport.parseRetryAfter(Array(value.utf8), responseTime: responseTime)
}

private func feedResponseHeader(_ callbacks: OpaquePointer, _ line: String) -> Int {
  let bytes = Array(line.utf8)
  return bytes.withUnsafeBufferPointer {
    Int(FleckEventHTTPTestResponseCallbacksHeader(callbacks, $0.baseAddress, $0.count))
  }
}

private func feedResponseBody(_ callbacks: OpaquePointer, _ bytes: [UInt8]) -> Int {
  bytes.withUnsafeBufferPointer {
    Int(FleckEventHTTPTestResponseCallbacksBody(callbacks, $0.baseAddress, $0.count))
  }
}

private func nativeRetryAfterValue(_ callbacks: OpaquePointer) -> String? {
  var value = [UInt8](repeating: 0, count: 1_024)
  var length = 0
  let copied = value.withUnsafeMutableBufferPointer {
    FleckEventHTTPTestResponseCallbacksCopyRetryAfter(
      callbacks, $0.baseAddress, $0.count, &length)
  }
  guard copied == 1, (1...value.count).contains(length) else { return nil }
  return String(decoding: value.prefix(length), as: UTF8.self)
}

private func withCStringPointers<T>(
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

private func makeSignature(body: Data) throws -> AgentEventWebhookSignature {
  try AgentEventWebhookSigner.sign(
    id: "evt_native_fixture",
    timestamp: Date(timeIntervalSince1970: 1_729_000_000),
    body: body,
    secret: Data(repeating: 0x5a, count: 32)
  )
}

private func resolverIPv4(_ text: String) -> Data {
  var address = sockaddr_in()
  address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
  address.sin_family = sa_family_t(AF_INET)
  text.withCString { _ = inet_pton(AF_INET, $0, &address.sin_addr) }
  return withUnsafeBytes(of: address) { Data($0) }
}

private func resolverIPv6(_ text: String, scopeID: UInt32 = 0) -> Data {
  var address = sockaddr_in6()
  address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
  address.sin6_family = sa_family_t(AF_INET6)
  address.sin6_scope_id = scopeID
  text.withCString { _ = inet_pton(AF_INET6, $0, &address.sin6_addr) }
  return withUnsafeBytes(of: address) { Data($0) }
}

private struct FixtureConfiguration: Encodable {
  var maximumConnections = 1
  var responseStatus = 202
  var responseBodyBytes = 0
  var responseHeaders: [String: String] = [:]
  var stallBeforeTLSMilliseconds = 0
  var stallAfterRequestMilliseconds = 0
  var resetAfterRequest = false
}

private final class SyntheticTLSCertificate {
  private let ownedRoot: OwnedMCPFixtureRoot
  let certificateURL: URL
  let privateKeyURL: URL

  private init(ownedRoot: OwnedMCPFixtureRoot, certificateURL: URL, privateKeyURL: URL) {
    self.ownedRoot = ownedRoot
    self.certificateURL = certificateURL
    self.privateKeyURL = privateKeyURL
  }

  static func make(hostname: String) throws -> SyntheticTLSCertificate {
    let ownedRoot = try OwnedMCPFixtureRoot.create(kind: .eventHTTPTransport)
    let directory = ownedRoot.url
    let certificateURL = directory.appendingPathComponent("server.pem")
    let privateKeyURL = directory.appendingPathComponent("server-key.pem")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
    process.arguments = [
      "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256", "-days", "30",
      "-keyout", privateKeyURL.path, "-out", certificateURL.path,
      "-subj", "/CN=\(hostname)",
      "-addext", "subjectAltName=DNS:\(hostname)",
      "-addext", "basicConstraints=critical,CA:TRUE",
      "-addext", "keyUsage=critical,digitalSignature,keyCertSign,keyEncipherment",
      "-addext", "extendedKeyUsage=serverAuth",
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try runBounded(process, timeoutSeconds: 15)
    } catch {
      if (error as? HTTPFixtureError) == .processDidNotStop {
        Issue.record("The synthetic TLS certificate root is preserved because OpenSSL termination was not confirmed")
      } else {
        do { try ownedRoot.cleanup() }
        catch { Issue.record("The synthetic TLS certificate root could not be cleaned: \(error)") }
      }
      throw error
    }
    return SyntheticTLSCertificate(
      ownedRoot: ownedRoot,
      certificateURL: certificateURL,
      privateKeyURL: privateKeyURL
    )
  }

  func remove() {
    do { try ownedRoot.cleanup() }
    catch { Issue.record("The synthetic TLS certificate root could not be cleaned: \(error)") }
  }

  deinit { remove() }
}

private final class LocalTLSFixture: @unchecked Sendable {
  private let ownedRoot: OwnedMCPFixtureRoot
  private let process: Process
  private let termination = DispatchSemaphore(value: 0)
  private let logURL: URL
  private var processWasStarted = false
  private(set) var port: UInt16 = 0

  init(certificate: SyntheticTLSCertificate, configuration: FixtureConfiguration = .init()) throws {
    let ownedRoot = try OwnedMCPFixtureRoot.create(kind: .eventHTTPTransport)
    self.ownedRoot = ownedRoot
    let directoryURL = ownedRoot.url
    let configurationURL = directoryURL.appendingPathComponent("configuration.json")
    logURL = directoryURL.appendingPathComponent("events.json")
    let process = Process()
    self.process = process
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [
      "-I", "-B", "-S", "-u", "-c", Self.serverScript,
      certificate.certificateURL.path,
      certificate.privateKeyURL.path,
      configurationURL.path,
      logURL.path,
    ]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    process.terminationHandler = { [termination] _ in termination.signal() }
    do {
      try JSONEncoder().encode(configuration).write(to: configurationURL, options: .atomic)
      try process.run()
      processWasStarted = true
      guard let line = Self.readLine(from: output.fileHandleForReading, timeoutSeconds: 3),
        let parsedPort = UInt16(line)
      else {
        throw HTTPFixtureError.failedToStart
      }
      port = parsedPort
    } catch {
      let stopped = stop()
      try? output.fileHandleForReading.close()
      if stopped {
        do { try ownedRoot.cleanup() }
        catch { Issue.record("The failed local TLS fixture root could not be cleaned: \(error)") }
      } else {
        Issue.record("The local TLS fixture root is preserved because server termination was not confirmed")
      }
      throw error
    }
  }

  var events: [[String: Any]] {
    guard let bytes = try? Data(contentsOf: logURL),
      let events = try? JSONSerialization.jsonObject(with: bytes) as? [[String: Any]]
    else { return [] }
    return events
  }

  var httpByteCount: Int {
    events.reduce(0) { $0 + (($1["http_bytes"] as? Int) ?? 0) }
  }

  func callbackURL(hostname: String = "hook.example", path: String = "/hook") -> String {
    "https://\(hostname):\(port)\(path)"
  }

  func waitForRequest() async throws -> [String: Any] {
    let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
    while DispatchTime.now().uptimeNanoseconds < deadline {
      if let request = events.first(where: { $0["kind"] as? String == "request" }) {
        return request
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw HTTPFixtureError.requestTimedOut
  }

  func remove() {
    guard stop() else {
      Issue.record("The local TLS fixture root is preserved because server termination was not confirmed")
      return
    }
    do { try ownedRoot.cleanup() }
    catch { Issue.record("The local TLS fixture root could not be cleaned: \(error)") }
  }

  private func stop() -> Bool {
    guard processWasStarted else { return true }
    if process.isRunning { process.terminate() }
    var stopped = termination.wait(timeout: .now() + 1) == .success
    if !stopped && process.isRunning {
      _ = Darwin.kill(process.processIdentifier, SIGKILL)
    }
    if !stopped { stopped = termination.wait(timeout: .now() + 1) == .success }
    guard stopped && !process.isRunning else { return false }
    processWasStarted = false
    return true
  }

  fileprivate static func readLine(from handle: FileHandle, timeoutSeconds: TimeInterval) -> String?
  {
    let deadline =
      DispatchTime.now().uptimeNanoseconds
      + UInt64(max(timeoutSeconds, 0) * 1_000_000_000)
    var bytes = Data()
    while bytes.count < 8 {
      let now = DispatchTime.now().uptimeNanoseconds
      guard now < deadline else { return nil }
      let remainingNanoseconds = deadline - now
      let waitMilliseconds = Int32(
        min((remainingNanoseconds + 999_999) / 1_000_000, UInt64(Int32.max)))
      var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN), revents: 0)
      guard Darwin.poll(&descriptor, 1, waitMilliseconds) > 0 else { return nil }
      var byte: UInt8 = 0
      guard Darwin.read(handle.fileDescriptor, &byte, 1) == 1 else { return nil }
      if byte == 10 { return String(data: bytes, encoding: .utf8) }
      bytes.append(byte)
    }
    return nil
  }

  private static let serverScript = #"""
    import json, os, socket, ssl, struct, sys, time
    cert_path, key_path, config_path, log_path = sys.argv[1:5]
    config = json.load(open(config_path, "r"))
    events = []
    def record(value):
        events.append(value)
        temporary = log_path + ".tmp"
        with open(temporary, "w") as output:
            json.dump(events, output)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, log_path)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(cert_path, key_path)
    def server_name(_connection, name, _context):
        record({"kind": "sni", "name": name})
    context.set_servername_callback(server_name)
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 0))
    listener.listen(max(1, config.get("maximumConnections", 1)))
    listener.settimeout(10)
    port = listener.getsockname()[1]
    print(port, flush=True)
    for _ in range(config.get("maximumConnections", 1)):
        try:
            connection, _ = listener.accept()
        except socket.timeout:
            break
        record({"kind": "accepted"})
        connection.settimeout(5)
        delay = config.get("stallBeforeTLSMilliseconds", 0)
        if delay:
            time.sleep(delay / 1000)
        try:
            tls = context.wrap_socket(connection, server_side=True)
        except (OSError, ssl.SSLError, socket.timeout) as error:
            record({"kind": "tls-error", "description": type(error).__name__})
            continue
        record({"kind": "tls"})
        data = b""
        while b"\r\n\r\n" not in data:
            chunk = tls.recv(4096)
            if not chunk:
                break
            data += chunk
        if b"\r\n\r\n" not in data:
            record({"kind": "incomplete", "http_bytes": len(data)})
            tls.close()
            continue
        boundary = data.index(b"\r\n\r\n") + 4
        header_bytes = data[:boundary]
        lines = header_bytes.decode("latin-1").split("\r\n")
        headers = {}
        for line in lines[1:]:
            if ":" in line:
                name, value = line.split(":", 1)
                headers[name.strip().lower()] = value.strip()
        expected = int(headers.get("content-length", "0"))
        while len(data) < boundary + expected:
            chunk = tls.recv(min(4096, boundary + expected - len(data)))
            if not chunk:
                break
            data += chunk
        complete = min(len(data), boundary + expected)
        request_line = lines[0].split(" ", 2)
        target = request_line[1] if len(request_line) > 1 else ""
        record({
            "kind": "request", "target": target,
            "host": headers.get("host", ""), "headers": headers,
            "body_hex": data[boundary:complete].hex(), "http_bytes": complete,
        })
        if config.get("resetAfterRequest", False):
            tls.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
            tls.close()
            continue
        delay = config.get("stallAfterRequestMilliseconds", 0)
        if delay:
            time.sleep(delay / 1000)
        response_body = b"B" * config.get("responseBodyBytes", 0)
        response_headers = {
            "Content-Length": str(len(response_body)), "Connection": "close"
        }
        port_text = str(port)
        response_headers.update({
            key: value.replace("{PORT}", port_text)
            for key, value in config.get("responseHeaders", {}).items()
        })
        response = "HTTP/1.1 {} Synthetic\r\n".format(
            config.get("responseStatus", 202)
        )
        response += "".join("{}: {}\r\n".format(key, value)
                            for key, value in response_headers.items())
        response += "\r\n"
        try:
            tls.sendall(response.encode("ascii") + response_body)
        except OSError:
            pass
        tls.close()
    listener.close()
    """#
}

private enum HTTPFixtureError: Error, Equatable {
  case failedToStart
  case processFailed
  case processDidNotStop
  case requestTimedOut
}

private final class NativeCancellationHandle: @unchecked Sendable {
  let pointer: OpaquePointer

  init(_ pointer: OpaquePointer) {
    self.pointer = pointer
  }

  func cancel() {
    FleckEventHTTPTestCancellationCancel(pointer)
  }

  func destroy() {
    FleckEventHTTPTestCancellationDestroy(pointer)
  }
}

private func runBounded(_ process: Process, timeoutSeconds: TimeInterval) throws {
  let termination = DispatchSemaphore(value: 0)
  process.terminationHandler = { _ in termination.signal() }
  try process.run()
  guard termination.wait(timeout: .now() + timeoutSeconds) == .success else {
    if process.isRunning { process.terminate() }
    var stopped = termination.wait(timeout: .now() + 1) == .success
    if !stopped && process.isRunning {
      _ = Darwin.kill(process.processIdentifier, SIGKILL)
    }
    if !stopped { stopped = termination.wait(timeout: .now() + 1) == .success }
    guard stopped && !process.isRunning else { throw HTTPFixtureError.processDidNotStop }
    throw HTTPFixtureError.processFailed
  }
  guard process.terminationStatus == 0 else { throw HTTPFixtureError.processFailed }
}

private struct CapturedProcessResult {
  let status: Int32
  let timedOut: Bool
  let terminationObserved: Bool
  let stdout: String
  let stderr: String
}

private func captureProcess(
  executable: URL,
  arguments: [String],
  timeoutSeconds: TimeInterval
) throws -> CapturedProcessResult {
  let process = Process()
  process.executableURL = executable
  process.arguments = arguments
  process.standardInput = FileHandle.nullDevice
  let output = Pipe()
  let error = Pipe()
  process.standardOutput = output
  process.standardError = error
  let termination = DispatchSemaphore(value: 0)
  process.terminationHandler = { _ in termination.signal() }
  try process.run()

  var timedOut = false
  var terminationObserved = termination.wait(timeout: .now() + timeoutSeconds) == .success
  if !terminationObserved {
    timedOut = true
    if process.isRunning { process.terminate() }
    terminationObserved = termination.wait(timeout: .now() + 1) == .success
    if !terminationObserved && process.isRunning {
      _ = Darwin.kill(process.processIdentifier, SIGKILL)
    }
    if !terminationObserved {
      terminationObserved = termination.wait(timeout: .now() + 1) == .success
    }
  }
  let stdout = terminationObserved ? output.fileHandleForReading.readDataToEndOfFile() : Data()
  let stderr = terminationObserved ? error.fileHandleForReading.readDataToEndOfFile() : Data()
  return CapturedProcessResult(
    status: terminationObserved && !timedOut ? process.terminationStatus : -1,
    timedOut: timedOut,
    terminationObserved: terminationObserved,
    stdout: String(decoding: stdout, as: UTF8.self),
    stderr: String(decoding: stderr, as: UTF8.self)
  )
}
