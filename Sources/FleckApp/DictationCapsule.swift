#if os(macOS)
  import AppKit
  import Combine
  import FleckCore
  import QuartzCore
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
    case routingFailure(status: String, message: String)
    case failed(String)

    var presentation: DictationCapsulePresentation {
      DictationCapsulePresentation(status: self)
    }
  }

  enum FleckRailPointerResult: Equatable {
    case none
    case primaryClick
    case drag
  }

  struct FleckRailPointerGesture {
    static let dragThreshold: CGFloat = 4

    private var startPoint: CGPoint?
    private var consumed = false
    private(set) var isDragging = false

    var isTracking: Bool { startPoint != nil }

    mutating func mouseDown(at point: CGPoint, consumed: Bool) {
      startPoint = point
      self.consumed = consumed
      isDragging = false
    }

    mutating func mouseDragged(to point: CGPoint) {
      guard let startPoint, !consumed, !isDragging else { return }
      let dx = point.x - startPoint.x
      let dy = point.y - startPoint.y
      if (dx * dx + dy * dy).squareRoot() >= Self.dragThreshold {
        isDragging = true
      }
    }

    mutating func mouseUp(at point: CGPoint) -> FleckRailPointerResult {
      defer {
        startPoint = nil
        consumed = false
        isDragging = false
      }
      guard let startPoint, !consumed else { return .none }
      if isDragging { return .drag }
      let dx = point.x - startPoint.x
      let dy = point.y - startPoint.y
      return (dx * dx + dy * dy).squareRoot() < Self.dragThreshold
        ? .primaryClick
        : .drag
    }

    mutating func cancel() {
      startPoint = nil
      consumed = false
      isDragging = false
    }
  }

  struct DictationCapsuleContext: Equatable {
    let status: DictationCapsuleStatus
    let detailText: String?
    let compactDetailText: String?
    let sessionID: UUID?
    let trigger: DictationShortcutTrigger?
    let mode: DictationMode?
    let isHandsFree: Bool
    let pipelineStage: DictationPipelineStage?
    let cleanupOutcome: DictationCleanupOutcome?
    let failureStage: DictationPipelineStage?
    let failureKind: DictationCapsuleFailureKind?

    init(
      status: DictationCapsuleStatus,
      detailText: String? = nil,
      compactDetailText: String? = nil,
      sessionID: UUID? = nil,
      trigger: DictationShortcutTrigger? = nil,
      mode: DictationMode? = nil,
      isHandsFree: Bool = false,
      pipelineStage: DictationPipelineStage? = nil,
      cleanupOutcome: DictationCleanupOutcome? = nil,
      failureStage: DictationPipelineStage? = nil,
      failureKind: DictationCapsuleFailureKind? = nil
    ) {
      self.status = status
      self.detailText = detailText
      self.compactDetailText = compactDetailText
      self.sessionID = sessionID
      self.trigger = trigger
      self.mode = mode
      self.isHandsFree = isHandsFree
      self.pipelineStage = pipelineStage
      self.cleanupOutcome = cleanupOutcome
      self.failureStage = failureStage
      self.failureKind = failureKind
    }

    func presentationContext() -> Self {
      guard status.isSavedResult else { return self }
      return Self(status: .idle, sessionID: sessionID)
    }

  }

  enum DictationCapsuleFailureKind: Equatable {
    case microphoneAccess
    case save
    case modelRepair
    case generic

    static func resolve(
      message: String,
      failureStage: DictationPipelineStage?,
      isModelRepair: Bool = false
    ) -> Self? {
      if isModelRepair { return .modelRepair }
      if failureStage == .save { return .save }
      if message == DictationFailure.permissionDenied.localizedDescription
        || message == DictationFailure.unavailable.localizedDescription
      {
        return .microphoneAccess
      }
      return nil
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

    let visibleText: String?
    let secondaryVisibleText: String?
    let voiceOverText: String
    let symbolName: String
    let visualMode: DictationCapsuleVisualMode
    let widthCeiling: CGFloat
    let measuredWidth: CGFloat
    let stageTreatments: [FleckRailStageTreatment]

    init(
      status: DictationCapsuleStatus,
      action: DictationCapsuleAction? = nil,
      chooser: DictationCapsuleChooser? = nil,
      context: DictationCapsuleContext? = nil
    ) {
      let inputContext = context ?? DictationCapsuleContext(status: status)
      let isSavedResult = inputContext.status.isSavedResult
      let context = inputContext.presentationContext()
      let presentationStatus = context.status
      let presentationAction = isSavedResult ? nil : action
      let presentationChooser = isSavedResult ? nil : chooser
      let treatments = FleckRailStageTreatment.forContext(context)
      let copy = Self.copy(for: presentationStatus, context: context)
      let visualMode: DictationCapsuleVisualMode
      let symbolName: String
      switch presentationStatus {
      case .idle:
        visualMode = .idle
        symbolName = "square.grid.2x2"
      case .arming:
        visualMode = .arming
        symbolName = "square.grid.2x2"
      case .listening:
        visualMode = .listening
        symbolName = "waveform"
      case .finalizing, .cleaning, .routing, .saving:
        visualMode = .progress
        symbolName = "circle"
      case .saved:
        visualMode = .success
        symbolName = "checkmark"
      case .savedWithoutCleanup:
        visualMode = .warning
        symbolName = "exclamationmark.triangle"
      case .noSpeech:
        visualMode = .warning
        symbolName = "waveform.slash"
      case .repairingModel:
        visualMode = .progress
        symbolName = "wrench.and.screwdriver"
      case .failed:
        visualMode = .failure
        symbolName = "exclamationmark.circle"
      case .routingFailure:
        visualMode = .failure
        symbolName = "exclamationmark.circle"
      }

      let widthCeiling = Self.widthCeiling(
        for: presentationStatus,
        action: presentationAction,
        chooser: presentationChooser
      )
      let measuredWidth = Self.measuredWidth(
        for: copy,
        status: presentationStatus,
        action: presentationAction,
        chooser: presentationChooser,
        ceiling: widthCeiling
      )
      self.visibleText = copy.visible
      secondaryVisibleText = context.compactDetailText ?? context.detailText
      voiceOverText = context.detailText.map { "\(copy.voiceOver). \($0)" } ?? copy.voiceOver
      self.symbolName = symbolName
      self.visualMode = visualMode
      self.widthCeiling = widthCeiling
      self.measuredWidth = measuredWidth
      self.stageTreatments = treatments
    }

    static func widthCeiling(for status: DictationCapsuleStatus) -> CGFloat {
      DictationCapsuleController.size(for: status).width
    }

    private static func widthCeiling(
      for status: DictationCapsuleStatus,
      action: DictationCapsuleAction?,
      chooser: DictationCapsuleChooser?
    ) -> CGFloat {
      let base = widthCeiling(for: status)
      guard let chooser, chooser.displaysMenu else { return base }
      return base + chooserWidth(for: chooser) + (action == nil ? 15 : 7)
    }

    static func tailTruncated(_ text: String, maxCharacters: Int) -> String {
      guard text.count > maxCharacters, maxCharacters > 1 else {
        return text
      }
      return String(text.prefix(maxCharacters - 1)) + "…"
    }

    private static func copy(
      for status: DictationCapsuleStatus,
      context: DictationCapsuleContext
    ) -> (visible: String?, voiceOver: String) {
      switch status {
      case .idle:
        return (nil, "Fleck dictation ready")
      case .arming:
        return ("Starting", "Starting dictation")
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
      case .saved, .savedWithoutCleanup:
        return (nil, "Fleck dictation ready")
      case .noSpeech:
        return ("No speech heard", "No speech heard")
      case .repairingModel:
        return ("Repairing enhanced model", "Repairing enhanced dictation model")
      case .failed(let message):
        let text = failureCopy(for: context.failureKind)
        return (text, "\(text): \(message)")
      case .routingFailure(let status, let message):
        return (status, "Dictation routing needs attention: \(message)")
      }
    }

    private static func failureCopy(for kind: DictationCapsuleFailureKind?) -> String {
      switch kind {
      case .microphoneAccess:
        "Microphone access needed"
      case .save:
        "Couldn't save"
      case .modelRepair:
        "Model repair failed"
      case .generic, nil:
        "Dictation failed"
      }
    }

    private static func measuredWidth(
      for copy: (visible: String?, voiceOver: String),
      status: DictationCapsuleStatus,
      action: DictationCapsuleAction?,
      chooser: DictationCapsuleChooser?,
      ceiling: CGFloat
    ) -> CGFloat {
      guard let visible = copy.visible else { return ceiling }
      let markWidth = FleckRailIdentityMark.frameSize.width
      let glyphWidth: CGFloat = status == .finalizing || status == .cleaning
        || status == .routing || status == .saving ? 0 : 14
      let actionWidth = action.map(Self.actionWidth(for:)) ?? 0
      let chooserWidth = chooser.flatMap { $0.displaysMenu ? Self.chooserWidth(for: $0) : nil } ?? 0
      let controlSpacing: CGFloat = actionWidth > 0 && chooserWidth > 0 ? 7 : 0
      let dividerWidth: CGFloat = actionWidth == 0 && chooserWidth == 0
        ? 0
        : actionDividerSize.width + 14
      let estimate = 16 + markWidth + 7 + glyphWidth + (glyphWidth > 0 ? 7 : 0)
        + CGFloat(visible.count) * 7 + dividerWidth + actionWidth + controlSpacing + chooserWidth
      return min(ceiling, max(ceil(estimate), 1))
    }

    static func actionWidth(for action: DictationCapsuleAction) -> CGFloat {
      max(CGFloat(action.buttonTitle.count) * 7 + 4, 28)
    }

    static func chooserWidth(for chooser: DictationCapsuleChooser) -> CGFloat {
      CGFloat(chooser.menuTitle.count) * 7 + 9
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
      let failedIndex: Int? = {
        guard case .failed = status, let failureStage = context.failureStage else {
          return nil
        }
        return stages.firstIndex(of: failureStage)
      }()

      if status.isSavedResult {
        result = Array(repeating: .complete, count: stages.count)
      } else if let failedIndex {
        for index in 0..<failedIndex {
          result[index] = .complete
        }
        result[failedIndex] = .failed
      } else if case .failed = status {
        // A terminal failure without stage provenance must not guess at a tile.
      } else {
        if let pipelineStage = context.pipelineStage,
          let activeIndex = stages.firstIndex(of: pipelineStage)
        {
          for index in 0..<activeIndex {
            result[index] = .complete
          }
          result[activeIndex] = status == .finalizing && pipelineStage == .capture
            ? .complete
            : .active
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
          case .idle, .noSpeech, .repairingModel, .saved, .savedWithoutCleanup,
            .routingFailure, .failed:
            break
          }
        }
      }

      if context.cleanupOutcome == .usedRaw,
        result[1] != .active,
        result[1] != .failed,
        failedIndex.map({ 1 < $0 }) ?? !status.isFailure
      {
        result[1] = .fallback
      }

      if context.mode == .focused,
        result[2] != .active,
        result[2] != .failed,
        failedIndex.map({ 2 < $0 }) ?? !status.isFailure
      {
        result[2] = .skipped
      }
      return result
    }

    var usesFailureColor: Bool { self == .failed }
    var usesDiagonal: Bool { self == .failed }
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

    var luminance: Double {
      func linear(_ value: Double) -> Double {
        value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
      }
      return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
  }

  struct FleckRailColors: Equatable {
    static let shellOpacity = 0.96

    let accentHex: String
    let shell: FleckRailRGB
    let displayCore: FleckRailRGB
    let displayLive: FleckRailRGB
    let primaryText: FleckRailRGB
    let secondaryText: FleckRailRGB
    let success: FleckRailRGB
    let warning: FleckRailRGB
    let failure: FleckRailRGB
    let borderColor: Color
    let reduceTransparency: Bool
    let increasedContrast: Bool

    var effectiveShellOpacity: Double {
      reduceTransparency ? 1 : Self.shellOpacity
    }

    init(theme: FleckThemeSnapshot = .initial) {
      let palette = theme.palette
      accentHex = palette[.accent]
      shell = FleckRailRGB(hex: palette[.capsuleSurface])!
      displayCore = FleckRailRGB(hex: palette[.accent])!
      displayLive = FleckRailRGB(hex: palette[.focusRing])!
      primaryText = FleckRailRGB(hex: palette[.capsuleText])!
      secondaryText = FleckRailRGB(hex: palette[.caption])!
      success = FleckRailRGB(hex: palette[.success])!
      warning = FleckRailRGB(hex: palette[.warning])!
      failure = FleckRailRGB(hex: palette[.error])!
      borderColor = theme.color(.capsuleBorder)
      reduceTransparency = theme.reduceTransparency
      increasedContrast = theme.increasedContrast
    }

    var displayCoreHex: String { displayCore.hex }
    var displayLiveHex: String { displayLive.hex }
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
  }

  enum FleckRailAccessibility {
    enum Action: Equatable {
      case stop
      case cancel
      case dismiss
    }

    static func usesIncreasedContrast(_ contrast: ColorSchemeContrast) -> Bool {
      contrast == .increased
    }

    static func actions(for context: DictationCapsuleContext) -> [Action] {
      if context.status == .listening, context.isHandsFree {
        return [.stop, .cancel]
      }
      if context.status.isTerminalResult {
        return [.dismiss]
      }
      return []
    }
  }

  private enum FleckRailInteractionRegion: String, Equatable {
    case stop = "fleck-rail-stop"
    case cancel = "fleck-rail-cancel"
    case recovery = "fleck-rail-recovery"
  }

  enum FleckRailContentElement: Equatable {
    case mark
    case waveform
    case timer
    case terminalGlyph
    case statusText
    case divider
    case action
  }

  enum FleckRailContentOrder {
    static func markAndContent(for dock: DictationCapsuleDock) -> [FleckRailContentElement] {
      dock == .right ? [.statusText, .mark] : [.mark, .statusText]
    }

    static func listening(for dock: DictationCapsuleDock) -> [FleckRailContentElement] {
      dock == .right ? [.timer, .waveform, .mark] : [.mark, .waveform, .timer]
    }

    static func terminalCluster(
      for dock: DictationCapsuleDock,
      includesAction: Bool
    ) -> [FleckRailContentElement] {
      let left: [FleckRailContentElement] = includesAction
        ? [.terminalGlyph, .statusText, .divider, .action]
        : [.terminalGlyph, .statusText]
      return dock == .right ? Array(left.reversed()) : left
    }

    static func terminal(
      for dock: DictationCapsuleDock,
      includesAction: Bool
    ) -> [FleckRailContentElement] {
      let left = [.mark] + terminalCluster(for: .left, includesAction: includesAction)
      return dock == .right ? Array(left.reversed()) : left
    }
  }

  struct FleckRailLayout: Layout {
    let order: [FleckRailContentElement]
    let spacing: CGFloat

    private var isReversed: Bool {
      order.first == .statusText
    }

    func sizeThatFits(
      proposal: ProposedViewSize,
      subviews: Subviews,
      cache: inout ()
    ) -> CGSize {
      let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
      let visible = sizes.filter { $0.width > 0 && $0.height > 0 }
      guard let maxHeight = visible.map(\.height).max() else {
        return .zero
      }
      let intrinsicWidth = visible.map(\.width).reduce(0, +)
        + spacing * CGFloat(max(visible.count - 1, 0))
      let width = proposal.width.flatMap { $0.isFinite ? max($0, 0) : nil }
        ?? intrinsicWidth
      return CGSize(width: width, height: maxHeight)
    }

    func placeSubviews(
      in bounds: CGRect,
      proposal: ProposedViewSize,
      subviews: Subviews,
      cache: inout ()
    ) {
      let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
      let visibleIndices = subviews.indices.filter {
        sizes[$0].width > 0 && sizes[$0].height > 0
      }
      let orderedIndices = Array(visibleIndices)
      var proposedSizes = sizes
      if orderedIndices.count == 2 {
        let fixedIndex = orderedIndices[0]
        let flexibleIndex = orderedIndices[1]
        proposedSizes[flexibleIndex].width = max(
          bounds.width - proposedSizes[fixedIndex].width - spacing,
          0
        )
      }
      var cursor = isReversed ? bounds.maxX : bounds.minX

      for index in orderedIndices {
        let size = proposedSizes[index]
        let x = isReversed ? cursor - size.width : cursor
        subviews[index].place(
          at: CGPoint(x: x, y: bounds.midY - size.height / 2),
          proposal: ProposedViewSize(size)
        )
        cursor += isReversed ? -(size.width + spacing) : size.width + spacing
      }
    }
  }

  struct FleckRailTerminalLayout: Layout {
    let elements: [FleckRailContentElement]
    let order: [FleckRailContentElement]
    let spacing: CGFloat

    func sizeThatFits(
      proposal: ProposedViewSize,
      subviews: Subviews,
      cache: inout ()
    ) -> CGSize {
      let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
      let visible = sizes.filter { $0.width > 0 && $0.height > 0 }
      guard let maxHeight = visible.map(\.height).max() else {
        return .zero
      }
      let intrinsicWidth = visible.map(\.width).reduce(0, +)
        + spacing * CGFloat(max(visible.count - 1, 0))
      let width = proposal.width.flatMap { $0.isFinite ? max($0, 0) : nil }
        ?? intrinsicWidth
      return CGSize(width: width, height: maxHeight)
    }

    func placeSubviews(
      in bounds: CGRect,
      proposal: ProposedViewSize,
      subviews: Subviews,
      cache: inout ()
    ) {
      let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
      let orderedIndices: [Int] = order.compactMap { element -> Int? in
        guard let index = elements.firstIndex(of: element),
          sizes[index].width > 0,
          sizes[index].height > 0
        else {
          return nil
        }
        return index
      }
      var proposedSizes = sizes
      if let statusIndex = elements.firstIndex(of: .statusText),
        orderedIndices.contains(statusIndex)
      {
        let fixedWidth = orderedIndices.filter { $0 != statusIndex }
          .map { proposedSizes[$0].width }
          .reduce(0, +)
        proposedSizes[statusIndex].width = max(
          bounds.width - fixedWidth - spacing * CGFloat(max(orderedIndices.count - 1, 0)),
          0
        )
      }
      var cursor = bounds.minX
      for index in orderedIndices {
        let size = proposedSizes[index]
        subviews[index].place(
          at: CGPoint(x: cursor, y: bounds.midY - size.height / 2),
          proposal: ProposedViewSize(size)
        )
        cursor += size.width + spacing
      }
    }
  }

  struct FleckRailIdentityMark: View {
    nonisolated static let frameSize = CGSize(width: 18, height: 18)

    let image: NSImage?
    let color: Color

    init(image: NSImage?, color: Color) {
      self.image = image
      self.color = color
    }

    var body: some View {
      Group {
        if let image {
          Image(nsImage: image)
            .resizable()
            .renderingMode(.template)
            .interpolation(.high)
            .scaledToFit()
            .foregroundStyle(color)
        }
      }
      .frame(width: Self.frameSize.width, height: Self.frameSize.height)
      .background(FleckRailFrameProbe(identifier: "fleck-rail-mark"))
      .accessibilityHidden(true)
    }
  }

  struct FleckRailMark: View {
    enum Layout: Equatable {
      case mark
      case rail(reversed: Bool)
    }

    static let frameSize = CGSize(width: 14, height: 14)
    static let railFrameSize = CGSize(width: 30, height: 14)
    static let tileIDs = [0, 1, 2, 3]
    static let tileFrames = [
      CGRect(x: 0, y: 0, width: 6, height: 6),
      CGRect(x: 8, y: 0, width: 6, height: 6),
      CGRect(x: 0, y: 8, width: 6, height: 6),
      CGRect(x: 8, y: 8, width: 6, height: 6),
    ]
    static let railTileFrames = [
      CGRect(x: 0, y: 4, width: 6, height: 6),
      CGRect(x: 8, y: 4, width: 6, height: 6),
      CGRect(x: 16, y: 4, width: 6, height: 6),
      CGRect(x: 24, y: 4, width: 6, height: 6),
    ]
    static let innerHighlightThickness: CGFloat = 1

    let color: Color
    let activeTile: Int?
    let layout: Layout
    let treatments: [FleckRailStageTreatment]
    let colors: FleckRailColors

    init(
      color: Color = FleckRailColors().coreColor,
      activeTile: Int? = nil,
      layout: Layout = .mark,
      treatments: [FleckRailStageTreatment] = [],
      colors: FleckRailColors = FleckRailColors()
    ) {
      self.color = color
      self.activeTile = activeTile
      self.layout = layout
      self.treatments = treatments
      self.colors = colors
    }

    static func tileOrder(reversed: Bool) -> [Int] {
      reversed ? Array(tileIDs.reversed()) : tileIDs
    }

    static func layoutFrameSize(for layout: Layout) -> CGSize {
      switch layout {
      case .mark:
        frameSize
      case .rail:
        railFrameSize
      }
    }

    private static func tileFrames(for layout: Layout) -> [CGRect] {
      switch layout {
      case .mark:
        tileFrames
      case .rail:
        railTileFrames
      }
    }

    private var railReversed: Bool {
      if case .rail(let reversed) = layout { return reversed }
      return false
    }

    private func treatment(for tileID: Int) -> FleckRailStageTreatment? {
      treatments.indices.contains(tileID) ? treatments[tileID] : nil
    }

    private func fillColor(for tileID: Int) -> Color {
      guard let treatment = treatment(for: tileID) else {
        return tileID == activeTile ? color : color.opacity(activeTile == nil ? 1 : 0.28)
      }
      if treatment.usesFailureColor {
        return colors.failureColor
      }
      switch treatment {
      case .pending:
        return colors.secondaryTextColor.opacity(0.35)
      case .active:
        return colors.liveColor
      case .complete:
        return colors.coreColor
      case .skipped, .fallback:
        return .clear
      case .failed:
        return .clear
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

    var body: some View {
      let frames = Self.tileFrames(for: layout)
      let frameSize = Self.layoutFrameSize(for: layout)
      ZStack(alignment: .topLeading) {
        Color.clear
          .frame(width: frameSize.width, height: frameSize.height)
        ForEach(Self.tileOrder(reversed: railReversed), id: \.self) { tileID in
          let frame = frames[railReversed ? Self.tileIDs.count - 1 - tileID : tileID]
          let treatment = treatment(for: tileID)
          RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(fillColor(for: tileID))
            .frame(width: frame.width, height: frame.height)
            .overlay(alignment: .top) {
              Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: Self.innerHighlightThickness)
                .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
            }
            .overlay {
              if let treatment, treatment == .skipped || treatment == .fallback {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                  .stroke(strokeColor(for: treatment), lineWidth: 1)
                  .padding(1)
              }
              if treatment?.usesDiagonal == true {
                Path { path in
                  path.move(to: CGPoint(x: 1, y: 1))
                  path.addLine(to: CGPoint(x: frame.width - 1, y: frame.height - 1))
                }
                .stroke(Color.white.opacity(0.8), lineWidth: 1)
              }
            }
            .offset(x: frame.minX, y: frame.minY)
        }
      }
      .frame(width: frameSize.width, height: frameSize.height)
      .accessibilityHidden(true)
      .background(FleckRailFrameProbe(identifier: "fleck-rail-mark"))
    }
  }

  private final class FleckRailFrameProbeView: NSView {
    init(identifier: String) {
      super.init(frame: .zero)
      self.identifier = NSUserInterfaceItemIdentifier(identifier)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
      nil
    }
  }

  private struct FleckRailFrameProbe: NSViewRepresentable {
    let identifier: String

    func makeNSView(context: Context) -> FleckRailFrameProbeView {
      FleckRailFrameProbeView(identifier: identifier)
    }

    func updateNSView(_ nsView: FleckRailFrameProbeView, context: Context) {}
  }

  private struct FleckRailInteractionProbe: NSViewRepresentable {
    let region: FleckRailInteractionRegion

    func makeNSView(context: Context) -> FleckRailFrameProbeView {
      FleckRailFrameProbeView(identifier: region.rawValue)
    }

    func updateNSView(_ nsView: FleckRailFrameProbeView, context: Context) {}
  }

  struct DictationCapsuleChoice: Equatable, Identifiable {
    private static let visibleContextLimit = 48

    let id: UUID
    let title: String
    let contextHint: String
    let showsContextHint: Bool
    let currentDestinationTitle: String
    let isCurrentDestination: Bool

    var menuTitle: String {
      guard showsContextHint, !contextHint.isEmpty else { return title }
      let prefix = String(contextHint.prefix(Self.visibleContextLimit))
      let suffix = contextHint.count > Self.visibleContextLimit ? "…" : ""
      return "\(title) — \(prefix)\(suffix)"
    }

    var accessibilityLabel: String {
      let action = isCurrentDestination
        ? "Retry saving dictation in \(title)"
        : "Move dictation to \(title)"
      guard !contextHint.isEmpty else { return action }
      return "\(action). Context: \(contextHint)"
    }

    var accessibilityHint: String {
      if isCurrentDestination {
        return "Retries completion for this saved dictation in \(title)."
      }
      return "Moves this saved dictation from \(currentDestinationTitle) to \(title)."
    }
  }

  struct DictationCapsuleChooser: Equatable {
    let captureID: UUID
    let choices: [DictationCapsuleChoice]
    let allowsKeepInInbox: Bool
    let keepInboxTitle = "Keep in Inbox"
    let keepInboxAccessibilityLabel = "Keep dictation in Inbox"

    var displaysMenu: Bool {
      !choices.isEmpty || allowsKeepInInbox
    }

    var menuTitle: String {
      choices.isEmpty ? keepInboxTitle : "Choose note"
    }

    var menuAccessibilityLabel: String {
      menuTitle
    }

    var menuAccessibilityHint: String {
      if choices.isEmpty, allowsKeepInInbox {
        return "Opens the action to keep this saved dictation in Inbox."
      }
      if allowsKeepInInbox {
        return "Choose a note for this saved dictation or keep it in Inbox."
      }
      return "Choose a note for this saved dictation."
    }

    init(
      ambiguity: DictationRoutingAmbiguity,
      currentDestinationID: UUID? = nil,
      currentDestinationTitle: String = "Inbox",
      allowsKeepInInbox: Bool = true
    ) {
      captureID = ambiguity.captureID
      self.allowsKeepInInbox = allowsKeepInInbox
      let supported = ambiguity.choices
      let titleCounts = Dictionary(grouping: supported) {
        Self.normalizedTitle($0.destination.title)
      }.mapValues(\.count)
      choices = supported.map { choice in
        let title = Self.displayTitle(choice.destination.title)
        return DictationCapsuleChoice(
          id: choice.destination.noteID,
          title: title,
          contextHint: choice.contextHint,
          showsContextHint: titleCounts[Self.normalizedTitle(title), default: 0] > 1,
          currentDestinationTitle: Self.displayTitle(currentDestinationTitle),
          isCurrentDestination: choice.destination.noteID == currentDestinationID
        )
      }
    }

    private static func displayTitle(_ title: String) -> String {
      let normalized = title.split(whereSeparator: \Character.isWhitespace)
        .joined(separator: " ")
      return normalized.isEmpty ? "Untitled" : normalized
    }

    private static func normalizedTitle(_ title: String) -> String {
      displayTitle(title).lowercased()
    }
  }

  enum DictationCapsuleTransition: Equatable {
    case opacity
    case scaleAndOpacity

    static func forReduceMotion(_ reduceMotion: Bool) -> Self {
      reduceMotion ? .opacity : .scaleAndOpacity
    }
  }

  enum DictationCapsuleMotion {
    static let acknowledgement: TimeInterval = 0
    static let colorAndOpacity: TimeInterval = 0.09
    static let tileMorph: TimeInterval = 0.14
    static let contentExit: TimeInterval = 0.07
    static let shellSettle: TimeInterval = 0.12
    static let result: TimeInterval = 0.11
    static let dockSnap: TimeInterval = 0.18
    static let reduceMotionCrossfade: TimeInterval = 0.10
    static let processingLabelDelay: Duration = .milliseconds(450)

    static func transitionDuration(
      from: DictationCapsuleStatus,
      to: DictationCapsuleStatus,
      reduceMotion: Bool,
      dockChange: Bool = false
    ) -> TimeInterval {
      contentDuration(
        from: from,
        to: to,
        reduceMotion: reduceMotion,
        dockChange: dockChange
      )
    }

    static func contentDuration(
      from: DictationCapsuleStatus,
      to: DictationCapsuleStatus,
      reduceMotion: Bool,
      dockChange: Bool = false
    ) -> TimeInterval {
      if to == .arming {
        return acknowledgement
      }
      if reduceMotion {
        return reduceMotionCrossfade
      }
      if dockChange {
        return dockSnap
      }
      if isTerminal(to), !isTerminal(from) {
        return result
      }
      if to == .idle, isTerminal(from) {
        return contentExit
      }
      if isProgress(from) || isProgress(to) {
        return tileMorph
      }
      return colorAndOpacity
    }

    static func shellDuration(
      from: DictationCapsuleStatus,
      to: DictationCapsuleStatus,
      reduceMotion: Bool,
      dockChange: Bool = false
    ) -> TimeInterval {
      if to == .arming {
        return acknowledgement
      }
      if reduceMotion {
        return reduceMotionCrossfade
      }
      if dockChange {
        return dockSnap
      }
      if isTerminal(from), to == .idle {
        return shellSettle
      }
      return contentDuration(
        from: from,
        to: to,
        reduceMotion: false,
        dockChange: false
      )
    }

    static func usesTileMorph(
      from: DictationCapsuleStatus,
      to: DictationCapsuleStatus
    ) -> Bool {
      if isTerminal(to), !isTerminal(from) { return false }
      if to == .idle, isTerminal(from) { return false }
      return isProgress(from) || isProgress(to)
    }

    private static func isProgress(_ status: DictationCapsuleStatus) -> Bool {
      switch status {
      case .finalizing, .cleaning, .routing, .saving:
        true
      default:
        false
      }
    }

    private static func isTerminal(_ status: DictationCapsuleStatus) -> Bool {
      switch status {
      case .saved, .savedWithoutCleanup, .noSpeech, .routingFailure, .failed:
        true
      default:
        false
      }
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

    var title: String {
      switch self {
      case .undo: "Undo"
      case .copy: "Copy"
      case .openHistory: "Open Dictation History"
      case .openDestination: "Open Destination"
      }
    }

    var buttonTitle: String {
      switch self {
      case .undo: "Undo"
      case .copy: "Copy"
      case .openHistory: "History"
      case .openDestination: "Destination"
      }
    }

    var accessibilityLabel: String { title }
  }

  @MainActor
  final class DictationCapsulePresentationModel: ObservableObject {
    @Published private(set) var context: DictationCapsuleContext
    @Published private(set) var action: DictationCapsuleAction?
    @Published private(set) var chooser: DictationCapsuleChooser?
    @Published private(set) var dock: DictationCapsuleDock
    @Published private(set) var colors: FleckRailColors
    @Published private(set) var isListeningHover = false
    @Published private(set) var isDragActive = false
    @Published private(set) var showsProcessingLabel = false
    private(set) var presentationGeneration: UInt64 = 0
    private(set) var voiceOverLabel = "Fleck dictation ready"
    private(set) var actionHandler: @MainActor () -> Void
    private(set) var choiceHandler: @MainActor (UUID, UUID?) -> Void
    private(set) var stopHandler: @MainActor () -> Void
    private(set) var cancelHandler: @MainActor () -> Void
    private(set) var dismissHandler: @MainActor () -> Void
    private let announcementHandler: @MainActor (String) -> Void
    private let processingLabelSleeper: @MainActor (Duration) async -> Void
    private var processingLabelTask: Task<Void, Never>?

    init(
      context: DictationCapsuleContext = DictationCapsuleContext(status: .idle),
      dock: DictationCapsuleDock = .bottom,
      colors: FleckRailColors = FleckRailColors(),
      action: DictationCapsuleAction? = nil,
      chooser: DictationCapsuleChooser? = nil,
      onAction: @escaping @MainActor () -> Void = {},
      onChoice: @escaping @MainActor (UUID, UUID?) -> Void = { _, _ in },
      onStop: @escaping @MainActor () -> Void = {},
      onCancel: @escaping @MainActor () -> Void = {},
      onDismiss: @escaping @MainActor () -> Void = {},
      processingLabelSleeper: @escaping @MainActor (Duration) async -> Void = { duration in
        try? await Task.sleep(for: duration)
      },
      announcementHandler: @escaping @MainActor (String) -> Void = { _ in }
    ) {
      let isSavedResult = context.status.isSavedResult
      let presentationContext = context.presentationContext()
      self.context = presentationContext
      self.dock = dock.supportedPlacement
      self.colors = colors
      self.action = isSavedResult ? nil : action
      self.chooser = isSavedResult ? nil : chooser
      self.actionHandler = onAction
      self.choiceHandler = onChoice
      self.stopHandler = onStop
      self.cancelHandler = onCancel
      self.dismissHandler = onDismiss
      self.announcementHandler = announcementHandler
      self.processingLabelSleeper = processingLabelSleeper
      switch presentationContext.status {
      case .idle, .arming, .listening, .saved, .savedWithoutCleanup, .noSpeech,
        .routingFailure, .failed:
        self.voiceOverLabel = DictationCapsulePresentation(
          status: presentationContext.status,
          context: presentationContext
        ).voiceOverText
      default:
        break
      }
      if presentationContext.status != .listening || !presentationContext.isHandsFree {
        isListeningHover = false
      }
    }

    func update(
      context: DictationCapsuleContext,
      action: DictationCapsuleAction?,
      onAction: @escaping @MainActor () -> Void,
      chooser: DictationCapsuleChooser? = nil,
      onChoice: @escaping @MainActor (UUID, UUID?) -> Void = { _, _ in },
      onStop: (@MainActor () -> Void)? = nil,
      onCancel: (@MainActor () -> Void)? = nil
    ) {
      let previousContext = self.context
      let isSavedResult = context.status.isSavedResult
      let presentationContext = context.presentationContext()
      presentationGeneration &+= 1
      processingLabelTask?.cancel()
      processingLabelTask = nil
      showsProcessingLabel = false
      self.context = presentationContext
      self.action = isSavedResult ? nil : action
      self.chooser = isSavedResult ? nil : chooser
      self.actionHandler = onAction
      self.choiceHandler = onChoice
      if let onStop { self.stopHandler = onStop }
      if let onCancel { self.cancelHandler = onCancel }
      if presentationContext.status != .listening || !presentationContext.isHandsFree {
        isListeningHover = false
      }
      if isSavedResult || presentationContext.status != .idle {
        isDragActive = false
      }
      updateVoiceOverLabel(from: previousContext, to: presentationContext)
      scheduleProcessingLabel(for: presentationContext)
    }

    func updateDock(_ dock: DictationCapsuleDock) {
      self.dock = dock.supportedPlacement
    }

    func updateTheme(_ theme: FleckThemeSnapshot) {
      colors = FleckRailColors(theme: theme)
    }

    func updateIdleAccessibilityLabel(_ label: String) {
      guard context.status == .idle, voiceOverLabel != label else { return }
      objectWillChange.send()
      voiceOverLabel = label
    }

    func setListeningHover(_ isHovering: Bool) {
      isListeningHover = isHovering
    }

    func setDragActive(_ isActive: Bool) {
      isDragActive = isActive
    }

    func updateListeningActions(
      onStop: @escaping @MainActor () -> Void,
      onCancel: @escaping @MainActor () -> Void
    ) {
      stopHandler = onStop
      cancelHandler = onCancel
    }

    func updateDismissHandler(_ onDismiss: @escaping @MainActor () -> Void) {
      dismissHandler = onDismiss
    }

    func invalidatePresentation() {
      presentationGeneration &+= 1
      processingLabelTask?.cancel()
      processingLabelTask = nil
      showsProcessingLabel = false
    }

    private func scheduleProcessingLabel(for context: DictationCapsuleContext) {
      guard isProcessing(context.status), DictationCapsulePresentation(
        status: context.status,
        context: context
      ).visibleText != nil
      else {
        return
      }
      let generation = presentationGeneration
      let sleeper = processingLabelSleeper
      processingLabelTask = Task { @MainActor [weak self] in
        await sleeper(DictationCapsuleMotion.processingLabelDelay)
        guard
          !Task.isCancelled,
          let self,
          self.presentationGeneration == generation,
          self.context == context,
          self.isProcessing(self.context.status)
        else {
          return
        }
        self.showsProcessingLabel = true
      }
    }

    private func updateVoiceOverLabel(
      from previousContext: DictationCapsuleContext,
      to context: DictationCapsuleContext
    ) {
      if context.status == .idle {
        voiceOverLabel = DictationCapsulePresentation(status: .idle).voiceOverText
        return
      }
      if context.status == .arming {
        voiceOverLabel = DictationCapsulePresentation(status: .arming).voiceOverText
        return
      }
      if context.status == .listening,
        previousContext.status != .listening
          || previousContext.sessionID != context.sessionID
      {
        let label = DictationCapsulePresentation(
          status: .listening,
          context: context
        ).voiceOverText
        voiceOverLabel = label
        announcementHandler(label)
        return
      }
      guard isTerminal(context.status),
        previousContext != context
      else {
        return
      }
      let label = DictationCapsulePresentation(
        status: context.status,
        context: context
      ).voiceOverText
      let shouldAnnounce = previousContext.status != context.status
        || previousContext.sessionID != context.sessionID
        || voiceOverLabel != label
      voiceOverLabel = label
      if shouldAnnounce {
        announcementHandler(label)
      }
    }

    private func isProcessing(_ status: DictationCapsuleStatus) -> Bool {
      switch status {
      case .finalizing, .cleaning, .routing, .saving:
        true
      default:
        false
      }
    }

    private func isTerminal(_ status: DictationCapsuleStatus) -> Bool {
      switch status {
      case .saved, .savedWithoutCleanup, .noSpeech, .routingFailure, .failed:
        true
      default:
        false
      }
    }

    var showsDockIndicators: Bool { isDragActive }

    deinit {
      processingLabelTask?.cancel()
    }
  }

  @MainActor
  private final class DictationCapsuleInputRouter {
    var onPrimaryClick: @MainActor () -> Void = {}
    var onOpenFleck: @MainActor () -> Void = {}
    var onOpenHistory: @MainActor () -> Void = {}
    var onOpenSettings: @MainActor () -> Void = {}
    var onDismiss: @MainActor () -> Void = {}
    var onRecovery: @MainActor () -> Void = {}
    var onDragChanged: @MainActor (CGPoint) -> Void = { _ in }
    var onDragEnded: @MainActor (CGPoint, Bool) -> Void = { _, _ in }
  }

  final class DictationCapsulePanel: NSPanel {
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
      allowsActions = false
    }

    var allowsActions = false

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
    nonisolated static let livePillHostSize = CGSize(width: 180, height: 39)
    nonisolated static let idleSize = CGSize(width: 46, height: 24)
    nonisolated static let startingSize = CGSize(width: 104, height: 36)
    nonisolated static let listeningSize = CGSize(width: 176, height: 36)
    nonisolated static let activeSize = CGSize(width: 192, height: 36)
    nonisolated static let savedSize = CGSize(width: 264, height: 36)
    nonisolated static let savedWithoutCleanupSize = CGSize(width: 288, height: 36)
    nonisolated static let noSpeechSize = CGSize(width: 192, height: 36)
    nonisolated static let repairingModelSize = CGSize(width: 224, height: 36)
    nonisolated static let failureSize = CGSize(width: 264, height: 36)
    static let edgeInset: CGFloat = 10

    let panel: DictationCapsulePanel
    let waveformModel: DictationWaveformModel
    let presentationModel: DictationCapsulePresentationModel
    let fleckPillModel: FleckPillLivePresentationModel
    private let inputRouter: DictationCapsuleInputRouter
    private let monotonicNow: @MainActor () -> TimeInterval
    private let reduceMotionProvider: @MainActor () -> Bool
    private let automaticallyAdvancesLivePill: Bool
    private var hostingView: DictationCapsuleHostingView!
    private(set) var currentDock = DictationCapsuleDock.bottom
    private(set) var currentChooser: DictationCapsuleChooser?
    private var currentChoiceHandler: @MainActor (UUID, UUID?) -> Void = { _, _ in }
    private(set) var currentContext = DictationCapsuleContext(status: .idle)
    private var currentScreen: NSScreen?
    private var lastCoordinatorEvent: DictationCoordinatorEvent?
    private var retiredCoordinatorSessionIDs: Set<UUID> = []
    private var retiredCoordinatorSessionOrder: [UUID] = []
    private var onDockChanged: (@MainActor (DictationCapsuleDock) -> Void)?
    private var screenParametersObserver: DictationCapsuleObserverToken?
    private var dragOrigin: CGPoint?
    private var dragFrameOrigin: CGPoint?

    init(
      panel: DictationCapsulePanel = DictationCapsulePanel(),
      waveformModel: DictationWaveformModel = DictationWaveformModel(),
      monotonicNow: @escaping @MainActor () -> TimeInterval = {
        ProcessInfo.processInfo.systemUptime
      },
      automaticallyAdvancesLivePill: Bool = true,
      reduceMotionProvider: @escaping @MainActor () -> Bool = {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
      },
      theme: FleckThemeSnapshot = .initial,
      markLoader: @escaping @MainActor () -> NSImage? = {
        guard case .image(let image) = FleckMark.load(template: true) else {
          return nil
        }
        return image
      },
      announcementPoster: @escaping @MainActor (NSWindow, String) -> Void =
        DictationCapsuleController.postAnnouncement
    ) {
      self.panel = panel
      self.waveformModel = waveformModel
      self.monotonicNow = monotonicNow
      self.reduceMotionProvider = reduceMotionProvider
      self.automaticallyAdvancesLivePill = automaticallyAdvancesLivePill
      self.fleckPillModel = FleckPillLivePresentationModel()
      let persistentPanel = panel
      self.presentationModel = DictationCapsulePresentationModel(
        colors: FleckRailColors(theme: theme),
        announcementHandler: { [weak persistentPanel] message in
          guard let persistentPanel else { return }
          announcementPoster(persistentPanel, message)
        }
      )
      let inputRouter = DictationCapsuleInputRouter()
      self.inputRouter = inputRouter
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
      let hostingView = DictationCapsuleHostingView(
        model: presentationModel,
        waveformModel: waveformModel,
        fleckPillModel: fleckPillModel,
        markImage: markLoader(),
        inputRouter: inputRouter,
        automaticallyAdvancesLivePill: automaticallyAdvancesLivePill,
        onDockSelected: { [weak self] dock in self?.selectDock(dock) },
        onLivePillAnimationFrame: { [weak self] in self?.advanceLivePillAnimation() }
      )
      self.hostingView = hostingView
      panel.contentView = hostingView
      inputRouter.onDragChanged = { [weak self] point in
        self?.dragChanged(to: point)
      }
      inputRouter.onDragEnded = { [weak self] point, cancelled in
        self?.dragEnded(at: point, cancelled: cancelled)
      }
    }

    private var effectiveReduceMotion: Bool {
      reduceMotionProvider()
    }

    private static func postAnnouncement(_ panel: NSWindow, _ message: String) {
      NSAccessibility.post(
        element: panel,
        notification: .announcementRequested,
        userInfo: [
          .announcement: message,
          .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ]
      )
    }

    func presentIdle(
      dock: DictationCapsuleDock,
      accessibilityLabel: String = "Fleck dictation ready",
      onOpenFleck: @escaping @MainActor () -> Void,
      onDockChanged: @escaping @MainActor (DictationCapsuleDock) -> Void
    ) {
      let dock = dock.supportedPlacement
      let previousStatus = currentContext.status
      let now = monotonicNow()
      let renderedFrame = currentContext.sessionID.flatMap(fleckPillModel.displayedFrame(for:))
      retireCoordinatorSession(currentContext.sessionID)
      currentDock = dock
      currentContext = DictationCapsuleContext(status: .idle)
      lastCoordinatorEvent = nil
      if dock == .bottom {
        fleckPillModel.presentStandby(
          at: now,
          renderedFrame: renderedFrame,
          animated: panel.isVisible,
          reduceMotion: effectiveReduceMotion
        )
      } else {
        hideLivePillImmediately()
      }
      waveformModel.reset()
      currentChooser = nil
      currentChoiceHandler = { _, _ in }
      panel.allowsActions = false
      dragOrigin = nil
      dragFrameOrigin = nil
      presentationModel.setDragActive(false)
      hostingView.cancelPointerGesture()
      self.onDockChanged = onDockChanged
      presentationModel.updateDock(dock)
      presentationModel.update(
        context: currentContext,
        action: nil,
        onAction: {},
        chooser: nil,
        onChoice: { _, _ in }
      )
      presentationModel.updateIdleAccessibilityLabel(accessibilityLabel)
      inputRouter.onOpenFleck = onOpenFleck
      hostingView.refreshMenu()
      panel.hasShadow = !fleckPillModel.isVisible
      applyCurrentFrame(
        animated: panel.isVisible,
        from: previousStatus
      )
      panel.orderFrontRegardless()
    }

    func configureInteraction(
      onPrimaryClick: @escaping @MainActor () -> Void,
      onStop: @escaping @MainActor () -> Void,
      onCancel: @escaping @MainActor () -> Void,
      onOpenFleck: @escaping @MainActor () -> Void,
      onOpenHistory: @escaping @MainActor () -> Void,
      onOpenSettings: @escaping @MainActor () -> Void,
      onDismiss: @escaping @MainActor () -> Void,
      onRecovery: @escaping @MainActor () -> Void
    ) {
      inputRouter.onPrimaryClick = onPrimaryClick
      inputRouter.onOpenFleck = onOpenFleck
      inputRouter.onOpenHistory = onOpenHistory
      inputRouter.onOpenSettings = onOpenSettings
      inputRouter.onDismiss = onDismiss
      inputRouter.onRecovery = onRecovery
      presentationModel.updateListeningActions(onStop: onStop, onCancel: onCancel)
      presentationModel.updateDismissHandler(onDismiss)
      hostingView.refreshMenu()
    }

    func render(
      _ status: DictationCapsuleStatus,
      action: DictationCapsuleAction? = nil,
      chooser: DictationCapsuleChooser? = nil,
      coordinatorEvent: DictationCoordinatorEvent? = nil,
      onAction: @escaping @MainActor () -> Void = {},
      onChoice: @escaping @MainActor (UUID, UUID?) -> Void = { _, _ in }
    ) {
      let context = context(for: status)
      render(
        context,
        action: action,
        chooser: chooser,
        coordinatorEvent: coordinatorEvent,
        onAction: onAction,
        onChoice: onChoice
      )
    }

    func render(
      _ context: DictationCapsuleContext,
      action: DictationCapsuleAction? = nil,
      chooser: DictationCapsuleChooser? = nil,
      coordinatorEvent: DictationCoordinatorEvent? = nil,
      onAction: @escaping @MainActor () -> Void = {},
      onChoice: @escaping @MainActor (UUID, UUID?) -> Void = { _, _ in }
    ) {
      if let coordinatorEvent,
        let sessionID = coordinatorEvent.context?.sessionID,
        retiredCoordinatorSessionIDs.contains(sessionID)
      {
        guard
          sessionID == currentContext.sessionID,
          coordinatorEvent.terminal != nil || chooser != nil || context.status.isTerminalResult
        else { return }
      }
      let isSavedResult = context.status.isSavedResult
      let presentationContext = context.presentationContext()
      let presentationAction = isSavedResult ? nil : action
      let presentationChooser = isSavedResult ? nil : chooser
      let previousStatus = currentContext.status
      let previousSessionID = currentContext.sessionID
      if let eventSessionID = coordinatorEvent?.context?.sessionID,
        eventSessionID != previousSessionID
      {
        retireCoordinatorSession(previousSessionID)
      }
      let wasListening = previousStatus == .listening
      let now = monotonicNow()
      let displayedSessionID = presentationContext.sessionID
        ?? currentContext.sessionID
        ?? fleckPillModel.sessionID
      let renderedFrame = displayedSessionID.flatMap(fleckPillModel.displayedFrame(for:))
      var displayedEnergy = displayedWaveformEnergy(at: Date())
      currentContext = presentationContext
      lastCoordinatorEvent = coordinatorEvent
      if presentationContext.status == .listening {
        let isSameListeningSession = wasListening
          && previousSessionID == presentationContext.sessionID
        if !isSameListeningSession {
          waveformModel.beginListening()
          displayedEnergy = 0
        }
      } else {
        waveformModel.reset()
      }
      let reduceMotion = effectiveReduceMotion
      let visibleAction = presentationContext.status == .idle ? nil : presentationAction
      updateFleckPillPresentation(
        context: presentationContext,
        event: coordinatorEvent,
        renderedFrame: renderedFrame,
        displayedEnergy: displayedEnergy,
        now: now,
        reduceMotion: reduceMotion,
        animated: panel.isVisible
      )
      if coordinatorEvent?.terminal != nil {
        retireCoordinatorSession(coordinatorEvent?.context?.sessionID)
      }
      currentChooser = presentationChooser
      currentChoiceHandler = onChoice
      panel.allowsActions = presentationAction != nil
        || presentationChooser?.choices.isEmpty == false
        || presentationChooser?.allowsKeepInInbox == true
      presentationModel.update(
        context: presentationContext,
        action: visibleAction,
        onAction: onAction,
        chooser: presentationChooser,
        onChoice: { [weak self] captureID, noteID in
          self?.selectRoutingChoice(captureID: captureID, noteID: noteID)
        }
      )
      hostingView.refreshMenu()
      panel.hasShadow = !fleckPillModel.isVisible
      applyCurrentFrame(
        animated: panel.isVisible,
        from: previousStatus
      )
      panel.orderFrontRegardless()
    }

    func setDock(_ dock: DictationCapsuleDock) {
      let dock = dock.supportedPlacement
      currentDock = dock
      presentationModel.updateDock(dock)
      let now = monotonicNow()
      updateFleckPillPresentation(
        context: currentContext,
        event: lastCoordinatorEvent,
        renderedFrame: currentContext.sessionID.flatMap(fleckPillModel.displayedFrame(for:)),
        displayedEnergy: displayedWaveformEnergy(at: Date()),
        now: now,
        reduceMotion: effectiveReduceMotion,
        animated: panel.isVisible
      )
      hostingView.refreshMenu()
      panel.hasShadow = !fleckPillModel.isVisible
      applyCurrentFrame(
        animated: panel.isVisible,
        from: currentContext.status,
        dockChange: true
      )
    }

    func updateTheme(_ theme: FleckThemeSnapshot) {
      presentationModel.updateTheme(theme)
    }

    func updateIdleAccessibilityLabel(_ label: String) {
      guard currentContext.status == .idle else { return }
      presentationModel.updateIdleAccessibilityLabel(label)
    }

    func dismiss() {
      waveformModel.reset()
      hideLivePillImmediately()
      lastCoordinatorEvent = nil
      currentChooser = nil
      currentChoiceHandler = { _, _ in }
      panel.allowsActions = false
      presentationModel.invalidatePresentation()
      dragOrigin = nil
      dragFrameOrigin = nil
      presentationModel.setDragActive(false)
      hostingView.cancelPointerGesture()
      panel.orderOut(nil)
    }

    func selectRoutingChoice(captureID: UUID, noteID: UUID?) {
      guard
        let currentChooser,
        currentChooser.captureID == captureID
      else { return }
      let isValidChoice = noteID.map { noteID in
        currentChooser.choices.contains(where: { $0.id == noteID })
      } ?? currentChooser.allowsKeepInInbox
      guard isValidChoice else { return }
      currentChoiceHandler(captureID, noteID)
    }

    func updateAudioLevel(
      _ level: Float,
      presentationGeneration: UInt64? = nil
    ) {
      guard
        currentContext.status == .listening,
        panel.isVisible,
        presentationGeneration == nil
          || presentationGeneration == self.presentationModel.presentationGeneration
      else {
        return
      }
      let now = monotonicNow()
      let waveformNow = Date()
      let reduceMotion = effectiveReduceMotion
      waveformModel.receive(
        level: level,
        now: waveformNow,
        reduceMotion: reduceMotion
      )
      if currentDock == .bottom, fleckPillModel.sessionID == currentContext.sessionID,
        let sessionID = currentContext.sessionID
      {
        fleckPillModel.presentListening(
          sessionID: sessionID,
          at: now,
          displayedEnergy: displayedWaveformEnergy(at: waveformNow),
          reduceMotion: reduceMotion
        )
      }
    }

    func updateAudioLevel(_ level: Float, generation: UInt64) {
      updateAudioLevel(level, presentationGeneration: generation)
    }

    private func updateFleckPillPresentation(
      context: DictationCapsuleContext,
      event: DictationCoordinatorEvent?,
      renderedFrame: FleckPillArtworkFrame?,
      displayedEnergy: Double,
      now: TimeInterval,
      reduceMotion: Bool,
      animated: Bool
    ) {
      guard currentDock == .bottom else {
        hideLivePillImmediately()
        return
      }
      if context.status == .idle {
        fleckPillModel.presentStandby(
          at: now,
          renderedFrame: renderedFrame,
          animated: animated,
          reduceMotion: reduceMotion
        )
        return
      }
      guard
        let event,
        event.terminal == nil,
        let sessionID = context.sessionID,
        event.context?.sessionID == sessionID
      else {
        hideLivePillImmediately()
        return
      }
      switch context.status {
      case .arming where event.phase == .arming:
        fleckPillModel.presentArming(
          sessionID: sessionID,
          at: now,
          reduceMotion: reduceMotion
        )
      case .listening:
        guard case .listening = event.phase else {
          hideLivePillImmediately()
          return
        }
        fleckPillModel.presentListening(
          sessionID: sessionID,
          at: now,
          displayedEnergy: displayedEnergy,
          reduceMotion: reduceMotion
        )
      case .finalizing where event.phase == .finalizing,
        .cleaning where event.phase == .cleaning,
        .routing where event.phase == .routing,
        .saving where event.context?.pipelineStage == .save:
        fleckPillModel.presentProcessing(
          sessionID: sessionID,
          at: now,
          renderedFrame: renderedFrame,
          displayedEnergy: displayedEnergy,
          reduceMotion: reduceMotion
        )
      default:
        hideLivePillImmediately()
      }
    }

    private func hideLivePillImmediately() {
      if fleckPillModel.isVisible { fleckPillModel.hide() }
      panel.hasShadow = true
    }

    private func advanceLivePillAnimation() {
      guard automaticallyAdvancesLivePill, fleckPillModel.needsAnimation else { return }
      let previousState = fleckPillModel.state
      let previousHost = fleckPillModel.usesFixedHost
      let now = monotonicNow()
      fleckPillModel.tick(
        at: now,
        displayedEnergy: displayedWaveformEnergy(at: Date()),
        reduceMotion: effectiveReduceMotion
      )
      if previousState != fleckPillModel.state
        || previousHost != fleckPillModel.usesFixedHost
      {
        panel.hasShadow = !fleckPillModel.isVisible
        applyCurrentFrame(animated: false, from: currentContext.status)
      }
    }

    private func retireCoordinatorSession(_ sessionID: UUID?) {
      guard let sessionID, retiredCoordinatorSessionIDs.insert(sessionID).inserted else { return }
      retiredCoordinatorSessionOrder.append(sessionID)
      if retiredCoordinatorSessionOrder.count > 64 {
        retiredCoordinatorSessionIDs.remove(retiredCoordinatorSessionOrder.removeFirst())
      }
    }

    private func displayedWaveformEnergy(at date: Date) -> Double {
      let levels = waveformModel.barLevels(at: date, reduceMotion: false)
      return Double(levels[DictationWaveformModel.barCount / 2])
    }

    private func dragChanged(to point: CGPoint) {
      guard currentContext.status == .idle else { return }
      if dragOrigin == nil {
        dragOrigin = point
        dragFrameOrigin = panel.frame.origin
        presentationModel.setDragActive(true)
      }
      guard let dragOrigin, let dragFrameOrigin else { return }
      panel.setFrameOrigin(CGPoint(
        x: dragFrameOrigin.x + point.x - dragOrigin.x,
        y: dragFrameOrigin.y + point.y - dragOrigin.y
      ))
    }

    private func dragEnded(at point: CGPoint, cancelled: Bool) {
      guard dragOrigin != nil else { return }
      let originalFrameOrigin = dragFrameOrigin
      defer {
        dragOrigin = nil
        dragFrameOrigin = nil
        presentationModel.setDragActive(false)
      }
      if cancelled, let originalFrameOrigin {
        panel.setFrameOrigin(originalFrameOrigin)
        return
      }
      guard !cancelled, currentContext.status == .idle,
        let screen = screen(containing: point) ?? resolvedScreen()
      else { return }
      selectDock(Self.nearestDock(to: point, in: screen.visibleFrame), on: screen)
    }

    nonisolated static func size(
      for status: DictationCapsuleStatus,
      measuredWidth: CGFloat? = nil,
      widthCeiling: CGFloat? = nil
    ) -> CGSize {
      let ceiling: CGSize
      switch status {
      case .idle:
        ceiling = idleSize
      case .arming:
        ceiling = startingSize
      case .listening:
        ceiling = listeningSize
      case .finalizing, .cleaning, .routing, .saving:
        ceiling = activeSize
      case .saved, .savedWithoutCleanup:
        ceiling = idleSize
      case .noSpeech:
        ceiling = noSpeechSize
      case .repairingModel:
        ceiling = repairingModelSize
      case .routingFailure, .failed:
        ceiling = failureSize
      }

      switch status {
      case .saved, .savedWithoutCleanup, .routingFailure, .failed, .noSpeech:
        guard let measuredWidth else { return ceiling }
        return CGSize(
          width: min(max(measuredWidth, 0), widthCeiling ?? ceiling.width),
          height: ceiling.height
        )
      default:
        return ceiling
      }
    }

    static func frame(
      for dock: DictationCapsuleDock,
      status: DictationCapsuleStatus,
      measuredWidth: CGFloat? = nil,
      in visibleFrame: CGRect
    ) -> CGRect {
      frame(
        for: dock,
        size: size(for: status, measuredWidth: measuredWidth),
        in: visibleFrame
      )
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

    nonisolated static func livePillFrame(in visibleFrame: CGRect) -> CGRect {
      let width = min(max(livePillHostSize.width, 0), max(visibleFrame.width, 0))
      let height = min(max(livePillHostSize.height, 0), max(visibleFrame.height, 0))
      return CGRect(
        x: visibleFrame.midX - width / 2,
        y: visibleFrame.minY,
        width: width,
        height: height
      )
    }

    static func nearestDock(
      to point: CGPoint,
      in visibleFrame: CGRect
    ) -> DictationCapsuleDock {
      .bottom
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
          failureStage: currentContext.failureStage,
          failureKind: currentContext.failureKind
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

    private func applyCurrentFrame(
      animated: Bool,
      from previousStatus: DictationCapsuleStatus,
      dockChange: Bool = false
    ) {
      guard let screen = resolvedScreen() else { return }
      currentScreen = screen
      let presentation = DictationCapsulePresentation(
        status: currentContext.status,
        action: presentationModel.action,
        chooser: currentChooser,
        context: currentContext
      )
      let usesLivePillHost = currentDock == .bottom && fleckPillModel.usesFixedHost
      let finalFrame: CGRect = usesLivePillHost
        ? Self.livePillFrame(in: screen.visibleFrame)
        : Self.frame(
          for: currentDock,
          size: Self.size(
            for: currentContext.status,
            measuredWidth: presentation.measuredWidth,
            widthCeiling: presentation.widthCeiling
          ),
          in: screen.visibleFrame
        )
      let reduceMotion = effectiveReduceMotion
      if reduceMotion {
        panel.setFrame(finalFrame, display: true)
        panel.alphaValue = 1
        guard animated else { return }
        let duration = DictationCapsuleMotion.shellDuration(
          from: previousStatus,
          to: currentContext.status,
          reduceMotion: true,
          dockChange: dockChange
        )
        guard duration > 0 else { return }
        let transition = CATransition()
        transition.type = .fade
        transition.duration = duration
        transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
        hostingView.wantsLayer = true
        hostingView.layer?.add(
          transition,
          forKey: "fleck-dictation-content-crossfade"
        )
        return
      }
      guard animated, !fleckPillModel.isVisible else {
        panel.setFrame(finalFrame, display: true)
        panel.alphaValue = 1
        return
      }
      let duration = DictationCapsuleMotion.shellDuration(
        from: previousStatus,
        to: currentContext.status,
        reduceMotion: false,
        dockChange: dockChange
      )
      guard duration > 0 else {
        panel.setFrame(finalFrame, display: true)
        panel.alphaValue = 1
        return
      }
      NSAnimationContext.runAnimationGroup { context in
        context.duration = duration
        context.timingFunction = CAMediaTimingFunction(
          name: !reduceMotion && !dockChange
            && DictationCapsuleMotion.usesTileMorph(
              from: previousStatus,
              to: currentContext.status
            )
            ? .easeInEaseOut
            : .easeOut
        )
        panel.animator().alphaValue = 1
        panel.animator().setFrame(finalFrame, display: true)
      }
    }

    private func selectDock(
      _ dock: DictationCapsuleDock,
      on screen: NSScreen? = nil
    ) {
      let dock = dock.supportedPlacement
      currentDock = dock
      if let screen { currentScreen = screen }
      presentationModel.updateDock(dock)
      let now = monotonicNow()
      updateFleckPillPresentation(
        context: currentContext,
        event: lastCoordinatorEvent,
        renderedFrame: currentContext.sessionID.flatMap(fleckPillModel.displayedFrame(for:)),
        displayedEnergy: displayedWaveformEnergy(at: Date()),
        now: now,
        reduceMotion: effectiveReduceMotion,
        animated: panel.isVisible
      )
      panel.hasShadow = !fleckPillModel.isVisible
      applyCurrentFrame(
        animated: true,
        from: currentContext.status,
        dockChange: true
      )
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
      applyCurrentFrame(
        animated: false,
        from: currentContext.status
      )
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
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @ObservedObject var model: DictationCapsulePresentationModel
    @ObservedObject var waveformModel: DictationWaveformModel
    @ObservedObject var fleckPillModel: FleckPillLivePresentationModel
    let automaticallyAdvancesLivePill: Bool
    let onLivePillAnimationFrame: @MainActor () -> Void
    let markImage: NSImage?

    private var presentation: DictationCapsulePresentation {
      DictationCapsulePresentation(
        status: model.context.status,
        action: model.action,
        chooser: model.chooser,
        context: model.context
      )
    }

    private var increaseContrast: Bool {
      model.colors.increasedContrast
        || FleckRailAccessibility.usesIncreasedContrast(colorSchemeContrast)
    }

    private var usesLivePillPrimaryContent: Bool {
      guard model.dock == .bottom, fleckPillModel.usesFixedHost else { return false }
      if model.context.status == .idle {
        return model.action == nil
      }
      return switch model.context.status {
      case .arming, .listening, .finalizing, .cleaning, .routing, .saving:
        true
      default:
        false
      }
    }

    var body: some View {
      accessibilityContent
        .onHover { isHovering in
          model.setListeningHover(
            isHovering
              && model.context.status == .listening
              && model.context.isHandsFree
          )
        }
        .background(alignment: .topLeading) {
          if automaticallyAdvancesLivePill {
            TimelineView(
              .animation(
                minimumInterval: reduceMotion ? 1 / 15 : 1 / 60,
                paused: !fleckPillModel.needsAnimation
              )
            ) { context in
              Color.clear
                .frame(width: 1, height: 1)
                .onChange(of: context.date) { _, _ in onLivePillAnimationFrame() }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
          }
        }
    }

    @ViewBuilder
    private var accessibilityContent: some View {
      let actions = FleckRailAccessibility.actions(for: model.context)
      if actions.contains(.stop) {
        shellContent
          .accessibilityAction(named: "Stop") {
            model.stopHandler()
          }
          .accessibilityAction(named: "Cancel") {
            model.cancelHandler()
          }
      } else if actions.contains(.dismiss) {
        shellContent
          .accessibilityAction(named: "Dismiss") {
            model.dismissHandler()
          }
      } else {
        shellContent
      }
    }

    private var shellContent: some View {
      railContent
        .foregroundStyle(model.colors.primaryTextColor)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
          if fleckPillModel.isVisible {
            FleckPillCanvas(
              frame: fleckPillModel.frame,
              layers: FleckPillCanvasLayers(
                rim: true,
                shoulders: !reduceTransparency,
                signal: true,
                halo: !reduceTransparency && !increaseContrast
              ),
              renderGeneration: fleckPillModel.renderGeneration,
              renderSessionID: fleckPillModel.sessionID,
              receipt: fleckPillModel.renderReceipt,
              colors: model.colors
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else {
            RoundedRectangle(
              cornerRadius: presentation.visualMode == .idle || presentation.visualMode == .arming ? 10 : 12,
              style: .continuous
            )
            .fill(model.colors.shellColor.opacity(model.colors.effectiveShellOpacity))
            .overlay {
              RoundedRectangle(
                cornerRadius: presentation.visualMode == .idle || presentation.visualMode == .arming ? 10 : 12,
                style: .continuous
              )
              .stroke(model.colors.borderColor, lineWidth: increaseContrast ? 1.5 : 0.8)
            }
            .overlay(alignment: .top) {
              Rectangle()
                .fill(model.colors.borderColor.opacity(0.22))
                .frame(height: 1)
                .padding(.horizontal, 10)
            }
          }
        }
        .overlay {
          if model.showsDockIndicators {
            FleckRailDockIndicators(colors: model.colors)
          }
        }
        .clipShape(
          RoundedRectangle(
            cornerRadius: fleckPillModel.usesFixedHost
              ? 0
              : (presentation.visualMode == .idle || presentation.visualMode == .arming ? 10 : 12),
            style: .continuous
          )
        )
        .accessibilityElement(
          children: model.action == nil && model.chooser == nil ? .ignore : .contain
        )
        .accessibilityLabel(model.voiceOverLabel)
        .accessibilityAddTraits(.isStaticText)
    }

    private struct FleckRailDockIndicators: View {
      let colors: FleckRailColors

      var body: some View {
        ZStack {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(colors.coreColor.opacity(0.48), lineWidth: 1)
            .padding(2)
          Capsule()
            .fill(colors.coreColor)
            .frame(width: 8, height: 2)
            .offset(y: 9)
        }
        .background(FleckRailFrameProbe(identifier: "fleck-dock-indicators"))
        .accessibilityHidden(true)
        .allowsHitTesting(false)
      }
    }

    @ViewBuilder
    private var railContent: some View {
      if usesLivePillPrimaryContent {
        livePillControls
      } else {
        switch model.context.status {
        case .idle:
          idleContent
        case .arming:
          startingContent
        case .listening:
          listeningContent
        case .finalizing, .cleaning, .routing, .saving:
          processingCore
        default:
          FleckRailLayout(
            order: FleckRailContentOrder.markAndContent(for: model.dock),
            spacing: 7
          ) {
            railMark
            stateContent
          }
        }
      }
    }

    @ViewBuilder
    private var livePillControls: some View {
      if model.context.status == .listening {
        TimelineView(
          .periodic(
            from: .now,
            by: DictationWaveformRefreshSchedule.interval(reduceMotion: reduceMotion)
          )
        ) { context in
          HStack {
            Spacer(minLength: 0)
            listeningActionZone(at: context.date)
          }
        }
      } else {
        Color.clear
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .accessibilityHidden(true)
          .allowsHitTesting(false)
      }
    }

    private var idleContent: some View {
      identityMark
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var identityMark: some View {
      FleckRailIdentityMark(image: markImage, color: model.colors.coreColor)
    }

    private var startingContent: some View {
      FleckRailLayout(
        order: FleckRailContentOrder.markAndContent(for: model.dock),
        spacing: 7
      ) {
        identityMark
        Text(presentation.visibleText ?? "")
          .font(.system(size: 12, weight: .medium, design: .default))
          .lineLimit(1)
          .foregroundStyle(model.colors.primaryTextColor)
          .background(FleckRailFrameProbe(identifier: "fleck-rail-starting-text"))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var railMark: some View {
      if usesProgressRail {
        progressMark
      } else {
        identityMark
      }
    }

    private var progressMark: some View {
      FleckRailMark(
        color: model.colors.coreColor,
        activeTile: model.context.status == .arming ? 0 : nil,
        layout: usesProgressRail ? .rail(reversed: model.dock == .right) : .mark,
        treatments: usesProgressRail ? presentation.stageTreatments : [],
        colors: model.colors
      )
      .animation(
        reduceMotion ? nil : .easeInOut(duration: DictationCapsuleMotion.tileMorph),
        value: usesProgressRail
      )
      .animation(
        reduceMotion ? nil : .easeInOut(duration: DictationCapsuleMotion.tileMorph),
        value: presentation.stageTreatments
      )
    }

    @ViewBuilder
    private var processingCore: some View {
      if model.showsProcessingLabel {
        HStack(spacing: 7) {
          if model.dock == .right {
            processingText
            progressMark
          } else {
            progressMark
            processingText
          }
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        progressMark
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }

    private var usesProgressRail: Bool {
      switch model.context.status {
      case .finalizing, .cleaning, .routing, .saving:
        true
      default:
        false
      }
    }

    @ViewBuilder
    private var stateContent: some View {
      switch model.context.status {
      case .idle, .arming:
        EmptyView()
      case .listening:
        listeningContent
      case .finalizing, .cleaning, .routing, .saving:
        processingText
      case .saved, .savedWithoutCleanup, .noSpeech, .repairingModel,
        .routingFailure, .failed:
        terminalContent
      }
    }

    private var listeningContent: some View {
      TimelineView(
        .periodic(
          from: .now,
          by: DictationWaveformRefreshSchedule.interval(reduceMotion: reduceMotion)
        )
      ) { context in
        listeningCore(at: context.date)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .accessibilityLabel("Dictation listening")
      }
    }

    private func listeningCore(at date: Date) -> some View {
      ZStack {
        waveform(at: date)
        HStack {
          if model.dock == .right {
            listeningActionZone(at: date)
            Spacer(minLength: 0)
            identityMark
          } else {
            identityMark
            Spacer(minLength: 0)
            listeningActionZone(at: date)
          }
        }
      }
    }

    private func listeningActionZone(at date: Date) -> some View {
      ZStack {
        elapsedText(at: date)
          .frame(maxWidth: .infinity, alignment: .trailing)
          .opacity(model.isListeningHover && model.context.isHandsFree ? 0 : 1)
        HStack(spacing: 2) {
          Button(action: model.stopHandler) {
            Image(systemName: "stop.fill")
              .font(.system(size: 11, weight: .semibold))
              .frame(width: 28, height: 28)
          }
            .buttonStyle(.borderless)
            .accessibilityLabel("Stop")
            .background(FleckRailInteractionProbe(region: .stop))
          Button(action: model.cancelHandler) {
            Image(systemName: "xmark")
              .font(.system(size: 11, weight: .semibold))
              .frame(width: 28, height: 28)
          }
            .buttonStyle(.borderless)
            .accessibilityLabel("Cancel")
            .background(FleckRailInteractionProbe(region: .cancel))
        }
        .opacity(model.isListeningHover && model.context.isHandsFree ? 1 : 0)
        .allowsHitTesting(model.isListeningHover && model.context.isHandsFree)
      }
      .frame(width: 58, height: 28)
      .background(FleckRailFrameProbe(identifier: "fleck-rail-timer"))
    }

    private func waveform(at date: Date) -> some View {
      HStack(alignment: .center, spacing: DictationWaveformModel.barGap) {
        ForEach(
          Array(
            waveformModel.barHeights(
              at: date,
              reduceMotion: reduceMotion
            ).enumerated()
          ),
          id: \.offset
        ) { _, height in
          Capsule()
            .fill(model.colors.liveColor)
            .frame(width: DictationWaveformModel.barWidth, height: height)
        }
      }
      .accessibilityHidden(true)
      .background(FleckRailFrameProbe(identifier: "fleck-rail-waveform"))
    }

    private func elapsedText(at date: Date) -> some View {
      Text(waveformModel.elapsedText(at: date))
        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
        .foregroundStyle(
          increaseContrast ? model.colors.primaryTextColor : model.colors.secondaryTextColor
        )
        .monospacedDigit()
        .frame(width: 34, alignment: .trailing)
        .background(FleckRailFrameProbe(identifier: "fleck-rail-elapsed"))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var processingText: some View {
      if let visibleText = presentation.visibleText {
        Text(visibleText)
          .font(.system(size: 12, weight: .medium, design: .default))
          .lineLimit(1)
          .truncationMode(.tail)
          .foregroundStyle(model.colors.primaryTextColor)
          .background(FleckRailFrameProbe(identifier: "fleck-rail-processing-text"))
          .opacity(model.showsProcessingLabel ? 1 : 0)
          .animation(
            reduceMotion
              ? .easeOut(duration: DictationCapsuleMotion.reduceMotionCrossfade)
              : .easeOut(duration: DictationCapsuleMotion.colorAndOpacity),
            value: model.showsProcessingLabel
          )
      }
    }

    @ViewBuilder
    private var terminalContent: some View {
      FleckRailTerminalLayout(
        elements: [.terminalGlyph, .statusText, .divider, .action],
        order: FleckRailContentOrder.terminalCluster(
          for: model.dock,
          includesAction: model.action != nil || model.chooser != nil
        ),
        spacing: 7
      ) {
        terminalGlyph
        terminalText
        terminalDivider
        terminalButton
      }
      .transition(
        .asymmetric(
          insertion: .opacity.animation(
            .easeOut(
              duration: reduceMotion
                ? DictationCapsuleMotion.reduceMotionCrossfade
                : DictationCapsuleMotion.result
            )
          ),
          removal: .opacity.animation(
            .easeOut(
              duration: reduceMotion
                ? DictationCapsuleMotion.reduceMotionCrossfade
                : DictationCapsuleMotion.contentExit
            )
          )
        )
      )
    }

    @ViewBuilder
    private var terminalGlyph: some View {
      if model.context.status == .noSpeech || model.context.status.isFailure {
        Image(systemName: presentation.symbolName)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(
            model.context.status == .noSpeech
              ? model.colors.warningColor
              : model.colors.failureColor
          )
          .background(FleckRailFrameProbe(identifier: "fleck-terminal-glyph"))
          .accessibilityHidden(true)
      } else if model.context.status == .repairingModel {
        Image(systemName: presentation.symbolName)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(model.colors.liveColor)
          .background(FleckRailFrameProbe(identifier: "fleck-terminal-glyph"))
          .accessibilityHidden(true)
      } else {
        Image(systemName: presentation.symbolName)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(
            model.context.status.isSavedWithoutCleanup
              ? model.colors.warningColor
              : model.colors.successColor
          )
          .background(FleckRailFrameProbe(identifier: "fleck-terminal-glyph"))
          .accessibilityHidden(true)
      }
    }

    @ViewBuilder
    private var terminalText: some View {
      if let visibleText = presentation.visibleText {
        VStack(alignment: .leading, spacing: 0) {
          Text(visibleText)
            .font(.system(size: 12, weight: .medium, design: .default))
          if let secondary = presentation.secondaryVisibleText {
            Text(secondary)
              .font(.system(size: 9.5, weight: .regular, design: .default))
              .foregroundStyle(model.colors.secondaryTextColor)
          }
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .foregroundStyle(model.colors.primaryTextColor)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FleckRailFrameProbe(identifier: "fleck-terminal-text"))
      }
    }

    @ViewBuilder
    private var terminalDivider: some View {
      if model.action != nil || model.chooser != nil {
        Rectangle()
          .fill(model.colors.secondaryTextColor.opacity(0.25))
          .frame(
            width: DictationCapsulePresentation.actionDividerSize.width,
            height: DictationCapsulePresentation.actionDividerSize.height
          )
          .background(FleckRailFrameProbe(identifier: "fleck-terminal-divider"))
          .accessibilityHidden(true)
      }
    }

    @ViewBuilder
    private var terminalButton: some View {
      HStack(spacing: 7) {
        if let action = model.action {
          Button(action.buttonTitle, action: model.actionHandler)
            .buttonStyle(.borderless)
            .font(.system(size: 11, weight: .semibold, design: .default))
            .foregroundStyle(model.colors.coreColor)
            .tint(model.colors.coreColor)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(
              width: DictationCapsulePresentation.actionWidth(for: action),
              alignment: .center
            )
            .fixedSize(horizontal: false, vertical: true)
            .background(FleckRailInteractionProbe(region: .recovery))
            .accessibilityLabel(action.accessibilityLabel)
        }
        chooserMenu
      }
      .background(FleckRailInteractionProbe(region: .recovery))
    }

    @ViewBuilder
    private var chooserMenu: some View {
      if let chooser = model.chooser, chooser.displaysMenu {
        Menu(chooser.menuTitle) {
          ForEach(chooser.choices) { choice in
            Button(choice.menuTitle) {
              model.choiceHandler(chooser.captureID, choice.id)
            }
            .accessibilityLabel(choice.accessibilityLabel)
            .accessibilityHint(choice.accessibilityHint)
          }
          if chooser.allowsKeepInInbox {
            Divider()
            Button(chooser.keepInboxTitle) {
              model.choiceHandler(chooser.captureID, nil)
            }
            .accessibilityLabel(chooser.keepInboxAccessibilityLabel)
            .accessibilityHint("Leaves this saved dictation in Inbox.")
          }
        }
        .menuStyle(.borderlessButton)
        .font(.system(size: 11, weight: .semibold))
        .background(FleckRailFrameProbe(identifier: "fleck-rail-chooser"))
        .accessibilityLabel(chooser.menuAccessibilityLabel)
        .accessibilityHint(chooser.menuAccessibilityHint)
      }
    }
  }

  private extension DictationCapsuleStatus {
    var isSavedResult: Bool {
      switch self {
      case .saved, .savedWithoutCleanup:
        true
      default:
        false
      }
    }

    var isFailure: Bool {
      if case .failed = self { return true }
      if case .routingFailure = self { return true }
      return false
    }

    var isSavedWithoutCleanup: Bool {
      if case .savedWithoutCleanup = self { return true }
      return false
    }

    var isTerminalResult: Bool {
      switch self {
      case .saved, .savedWithoutCleanup, .noSpeech, .routingFailure, .failed:
        true
      default:
        false
      }
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
    private let fleckPillModel: FleckPillLivePresentationModel
    private let inputRouter: DictationCapsuleInputRouter
    private let onDockSelected: @MainActor (DictationCapsuleDock) -> Void
    private let hostingView: DictationCapsuleEventHostingView

    init(
      model: DictationCapsulePresentationModel,
      waveformModel: DictationWaveformModel,
      fleckPillModel: FleckPillLivePresentationModel,
      markImage: NSImage?,
      inputRouter: DictationCapsuleInputRouter,
      automaticallyAdvancesLivePill: Bool,
      onDockSelected: @escaping @MainActor (DictationCapsuleDock) -> Void,
      onLivePillAnimationFrame: @escaping @MainActor () -> Void
    ) {
      self.model = model
      self.fleckPillModel = fleckPillModel
      self.inputRouter = inputRouter
      self.onDockSelected = onDockSelected
      self.hostingView = DictationCapsuleEventHostingView(
        rootView: DictationCapsuleView(
          model: model,
          waveformModel: waveformModel,
          fleckPillModel: fleckPillModel,
          automaticallyAdvancesLivePill: automaticallyAdvancesLivePill,
          onLivePillAnimationFrame: onLivePillAnimationFrame,
          markImage: markImage
        ),
        model: model,
        inputRouter: inputRouter
      )
      self.hostingView.sizingOptions = []
      super.init(frame: .zero)
      hostingView.translatesAutoresizingMaskIntoConstraints = false
      addSubview(hostingView)
      NSLayoutConstraint.activate([
        hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
        hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
        hostingView.topAnchor.constraint(equalTo: topAnchor),
        hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
      ])
      menu = makeContextMenu()
      hostingView.menu = menu
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
      let localPoint = convert(point, from: superview)
      guard bounds.contains(localPoint) else { return nil }
      if fleckPillModel.isVisible {
        let actionPoint = hostingView.convert(localPoint, from: self)
        if hostingView.actionRegion(at: actionPoint) != nil {
          return super.hitTest(point)
        }
        let shell = FleckPillGeometry.shell(expansion: fleckPillModel.frame.expansion)
        let scale = FleckPillGeometry.artworkScale
        func local(_ point: FleckPillPoint) -> NSPoint {
          let transformed = shell.shellTransform.applying(to: point)
          let x = (bounds.width - FleckPillGeometry.canvasSize.width) / 2
            + scale * (8 + transformed.x)
          let y = (bounds.height - FleckPillGeometry.canvasSize.height) / 2
            + scale * (12 + transformed.y)
          return NSPoint(x: bounds.minX + x, y: isFlipped ? bounds.minY + y : bounds.maxY - y)
        }
        let path = NSBezierPath()
        for command in shell.fill.commands {
          switch command {
          case .move(let point):
            path.move(to: local(point))
          case .line(let point):
            path.line(to: local(point))
          case .cubic(let first, let second, let end):
            path.curve(to: local(end), controlPoint1: local(first), controlPoint2: local(second))
          case .close:
            path.close()
          }
        }
        return path.contains(localPoint) ? hostingView : nil
      }
      let radius: CGFloat = model.context.status == .idle || model.context.status == .arming ? 10 : 12
      let path = NSBezierPath(
        roundedRect: bounds,
        xRadius: radius,
        yRadius: radius
      )
      return path.contains(localPoint) ? super.hitTest(point) : nil
    }

    func refreshMenu() {
      menu = makeContextMenu()
      hostingView.menu = menu
    }

    func cancelPointerGesture() {
      hostingView.cancelPointerGesture()
    }

    private func makeContextMenu() -> NSMenu {
      let menu = NSMenu()
      addItem("Open Fleck", action: #selector(openFleck), to: menu)
      addItem("Dictation History", action: #selector(openHistory), to: menu)
      addItem("Dictation Settings", action: #selector(openSettings), to: menu)
      addItem("Dock Bottom", action: #selector(dockBottom), to: menu)

      if model.context.status.isFailure || model.context.status.isTerminalResult {
        addItem("Dismiss", action: #selector(dismiss), to: menu)
      }
      if let action = model.action, action != .openHistory {
        addItem(action.title, action: #selector(recovery), to: menu)
      }
      return menu
    }

    private func addItem(_ title: String, action: Selector, to menu: NSMenu) {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }

    @objc private func openFleck() {
      inputRouter.onOpenFleck()
    }

    @objc private func openHistory() {
      inputRouter.onOpenHistory()
    }

    @objc private func openSettings() {
      inputRouter.onOpenSettings()
    }

    @objc private func dismiss() {
      inputRouter.onDismiss()
    }

    @objc private func recovery() {
      inputRouter.onRecovery()
    }

    @objc private func dockBottom() {
      onDockSelected(.bottom)
    }

  }

  @MainActor
  private final class DictationCapsuleEventHostingView: NSHostingView<DictationCapsuleView> {
    private let model: DictationCapsulePresentationModel
    private let inputRouter: DictationCapsuleInputRouter
    private var gesture = FleckRailPointerGesture()
    private var consumedGesture = false
    private var consumedRegion: FleckRailInteractionRegion?
    private weak var consumedTarget: NSView?

    init(
      rootView: DictationCapsuleView,
      model: DictationCapsulePresentationModel,
      inputRouter: DictationCapsuleInputRouter
    ) {
      self.model = model
      self.inputRouter = inputRouter
      super.init(rootView: rootView)
    }

    required init(rootView: DictationCapsuleView) {
      self.model = rootView.model
      self.inputRouter = DictationCapsuleInputRouter()
      super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
      let point = convert(event.locationInWindow, from: nil)
      let region = actionRegion(at: point)
      consumedRegion = region
      consumedGesture = region != nil
      consumedTarget = region == nil ? nil : actionTarget(at: point)
      gesture.mouseDown(at: point, consumed: consumedGesture)
    }

    override func mouseDragged(with event: NSEvent) {
      let point = convert(event.locationInWindow, from: nil)
      gesture.mouseDragged(to: point)
      if consumedGesture {
        return
      }
      guard gesture.isDragging else { return }
      let screenPoint = window?.convertPoint(toScreen: event.locationInWindow)
        ?? NSEvent.mouseLocation
      inputRouter.onDragChanged(screenPoint)
    }

    override func mouseUp(with event: NSEvent) {
      let point = convert(event.locationInWindow, from: nil)
      let wasDragging = gesture.isDragging
      let wasConsumed = consumedGesture
      let region = consumedRegion
      consumedGesture = false
      consumedRegion = nil
      let target = consumedTarget
      consumedTarget = nil
      let result = gesture.mouseUp(at: point)
      let screenPoint = window?.convertPoint(toScreen: event.locationInWindow)
        ?? NSEvent.mouseLocation
      switch result {
      case .none:
        if wasConsumed, let region, actionRegion(at: point) == region {
          forwardAction(to: target)
        }
        inputRouter.onDragEnded(screenPoint, true)
      case .primaryClick:
        inputRouter.onPrimaryClick()
      case .drag:
        if !wasDragging {
          inputRouter.onDragChanged(screenPoint)
        }
        inputRouter.onDragEnded(screenPoint, false)
      }
    }

    override func rightMouseDown(with event: NSEvent) {
      cancelPointerGesture()
      super.rightMouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
      menu
    }

    func cancelPointerGesture() {
      let wasDragging = gesture.isDragging
      consumedGesture = false
      consumedRegion = nil
      consumedTarget = nil
      gesture.cancel()
      if wasDragging {
        inputRouter.onDragEnded(NSEvent.mouseLocation, true)
      }
    }

    func actionRegion(at point: NSPoint) -> FleckRailInteractionRegion? {
      let actions = FleckRailAccessibility.actions(for: model.context)
      let regions: [FleckRailInteractionRegion] = {
        var regions: [FleckRailInteractionRegion] = []
        if actions.contains(.stop), model.isListeningHover {
          regions += [.stop, .cancel]
        }
        if (model.action != nil || model.chooser != nil), model.context.status.isTerminalResult {
          regions.append(.recovery)
        }
        return regions
      }()
      for region in regions {
        guard let probe = descendant(with: region.rawValue) else { continue }
        let frame = probe.convert(probe.bounds, to: self)
        if frame.contains(point) {
          return region
        }
      }
      return nil
    }

    private func actionTarget(at point: NSPoint) -> NSView? {
      var candidate = super.hitTest(point)
      let performClick = #selector(NSButton.performClick(_:))
      while let view = candidate {
        if view.responds(to: performClick) {
          return view
        }
        if view === self { break }
        candidate = view.superview
      }
      return nil
    }

    private func forwardAction(to target: NSView?) {
      let performClick = #selector(NSButton.performClick(_:))
      guard let target, target.responds(to: performClick) else { return }
      // SwiftUI's AppKit button owns this selector but its mouse tracking loop
      // cannot be re-entered from the persistent rail host.
      _ = target.perform(performClick, with: nil)
    }

  }

  private extension NSView {
    func descendant(with identifier: String) -> NSView? {
      for subview in subviews {
        if subview.identifier?.rawValue == identifier {
          return subview
        }
        if let descendant = subview.descendant(with: identifier) {
          return descendant
        }
      }
      return nil
    }
  }
#endif
