#if os(macOS) && DEBUG
import AppKit
import Combine
import SwiftUI

@MainActor
final class FleckPillDebugHarnessModel: ObservableObject {
  @Published private(set) var clock = FleckPillPlaybackClock()
  @Published var layers = FleckPillCanvasLayers()
  @Published var backdrop = FleckPillCanvasBackdrop.dark

  var snapshot: FleckPillPlaybackClock.Snapshot { clock.snapshot() }
  var frame: FleckPillMotionFrame { FleckPillMotion.sample(snapshot.time) }

  func togglePlayback(at timestamp: Double) {
    if snapshot.playing {
      _ = clock.pause(at: timestamp)
    } else {
      _ = clock.play(at: timestamp)
    }
  }

  func tick(at timestamp: Double) {
    _ = clock.tick(at: timestamp)
  }

  func seek(to time: Double, at timestamp: Double? = nil) {
    _ = clock.seek(to: time, at: timestamp)
  }

  func setRate(_ rate: Double, at timestamp: Double? = nil) {
    _ = clock.setRate(rate, at: timestamp)
  }

  func setLoops(_ loops: Bool) {
    _ = clock.setLoops(loops)
  }

  func step(frames: Int) {
    _ = clock.step(frames: frames)
  }

  func select(_ pose: FleckPillPose) {
    _ = clock.select(pose)
  }
}

@MainActor
struct FleckPillDebugHarness: View {
  @ObservedObject var model: FleckPillDebugHarnessModel
  var onClose: () -> Void = {}

  init(
    model: FleckPillDebugHarnessModel = FleckPillDebugHarnessModel(),
    onClose: @escaping () -> Void = {}
  ) {
    self.model = model
    self.onClose = onClose
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .center, spacing: 20) {
        FleckPillCanvas(
          frame: model.frame,
          layers: model.layers,
          backdrop: model.backdrop
        )
        .overlay(alignment: .bottom) {
          Rectangle().fill(Color.white.opacity(0.18)).frame(height: 1)
        }
        VStack(alignment: .leading, spacing: 5) {
          Text("Fleck v2 native motion")
            .font(.system(size: 13, weight: .medium))
          Text("\(model.snapshot.time, format: .number.precision(.fractionLength(3)))s · \(model.frame.label)")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        Button("Close", action: onClose)
          .accessibilityIdentifier("fleck-pill-harness-close")
      }
      HStack(spacing: 8) {
        Button(model.snapshot.playing ? "Pause" : "Play") {
          model.togglePlayback(at: timestamp())
        }
        .keyboardShortcut(.space, modifiers: [])
        .accessibilityIdentifier("fleck-pill-harness-play-pause")
        Button("−1 frame") { model.step(frames: -1) }
          .accessibilityIdentifier("fleck-pill-harness-step-back")
        Button("+1 frame") { model.step(frames: 1) }
          .accessibilityIdentifier("fleck-pill-harness-step-forward")
        Toggle("Loop", isOn: Binding(
          get: { model.snapshot.loops },
          set: { model.setLoops($0) }
        ))
        .toggleStyle(.checkbox)
        .accessibilityIdentifier("fleck-pill-harness-loop")
        Picker("Backdrop", selection: $model.backdrop) {
          Text("Dark").tag(FleckPillCanvasBackdrop.dark)
          Text("Bright").tag(FleckPillCanvasBackdrop.bright)
          Text("Clear").tag(FleckPillCanvasBackdrop.clear)
        }
        .pickerStyle(.segmented)
        .frame(width: 210)
        .accessibilityIdentifier("fleck-pill-harness-backdrop")
      }
      HStack(spacing: 12) {
        Text("Time")
        Slider(value: Binding(
          get: { model.snapshot.time },
          set: { model.seek(to: $0, at: model.snapshot.playing ? timestamp() : nil) }
        ), in: 0...FleckPillMotion.duration)
        .frame(minWidth: 220)
        .accessibilityIdentifier("fleck-pill-harness-time")
        Text("Rate")
        Slider(value: Binding(
          get: { model.snapshot.rate },
          set: { model.setRate($0, at: model.snapshot.playing ? timestamp() : nil) }
        ), in: 0.1...2)
        .frame(width: 110)
        .accessibilityIdentifier("fleck-pill-harness-rate")
        Text("\(model.snapshot.rate, format: .number.precision(.fractionLength(1)))×")
          .frame(width: 34, alignment: .trailing)
      }
      HStack(spacing: 7) {
        ForEach(FleckPillPose.allCases, id: \.rawValue) { pose in
          Button(pose.rawValue.capitalized) { model.select(pose) }
            .accessibilityIdentifier("fleck-pill-harness-pose-\(pose.rawValue)")
        }
        Spacer()
        Toggle("Rim", isOn: $model.layers.rim)
        Toggle("Shoulders", isOn: $model.layers.shoulders)
        Toggle("Signal", isOn: $model.layers.signal)
        Toggle("Halo", isOn: $model.layers.halo)
      }
      .toggleStyle(.checkbox)
      Text("Synthetic fixture playback only. No microphone, live audio, or production feedback wiring.")
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }
    .padding(18)
    .frame(minWidth: 560, alignment: .leading)
    .background(alignment: .topLeading) {
      TimelineView(.animation(minimumInterval: 1 / 60, paused: !model.snapshot.playing)) { timeline in
        Color.clear
          .frame(width: 1, height: 1)
          .onChange(of: timeline.date) { _, _ in model.tick(at: timestamp()) }
      }
      .allowsHitTesting(false)
    }
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private func timestamp() -> Double {
    ProcessInfo.processInfo.systemUptime * 1_000
  }
}

@MainActor
enum FleckPillDebugHarnessPresenter {
  private static let panel: DictationCapsulePanel = {
    let panel = DictationCapsulePanel()
    panel.title = "Fleck v2 native motion"
    panel.hasShadow = true
    panel.ignoresMouseEvents = false
    panel.setContentSize(NSSize(width: 720, height: 230))
    return panel
  }()

  static func open() {
    if panel.contentView == nil {
      let harnessPanel = panel
      let view = FleckPillDebugHarness(onClose: { [weak harnessPanel] in
        harnessPanel?.orderOut(nil)
      })
      panel.contentView = NSHostingView(rootView: view)
    }
    panel.center()
    panel.orderFrontRegardless()
  }
}
#endif
