#if os(macOS) && DEBUG
  import CryptoKit
  import Foundation
  import Testing

  @testable import FleckApp

  private enum FleckPillFixtureSupport {
    static let expectedSHA256 = "c294443bb4c5402fbc00aad0c4cb635dada3605e46c2d1dda3e9a4e17232681a"
    static let url = ProcessInfo.processInfo.environment["FLECK_PILL_REFERENCE_FIXTURE"]
      .map(URL.init(fileURLWithPath:))

    static func load() throws -> (NativeReferenceFixture, Data) {
      let url = try #require(url)
      let data = try Data(contentsOf: url)
      let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
      #expect(digest == expectedSHA256)
      return (try JSONDecoder().decode(NativeReferenceFixture.self, from: data), data)
    }

    static func expectClose(_ actual: Double, _ expected: Double, tolerance: Double = 0.000001) {
      #expect(abs(actual - expected) <= tolerance, "\(actual) differs from \(expected)")
    }

    static func expectNumbers(
      _ actual: [Double],
      _ expected: [Double],
      tolerance: Double,
      sourceLocation: SourceLocation = #_sourceLocation
    ) {
      #expect(actual.count == expected.count, "Numeric token counts differ", sourceLocation: sourceLocation)
      for (index, pair) in zip(actual, expected).enumerated() {
        #expect(
          abs(pair.0 - pair.1) <= tolerance,
          "Value \(index): \(pair.0) differs from \(pair.1)",
          sourceLocation: sourceLocation
        )
      }
    }

    static func expectPath(
      _ actual: String,
      _ expected: String,
      sourceLocation: SourceLocation = #_sourceLocation
    ) {
      let actualTokens = actual.split(whereSeparator: { $0.isWhitespace }).map(String.init)
      let expectedTokens = expected.split(whereSeparator: { $0.isWhitespace }).map(String.init)
      let actualCommands = actualTokens.filter { $0.first?.isLetter == true }
      let expectedCommands = expectedTokens.filter { $0.first?.isLetter == true }
      #expect(actualCommands == expectedCommands, "Path command sequences differ", sourceLocation: sourceLocation)
      let actualNumbers = actualTokens.compactMap(Double.init)
      let expectedNumbers = expectedTokens.compactMap(Double.init)
      expectNumbers(actualNumbers, expectedNumbers, tolerance: 0.0001, sourceLocation: sourceLocation)
    }
  }

  private struct NativeReferenceFixture: Decodable {
    var formatVersion: Int
    var units: Units
    var phaseRateRadiansPerSecond: Double
    var anchors: [String: Double]
    var staticBounds: [String: Bounds]
    var contours: [String: String]
    var easing: [Easing]
    var geometry: [Geometry]
    var frames: [FrameCase]
    var waves: [Wave]

    struct Units: Decodable {
      var artworkToLogical: Double
      var viewBox: [Double]
      var baselineArtworkY: Double
      var nativeCanvasPoints: [Double]
    }

    struct Bounds: Decodable {
      var width: Double
      var height: Double
    }

    struct Easing: Decodable {
      var t: Double
      var value: Double
    }

    struct Geometry: Decodable {
      var expansion: Double
      var contour: String
      var fill: String
      var transform: String
      var scaleY: Double
      var translateY: Double
      var lightTransform: String
      var bodyTop: Double
      var width: Double
      var height: Double
    }

    struct FrameCase: Decodable {
      var time: Double
      var frame: Frame
      var geometry: Geometry
      var signal: Signal
    }

    struct Frame: Decodable {
      var time: Double
      var referenceState: String
      var label: String
      var segment: String
      var expansion: Double
      var energy: Double
      var phase: Double
      var activationMix: Double
      var processingMix: Double
      var signalOpacity: Double
      var glint: Double
      var glintOpacity: Double
    }

    struct Signal: Decodable {
      var points: [Point]
      var core: String
      var scatter: String
      var line: String
      var waveOpacity: Double
      var lineOpacity: Double
    }

    struct Point: Decodable {
      var x: Double
      var y: Double
    }

    struct Wave: Decodable {
      var energy: Double
      var phase: Double
      var state: String
      var points: [Point]
    }
  }

  @Test(.enabled(if: FleckPillFixtureSupport.url != nil, "Set FLECK_PILL_REFERENCE_FIXTURE to the approved v2 fixture"))
  func FleckPillNativeOutputMatchesApprovedFixture() throws {
    let (fixture, _) = try FleckPillFixtureSupport.load()
    #expect(fixture.formatVersion == 1)
    FleckPillFixtureSupport.expectClose(fixture.units.artworkToLogical, 0.75)
    FleckPillFixtureSupport.expectClose(fixture.units.baselineArtworkY, 40)
    FleckPillFixtureSupport.expectNumbers(fixture.units.viewBox, [-8, -12, 240, 52], tolerance: 0.000001)
    FleckPillFixtureSupport.expectNumbers(fixture.units.nativeCanvasPoints, [180, 39], tolerance: 0.000001)
    FleckPillFixtureSupport.expectClose(fixture.phaseRateRadiansPerSecond, FleckPillMotion.wavePhaseRate)
    #expect(fixture.anchors == Dictionary(uniqueKeysWithValues: FleckPillMotion.anchors.map { ($0.key.rawValue, $0.value) }))

    for sample in fixture.easing {
      FleckPillFixtureSupport.expectClose(FleckPillGeometry.smooth(sample.t), sample.value)
    }

    #expect(fixture.geometry.count == 9)
    for expected in fixture.geometry {
      let actual = FleckPillGeometry.shell(expansion: expected.expansion)
      FleckPillFixtureSupport.expectClose(actual.expansion, expected.expansion)
      FleckPillFixtureSupport.expectPath(actual.contour.data, expected.contour)
      FleckPillFixtureSupport.expectPath(actual.fill.data, expected.fill)
      FleckPillFixtureSupport.expectNumbers(
        transformNumbers(actual.shellTransform.data),
        transformNumbers(expected.transform),
        tolerance: 0.0001
      )
      if expected.lightTransform.isEmpty {
        #expect(actual.lightTransform.translateX == 0)
        #expect(actual.lightTransform.translateY == 0)
        #expect(actual.lightTransform.scaleX == 1)
        #expect(actual.lightTransform.scaleY == 1)
      } else {
        FleckPillFixtureSupport.expectNumbers(
          transformNumbers(actual.lightTransform.data),
          transformNumbers(expected.lightTransform),
          tolerance: 0.0001
        )
      }
      FleckPillFixtureSupport.expectClose(actual.scaleY, expected.scaleY)
      FleckPillFixtureSupport.expectClose(actual.translateY, expected.translateY)
      FleckPillFixtureSupport.expectClose(actual.bodyTop, expected.bodyTop)
      FleckPillFixtureSupport.expectClose(actual.width, expected.width)
      FleckPillFixtureSupport.expectClose(actual.height, expected.height)
    }

    #expect(fixture.frames.count == 27)
    for expected in fixture.frames {
      let actual = FleckPillMotion.sample(expected.time)
      FleckPillFixtureSupport.expectClose(actual.time, expected.frame.time)
      #expect(actual.state.rawValue == expected.frame.referenceState)
      #expect(actual.label == expected.frame.label)
      #expect(actual.segment == expected.frame.segment)
      FleckPillFixtureSupport.expectClose(actual.expansion, expected.frame.expansion)
      FleckPillFixtureSupport.expectClose(actual.energy, expected.frame.energy)
      FleckPillFixtureSupport.expectClose(actual.phase, expected.frame.phase)
      FleckPillFixtureSupport.expectClose(actual.activationMix, expected.frame.activationMix)
      FleckPillFixtureSupport.expectClose(actual.processingMix, expected.frame.processingMix)
      FleckPillFixtureSupport.expectClose(actual.signalOpacity, expected.frame.signalOpacity)
      FleckPillFixtureSupport.expectClose(actual.glint, expected.frame.glint)
      FleckPillFixtureSupport.expectClose(actual.glintOpacity, expected.frame.glintOpacity)

      let geometry = FleckPillGeometry.shell(expansion: actual.expansion)
      FleckPillFixtureSupport.expectPath(geometry.contour.data, expected.geometry.contour)
      FleckPillFixtureSupport.expectPath(geometry.fill.data, expected.geometry.fill)
      let signal = FleckPillMotion.signalGeometry(actual)
      expectPoints(signal.points, expected.signal.points)
      FleckPillFixtureSupport.expectPath(signal.core.data, expected.signal.core)
      FleckPillFixtureSupport.expectPath(signal.scatter.data, expected.signal.scatter)
      FleckPillFixtureSupport.expectPath(signal.line.data, expected.signal.line)
      FleckPillFixtureSupport.expectClose(signal.waveOpacity, expected.signal.waveOpacity)
      FleckPillFixtureSupport.expectClose(signal.lineOpacity, expected.signal.lineOpacity)
    }

    #expect(fixture.waves.count == 12)
    for expected in fixture.waves {
      let pose = try #require(FleckPillPose(rawValue: expected.state))
      let actual = FleckPillGeometry.waveSamples(
        energy: expected.energy,
        phase: expected.phase,
        pose: pose
      )
      expectPoints(actual, expected.points)
    }

    for pose in FleckPillPose.allCases {
      let expected = try #require(fixture.staticBounds[pose.rawValue])
      let frame = try FleckPillGeometry.pose(named: pose.rawValue)
      let geometry = FleckPillGeometry.shell(expansion: frame.expansion)
      FleckPillFixtureSupport.expectClose(geometry.width, expected.width)
      FleckPillFixtureSupport.expectClose(geometry.height, expected.height)
    }
    FleckPillFixtureSupport.expectPath(
      FleckPillGeometry.shell(expansion: 0).contour.data,
      try #require(fixture.contours["standby"])
    )
    FleckPillFixtureSupport.expectPath(
      FleckPillGeometry.shell(expansion: 1).contour.data,
      try #require(fixture.contours["active"])
    )
  }

  private func expectPoints(
    _ actual: [FleckPillPoint],
    _ expected: [NativeReferenceFixture.Point]
  ) {
    #expect(actual.count == expected.count, "Point counts differ")
    for pair in zip(actual, expected) {
      FleckPillFixtureSupport.expectClose(pair.0.x, pair.1.x, tolerance: 0.000001)
      FleckPillFixtureSupport.expectClose(pair.0.y, pair.1.y, tolerance: 0.000001)
    }
  }

  private func transformNumbers(_ text: String) -> [Double] {
    text.split(whereSeparator: { $0.isWhitespace || $0 == "(" || $0 == ")" })
      .compactMap { Double($0) }
  }
#endif
