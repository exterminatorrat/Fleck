#if os(macOS)
  import AppKit
  import Foundation
  import FleckCore
  import Testing

  @testable import FleckApp

  private enum FleckErrorReferenceSupport {
    static let url: URL? = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/error-v3-reference.json")

    static func load() throws -> Reference {
      let url = try #require(url)
      return try JSONDecoder().decode(Reference.self, from: Data(contentsOf: url))
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
  }

  @MainActor
  private final class FleckErrorTestClock {
    var now = 0.0
  }

  private struct Reference: Decodable {
    let errors: [String: ErrorSurface]
    let style: Style
    let layouts: [String: Layout]
    let shellFrames: [ShellFrame]
    let buttonFeedback: [String: Feedback]

    struct ErrorSurface: Decodable {
      let message: String
      let action: String
    }

    struct Style: Decodable {
      let messageBaselineShift: Double
      let actionBaselineShift: Double
      let messageSize: Double
      let actionSize: Double
      let messageColor: String
      let actionColor: String
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

    struct ShellFrame: Decodable {
      let target: String
      let dismissal: Double
      let contour: String
      let width: Double
      let height: Double
      let baseline: Double
    }

    struct Feedback: Decodable {
      let fill: [Double]
      let rim: [Double]
      let reflection: Double
      let scale: Double
      let color: String
    }
  }

  @Test
  func FleckErrorNativeGeometryMatchesFrozenReference() throws {
    let fixture = try FleckErrorReferenceSupport.load()
    let layout = FleckErrorLayout.approved
    let expected = try #require(fixture.layouts["microphone"])
    FleckErrorReferenceSupport.expectClose(layout.canvasWidth, expected.width)
    FleckErrorReferenceSupport.expectClose(layout.canvasHeight, expected.height)
    FleckErrorReferenceSupport.expectClose(layout.visibleWidth, expected.visibleWidth)
    FleckErrorReferenceSupport.expectClose(layout.visibleHeight, expected.visibleHeight)
    FleckErrorReferenceSupport.expectClose(layout.baseline, expected.baseline)
    FleckErrorReferenceSupport.expectClose(layout.scale, expected.k)
    FleckErrorReferenceSupport.expectClose(layout.artworkWidth, expected.artWidth)
    FleckErrorReferenceSupport.expectClose(layout.centerExtension, expected.extra)
    FleckErrorReferenceSupport.expectClose(layout.artworkPadding, expected.pad)
    FleckErrorReferenceSupport.expectClose(layout.messageCenterX, expected.message.x)
    FleckErrorReferenceSupport.expectClose(layout.contentCenterY, expected.message.y)
    FleckErrorReferenceSupport.expectClose(FleckErrorGeometry.messageSize, fixture.style.messageSize)
    FleckErrorReferenceSupport.expectClose(FleckErrorGeometry.actionSize, fixture.style.actionSize)
    FleckErrorReferenceSupport.expectClose(
      FleckErrorGeometry.svgMessageBaselineShift,
      fixture.style.messageBaselineShift
    )
    FleckErrorReferenceSupport.expectClose(
      FleckErrorGeometry.svgActionBaselineShift,
      fixture.style.actionBaselineShift
    )
    #expect(FleckErrorGeometry.messageColorHex.lowercased() == fixture.style.messageColor.lowercased())
    #expect(FleckErrorGeometry.defaultActionColorHex.lowercased() == fixture.style.actionColor.lowercased())
    FleckErrorReferenceSupport.expectClose(layout.messageTextCenterY, expected.message.y)
    FleckErrorReferenceSupport.expectClose(layout.buttonX, expected.button.x)
    FleckErrorReferenceSupport.expectClose(layout.buttonY, expected.button.y)
    FleckErrorReferenceSupport.expectClose(layout.buttonWidth, expected.button.width)
    FleckErrorReferenceSupport.expectClose(layout.buttonHeight, expected.button.height)
    FleckErrorReferenceSupport.expectClose(layout.buttonFaceX, expected.button.visual.x)
    FleckErrorReferenceSupport.expectClose(layout.buttonFaceY, expected.button.visual.y)
    FleckErrorReferenceSupport.expectClose(layout.buttonFaceWidth, expected.button.visual.width)
    FleckErrorReferenceSupport.expectClose(layout.buttonFaceHeight, expected.button.visual.height)
    FleckErrorReferenceSupport.expectClose(layout.actionLabelCenterY, expected.button.visual.height / 2)

    for sample in fixture.shellFrames {
      let target = try #require(FleckErrorShellTarget(rawValue: sample.target))
      let actual = FleckErrorGeometry.shell(dismissal: sample.dismissal, target: target)
      FleckErrorReferenceSupport.expectClose(actual.width, sample.width)
      FleckErrorReferenceSupport.expectClose(actual.height, sample.height)
      FleckErrorReferenceSupport.expectClose(actual.baseline, sample.baseline)
      FleckErrorReferenceSupport.expectPath(actual.contour.data, sample.contour)
    }
  }

  @Test @MainActor
  func FleckErrorButtonFeedbackMatchesFrozenReference() throws {
    let fixture = try FleckErrorReferenceSupport.load()
    for phase in FleckErrorButtonPhase.allCases {
      let expected = try #require(fixture.buttonFeedback[phase.rawValue])
      let actual = FleckErrorGeometry.buttonFeedback(for: phase)
      #expect(actual.fill == expected.fill)
      #expect(actual.rim == expected.rim)
      FleckErrorReferenceSupport.expectClose(actual.reflection, expected.reflection)
      FleckErrorReferenceSupport.expectClose(actual.scale, expected.scale)
      #expect(actual.colorHex.lowercased() == expected.color.lowercased())
    }
    FleckErrorReferenceSupport.expectClose(FleckErrorGeometry.pressDuration, 0.07)
    #expect(FleckErrorActionStyle.pressAnimationDuration(reduceMotion: false) == 0.07)
    #expect(FleckErrorActionStyle.pressAnimationDuration(reduceMotion: true) == nil)
    FleckErrorReferenceSupport.expectClose(FleckErrorGeometry.buttonFillRimDuration, 0.09)
    FleckErrorReferenceSupport.expectClose(FleckErrorGeometry.buttonColorReflectionDuration, 0.11)
    FleckErrorReferenceSupport.expectClose(FleckErrorGeometry.labelFadeDuration, 0.12)
    for duration in [
      FleckErrorGeometry.pressDuration,
      FleckErrorGeometry.buttonFillRimDuration,
      FleckErrorGeometry.buttonColorReflectionDuration,
      FleckErrorGeometry.labelFadeDuration,
    ] {
      #expect(FleckErrorActionStyle.animationDuration(duration, reduceMotion: false) == duration)
      #expect(FleckErrorActionStyle.animationDuration(duration, reduceMotion: true) == nil)
    }
    FleckErrorReferenceSupport.expectClose(FleckErrorGeometry.copiedHoldDuration, 0.7)
    FleckErrorReferenceSupport.expectClose(FleckErrorGeometry.dismissalDuration, 0.24)
    FleckErrorReferenceSupport.expectClose(FleckErrorGeometry.retryMorphDuration, 0.32)
    FleckErrorReferenceSupport.expectClose(FleckErrorGeometry.contentExitDuration, 0.11)
  }

  @Test
  func FleckErrorButtonFeedbackInterpolatesFrozenEndpoints() {
    let start = FleckErrorGeometry.buttonFeedback(for: .copyFailed)
    let end = FleckErrorGeometry.buttonFeedback(for: .hover)
    let halfway = FleckErrorGeometry.interpolatedButtonFeedback(
      from: .copyFailed,
      to: .hover,
      progress: 0.5
    )

    #expect(FleckErrorGeometry.interpolatedButtonFeedback(
      from: .copyFailed,
      to: .hover,
      progress: 0
    ) == start)
    #expect(FleckErrorGeometry.interpolatedButtonFeedback(
      from: .copyFailed,
      to: .hover,
      progress: 1
    ) == end)
    for (actual, expected) in zip(halfway.fill, [0.037, 0.015, 0.0075]) {
      FleckErrorReferenceSupport.expectClose(actual, expected)
    }
    for (actual, expected) in zip(halfway.rim, [0.335, 0.075, 0.18]) {
      FleckErrorReferenceSupport.expectClose(actual, expected)
    }
    FleckErrorReferenceSupport.expectClose(halfway.reflection, 0.045)
    FleckErrorReferenceSupport.expectClose(halfway.scale, 1)
    FleckErrorReferenceSupport.expectClose(halfway.color.red, 221.5 / 255)
    FleckErrorReferenceSupport.expectClose(halfway.color.green, 222.5 / 255)
    FleckErrorReferenceSupport.expectClose(halfway.color.blue, 223.5 / 255)
    #expect(halfway.colorHex == "#dedfe0")
  }

  @Test func FleckErrorSurfaceFramesKeepTheirVisibleShellOnTheDock() {
    let visible = CGRect(x: 12, y: 40, width: 1_440, height: 900)
    let layout = FleckErrorLayout.approved
    let bottom = DictationCapsuleController.errorSurfaceFrame(for: .bottom, in: visible)
    let normalPill = DictationCapsuleController.livePillFrame(in: visible)
    FleckErrorReferenceSupport.expectClose(bottom.minY, normalPill.minY)
    FleckErrorReferenceSupport.expectClose(bottom.midX, visible.midX)

    let left = DictationCapsuleController.errorSurfaceFrame(for: .left, in: visible)
    FleckErrorReferenceSupport.expectClose(
      left.minX + layout.artworkPadding,
      visible.minX + DictationCapsuleController.edgeInset
    )
    FleckErrorReferenceSupport.expectClose(
      left.minY + layout.visibleHeight / 2,
      visible.midY
    )

    let right = DictationCapsuleController.errorSurfaceFrame(for: .right, in: visible)
    FleckErrorReferenceSupport.expectClose(
      right.minX + layout.canvasWidth - layout.artworkPadding,
      visible.maxX - DictationCapsuleController.edgeInset
    )
    FleckErrorReferenceSupport.expectClose(
      right.minY + layout.visibleHeight / 2,
      visible.midY
    )
  }

  @Test func FleckErrorActionsPreserveFailureSemantics() throws {
    let fixture = try FleckErrorReferenceSupport.load()
    #expect(FleckErrorKind.allCases == [
      .microphone, .dictation, .insertion, .noSpeech, .usedOriginal, .repairing, .attention,
    ])

    let microphoneReference = try #require(fixture.errors["microphone"])
    #expect(FleckErrorKind.microphone.message == microphoneReference.message)
    #expect(FleckErrorKind.microphone.actionTitle == microphoneReference.action)
    let dictationReference = try #require(fixture.errors["dictation"])
    #expect(FleckErrorKind.dictation.message == dictationReference.message)
    #expect(FleckErrorKind.dictation.actionTitle == dictationReference.action)
    let insertionReference = try #require(fixture.errors["insertion"])
    #expect(FleckErrorKind.insertion.message == insertionReference.message)
    #expect(FleckErrorKind.insertion.actionTitle == insertionReference.action)

    let microphone = DictationCapsuleContext(
      status: .failed("Permission is denied."),
      failureStage: .capture,
      failureKind: .microphoneAccess
    )
    #expect(FleckErrorKind.resolve(context: microphone, action: nil) == .microphone)

    let capture = DictationCapsuleContext(status: .failed("Audio capture ended."), failureStage: .capture)
    #expect(FleckErrorKind.resolve(context: capture, action: nil) == .dictation)
    #expect(FleckErrorKind.resolve(context: capture, action: .copy)?.message == "Dictation failed")
    #expect(FleckErrorKind.resolve(
      context: DictationCapsuleContext(status: .noSpeech),
      action: nil
    )?.message == "No speech heard")
    #expect(FleckErrorKind.resolve(
      context: DictationCapsuleContext(status: .failed("Unattributed failure.")),
      action: nil
    )?.message == "Dictation failed")

    let insertion = DictationCapsuleContext(
      status: .failed("Unable to save dictation."),
      failureStage: .save,
      failureProvenance: .insertion,
      failureKind: .save
    )
    #expect(FleckErrorKind.resolve(context: insertion, action: .copy) == .insertion)
    #expect(FleckErrorKind.resolve(context: insertion, action: .copy)?.message == "Couldn’t insert text")
    #expect(FleckErrorKind.resolve(context: insertion, action: .openHistory) == .attention)
    #expect(FleckErrorKind.resolve(context: insertion, action: nil) == .attention)

    let routing = DictationCapsuleContext(
      status: .failed("A routing result is not an insertion failure."),
      failureStage: .organize,
      failureKind: .generic
    )
    #expect(FleckErrorKind.resolve(context: routing, action: .copy)?.message == "Dictation failed")
    #expect(FleckErrorKind.resolve(
      context: DictationCapsuleContext(
        status: .failed("Speech Recognition access is unavailable."),
        failureStage: .capture,
        failureKind: .speechRecognitionAccess
      ),
      action: nil
    )?.message == "Dictation failed")
    #expect(FleckErrorKind.resolve(
      context: DictationCapsuleContext(status: .routingFailure(status: "Needs attention", message: "Routing failed.")),
      action: .copy
    ) == .attention)
  }

  @Test @MainActor func FleckErrorSaveRecoveryRequiresTypedFailureProvenance() {
    let saving = DictationCapsuleContext(
      status: .failed("Unable to save dictation."),
      failureStage: .save,
      failureKind: .save
    )
    #expect(FleckErrorKind.resolve(context: saving, action: .copy) == .attention)

    let persistence = DictationCapsuleContext(
      status: .failed("Unable to save dictation."),
      failureStage: .save,
      failureProvenance: .persistence,
      failureKind: .save
    )
    #expect(FleckErrorKind.resolve(context: persistence, action: .copy) == .attention)

    let panel = DictationCapsulePanel()
    let controller = DictationCapsuleController(panel: panel)
    controller.render(persistence, action: .copy)
    #expect(controller.errorPresentationModel.presentation?.message == "Couldn't save")
    #expect(controller.errorPresentationModel.presentation?.actionTitle == "Copy")
    #expect(controller.presentationModel.action == .copy)
    controller.render(persistence, action: .openHistory)
    #expect(controller.errorPresentationModel.presentation?.message == "Couldn't save")
    #expect(controller.errorPresentationModel.presentation?.actionTitle == "History")
    #expect(controller.presentationModel.action == .openHistory)
    controller.dismiss()

    let insertion = DictationCapsuleContext(
      status: .failed("Unable to insert dictated text."),
      failureStage: .save,
      failureProvenance: .insertion,
      failureKind: .save
    )
    let error = FleckErrorKind.resolve(context: insertion, action: .copy)
    #expect(error?.message == "Couldn’t insert text")
    #expect(error?.actionTitle == "Copy text")
    #expect(error?.accessibilityHint.contains("does not retry insertion") == true)
  }

  @Test @MainActor
  func FleckErrorPersistenceRecoveryUsesFixedTerminalSurface() {
    let persistence = DictationCapsuleContext(
      status: .failed("Unable to save dictation."),
      failureStage: .save,
      failureProvenance: .persistence,
      failureKind: .save
    )
    let controller = DictationCapsuleController(panel: DictationCapsulePanel())
    controller.render(persistence, action: .openHistory)

    #expect(controller.errorPresentationModel.presentation?.message == "Couldn't save")
    #expect(controller.errorPresentationModel.presentation?.actionTitle == "History")
    #expect(controller.presentationModel.action == .openHistory)
    controller.dismiss()
  }

  @Test @MainActor
  func FleckErrorTerminalStatesUseFixedShellCopyAndRealActions() {
    let noSpeech = DictationCapsuleContext(status: .noSpeech)
    let repair = DictationCapsuleContext(status: .repairingModel)
    let modelRepairFailure = DictationCapsuleContext(
      status: .failed("The model could not be repaired."),
      failureStage: .polish,
      failureKind: .modelRepair
    )
    let routingFailure = DictationCapsuleContext(
      status: .routingFailure(status: "Needs attention", message: "The destination did not save.")
    )
    let cases: [(
      DictationCapsuleContext,
      DictationCapsuleAction?,
      String,
      String?
    )] = [
      (noSpeech, nil, "No speech heard", "Try again"),
      (repair, nil, "Repairing model", nil),
      (modelRepairFailure, .openHistory, "Model repair failed", "History"),
      (routingFailure, .openDestination, "Needs attention", "Destination"),
    ]

    for (context, action, message, actionTitle) in cases {
      let controller = DictationCapsuleController(panel: DictationCapsulePanel())
      controller.render(context, action: action)

      #expect(controller.errorPresentationModel.presentation?.message == message)
      #expect(controller.errorPresentationModel.presentation?.actionTitle == actionTitle)
      #expect(controller.presentationModel.action == action)
      controller.dismiss()
    }
  }

  @Test @MainActor
  func FleckErrorFallbackRequiresAnExplicitUsableOriginalOutcome() {
    for cleanupOutcome: DictationCleanupOutcome? in [nil, .pending, .cleaned, .usedRaw] {
      let controller = DictationCapsuleController(panel: DictationCapsulePanel())
      controller.render(DictationCapsuleContext(
        status: .savedWithoutCleanup(destination: "Inbox"),
        cleanupOutcome: cleanupOutcome
      ))

      #expect(controller.errorPresentationModel.presentation == nil)
      controller.dismiss()
    }
  }

  @Test @MainActor
  func FleckErrorFallbackRequiresExplicitServiceFallbackProvenance() {
    let controller = DictationCapsuleController(panel: DictationCapsulePanel())
    controller.render(DictationCapsuleContext(
      status: .savedWithoutCleanup(destination: "Inbox"),
      cleanupOutcome: .usedRaw,
      cleanupFallbackProvenance: .serviceFallback
    ))

    #expect(controller.currentContext.status == .idle)
    #expect(controller.errorPresentationModel.presentation == nil)
    controller.dismiss()
  }

  @Test @MainActor
  func FleckErrorFallbackKeepsVisibleRoutingChooserInRegularShell() throws {
    let captureID = UUID()
    let chooser = DictationCapsuleChooser(
      ambiguity: .init(
        captureID: captureID,
        choices: [
          .init(
            destination: .init(noteID: UUID(), title: "Projects"),
            contextHint: "Synthetic roadmap"
          ),
          .init(
            destination: .init(noteID: UUID(), title: "Personal"),
            contextHint: "Synthetic plans"
          ),
        ]
      )
    )
    let controller = DictationCapsuleController(panel: DictationCapsulePanel())
    controller.render(
      DictationCapsuleContext(
        status: .savedWithoutCleanup(destination: "Inbox"),
        sessionID: captureID,
        cleanupOutcome: .usedRaw,
        cleanupFallbackProvenance: .serviceFallback
      ),
      action: .undo,
      chooser: chooser
    )

    #expect(controller.errorPresentationModel.presentation == nil)
    #expect(controller.currentChooser == nil)
    #expect(controller.presentationModel.chooser == nil)
    #expect(!controller.panel.allowsActions)
    #expect(controller.currentContext.status == .idle)
    #expect(controller.panel.frame.size != DictationCapsuleController.errorSurfaceSize)
    let host = try #require(controller.panel.contentView)
    host.layoutSubtreeIfNeeded()
    let identifiers = fleckErrorDescendants(of: host).compactMap { $0.identifier?.rawValue }
    #expect(!identifiers.contains("fleck-rail-chooser"))
    #expect(!identifiers.contains("fleck-error-surface"))
    controller.dismiss()
  }

  @Test @MainActor
  func FleckErrorFixedShellPreservesRouteContextWithoutPillChooser() throws {
    let captureID = UUID()
    let chooser = DictationCapsuleChooser(
      ambiguity: .init(
        captureID: captureID,
        choices: []
      ),
      allowsKeepInInbox: false
    )
    let controller = DictationCapsuleController(panel: DictationCapsulePanel())
    controller.render(
      DictationCapsuleContext(
        status: .routingFailure(status: "Needs attention", message: "The destination did not save."),
        sessionID: captureID
      ),
      action: .openDestination,
      chooser: chooser
    )

    #expect(controller.errorPresentationModel.presentation?.kind == .attention)
    #expect(controller.errorPresentationModel.presentation?.actionTitle == "Destination")
    #expect(controller.currentChooser == chooser)
    #expect(controller.presentationModel.action == .openDestination)
    let host = try #require(controller.panel.contentView)
    host.layoutSubtreeIfNeeded()
    #expect(fleckErrorDescendants(of: host).allSatisfy {
      $0.identifier?.rawValue != "fleck-rail-chooser"
    })
    controller.dismiss()
  }

  @Test @MainActor
  func FleckPillDoesNotExposeUndoOrRoutingChooser() {
    let chooser = DictationCapsuleChooser(
      ambiguity: .init(
        captureID: UUID(),
        choices: [
          .init(
            destination: .init(noteID: UUID(), title: "Projects"),
            contextHint: "Synthetic roadmap"
          )
        ]
      )
    )
    let controller = DictationCapsuleController(panel: DictationCapsulePanel())
    controller.render(
      .init(status: .saved(destination: "Inbox")),
      action: .undo,
      chooser: chooser
    )

    #expect(controller.currentContext.status == .idle)
    #expect(controller.presentationModel.action == nil)
    #expect(controller.currentChooser == nil)
    #expect(!controller.panel.allowsActions)
    #expect(controller.panel.frame.size == DictationCapsuleController.livePillHostSize)
    controller.dismiss()
  }

  @Test @MainActor
  func quietSavedRecoveryPreservesRouteSnapshotWithoutPillControls() throws {
    let captureID = UUID()
    let chooser = DictationCapsuleChooser(
      ambiguity: .init(
        captureID: captureID,
        choices: [
          .init(
            destination: .init(noteID: UUID(), title: "Projects"),
            contextHint: "Synthetic roadmap"
          )
        ]
      )
    )
    let context = DictationCapsuleContext(status: .idle, sessionID: captureID)
    let panel = DictationCapsulePanel()
    let controller = DictationCapsuleController(panel: panel)
    let presentation = DictationCapsulePresentation(
      status: .idle,
      action: .undo,
      chooser: chooser,
      context: context
    )
    let expectedSize = DictationCapsuleController.size(
      for: .idle,
      measuredWidth: presentation.measuredWidth,
      widthCeiling: presentation.widthCeiling
    )

    controller.render(context, action: .undo, chooser: chooser)

    #expect(controller.currentContext.status == .idle)
    #expect(presentation.visibleText == nil)
    #expect(presentation.widthCeiling == DictationCapsuleController.idleSize.width)
    #expect(expectedSize == DictationCapsuleController.idleSize)
    #expect(panel.frame.size == DictationCapsuleController.livePillHostSize)
    #expect(controller.currentChooser == chooser)
    #expect(controller.presentationModel.action == nil)
    #expect(!controller.panel.allowsActions)
    #expect(controller.errorPresentationModel.presentation == nil)

    panel.orderOut(nil)
    let host = try #require(panel.contentView)
    host.layoutSubtreeIfNeeded()
    #expect(fleckErrorDescendants(of: host).allSatisfy {
      $0.identifier?.rawValue != "fleck-rail-recovery"
        && $0.identifier?.rawValue != "fleck-rail-chooser"
    })
    controller.dismiss()
  }

  @Test @MainActor
  func FleckErrorTerminalGeometryPreservesTheFixedShellAndCentersContent() throws {
    let layout = FleckErrorLayout.approved
    FleckErrorReferenceSupport.expectClose(layout.canvasWidth, 403.02702702702703)
    FleckErrorReferenceSupport.expectClose(layout.canvasHeight, 61.83783783783784)
    FleckErrorReferenceSupport.expectClose(layout.visibleWidth, 384)
    FleckErrorReferenceSupport.expectClose(layout.visibleHeight, 44)
    FleckErrorReferenceSupport.expectClose(
      layout.buttonY + layout.buttonHeight / 2,
      layout.messageTextCenterY
    )

    let microphone = FleckErrorPresentationModel(monotonicNow: { 1 })
    microphone.reconcile(
      context: DictationCapsuleContext(
        status: .failed("Permission is denied."),
        failureStage: .capture,
        failureKind: .microphoneAccess
      ),
      action: nil,
      entryFrame: nil,
      animated: false,
      reduceMotion: false
    )
    let microphonePresentation = try #require(microphone.presentation)
    let messageWidth = FleckErrorGeometry.microphoneMessageWidth()
    let expectedOffset = FleckErrorGeometry.microphoneContentOffset(messageWidth: messageWidth)
    FleckErrorReferenceSupport.expectClose(microphonePresentation.contentCenterOffset, expectedOffset)
    let messageLeft = microphonePresentation.messageCenterX(in: layout) - messageWidth / 2
    let buttonFaceRight = layout.buttonX + expectedOffset + layout.buttonFaceX + layout.buttonFaceWidth
    FleckErrorReferenceSupport.expectClose(
      (messageLeft + buttonFaceRight) / 2,
      layout.canvasWidth / 2
    )

    let usedOriginal = FleckErrorPresentationModel(monotonicNow: { 2 })
    usedOriginal.reconcile(
      context: DictationCapsuleContext(
        status: .savedWithoutCleanup(destination: "Inbox"),
        cleanupOutcome: .usedRaw,
        cleanupFallbackProvenance: .serviceFallback
      ),
      action: nil,
      entryFrame: nil,
      animated: false,
      reduceMotion: false
    )
    let singleLine = try #require(usedOriginal.presentation)
    FleckErrorReferenceSupport.expectClose(
      singleLine.messageCenterX(in: layout),
      layout.canvasWidth / 2
    )
  }

  @Test
  func FleckErrorRepairSignalMatchesFrozenShimmerAndReduceMotion() {
    for (seconds, glint, opacity) in [
      (0.0, 0.0, 0.0),
      (0.2, 0.23255814, 1.0),
      (0.5246, 0.61, 1.0),
      (0.8, 0.930232558, 0.790123457),
      (0.9, 1.0, 0.0),
      (1.1, 0.0, 0.0),
    ] {
      let sample = FleckErrorRepairMotion.sample(at: seconds, reduceMotion: false)
      FleckErrorReferenceSupport.expectClose(sample.glint, glint)
      FleckErrorReferenceSupport.expectClose(sample.opacity, opacity)
    }

    #expect(FleckErrorRepairMotion.sample(at: 0, reduceMotion: true)
      == FleckErrorRepairSample(glint: 0.61, opacity: 1))

    let transform = FleckErrorGeometry.repairProgressTransform()
    let layout = FleckErrorLayout.approved
    FleckErrorReferenceSupport.expectClose(Double(transform.a), 0.75)
    FleckErrorReferenceSupport.expectClose(Double(transform.d), 0.75)
    FleckErrorReferenceSupport.expectClose(
      Double(transform.tx + CGFloat(112 * 0.75)),
      layout.buttonX + layout.buttonWidth / 2
    )
    FleckErrorReferenceSupport.expectClose(
      Double(transform.ty + CGFloat(26.4 * 0.75)),
      layout.messageTextCenterY
    )
  }

  @Test func FleckErrorPendingLabelsNameTheirActualRecovery() {
    for (kind, label) in [
      (FleckErrorKind.microphone, "Opening…"),
      (FleckErrorKind.dictation, "Opening…"),
      (FleckErrorKind.noSpeech, "Opening…"),
      (FleckErrorKind.insertion, "Copying…"),
    ] {
      let presentation = FleckErrorPresentation(
        kind: kind,
        sessionID: nil,
        phase: .pending,
        dismissal: 0,
        target: .standby,
        sourceFrame: nil,
        messageOverride: nil,
        actionToken: 1
      )
      #expect(presentation.actionTitle == label)
    }
  }

  @Test @MainActor func FleckErrorPresentationInvalidatesActionsWhenSessionChanges() {
    let model = FleckErrorPresentationModel(monotonicNow: { 0 })
    let firstSession = UUID()
    model.reconcile(
      context: DictationCapsuleContext(
        status: .failed("Capture failed."),
        sessionID: firstSession,
        failureStage: .capture
      ),
      action: nil,
      entryFrame: nil,
      animated: false,
      reduceMotion: false
    )
    #expect(model.presentation?.kind == .dictation)
    let token = model.beginAction()
    #expect(model.presentation?.phase == .pending)
    #expect(model.presentation?.actionToken == token)

    let nextSession = UUID()
    model.reconcile(
      context: DictationCapsuleContext(
        status: .arming,
        sessionID: nextSession,
        pipelineStage: .capture
      ),
      action: nil,
      entryFrame: nil,
      animated: false,
      reduceMotion: true
    )
    #expect(model.presentation?.target == .activating)
    #expect(model.presentation?.sessionID == nextSession)
    #expect(model.presentation?.actionToken == nil)
    model.clear()
    #expect(model.presentation == nil)
  }

  @Test @MainActor func FleckErrorCopyFailureAndSuccessKeepTheirDistinctOutcomes() throws {
    let model = FleckErrorPresentationModel(monotonicNow: { 0 })
    let sessionID = UUID()
    let context = DictationCapsuleContext(
      status: .failed("Unable to insert dictated text."),
      sessionID: sessionID,
      failureStage: .save,
      failureProvenance: .insertion,
      failureKind: .save
    )
    model.reconcile(
      context: context,
      action: .copy,
      entryFrame: nil,
      animated: false,
      reduceMotion: false
    )
    #expect(model.presentation?.kind == .insertion)

    let failedToken = try #require(model.beginAction())
    model.finishCopy(failedToken, succeeded: false)
    #expect(model.presentation?.phase == .copyFailed)
    #expect(model.presentation?.message == "Couldn’t copy text")
    #expect(model.presentation?.actionTitle == "Try again")
    for (interaction, expected) in [
      (FleckErrorButtonInteraction.idle, FleckErrorButtonPhase.copyFailed),
      (.hover, .hover),
      (.focus, .focus),
      (.pressed, .pressed),
    ] {
      let feedbackPhase = FleckErrorActionStyle.feedbackPhase(
        for: try #require(model.presentation?.phase),
        interaction: interaction
      )
      #expect(feedbackPhase == expected)
      #expect(model.presentation?.phase == .copyFailed)
      #expect(model.presentation?.message == "Couldn’t copy text")
      #expect(model.presentation?.actionTitle == "Try again")
    }

    let copiedToken = try #require(model.beginAction())
    model.finishCopy(copiedToken, succeeded: true)
    #expect(model.presentation?.phase == .copied)
    #expect(model.presentation?.actionTitle == "Copied")
    #expect(model.presentation?.actionToken == copiedToken)
    #expect(model.beginAction() == nil)

    let nextSession = UUID()
    model.reconcile(
      context: DictationCapsuleContext(status: .arming, sessionID: nextSession),
      action: nil,
      entryFrame: nil,
      animated: false,
      reduceMotion: true
    )
    #expect(model.presentation?.target == .activating)
    #expect(model.presentation?.actionToken == nil)
  }

  @Test @MainActor
  func FleckErrorAttentionCopyAcknowledgesBothPasteboardOutcomes() throws {
    let model = FleckErrorPresentationModel(monotonicNow: { 0 })
    let context = DictationCapsuleContext(
      status: .routingFailure(status: "Needs attention", message: "The destination did not save."),
      sessionID: UUID()
    )
    model.reconcile(
      context: context,
      action: .copy,
      entryFrame: nil,
      animated: false,
      reduceMotion: false
    )
    #expect(model.presentation?.kind == .attention)
    #expect(model.presentation?.actionTitle == "Copy")

    let failedToken = try #require(model.beginAction())
    #expect(model.presentation?.actionTitle == "Copying…")
    model.finishCopy(failedToken, succeeded: false)
    #expect(model.presentation?.phase == .copyFailed)
    #expect(model.presentation?.message == "Couldn’t copy text")
    #expect(model.presentation?.actionTitle == "Try again")

    let copiedToken = try #require(model.beginAction())
    model.finishCopy(copiedToken, succeeded: true)
    #expect(model.presentation?.phase == .copied)
    #expect(model.presentation?.actionTitle == "Copied")
    model.clear()
  }

  @Test @MainActor
  func FleckErrorCopyWritesToAnIsolatedPasteboard() {
    let pasteboard = NSPasteboard(name: .init("FleckCopyTest-\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    #expect(pasteboard.setString("previous", forType: .string))

    #expect(DictationRuntime.writeCopyText("copied text", to: pasteboard))
    #expect(pasteboard.string(forType: .string) == "copied text")
  }

  @Test @MainActor
  func FleckErrorDockChangeKeepsShadowSuppressedWhileErrorIsVisible() {
    let panel = DictationCapsulePanel()
    let controller = DictationCapsuleController(panel: panel)
    defer { controller.dismiss() }
    controller.render(DictationCapsuleContext(
      status: .failed("Capture failed."),
      sessionID: UUID(),
      failureStage: .capture
    ))
    panel.orderOut(nil)

    #expect(controller.errorPresentationModel.presentation != nil)
    #expect(!panel.hasShadow)
    controller.setDock(.left)
    #expect(controller.errorPresentationModel.presentation != nil)
    #expect(!panel.hasShadow)
  }

  @Test
  func FleckErrorMovingReflectionsFollowBrowserDismissalProgress() {
    let layout = FleckErrorLayout.approved
    for dismissal in [0.0, 0.5, 1.0] {
      let shell = FleckErrorGeometry.shell(dismissal: dismissal, target: .standby)
      let transform = FleckErrorGeometry.reflectionTransform(for: shell, layout: layout)
      let scaleX = shell.width / layout.visibleWidth
      let scaleY = shell.height / layout.visibleHeight
      let translateX = layout.artworkWidth / 2 * (1 - scaleX)
      let translateY = 40 * (1 - scaleY)

      FleckErrorReferenceSupport.expectClose(
        FleckErrorGeometry.reflectionOpacity(dismissal: dismissal),
        1 - dismissal
      )
      FleckErrorReferenceSupport.expectClose(transform.a, layout.scale * scaleX)
      FleckErrorReferenceSupport.expectClose(transform.d, layout.scale * 0.925 * scaleY)
      FleckErrorReferenceSupport.expectClose(
        transform.tx,
        layout.artworkPadding + layout.scale * translateX
      )
      FleckErrorReferenceSupport.expectClose(
        transform.ty,
        layout.scale * 15 + layout.scale * 0.925 * translateY
      )
    }
  }

  @Test @MainActor func FleckErrorPresentationRejectsAStaleCopyCompletion() throws {
    let model = FleckErrorPresentationModel(monotonicNow: { 0 })
    func context(_ sessionID: UUID) -> DictationCapsuleContext {
      DictationCapsuleContext(
        status: .failed("Unable to insert dictated text."),
        sessionID: sessionID,
        failureStage: .save,
        failureProvenance: .insertion,
        failureKind: .save
      )
    }

    model.reconcile(
      context: context(UUID()),
      action: .copy,
      entryFrame: nil,
      animated: false,
      reduceMotion: false
    )
    let staleToken = try #require(model.beginAction())
    let nextSession = UUID()
    model.reconcile(
      context: context(nextSession),
      action: .copy,
      entryFrame: nil,
      animated: false,
      reduceMotion: false
    )
    let currentToken = try #require(model.beginAction())
    model.finishCopy(staleToken, succeeded: true)

    #expect(model.presentation(forActionToken: staleToken) == nil)
    #expect(model.presentation(forActionToken: currentToken) != nil)
    #expect(model.presentation?.sessionID == nextSession)
    #expect(model.presentation?.phase == .pending)
    #expect(model.presentation?.actionToken == currentToken)
    #expect(model.presentation?.message == "Couldn’t insert text")
  }

  @Test @MainActor
  func FleckErrorRetryMorphRetargetsAcrossReadinessEvents() async throws {
    let clock = FleckErrorTestClock()
    var completedTargets: [FleckErrorShellTarget] = []
    let model = FleckErrorPresentationModel(monotonicNow: { clock.now })
    model.onTransitionComplete = { completedTargets.append($0) }
    model.reconcile(
      context: DictationCapsuleContext(
        status: .failed("Capture failed."),
        sessionID: UUID(),
        failureStage: .capture
      ),
      action: nil,
      entryFrame: nil,
      animated: false,
      reduceMotion: false
    )

    let firstRetrySession = UUID()
    func context(_ status: DictationCapsuleStatus, sessionID: UUID) -> DictationCapsuleContext {
      DictationCapsuleContext(status: status, sessionID: sessionID, pipelineStage: .capture)
    }
    model.reconcile(
      context: context(.arming, sessionID: firstRetrySession),
      action: nil,
      entryFrame: nil,
      animated: true,
      reduceMotion: false
    )
    clock.now = 0.1
    for _ in 0..<8 {
      guard model.presentation?.dismissal == 0 else { break }
      try await Task.sleep(for: .milliseconds(16))
    }
    let firstProgress = try #require(model.presentation?.dismissal)
    #expect(firstProgress > 0)
    #expect(firstProgress < 1)
    #expect(abs(firstProgress - FleckPillGeometry.smooth(0.1 / 0.32)) < 0.05)

    model.reconcile(
      context: context(.arming, sessionID: firstRetrySession),
      action: nil,
      entryFrame: nil,
      animated: true,
      reduceMotion: false
    )
    #expect(model.presentation?.sessionID == firstRetrySession)
    #expect(model.presentation?.dismissal == firstProgress)

    model.reconcile(
      context: context(.listening, sessionID: firstRetrySession),
      action: nil,
      entryFrame: nil,
      animated: true,
      reduceMotion: false
    )
    #expect(model.presentation?.sessionID == firstRetrySession)
    #expect(model.presentation?.target == .activating)

    let interruptedRetrySession = UUID()
    let beforeRetarget = try #require(model.presentation?.dismissal)
    model.reconcile(
      context: context(.arming, sessionID: interruptedRetrySession),
      action: nil,
      entryFrame: nil,
      animated: true,
      reduceMotion: false
    )
    #expect(model.presentation?.sessionID == interruptedRetrySession)
    #expect(model.presentation?.target == .activating)
    #expect(model.presentation?.dismissal == beforeRetarget)

    model.reconcile(
      context: context(.arming, sessionID: interruptedRetrySession),
      action: nil,
      entryFrame: nil,
      animated: true,
      reduceMotion: false
    )
    #expect(model.presentation?.dismissal == beforeRetarget)
    model.reconcile(
      context: context(.listening, sessionID: interruptedRetrySession),
      action: nil,
      entryFrame: nil,
      animated: true,
      reduceMotion: false
    )
    #expect(model.presentation?.sessionID == interruptedRetrySession)

    clock.now = 0.5
    for _ in 0..<8 {
      guard model.presentation?.dismissal != 1 else { break }
      try await Task.sleep(for: .milliseconds(16))
    }
    #expect(model.presentation?.dismissal == 1)
    #expect(completedTargets == [.activating])
  }

  @Test @MainActor
  func FleckErrorRetryMorphStartsAfterExpandedErrorEntry() async throws {
    let clock = FleckErrorTestClock()
    var completedTargets: [FleckErrorShellTarget] = []
    let model = FleckErrorPresentationModel(monotonicNow: { clock.now })
    model.onTransitionComplete = { completedTargets.append($0) }
    let entryFrame = FleckPillArtworkFrame(
      expansion: 1,
      energy: 0,
      phase: 0,
      activationMix: 0,
      processingMix: 0,
      signalOpacity: 0,
      glint: 0,
      glintOpacity: 0
    )
    model.reconcile(
      context: DictationCapsuleContext(
        status: .failed("Capture failed."),
        sessionID: UUID(),
        failureStage: .capture
      ),
      action: nil,
      entryFrame: entryFrame,
      animated: true,
      reduceMotion: false
    )
    #expect(model.presentation?.target == .activating)
    #expect(model.presentation?.sourceFrame == entryFrame)

    clock.now = FleckErrorGeometry.dismissalDuration
    for _ in 0..<8 {
      guard model.presentation?.dismissal != 0 else { break }
      try await Task.sleep(for: .milliseconds(16))
    }
    #expect(model.presentation?.dismissal == 0)

    _ = try #require(model.beginAction())
    let retrySessionID = UUID()
    func context(_ status: DictationCapsuleStatus) -> DictationCapsuleContext {
      DictationCapsuleContext(status: status, sessionID: retrySessionID, pipelineStage: .capture)
    }
    model.reconcile(
      context: context(.arming),
      action: nil,
      entryFrame: nil,
      animated: true,
      reduceMotion: false
    )
    #expect(model.presentation?.phase == .pending)
    #expect(model.presentation?.actionToken == nil)
    #expect(model.presentation?.sourceFrame == nil)

    clock.now = FleckErrorGeometry.dismissalDuration + 0.1
    for _ in 0..<8 {
      guard (model.presentation?.dismissal ?? 0) == 0 else { break }
      try await Task.sleep(for: .milliseconds(16))
    }
    let firstProgress = try #require(model.presentation?.dismissal)
    #expect(firstProgress > 0)
    #expect(firstProgress < 1)
    #expect(abs(firstProgress - FleckPillGeometry.smooth(
      0.1 / FleckErrorGeometry.retryMorphDuration
    )) < 0.05)

    model.reconcile(
      context: context(.arming),
      action: nil,
      entryFrame: nil,
      animated: true,
      reduceMotion: false
    )
    model.reconcile(
      context: context(.listening),
      action: nil,
      entryFrame: nil,
      animated: true,
      reduceMotion: false
    )
    #expect(model.presentation?.dismissal == firstProgress)

    clock.now = FleckErrorGeometry.dismissalDuration + 0.5
    for _ in 0..<8 {
      guard model.presentation?.dismissal != 1 else { break }
      try await Task.sleep(for: .milliseconds(16))
    }
    #expect(model.presentation?.dismissal == 1)
    #expect(completedTargets == [.activating])
  }

  @Test @MainActor
  func FleckErrorRetrySameKindFailureDuringExitKeepsReplacementActionable() async throws {
    @MainActor final class Clock {
      var now = 0.0
    }
    let clock = Clock()
    let panel = DictationCapsulePanel()
    let controller = DictationCapsuleController(
      panel: panel,
      monotonicNow: { clock.now },
      automaticallyAdvancesLivePill: false,
      reduceMotionProvider: { false },
      markLoader: { nil }
    )
    defer { controller.dismiss() }
    var completedTargets: [FleckErrorShellTarget] = []
    let onTransitionComplete = controller.errorPresentationModel.onTransitionComplete
    controller.errorPresentationModel.onTransitionComplete = { target in
      completedTargets.append(target)
      onTransitionComplete(target)
    }
    func capsuleContext(
      _ status: DictationCapsuleStatus,
      sessionID: UUID,
      failureStage: DictationPipelineStage? = nil
    ) -> DictationCapsuleContext {
      DictationCapsuleContext(
        status: status,
        sessionID: sessionID,
        mode: .smartCapture,
        pipelineStage: .capture,
        failureStage: failureStage
      )
    }
    func coordinatorContext(
      _ sessionID: UUID,
      failureStage: DictationPipelineStage? = nil
    ) -> DictationCoordinatorContext {
      DictationCoordinatorContext(
        sessionID: sessionID,
        mode: .smartCapture,
        pipelineStage: .capture,
        cleanupOutcome: nil,
        failureStage: failureStage
      )
    }

    let firstSessionID = UUID()
    controller.render(
      capsuleContext(
        .failed("Capture failed."),
        sessionID: firstSessionID,
        failureStage: .capture
      ),
      coordinatorEvent: DictationCoordinatorEvent(
        phase: .failed("Capture failed."),
        terminal: .failed("Capture failed."),
        context: coordinatorContext(firstSessionID, failureStage: .capture)
      )
    )
    #expect(controller.errorPresentationModel.presentation?.kind == .dictation)
    #expect(controller.errorPresentationModel.presentation?.sessionID == firstSessionID)
    #expect(controller.errorPresentationModel.presentation?.dismissal == 0)
    #expect(panel.isVisible)

    let retryToken = try #require(controller.errorPresentationModel.beginAction())
    #expect(controller.errorPresentationModel.presentation(forActionToken: retryToken) != nil)
    let retrySessionID = UUID()
    controller.render(
      capsuleContext(.arming, sessionID: retrySessionID),
      coordinatorEvent: DictationCoordinatorEvent(
        phase: .arming,
        terminal: nil,
        context: coordinatorContext(retrySessionID)
      )
    )
    #expect(controller.errorPresentationModel.presentation?.sessionID == retrySessionID)
    #expect(controller.errorPresentationModel.presentation?.target == .activating)
    #expect(controller.errorPresentationModel.presentation?.actionToken == nil)

    clock.now = 0.1
    for _ in 0..<8 {
      guard controller.errorPresentationModel.presentation?.dismissal == 0 else { break }
      try await Task.sleep(for: .milliseconds(16))
    }
    let exitProgress = try #require(controller.errorPresentationModel.presentation?.dismissal)
    #expect(exitProgress > 0)
    #expect(exitProgress < 1)

    controller.render(
      capsuleContext(
        .failed("Capture failed again."),
        sessionID: retrySessionID,
        failureStage: .capture
      ),
      coordinatorEvent: DictationCoordinatorEvent(
        phase: .failed("Capture failed again."),
        terminal: .failed("Capture failed again."),
        context: coordinatorContext(retrySessionID, failureStage: .capture)
      )
    )
    #expect(controller.errorPresentationModel.presentation?.kind == .dictation)
    #expect(controller.errorPresentationModel.presentation?.sessionID == retrySessionID)
    #expect(controller.errorPresentationModel.presentation?.target == .standby)
    #expect(controller.errorPresentationModel.presentation?.phase == .default)
    #expect(controller.errorPresentationModel.presentation?.dismissal == 0)
    #expect(controller.errorPresentationModel.presentation?.actionTitle == "Try again")

    clock.now = FleckErrorGeometry.retryMorphDuration + 0.1
    try await Task.sleep(for: .milliseconds(128))
    let replacement = try #require(controller.errorPresentationModel.presentation)
    #expect(replacement.sessionID == retrySessionID)
    #expect(replacement.kind == .dictation)
    #expect(replacement.contentOpacity == 1)
    #expect(replacement.actionTitle == "Try again")
    #expect(panel.isVisible)
    #expect(completedTargets.isEmpty)
    let replacementAction = try #require(controller.errorPresentationModel.beginAction())
    #expect(
      controller.errorPresentationModel.presentation(forActionToken: replacementAction)?.sessionID
        == retrySessionID
    )
  }

  @MainActor
  private func fleckErrorDescendants(of view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(fleckErrorDescendants)
  }

  @Test @MainActor
  func FleckErrorRecoveryProbeIsBoundedAndDoesNotConsumeShellClicks() throws {
    let panel = DictationCapsulePanel()
    let controller = DictationCapsuleController(panel: panel)
    var recoveryTokens: [UInt64] = []
    controller.configureInteraction(
      onPrimaryClick: {}, onStop: {}, onCancel: {}, onOpenFleck: {},
      onOpenHistory: {}, onOpenSettings: {}, onDismiss: {}, onRecovery: {},
      onErrorRecovery: { recoveryTokens.append($0) }
    )
    let context = DictationCapsuleContext(
      status: .failed("Unable to insert dictated text."),
      sessionID: UUID(),
      failureStage: .save,
      failureProvenance: .insertion,
      failureKind: .save
    )
    controller.render(context, action: .copy)
    let copyAttempt = try #require(controller.errorPresentationModel.beginAction())
    controller.errorPresentationModel.finishCopy(copyAttempt, succeeded: false)
    #expect(controller.errorPresentationModel.presentation?.phase == .copyFailed)
    panel.orderOut(nil)
    let host = try #require(panel.contentView)
    host.layoutSubtreeIfNeeded()
    guard let probe = fleckErrorDescendants(of: host).first(where: {
      $0.identifier?.rawValue == "fleck-rail-recovery"
    }) else {
      Issue.record("Expected the recovery interaction probe")
      return
    }
    let probeFrame = probe.convert(probe.bounds, to: host)
    #expect(probeFrame.size == CGSize(width: 72, height: 28))

    func hitTestHost(_ point: NSPoint) -> NSView? {
      host.hitTest(host.convert(point, to: host.superview))
    }
    let buttonCenter = NSPoint(x: probeFrame.midX, y: probeFrame.midY)
    let buttonTarget = try #require(hitTestHost(buttonCenter))
    #expect(buttonTarget === host.subviews.first)

    let shellOutsideButton = NSPoint(x: probeFrame.minX - 1, y: probeFrame.midY)
    #expect(hitTestHost(shellOutsideButton) != nil)
    #expect(hitTestHost(NSPoint(x: 1, y: host.bounds.midY)) == nil)

    func events(at hostPoint: NSPoint, eventNumber: Int) throws -> (NSView, NSEvent, NSEvent) {
      let target = try #require(hitTestHost(hostPoint))
      let localPoint = target.convert(hostPoint, from: host)
      let windowPoint = target.convert(localPoint, to: nil)
      let down = try #require(NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: windowPoint,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: panel.windowNumber,
        context: nil,
        eventNumber: eventNumber,
        clickCount: 1,
        pressure: 0
      ))
      let up = try #require(NSEvent.mouseEvent(
        with: .leftMouseUp,
        location: windowPoint,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: panel.windowNumber,
        context: nil,
        eventNumber: eventNumber + 1,
        clickCount: 1,
        pressure: 0
      ))
      return (target, down, up)
    }
    func click(at hostPoint: NSPoint, eventNumber: Int) throws {
      let (target, down, up) = try events(at: hostPoint, eventNumber: eventNumber)
      target.mouseDown(with: down)
      target.mouseUp(with: up)
    }
    try click(at: shellOutsideButton, eventNumber: 120)
    #expect(recoveryTokens.isEmpty)
    let (target, down, _) = try events(at: buttonCenter, eventNumber: 122)
    let (_, _, releaseOutside) = try events(at: shellOutsideButton, eventNumber: 124)
    target.mouseDown(with: down)
    #expect(controller.errorPresentationModel.isActionPressed)
    #expect(controller.errorPresentationModel.presentation?.phase == .copyFailed)
    target.mouseUp(with: releaseOutside)
    #expect(!controller.errorPresentationModel.isActionPressed)
    #expect(controller.errorPresentationModel.presentation?.phase == .copyFailed)
    #expect(recoveryTokens.isEmpty)

    let (retryTarget, retryDown, retryUp) = try events(at: buttonCenter, eventNumber: 126)
    retryTarget.mouseDown(with: retryDown)
    #expect(controller.errorPresentationModel.isActionPressed)
    retryTarget.mouseUp(with: retryUp)
    #expect(!controller.errorPresentationModel.isActionPressed)
    #expect(recoveryTokens.count == 1)
    #expect(recoveryTokens.first != nil)
    controller.dismiss()
  }
#endif
