#if os(macOS)
  import AppKit
  import Combine
  import FleckCore
  import SwiftUI

  enum DictationCapsuleStatus: Equatable {
    case idle
    case arming
    case listening
    case finalizing
    case cleaning
    case routing
    case saving
    case saved(destination: String)
    case savedWithoutCleanup(destination: String)
    case noSpeech
    case repairingModel
    case failed(String)

    var presentation: DictationCapsulePresentation {
      DictationCapsulePresentation(status: self)
    }
  }

  struct DictationCapsuleContext: Equatable {
    let status: DictationCapsuleStatus
    let sessionID: UUID?
    let trigger: DictationShortcutTrigger?
    let mode: DictationMode?
    let isHandsFree: Bool
    let pipelineStage: DictationPipelineStage?
    let cleanupOutcome: DictationCleanupOutcome?
    let failureStage: DictationPipelineStage?

    init(
      status: DictationCapsuleStatus,
      sessionID: UUID? = nil,
      trigger: DictationShortcutTrigger? = nil,
      mode: DictationMode? = nil,
      isHandsFree: Bool = false,
      pipelineStage: DictationPipelineStage? = nil,
      cleanupOutcome: DictationCleanupOutcome? = nil,
      failureStage: DictationPipelineStage? = nil
    ) {
      self.status = status
      self.sessionID = sessionID
      self.trigger = trigger
      self.mode = mode
      self.isHandsFree = isHandsFree
      self.pipelineStage = pipelineStage
      self.cleanupOutcome = cleanupOutcome
      self.failureStage = failureStage
    }

    var presentation: DictationCapsulePresentation {
      DictationCapsulePresentation(status: status, context: self)
    }

    var stageTreatments: [FleckRailStageTreatment] {
      FleckRailStageTreatment.forContext(self)
    }
  }

  enum DictationCapsuleVisualMode: Equatable {
    case idle
    case arming
    case listening
    case progress
    case success
    case warning
    case failure
  }

  struct DictationCapsulePresentation: Equatable {
    static let actionDividerSize = CGSize(width: 1, height: 16)

    let context: DictationCapsuleContext
    let visibleText: String?
    let voiceOverText: String
    let symbolName: String
    let visualMode: DictationCapsuleVisualMode
    let widthCeiling: CGFloat
    let measuredWidth: CGFloat
    let stageTreatments: [FleckRailStageTreatment]
    let usesFleckMark: Bool
    var isSuccess = false

    init(
      status: DictationCapsuleStatus,
      action: DictationCapsuleAction? = nil,
      context: DictationCapsuleContext? = nil
    ) {
      let context = context ?? DictationCapsuleContext(status: status)
      let treatments = FleckRailStageTreatment.forContext(context)
      let copy = Self.copy(for: status)
      let visualMode: DictationCapsuleVisualMode
      let symbolName: String
      let usesFleckMark: Bool
      switch status {
      case .idle:
        visualMode = .idle
        symbolName = "square.grid.2x2"
        usesFleckMark = true
      case .arming:
        visualMode = .arming
        symbolName = "square.grid.2x2"
        usesFleckMark = true
      case .listening:
        visualMode = .listening
        symbolName = "waveform"
        usesFleckMark = true
      case .finalizing, .cleaning, .routing, .saving:
        visualMode = .progress
        symbolName = "circle"
        usesFleckMark = true
      case .saved:
        visualMode = .success
        symbolName = "checkmark"
        usesFleckMark = true
      case .savedWithoutCleanup:
        visualMode = .warning
        symbolName = "exclamationmark.triangle"
        usesFleckMark = true
      case .noSpeech:
        visualMode = .warning
        symbolName = "waveform.slash"
        usesFleckMark = false
      case .repairingModel:
        visualMode = .progress
        symbolName = "wrench.and.screwdriver"
        usesFleckMark = true
      case .failed:
        visualMode = .failure
        symbolName = "exclamationmark.circle"
        usesFleckMark = false
      }

      let widthCeiling = Self.widthCeiling(for: status)
      let measuredWidth = Self.measuredWidth(
        for: copy,
        status: status,
        action: action,
        ceiling: widthCeiling
      )
      self.visibleText = copy.visible
      self.context = context
      self.voiceOverText = copy.voiceOver
      self.symbolName = symbolName
      self.visualMode = visualMode
      self.widthCeiling = widthCeiling
      self.measuredWidth = measuredWidth
      self.stageTreatments = treatments
      self.usesFleckMark = usesFleckMark
      self.isSuccess = status.isSuccess
    }

    static func result(
      status: DictationCapsuleStatus,
      action: DictationCapsuleAction? = nil
    ) -> Self {
      Self(status: status, action: action)
    }

    static func widthCeiling(for status: DictationCapsuleStatus) -> CGFloat {
      switch status {
      case .idle, .arming:
        46
      case .listening:
        176
      case .finalizing, .cleaning, .routing, .saving, .noSpeech:
        192
      case .saved:
        264
      case .savedWithoutCleanup:
        288
      case .repairingModel:
        224
      case .failed:
        264
      }
    }

    static func tailTruncated(_ text: String, maxCharacters: Int) -> String {
      guard text.count > maxCharacters, maxCharacters > 1 else {
        return text
      }
      return String(text.prefix(maxCharacters - 1)) + "…"
    }

    private static func copy(for status: DictationCapsuleStatus) -> (visible: String?, voiceOver: String) {
      switch status {
      case .idle:
        return (nil, "Fleck dictation ready")
      case .arming:
        return (nil, "Starting dictation")
      case .listening:
        return (nil, "Dictation listening")
      case .finalizing:
        return ("Finishing", "Finishing dictation")
      case .cleaning:
        return ("Polishing", "Polishing dictation")
      case .routing:
        return ("Organizing", "Organizing dictation")
      case .saving:
        return ("Saving", "Saving dictation")
      case .saved(let destination):
        let destination = tailTruncated(destination, maxCharacters: 30)
        let text = "Saved to \(destination)"
        return (text, text)
      case .savedWithoutCleanup(let destination):
        let destination = tailTruncated(destination, maxCharacters: 27)
        let text = "Saved original to \(destination)"
        return (text, text)
      case .noSpeech:
        return ("No speech heard", "No speech heard")
      case .repairingModel:
        return ("Repairing enhanced model", "Repairing enhanced dictation model")
      case .failed(let message):
        let text = failureCopy(for: message)
        return (text, text)
      }
    }

    private static func failureCopy(for message: String) -> String {
      let normalized = message.lowercased()
      if normalized.contains("microphone")
        || normalized.contains("permission")
        || normalized.contains("audio")
        || normalized.contains("speech recognition")
      {
        return "Microphone access needed"
      }
      if normalized.contains("repair") && normalized.contains("model") {
        return "Model repair failed"
      }
      if normalized.contains("save")
        || normalized.contains("persist")
        || normalized.contains("insert")
        || normalized.contains("commit")
      {
        return "Couldn't save"
      }
      return "Couldn't save"
    }

    private static func measuredWidth(
      for copy: (visible: String?, voiceOver: String),
      status: DictationCapsuleStatus,
      action: DictationCapsuleAction?,
      ceiling: CGFloat
    ) -> CGFloat {
      guard let visible = copy.visible else { return ceiling }
      let markWidth: CGFloat = 14
      let glyphWidth: CGFloat = status == .finalizing || status == .cleaning
        || status == .routing || status == .saving ? 0 : 14
      let actionWidth = action.map { CGFloat(max($0.title.count * 6, 24)) } ?? 0
      let dividerWidth: CGFloat = action == nil ? 0 : actionDividerSize.width + 7
      let estimate = 16 + markWidth + 7 + glyphWidth + (glyphWidth > 0 ? 7 : 0)
        + CGFloat(visible.count) * 6.2 + dividerWidth + actionWidth
      return min(ceiling, max(ceil(estimate), 1))
    }
  }

  private extension DictationCapsuleStatus {
    var isSuccess: Bool {
      switch self {
      case .saved, .savedWithoutCleanup:
        true
      default:
        false
      }
    }
  }

  enum FleckRailStageTreatment: Equatable {
    case pending
    case active
    case complete
    case skipped
    case fallback
    case failed

    static let stages: [DictationPipelineStage] = [
      .capture, .polish, .organize, .save,
    ]

    static func forContext(_ context: DictationCapsuleContext) -> [Self] {
      var result = Array(repeating: Self.pending, count: stages.count)
      let status = context.status
      let isTerminalSuccess: Bool
      switch status {
      case .saved, .savedWithoutCleanup:
        isTerminalSuccess = true
      default:
        isTerminalSuccess = false
      }

      if isTerminalSuccess {
        result = Array(repeating: .complete, count: stages.count)
      } else {
        switch status {
        case .arming, .listening:
          result[0] = .active
        case .finalizing:
          result[0] = .complete
        case .cleaning:
          result[0] = .complete
          result[1] = .active
        case .routing:
          result[0] = .complete
          result[1] = .complete
          result[2] = .active
        case .saving:
          result[0] = .complete
          result[1] = .complete
          result[2] = .complete
          result[3] = .active
        case .failed:
          if let failureStage = context.failureStage,
            let failedIndex = stages.firstIndex(of: failureStage)
          {
            for index in 0..<failedIndex {
              result[index] = .complete
            }
            result[failedIndex] = .failed
          }
        case .idle, .noSpeech, .repairingModel, .saved, .savedWithoutCleanup:
          break
        }
      }

      if context.cleanupOutcome == .usedRaw,
        result[1] != .failed
      {
        result[1] = .fallback
      }

      if context.mode == .focused,
        result[2] != .failed
      {
        result[2] = .skipped
      }
      return result
    }

    static func treatments(for context: DictationCapsuleContext) -> [Self] {
      forContext(context)
    }
  }

  struct FleckRailRGB: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
      self.red = min(max(red, 0), 1)
      self.green = min(max(green, 0), 1)
      self.blue = min(max(blue, 0), 1)
    }

    init?(hex: String) {
      let value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "#", with: "")
      guard value.count == 6, let integer = UInt64(value, radix: 16) else {
        return nil
      }
      self.init(
        red: Double((integer >> 16) & 0xFF) / 255,
        green: Double((integer >> 8) & 0xFF) / 255,
        blue: Double(integer & 0xFF) / 255
      )
    }

    var hex: String {
      String(
        format: "#%02X%02X%02X",
        Int((red * 255).rounded()),
        Int((green * 255).rounded()),
        Int((blue * 255).rounded())
      )
    }

    func mixed(with other: Self, amount: Double) -> Self {
      let amount = min(max(amount, 0), 1)
      return Self(
        red: red + (other.red - red) * amount,
        green: green + (other.green - green) * amount,
        blue: blue + (other.blue - blue) * amount
      )
    }

    var luminance: Double {
      func linear(_ value: Double) -> Double {
        value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
      }
      return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
  }

  struct FleckRailColors: Equatable {
    static let defaultAccentHex = "#7C6CF2"
    static let defaultLiveHex = "#A79DFF"
    static let shellHex = "#17151C"
    static let shellOpacity = 0.96
    static let primaryTextHex = "#F7F5FA"
    static let secondaryTextHex = "#B6B1BF"
    static let successHex = "#5DD68A"
    static let warningHex = "#FFB24A"
    static let failureHex = "#FF6B70"

    let accentHex: String
    let shell: FleckRailRGB
    let displayCore: FleckRailRGB
    let displayLive: FleckRailRGB

    init(accentHex: String = Self.defaultAccentHex) {
      self.accentHex = accentHex
      self.shell = FleckRailRGB(hex: Self.shellHex)!
      let base = FleckRailRGB(hex: accentHex) ?? FleckRailRGB(hex: Self.defaultAccentHex)!
      if accentHex.uppercased() == Self.defaultAccentHex {
        self.displayCore = base
        self.displayLive = FleckRailRGB(hex: Self.defaultLiveHex)!
      } else {
        let core = Self.contrastSafe(base, against: shell, minimum: 3)
        self.displayCore = core
        self.displayLive = Self.contrastSafe(
          core.mixed(with: FleckRailRGB(red: 1, green: 1, blue: 1), amount: 0.22),
          against: shell,
          minimum: 3
        )
      }
    }

    var displayCoreHex: String { displayCore.hex }
    var displayLiveHex: String { displayLive.hex }
    var coreHex: String { displayCoreHex }
    var liveHex: String { displayLiveHex }
    var storedAccentHex: String { accentHex }
    var shellHex: String { Self.shellHex }
    var shellOpacity: Double { Self.shellOpacity }
    var primaryText: FleckRailRGB { FleckRailRGB(hex: Self.primaryTextHex)! }
    var secondaryText: FleckRailRGB { FleckRailRGB(hex: Self.secondaryTextHex)! }
    var success: FleckRailRGB { FleckRailRGB(hex: Self.successHex)! }
    var warning: FleckRailRGB { FleckRailRGB(hex: Self.warningHex)! }
    var failure: FleckRailRGB { FleckRailRGB(hex: Self.failureHex)! }

    var shellColor: Color { Color(red: shell.red, green: shell.green, blue: shell.blue) }
    var coreColor: Color {
      Color(red: displayCore.red, green: displayCore.green, blue: displayCore.blue)
    }
    var liveColor: Color {
      Color(red: displayLive.red, green: displayLive.green, blue: displayLive.blue)
    }
    var primaryTextColor: Color {
      Color(red: primaryText.red, green: primaryText.green, blue: primaryText.blue)
    }
    var secondaryTextColor: Color {
      Color(red: secondaryText.red, green: secondaryText.green, blue: secondaryText.blue)
    }

    static func contrastRatio(_ foreground: FleckRailRGB, against background: FleckRailRGB) -> Double {
      let lighter = max(foreground.luminance, background.luminance)
      let darker = min(foreground.luminance, background.luminance)
      return (lighter + 0.05) / (darker + 0.05)
    }

    private static func contrastSafe(
      _ color: FleckRailRGB,
      against background: FleckRailRGB,
      minimum: Double
    ) -> FleckRailRGB {
      guard contrastRatio(color, against: background) < minimum else { return color }
      var low = 0.0
      var high = 1.0
      for _ in 0..<24 {
        let amount = (low + high) / 2
        let candidate = color.mixed(with: FleckRailRGB(red: 1, green: 1, blue: 1), amount: amount)
        if contrastRatio(candidate, against: background) >= minimum {
          high = amount
        } else {
          low = amount
        }
      }
      return color.mixed(with: FleckRailRGB(red: 1, green: 1, blue: 1), amount: high)
    }
  }

  struct FleckRailMark: View {
    static let frameSize = CGSize(width: 14, height: 14)
    static let tileIDs = [0, 1, 2, 3]
    static let tileFrames = [
      CGRect(x: 0, y: 0, width: 6, height: 6),
      CGRect(x: 8, y: 0, width: 6, height: 6),
      CGRect(x: 0, y: 8, width: 6, height: 6),
      CGRect(x: 8, y: 8, width: 6, height: 6),
    ]
    static let innerHighlightThickness: CGFloat = 1

    let color: Color
    let activeTile: Int?

    init(color: Color = FleckRailColors().coreColor, activeTile: Int? = nil) {
      self.color = color
      self.activeTile = activeTile
    }

    var body: some View {
      ZStack(alignment: .topLeading) {
        ForEach(Self.tileIDs, id: \.self) { tileID in
          let frame = Self.tileFrames[tileID]
          RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(tileID == activeTile ? color : color.opacity(activeTile == nil ? 1 : 0.28))
            .frame(width: frame.width, height: frame.height)
            .overlay(alignment: .top) {
              Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: Self.innerHighlightThickness)
                .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
            }
            .offset(x: frame.minX, y: frame.minY)
        }
      }
      .frame(width: Self.frameSize.width, height: Self.frameSize.height)
      .accessibilityHidden(true)
    }
  }

  enum DictationCapsuleTransition: Equatable {
    case opacity
    case scaleAndOpacity

    static func forReduceMotion(_ reduceMotion: Bool) -> Self {
      reduceMotion ? .opacity : .scaleAndOpacity
    }
  }

  enum DictationWaveformRefreshSchedule {
    static func interval(reduceMotion: Bool) -> TimeInterval {
      reduceMotion ? 1 / 15 : 1 / 30
    }
  }

  enum DictationCapsuleAction: Equatable {
    case undo
    case copy
    case openHistory
    case openDestination
    case dismiss

    var title: String {
      switch self {
      case .undo: "Undo"
      case .copy: "Copy"
      case .openHistory: "Open Dictation History"
      case .openDestination: "Open Destination"
      case .dismiss: "Dismiss"
      }
    }

    var accessibilityLabel: String { title }
  }

  @MainActor
  final class DictationCapsulePresentationModel: ObservableObject {
    @Published private(set) var context: DictationCapsuleContext
    @Published private(set) var action: DictationCapsuleAction?
    @Published private(set) var dock: DictationCapsuleDock
    @Published private(set) var colors: FleckRailColors
    private(set) var actionHandler: @MainActor () -> Void

    init(
      context: DictationCapsuleContext = DictationCapsuleContext(status: .idle),
      dock: DictationCapsuleDock = .bottom,
      colors: FleckRailColors = FleckRailColors(),
      action: DictationCapsuleAction? = nil,
      onAction: @escaping @MainActor () -> Void = {}
    ) {
      self.context = context
      self.dock = dock
      self.colors = colors
      self.action = action
      self.actionHandler = onAction
    }

    func update(
      context: DictationCapsuleContext,
      action: DictationCapsuleAction?,
      onAction: @escaping @MainActor () -> Void
    ) {
      self.context = context
      self.action = action
      self.actionHandler = onAction
    }

    func updateDock(_ dock: DictationCapsuleDock) {
      self.dock = dock
    }

    func updateAccentHex(_ accentHex: String) {
      colors = FleckRailColors(accentHex: accentHex)
    }
  }

  final class DictationCapsulePanel: NSPanel {
    var allowsActions = false

    init() {
      super.init(
        contentRect: .zero,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: true
      )
      level = .floating
      collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
      isFloatingPanel = true
      hidesOnDeactivate = false
      isReleasedWhenClosed = false
      isMovableByWindowBackground = false
      isOpaque = false
      backgroundColor = .clear
      hasShadow = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
  }

  private final class DictationCapsuleObserverToken: @unchecked Sendable {
    let value: NSObjectProtocol

    init(_ value: NSObjectProtocol) {
      self.value = value
    }
  }

  @MainActor
  final class DictationCapsuleController {
    static let idleSize = CGSize(width: 46, height: 24)
    static let listeningSize = CGSize(width: 176, height: 36)
    static let activeSize = CGSize(width: 192, height: 36)
    static let savedSize = CGSize(width: 264, height: 36)
    static let savedWithoutCleanupSize = CGSize(width: 288, height: 36)
    static let noSpeechSize = CGSize(width: 192, height: 36)
    static let repairingModelSize = CGSize(width: 224, height: 36)
    static let failureSize = CGSize(width: 264, height: 36)
    static let edgeInset: CGFloat = 10

    let panel: DictationCapsulePanel
    let waveformModel: DictationWaveformModel
    let presentationModel: DictationCapsulePresentationModel
    private(set) var currentDock = DictationCapsuleDock.bottom
    private(set) var currentContext = DictationCapsuleContext(status: .idle)
    private var currentAction: DictationCapsuleAction?
    private var currentActionHandler: @MainActor () -> Void = {}
    private var currentScreen: NSScreen?
    private var onOpenFleck: (@MainActor () -> Void)?
    private var onDockChanged: (@MainActor (DictationCapsuleDock) -> Void)?
    private var screenParametersObserver: DictationCapsuleObserverToken?

    init(
      panel: DictationCapsulePanel = DictationCapsulePanel(),
      waveformModel: DictationWaveformModel = DictationWaveformModel(),
      accentHex: String = FleckRailColors.defaultAccentHex
    ) {
      self.panel = panel
      self.waveformModel = waveformModel
      self.presentationModel = DictationCapsulePresentationModel(
        colors: FleckRailColors(accentHex: accentHex)
      )
      screenParametersObserver = DictationCapsuleObserverToken(
        NotificationCenter.default.addObserver(
          forName: NSApplication.didChangeScreenParametersNotification,
          object: nil,
          queue: .main
        ) { [weak self] _ in
          Task { @MainActor [weak self] in
            self?.redockAfterScreenChange()
          }
        }
      )
      panel.contentView = DictationCapsuleHostingView(
        model: presentationModel,
        waveformModel: waveformModel,
        onOpenFleck: { [weak self] in self?.onOpenFleck?() },
        onDragEnded: { [weak self] in self?.finishDrag() },
        onDockSelected: { [weak self] dock in self?.selectDock(dock) }
      )
    }

    func presentIdle(
      dock: DictationCapsuleDock,
      onOpenFleck: @escaping @MainActor () -> Void,
      onDockChanged: @escaping @MainActor (DictationCapsuleDock) -> Void
    ) {
      currentDock = dock
      currentContext = DictationCapsuleContext(status: .idle)
      waveformModel.reset()
      currentAction = nil
      currentActionHandler = {}
      self.onOpenFleck = onOpenFleck
      self.onDockChanged = onDockChanged
      presentationModel.updateDock(dock)
      presentationModel.update(context: currentContext, action: nil, onAction: {})
      panel.allowsActions = false
      applyCurrentFrame(animated: panel.isVisible)
      panel.orderFrontRegardless()
    }

    func render(
      _ status: DictationCapsuleStatus,
      action: DictationCapsuleAction? = nil,
      onAction: @escaping @MainActor () -> Void = {}
    ) {
      let context = context(for: status)
      render(context, action: action, onAction: onAction)
    }

    func render(
      _ context: DictationCapsuleContext,
      action: DictationCapsuleAction? = nil,
      onAction: @escaping @MainActor () -> Void = {}
    ) {
      let wasListening = currentContext.status == .listening
      currentContext = context
      if context.status == .listening {
        if !wasListening {
          waveformModel.beginListening()
        }
      } else {
        waveformModel.reset()
      }
      currentAction = action
      currentActionHandler = onAction
      presentationModel.update(context: context, action: action, onAction: onAction)
      panel.allowsActions = action != nil
      applyCurrentFrame(animated: panel.isVisible)
      panel.orderFrontRegardless()
    }

    func setDock(_ dock: DictationCapsuleDock) {
      currentDock = dock
      presentationModel.updateDock(dock)
      applyCurrentFrame(animated: panel.isVisible)
    }

    func updateAccentHex(_ accentHex: String) {
      presentationModel.updateAccentHex(accentHex)
    }

    func dismiss() {
      waveformModel.reset()
      panel.allowsActions = false
      panel.orderOut(nil)
    }

    func updateAudioLevel(_ level: Float) {
      guard currentContext.status == .listening, panel.isVisible else { return }
      waveformModel.receive(level: level)
    }

    static func size(for status: DictationCapsuleStatus) -> CGSize {
      switch status {
      case .idle, .arming:
        idleSize
      case .listening:
        listeningSize
      case .finalizing, .cleaning, .routing, .saving:
        activeSize
      case .saved:
        savedSize
      case .savedWithoutCleanup:
        savedWithoutCleanupSize
      case .noSpeech:
        noSpeechSize
      case .repairingModel:
        repairingModelSize
      case .failed:
        failureSize
      }
    }

    static func size(for context: DictationCapsuleContext) -> CGSize {
      size(for: context.status)
    }

    static func frame(
      for dock: DictationCapsuleDock,
      in visibleFrame: CGRect
    ) -> CGRect {
      frame(for: dock, size: idleSize, in: visibleFrame)
    }

    static func frame(
      for dock: DictationCapsuleDock,
      size: CGSize,
      in visibleFrame: CGRect
    ) -> CGRect {
      let width = min(max(size.width, 0), max(visibleFrame.width, 0))
      let height = min(max(size.height, 0), max(visibleFrame.height, 0))
      let fittedSize = CGSize(width: width, height: height)
      let horizontalInset = min(edgeInset, max((visibleFrame.width - width) / 2, 0))
      let verticalInset = min(edgeInset, max((visibleFrame.height - height) / 2, 0))
      let origin: CGPoint
      switch dock {
      case .bottom:
        origin = CGPoint(
          x: visibleFrame.midX - width / 2,
          y: visibleFrame.minY + verticalInset
        )
      case .left:
        origin = CGPoint(
          x: visibleFrame.minX + horizontalInset,
          y: visibleFrame.midY - height / 2
        )
      case .right:
        origin = CGPoint(
          x: visibleFrame.maxX - horizontalInset - width,
          y: visibleFrame.midY - height / 2
        )
      }
      return CGRect(origin: origin, size: fittedSize)
    }

    static func nearestDock(
      to point: CGPoint,
      in visibleFrame: CGRect
    ) -> DictationCapsuleDock {
      let bottomDistance = abs(point.y - visibleFrame.minY)
      let leftDistance = abs(point.x - visibleFrame.minX)
      let rightDistance = abs(point.x - visibleFrame.maxX)
      if bottomDistance <= leftDistance, bottomDistance <= rightDistance {
        return .bottom
      }
      return leftDistance <= rightDistance ? .left : .right
    }

    static func preferredDisplay<T>(
      keyboardFocus: T?,
      pointer: T?,
      primary: T?
    ) -> T? {
      keyboardFocus ?? pointer ?? primary
    }

    private func context(for status: DictationCapsuleStatus) -> DictationCapsuleContext {
      switch status {
      case .idle:
        DictationCapsuleContext(status: status)
      default:
        DictationCapsuleContext(
          status: status,
          sessionID: currentContext.sessionID,
          trigger: currentContext.trigger,
          mode: currentContext.mode,
          isHandsFree: currentContext.isHandsFree,
          pipelineStage: pipelineStage(for: status) ?? currentContext.pipelineStage,
          cleanupOutcome: currentContext.cleanupOutcome,
          failureStage: currentContext.failureStage
        )
      }
    }

    private func pipelineStage(for status: DictationCapsuleStatus) -> DictationPipelineStage? {
      switch status {
      case .arming, .listening, .finalizing:
        .capture
      case .cleaning:
        .polish
      case .routing:
        .organize
      case .saving:
        .save
      default:
        nil
      }
    }

    private func activeScreen() -> NSScreen? {
      let pointer = NSEvent.mouseLocation
      let pointerScreen = NSScreen.screens.first { $0.frame.contains(pointer) }
      return Self.preferredDisplay(
        keyboardFocus: NSScreen.main,
        pointer: pointerScreen,
        primary: NSScreen.screens.first
      )
    }

    private func applyCurrentFrame(animated: Bool) {
      guard let screen = resolvedScreen() else { return }
      currentScreen = screen
      let finalFrame = Self.frame(
        for: currentDock,
        size: Self.size(for: currentContext.status),
        in: screen.visibleFrame
      )
      let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
      guard animated else {
        panel.setFrame(finalFrame, display: true)
        panel.alphaValue = 1
        return
      }
      if reduceMotion {
        panel.setFrame(finalFrame, display: true)
      }
      NSAnimationContext.runAnimationGroup { context in
        context.duration = reduceMotion ? 0.1 : 0.12
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        panel.animator().alphaValue = 1
        if !reduceMotion {
          panel.animator().setFrame(finalFrame, display: true)
        }
      }
    }

    private func finishDrag() {
      let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
      guard let screen = screen(containing: center) ?? resolvedScreen() else {
        return
      }
      selectDock(Self.nearestDock(to: center, in: screen.visibleFrame), on: screen)
    }

    private func selectDock(
      _ dock: DictationCapsuleDock,
      on screen: NSScreen? = nil
    ) {
      currentDock = dock
      if let screen { currentScreen = screen }
      presentationModel.updateDock(dock)
      applyCurrentFrame(animated: true)
      onDockChanged?(dock)
    }

    private func resolvedScreen() -> NSScreen? {
      if let currentScreen, NSScreen.screens.contains(where: { $0 === currentScreen }) {
        return currentScreen
      }
      return panel.screen ?? activeScreen()
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
      NSScreen.screens.first { $0.frame.contains(point) }
    }

    private func redockAfterScreenChange() {
      let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
      currentScreen = screen(containing: center) ?? activeScreen()
      applyCurrentFrame(animated: false)
    }

    deinit {
      if let screenParametersObserver {
        NotificationCenter.default.removeObserver(screenParametersObserver.value)
      }
    }
  }

  private struct DictationCapsuleView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityDifferentiateWithoutColor) private var increaseContrast

    @ObservedObject var model: DictationCapsulePresentationModel
    @ObservedObject var waveformModel: DictationWaveformModel

    private var presentation: DictationCapsulePresentation {
      DictationCapsulePresentation(
        status: model.context.status,
        action: model.action,
        context: model.context
      )
    }

    var body: some View {
      railContent
        .foregroundStyle(model.colors.primaryTextColor)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
          RoundedRectangle(
            cornerRadius: presentation.visualMode == .idle || presentation.visualMode == .arming ? 10 : 12,
            style: .continuous
          )
          .fill(model.colors.shellColor.opacity(reduceTransparency ? 1 : FleckRailColors.shellOpacity))
          .overlay {
            RoundedRectangle(
              cornerRadius: presentation.visualMode == .idle || presentation.visualMode == .arming ? 10 : 12,
              style: .continuous
            )
            .stroke(
              Color.white.opacity(increaseContrast ? 0.35 : 0.0),
              lineWidth: increaseContrast ? 1 : 0
            )
          }
          .overlay(alignment: .top) {
            Rectangle()
              .fill(Color.white.opacity(0.10))
              .frame(height: 1)
              .padding(.horizontal, 10)
          }
        }
        .clipShape(
          RoundedRectangle(
            cornerRadius: presentation.visualMode == .idle || presentation.visualMode == .arming ? 10 : 12,
            style: .continuous
          )
        )
        .accessibilityElement(children: model.action == nil ? .ignore : .contain)
        .accessibilityLabel(presentation.voiceOverText)
        .accessibilityAddTraits(.isStaticText)
    }

    @ViewBuilder
    private var railContent: some View {
      switch model.context.status {
      case .idle, .arming:
        FleckRailMark(
          color: model.colors.coreColor,
          activeTile: model.context.status == .arming ? 0 : nil
        )
      case .listening:
        mirroredContent(listeningContent)
      case .finalizing, .cleaning, .routing, .saving:
        processingLayout
      case .saved, .savedWithoutCleanup, .noSpeech, .repairingModel, .failed:
        mirroredContent(terminalContent)
      }
    }

    @ViewBuilder
    private func mirroredContent<Content: View>(_ content: Content) -> some View {
      if model.dock == .right {
        HStack(spacing: 7) {
          content
          FleckRailMark(color: model.colors.coreColor)
        }
      } else {
        HStack(spacing: 7) {
          FleckRailMark(color: model.colors.coreColor)
          content
        }
      }
    }

    private var listeningContent: some View {
      TimelineView(
        .periodic(
          from: .now,
          by: DictationWaveformRefreshSchedule.interval(reduceMotion: reduceMotion)
        )
      ) { context in
        HStack(spacing: 7) {
          HStack(alignment: .center, spacing: 2) {
            ForEach(
              Array(
                waveformModel.barLevels(
                  at: context.date,
                  reduceMotion: reduceMotion
                ).prefix(7).enumerated()
              ),
              id: \.offset
            ) { _, level in
              Capsule()
                .fill(model.colors.liveColor)
                .frame(width: 2.5, height: 4 + (level * 13))
            }
          }
          .accessibilityHidden(true)
          Text(waveformModel.elapsedText(at: context.date))
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .foregroundStyle(
              increaseContrast ? model.colors.primaryTextColor : model.colors.secondaryTextColor
            )
            .monospacedDigit()
            .frame(width: 34, alignment: .trailing)
            .accessibilityHidden(true)
        }
        .accessibilityLabel("Dictation listening")
      }
    }

    @ViewBuilder
    private var processingLayout: some View {
      if model.dock == .right {
        HStack(spacing: 7) {
          processingText
          FleckRailStageView(
            treatments: presentation.stageTreatments,
            colors: model.colors,
            reversed: true
          )
        }
      } else {
        HStack(spacing: 7) {
          FleckRailStageView(
            treatments: presentation.stageTreatments,
            colors: model.colors,
            reversed: false
          )
          processingText
        }
      }
    }

    @ViewBuilder
    private var processingText: some View {
      if let visibleText = presentation.visibleText {
        Text(visibleText)
          .font(.system(size: 12, weight: .medium, design: .default))
          .lineLimit(1)
          .truncationMode(.tail)
          .foregroundStyle(model.colors.primaryTextColor)
      }
    }

    private var terminalContent: some View {
      HStack(spacing: 7) {
        if model.context.status == .noSpeech || model.context.status.isFailure {
          Image(systemName: presentation.symbolName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(model.context.status == .noSpeech ? model.colors.warningColor : model.colors.failureColor)
            .accessibilityHidden(true)
        } else if model.context.status == .repairingModel {
          Image(systemName: presentation.symbolName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(model.colors.liveColor)
            .accessibilityHidden(true)
        } else {
          Image(systemName: presentation.symbolName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(model.context.status.isSavedWithoutCleanup ? model.colors.warningColor : model.colors.successColor)
            .accessibilityHidden(true)
        }
        if let visibleText = presentation.visibleText {
          Text(visibleText)
            .font(.system(size: 12, weight: .medium, design: .default))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(model.colors.primaryTextColor)
        }
        if model.action != nil {
          Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(width: DictationCapsulePresentation.actionDividerSize.width, height: DictationCapsulePresentation.actionDividerSize.height)
            .accessibilityHidden(true)
          if let action = model.action {
            Button(action.title, action: model.actionHandler)
              .buttonStyle(.borderless)
              .font(.system(size: 11, weight: .semibold, design: .default))
              .accessibilityLabel(action.accessibilityLabel)
          }
        }
      }
    }
  }

  private struct FleckRailStageView: View {
    let treatments: [FleckRailStageTreatment]
    let colors: FleckRailColors
    let reversed: Bool

    var body: some View {
      HStack(spacing: 3) {
        ForEach(Array((reversed ? treatments.reversed() : treatments).enumerated()), id: \.offset) { index, treatment in
          let active = treatment == .active
          RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(fillColor(for: treatment))
            .overlay {
              if treatment == .skipped || treatment == .fallback {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                  .stroke(strokeColor(for: treatment), lineWidth: 1)
                  .padding(1)
              }
              if treatment == .failed {
                Path { path in
                  path.move(to: CGPoint(x: 1, y: 1))
                  path.addLine(to: CGPoint(x: 5, y: 5))
                }
                .stroke(Color.white.opacity(0.8), lineWidth: 1)
              }
            }
            .frame(width: active ? 7 : 6, height: active ? 7 : 6)
            .accessibilityHidden(true)
            .id(index)
        }
      }
      .frame(height: 14)
      .accessibilityHidden(true)
    }

    private func fillColor(for treatment: FleckRailStageTreatment) -> Color {
      switch treatment {
      case .pending:
        colors.secondaryTextColor.opacity(0.35)
      case .active:
        colors.liveColor
      case .complete:
        colors.coreColor
      case .skipped, .fallback, .failed:
        .clear
      }
    }

    private func strokeColor(for treatment: FleckRailStageTreatment) -> Color {
      switch treatment {
      case .fallback:
        colors.warningColor
      case .skipped:
        colors.secondaryTextColor.opacity(0.8)
      default:
        .clear
      }
    }
  }

  private extension DictationCapsuleStatus {
    var isFailure: Bool {
      if case .failed = self { return true }
      return false
    }

    var isSavedWithoutCleanup: Bool {
      if case .savedWithoutCleanup = self { return true }
      return false
    }
  }

  private extension FleckRailColors {
    var warningColor: Color {
      Color(red: warning.red, green: warning.green, blue: warning.blue)
    }
    var failureColor: Color {
      Color(red: failure.red, green: failure.green, blue: failure.blue)
    }
    var successColor: Color {
      Color(red: success.red, green: success.green, blue: success.blue)
    }
  }

  @MainActor
  private final class DictationCapsuleHostingView: NSView {
    private let model: DictationCapsulePresentationModel
    private let onOpenFleck: @MainActor () -> Void
    private let onDragEnded: @MainActor () -> Void
    private let onDockSelected: @MainActor (DictationCapsuleDock) -> Void
    private let hostingView: NSHostingView<DictationCapsuleView>

    init(
      model: DictationCapsulePresentationModel,
      waveformModel: DictationWaveformModel,
      onOpenFleck: @escaping @MainActor () -> Void,
      onDragEnded: @escaping @MainActor () -> Void,
      onDockSelected: @escaping @MainActor (DictationCapsuleDock) -> Void
    ) {
      self.model = model
      self.onOpenFleck = onOpenFleck
      self.onDragEnded = onDragEnded
      self.onDockSelected = onDockSelected
      self.hostingView = NSHostingView(
        rootView: DictationCapsuleView(model: model, waveformModel: waveformModel)
      )
      super.init(frame: .zero)
      hostingView.translatesAutoresizingMaskIntoConstraints = false
      addSubview(hostingView)
      NSLayoutConstraint.activate([
        hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
        hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
        hostingView.topAnchor.constraint(equalTo: topAnchor),
        hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
      ])
      menu = makeDockMenu()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
      guard let window else { return }
      let start = window.frame.origin
      window.performDrag(with: event)
      let end = window.frame.origin
      let movement = hypot(end.x - start.x, end.y - start.y)
      if movement < 4 {
        onOpenFleck()
      } else {
        onDragEnded()
      }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
      let radius: CGFloat = model.context.status == .idle || model.context.status == .arming ? 10 : 12
      let path = NSBezierPath(
        roundedRect: bounds,
        xRadius: radius,
        yRadius: radius
      )
      return path.contains(point) ? self : nil
    }

    private func makeDockMenu() -> NSMenu {
      let menu = NSMenu()
      for (title, action) in [
        ("Dock Bottom", #selector(dockBottom)),
        ("Dock Left", #selector(dockLeft)),
        ("Dock Right", #selector(dockRight)),
      ] {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
      }
      return menu
    }

    @objc private func dockBottom() {
      onDockSelected(.bottom)
    }

    @objc private func dockLeft() {
      onDockSelected(.left)
    }

    @objc private func dockRight() {
      onDockSelected(.right)
    }
  }
#endif
