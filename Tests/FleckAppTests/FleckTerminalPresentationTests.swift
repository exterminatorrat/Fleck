#if os(macOS)
import Foundation
import Testing

@testable import FleckApp

private enum FleckTerminalReferenceSupport {
  static let url: URL? = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/terminal-reference-v4.1.json")

  static func load() throws -> FleckTerminalReferenceFixture {
    let url = try #require(url)
    return try JSONDecoder().decode(
      FleckTerminalReferenceFixture.self,
      from: Data(contentsOf: url)
    )
  }

  static func expectClose(
    _ actual: Double,
    _ expected: Double,
    tolerance: Double = 0.000001,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    #expect(abs(actual - expected) <= tolerance, "\(actual) differs from \(expected)", sourceLocation: sourceLocation)
  }

  static func expectPath(
    _ actual: String,
    _ expected: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let actualTokens = actual.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    let expectedTokens = expected.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    #expect(
      actualTokens.filter { $0.first?.isLetter == true }
        == expectedTokens.filter { $0.first?.isLetter == true },
      "Path command sequences differ",
      sourceLocation: sourceLocation
    )
    let actualNumbers = actualTokens.compactMap(Double.init)
    let expectedNumbers = expectedTokens.compactMap(Double.init)
    #expect(actualNumbers.count == expectedNumbers.count, "Path numeric token counts differ", sourceLocation: sourceLocation)
    for (index, pair) in zip(actualNumbers, expectedNumbers).enumerated() {
      #expect(
        abs(pair.0 - pair.1) <= 0.0001,
        "Path value \(index): \(pair.0) differs from \(pair.1)",
        sourceLocation: sourceLocation
      )
    }
  }

  static func kind(_ name: String) -> FleckErrorKind? {
    switch name {
    case "noSpeech": .noSpeech
    case "usedOriginal": .usedOriginal
    case "repairing": .repairing
    case "microphone": .microphone
    case "dictation": .dictation
    case "insertion": .insertion
    default: nil
    }
  }

  static func phase(_ name: String) -> FleckErrorButtonPhase? {
    switch name {
    case "default", "standby": .default
    case "hover": .hover
    case "pressed": .pressed
    case "pending": .pending
    case "copied": .copied
    case "copyFailed": .copyFailed
    default: nil
    }
  }
}

private struct FleckTerminalReferenceFixture: Decodable {
  let version: String
  let frames: [Frame]
  let geometry: [Geometry]
  let shimmer: [Shimmer]

  struct Frame: Decodable {
    let kind: String
    let phase: String
    let layout: Layout
    let message: String
    let action: String?
    let contour: String
  }

  struct Layout: Decodable {
    let width: Double
    let height: Double
    let visibleWidth: Double
    let visibleHeight: Double
    let baseline: Double
    let k: Double
    let artWidth: Double
    let extra: Double
    let pad: Double
    let message: Message
    let button: Button

    struct Message: Decodable {
      let x: Double
      let y: Double
      let fontSize: Double
      let anchor: String
    }

    struct Button: Decodable {
      let x: Double
      let y: Double
      let width: Double
      let height: Double
      let fontSize: Double
      let visual: Visual

      struct Visual: Decodable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
      }
    }
  }

  struct Geometry: Decodable {
    let contour: String
    let width: Double
    let height: Double
    let baseline: Double
    let q: Double
  }

  struct Shimmer: Decodable {
    let seconds: Double
    let glint: Double
    let opacity: Double
  }
}

@Test @MainActor
func FleckTerminalNativeFramesMatchFrozenV41Fixture() throws {
  let fixture = try FleckTerminalReferenceSupport.load()
  #expect(fixture.version == "4.1")
  #expect(fixture.frames.count == 26)
  #expect(fixture.geometry.count == 7)
  #expect(fixture.shimmer.count == 6)
  #expect(Set(fixture.frames.map(\.kind)) == [
    "noSpeech", "usedOriginal", "repairing", "microphone", "dictation", "insertion",
  ])

  let layout = FleckErrorLayout.approved
  for frame in fixture.frames {
    let kind = try #require(FleckTerminalReferenceSupport.kind(frame.kind))
    let phase = try #require(FleckTerminalReferenceSupport.phase(frame.phase))
    let isMicrophone = kind == .microphone
    let nativeMessageWidth = isMicrophone ? FleckErrorGeometry.microphoneMessageWidth() : 0
    let nativeOffset = isMicrophone
      ? FleckErrorGeometry.microphoneContentOffset(messageWidth: nativeMessageWidth)
      : 0
    let presentation = FleckErrorPresentation(
      kind: kind,
      sessionID: nil,
      phase: phase,
      dismissal: frame.phase == "standby" ? 1 : 0,
      target: .standby,
      sourceFrame: nil,
      messageOverride: frame.phase == "copyFailed" ? frame.message : nil,
      actionToken: nil,
      contentCenterOffset: nativeOffset
    )
    let referenceOffset = isMicrophone
      ? FleckErrorGeometry.microphoneContentOffset(
        messageWidth: FleckErrorGeometry.microphoneFallbackMessageWidth
      )
      : 0
    let expectedMessageCenterX = kind == .usedOriginal
      ? layout.canvasWidth / 2
      : isMicrophone ? layout.messageCenterX + referenceOffset : layout.messageCenterX
    let expectedDismissal = frame.phase == "standby" ? 1.0 : 0.0
    let shell = FleckErrorGeometry.shell(dismissal: expectedDismissal, target: .standby)

    #expect(presentation.message == frame.message)
    #expect(presentation.actionTitle == frame.action)
    #expect(presentation.hasTrailingContent == (frame.action != nil || kind == .repairing))
    FleckTerminalReferenceSupport.expectClose(frame.layout.width, layout.canvasWidth)
    FleckTerminalReferenceSupport.expectClose(frame.layout.height, layout.canvasHeight)
    FleckTerminalReferenceSupport.expectClose(frame.layout.visibleWidth, layout.visibleWidth)
    FleckTerminalReferenceSupport.expectClose(frame.layout.visibleHeight, layout.visibleHeight)
    FleckTerminalReferenceSupport.expectClose(frame.layout.baseline, layout.baseline)
    FleckTerminalReferenceSupport.expectClose(frame.layout.k, layout.scale)
    FleckTerminalReferenceSupport.expectClose(frame.layout.artWidth, layout.artworkWidth)
    FleckTerminalReferenceSupport.expectClose(frame.layout.extra, layout.centerExtension)
    FleckTerminalReferenceSupport.expectClose(frame.layout.pad, layout.artworkPadding)
    FleckTerminalReferenceSupport.expectClose(frame.layout.message.x, expectedMessageCenterX)
    FleckTerminalReferenceSupport.expectClose(frame.layout.message.y, layout.messageTextCenterY)
    FleckTerminalReferenceSupport.expectClose(frame.layout.message.fontSize, FleckErrorGeometry.messageSize)
    #expect(frame.layout.message.anchor == "middle")
    FleckTerminalReferenceSupport.expectClose(
      frame.layout.button.x,
      layout.buttonX + referenceOffset
    )
    FleckTerminalReferenceSupport.expectClose(frame.layout.button.y, layout.buttonY)
    FleckTerminalReferenceSupport.expectClose(frame.layout.button.width, layout.buttonWidth)
    FleckTerminalReferenceSupport.expectClose(frame.layout.button.height, layout.buttonHeight)
    FleckTerminalReferenceSupport.expectClose(frame.layout.button.fontSize, FleckErrorGeometry.actionSize)
    FleckTerminalReferenceSupport.expectClose(frame.layout.button.visual.x, layout.buttonFaceX)
    FleckTerminalReferenceSupport.expectClose(frame.layout.button.visual.y, layout.buttonFaceY)
    FleckTerminalReferenceSupport.expectClose(frame.layout.button.visual.width, layout.buttonFaceWidth)
    FleckTerminalReferenceSupport.expectClose(frame.layout.button.visual.height, layout.buttonFaceHeight)
    FleckTerminalReferenceSupport.expectPath(shell.contour.data, frame.contour)

    if isMicrophone {
      let messageLeft = presentation.messageCenterX(in: layout) - nativeMessageWidth / 2
      let buttonFaceRight = layout.buttonX + nativeOffset + layout.buttonFaceX + layout.buttonFaceWidth
      FleckTerminalReferenceSupport.expectClose(
        (messageLeft + buttonFaceRight) / 2,
        layout.canvasWidth / 2
      )
    } else {
      FleckTerminalReferenceSupport.expectClose(
        presentation.messageCenterX(in: layout),
        expectedMessageCenterX
      )
    }
  }

  for sample in fixture.geometry {
    let shell = FleckErrorGeometry.shell(dismissal: sample.q, target: .standby)
    FleckTerminalReferenceSupport.expectClose(shell.width, sample.width)
    FleckTerminalReferenceSupport.expectClose(shell.height, sample.height)
    FleckTerminalReferenceSupport.expectClose(shell.baseline, sample.baseline)
    FleckTerminalReferenceSupport.expectPath(shell.contour.data, sample.contour)
  }
}

@Test
func FleckTerminalRepairShimmerMatchesFrozenV41Fixture() throws {
  let fixture = try FleckTerminalReferenceSupport.load()
  for sample in fixture.shimmer {
    let actual = FleckErrorRepairMotion.sample(at: sample.seconds, reduceMotion: false)
    FleckTerminalReferenceSupport.expectClose(actual.glint, sample.glint)
    FleckTerminalReferenceSupport.expectClose(actual.opacity, sample.opacity)
  }
  #expect(FleckErrorRepairMotion.cycleDuration == 1.1)
  #expect(FleckErrorRepairMotion.travelDuration == 0.86)
  #expect(FleckErrorRepairMotion.sample(at: 0, reduceMotion: true)
    == FleckErrorRepairSample(glint: 0.61, opacity: 1))
}
#endif
