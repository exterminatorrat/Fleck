#if os(macOS)
  import AppKit
  import SwiftUI

  struct FleckColorHSB: Equatable {
    var hue: Double
    var saturation: Double
    var brightness: Double
  }

  enum FleckColorHex {
    static func normalized(_ value: String) -> String? {
      let digits = value.hasPrefix("#") ? String(value.dropFirst()) : value
      guard digits.count == 6,
        digits.unicodeScalars.allSatisfy({ scalar in
          (48...57).contains(scalar.value)
            || (65...70).contains(scalar.value)
            || (97...102).contains(scalar.value)
        }),
        let number = UInt64(digits, radix: 16)
      else { return nil }
      return String(format: "#%06X", number)
    }

    static func normalizedUserInput(_ value: String) -> String? {
      guard value.hasPrefix("#") else { return nil }
      return normalized(value)
    }

    static func nsColor(from value: String) -> NSColor? {
      guard let normalized = normalized(value),
        let number = UInt64(normalized.dropFirst(), radix: 16)
      else { return nil }
      return NSColor(
        srgbRed: CGFloat((number >> 16) & 0xFF) / 255,
        green: CGFloat((number >> 8) & 0xFF) / 255,
        blue: CGFloat(number & 0xFF) / 255,
        alpha: 1
      )
    }

    static func hex(from color: NSColor?) -> String? {
      guard let color = color?.usingColorSpace(.sRGB), abs(color.alphaComponent - 1) < 0.0001 else {
        return nil
      }
      return String(
        format: "#%02X%02X%02X",
        Int((color.redComponent * 255).rounded()),
        Int((color.greenComponent * 255).rounded()),
        Int((color.blueComponent * 255).rounded())
      )
    }

    static func hsb(from color: NSColor?) -> FleckColorHSB? {
      guard let color = color?.usingColorSpace(.sRGB) else { return nil }
      let red = Double(color.redComponent)
      let green = Double(color.greenComponent)
      let blue = Double(color.blueComponent)
      let maximum = max(red, green, blue)
      let minimum = min(red, green, blue)
      let delta = maximum - minimum
      let hue: Double
      if delta == 0 {
        hue = 0
      } else if maximum == red {
        hue = ((green - blue) / delta / 6).truncatingRemainder(dividingBy: 1) < 0
          ? ((green - blue) / delta / 6).truncatingRemainder(dividingBy: 1) + 1
          : (green - blue) / delta / 6
      } else if maximum == green {
        hue = ((blue - red) / delta + 2) / 6
      } else {
        hue = ((red - green) / delta + 4) / 6
      }
      return FleckColorHSB(
        hue: hue,
        saturation: maximum == 0 ? 0 : delta / maximum,
        brightness: maximum
      )
    }

    static func hex(from hsb: FleckColorHSB) -> String? {
      let hue = clamped(hsb.hue) * 6
      let saturation = clamped(hsb.saturation)
      let brightness = clamped(hsb.brightness)
      let chroma = brightness * saturation
      let secondary = chroma * (1 - abs((hue.truncatingRemainder(dividingBy: 2)) - 1))
      let match = brightness - chroma
      let rgb: (Double, Double, Double)
      switch hue {
      case 0..<1: rgb = (chroma, secondary, 0)
      case 1..<2: rgb = (secondary, chroma, 0)
      case 2..<3: rgb = (0, chroma, secondary)
      case 3..<4: rgb = (0, secondary, chroma)
      case 4..<5: rgb = (secondary, 0, chroma)
      default: rgb = (chroma, 0, secondary)
      }
      return hex(
        from: NSColor(
          srgbRed: CGFloat(rgb.0 + match),
          green: CGFloat(rgb.1 + match),
          blue: CGFloat(rgb.2 + match),
          alpha: 1
        )
      )
    }

    private static func clamped(_ value: Double) -> Double {
      guard value.isFinite else { return 0 }
      return min(max(value, 0), 1)
    }
  }

  struct FleckColorDraft: Equatable {
    private(set) var hsb: FleckColorHSB
    private(set) var hexText: String
    private(set) var isHexInvalid = false

    init(hex: String?, fallbackHex: String = "#7C6CF2") {
      let resolvedHex = hex.flatMap(FleckColorHex.normalized) ?? FleckColorHex.normalized(fallbackHex) ?? "#7C6CF2"
      let resolvedColor = FleckColorHex.nsColor(from: resolvedHex)
      hsb = FleckColorHex.hsb(from: resolvedColor) ?? FleckColorHSB(hue: 0, saturation: 0, brightness: 0)
      hexText = resolvedHex
    }

    var color: Color {
      Color(
        hue: hsb.hue,
        saturation: hsb.saturation,
        brightness: hsb.brightness
      )
    }

    var committedHex: String? {
      guard !isHexInvalid else { return nil }
      return FleckColorHex.normalizedUserInput(hexText)
    }

    mutating func setHex(_ value: String) {
      hexText = value
      guard let normalized = FleckColorHex.normalizedUserInput(value),
        let nextHSB = FleckColorHex.hsb(from: FleckColorHex.nsColor(from: normalized))
      else {
        isHexInvalid = true
        return
      }
      hsb = nextHSB
      isHexInvalid = false
    }

    mutating func setHSB(_ value: FleckColorHSB) {
      let next = FleckColorHSB(
        hue: Self.clamped(value.hue),
        saturation: Self.clamped(value.saturation),
        brightness: Self.clamped(value.brightness)
      )
      hsb = next
      hexText = FleckColorHex.hex(from: next) ?? hexText
      isHexInvalid = false
    }

    mutating func setHSB(hue: Double, saturation: Double, brightness: Double) {
      setHSB(FleckColorHSB(hue: hue, saturation: saturation, brightness: brightness))
    }

    private static func clamped(_ value: Double) -> Double {
      guard value.isFinite else { return 0 }
      return min(max(value, 0), 1)
    }
  }

  struct FleckPaletteOption: Identifiable, Equatable {
    let name: String
    let hex: String

    var id: String { hex }

    var swatchImage: NSImage? {
      guard let color = NSColor(hex: hex) else { return nil }
      let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
        color.setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
        return true
      }
      image.isTemplate = false
      return image
    }

    static func matchesPaletteColor(_ color: NSColor?, hex: String) -> Bool {
      guard let actual = sRGB8BitComponents(color),
        let expected = sRGB8BitComponents(NSColor(hex: hex))
      else { return false }
      return zip(actual, expected).allSatisfy { abs($0 - $1) <= 1 }
    }

    static func paletteName(for color: NSColor?) -> String? {
      all.first { matchesPaletteColor(color, hex: $0.hex) }?.name
    }

    private static func sRGB8BitComponents(_ color: NSColor?) -> [Int]? {
      guard let color = color?.usingColorSpace(.sRGB) else { return nil }
      return [
        Int((color.redComponent * 255).rounded()),
        Int((color.greenComponent * 255).rounded()),
        Int((color.blueComponent * 255).rounded()),
        Int((color.alphaComponent * 255).rounded()),
      ]
    }

    static let all = [
      Self(name: "Red", hex: "#FF4245"),
      Self(name: "Orange", hex: "#FF9230"),
      Self(name: "Yellow", hex: "#FFD600"),
      Self(name: "Green", hex: "#30D158"),
      Self(name: "Blue", hex: "#0091FF"),
      Self(name: "Purple", hex: "#DB34F2"),
      Self(name: "Pink", hex: "#FF375F"),
      Self(name: "Gray", hex: "#98989D"),
    ]
  }

  struct FleckColorPicker: View {
    let currentHex: String?
    let currentLabel: String?
    let resetTitle: String?
    let onCommit: (String?) -> Void
    let onCancel: () -> Void
    @State private var draft: FleckColorDraft

    init(
      currentHex: String?,
      currentLabel: String? = nil,
      resetTitle: String? = nil,
      fallbackHex: String = "#7C6CF2",
      onCommit: @escaping (String?) -> Void,
      onCancel: @escaping () -> Void
    ) {
      self.currentHex = currentHex
      self.currentLabel = currentLabel
      self.resetTitle = resetTitle
      self.onCommit = onCommit
      self.onCancel = onCancel
      _draft = State(initialValue: FleckColorDraft(hex: currentHex, fallbackHex: fallbackHex))
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 10) {
          RoundedRectangle(cornerRadius: 8)
            .fill(draft.color)
            .frame(width: 34, height: 34)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 2) {
            Text("Color")
              .font(.headline)
            Text(draft.isHexInvalid ? "Invalid hex" : (draft.committedHex ?? "Custom"))
              .font(.caption)
              .foregroundStyle(draft.isHexInvalid ? .red : .secondary)
          }
          Spacer()
        }

        if let currentLabel {
          Text("Current: \(currentLabel)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 48))], spacing: 8) {
          ForEach(FleckPaletteOption.all) { option in
            Button {
              onCommit(option.hex)
            } label: {
              VStack(spacing: 4) {
                Circle()
                  .fill(Color(hex: option.hex) ?? .accentColor)
                  .frame(width: 24, height: 24)
                Text(option.name)
                  .font(.caption2)
              }
              .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(option.name)
            .accessibilityValue(draft.committedHex == option.hex ? "Selected" : "")
          }
        }

        Group {
          Slider(value: hsbBinding(\.hue), in: 0...1) {
            Text("Hue")
          } minimumValueLabel: {
            Text("0")
          } maximumValueLabel: {
            Text("1")
          }
          .accessibilityValue(String(format: "%.2f", draft.hsb.hue))
          Slider(value: hsbBinding(\.saturation), in: 0...1) {
            Text("Saturation")
          } minimumValueLabel: {
            Text("0")
          } maximumValueLabel: {
            Text("1")
          }
          .accessibilityValue(String(format: "%.2f", draft.hsb.saturation))
          Slider(value: hsbBinding(\.brightness), in: 0...1) {
            Text("Brightness")
          } minimumValueLabel: {
            Text("0")
          } maximumValueLabel: {
            Text("1")
          }
          .accessibilityValue(String(format: "%.2f", draft.hsb.brightness))
        }

        TextField(
          "#RRGGBB",
          text: Binding(
            get: { draft.hexText },
            set: { draft.setHex($0) }
          )
        )
        .textFieldStyle(.roundedBorder)
        .accessibilityLabel("Hex color")
        .accessibilityHint("Enter a six-digit #RRGGBB value.")
        .accessibilityValue(draft.isHexInvalid ? "Invalid" : draft.hexText)

        if draft.isHexInvalid {
          Text("Enter a six-digit #RRGGBB value.")
            .font(.caption)
            .foregroundStyle(.red)
            .accessibilityLabel("Invalid hex color")
        }

        HStack {
          if let resetTitle {
            Button(resetTitle) {
              onCommit(nil)
            }
          }
          Spacer()
          Button("Cancel", role: .cancel, action: onCancel)
          Button("Apply") {
            guard let hex = draft.committedHex else { return }
            onCommit(hex)
          }
          .keyboardShortcut(.defaultAction)
          .disabled(draft.isHexInvalid)
        }
      }
      .padding(16)
      .frame(width: 300)
    }

    private func hsbBinding(_ keyPath: WritableKeyPath<FleckColorHSB, Double>) -> Binding<Double> {
      Binding(
        get: { draft.hsb[keyPath: keyPath] },
        set: { value in
          var next = draft.hsb
          next[keyPath: keyPath] = value
          draft.setHSB(next)
        }
      )
    }
  }

  extension Color {
    init?(hex: String) {
      guard let color = FleckColorHex.nsColor(from: hex) else { return nil }
      self.init(nsColor: color)
    }

    var hexString: String? {
      FleckColorHex.hex(from: NSColor(self))
    }
  }

  extension NSColor {
    convenience init?(hex: String?) {
      guard let hex, let color = FleckColorHex.nsColor(from: hex) else { return nil }
      self.init(
        srgbRed: color.redComponent,
        green: color.greenComponent,
        blue: color.blueComponent,
        alpha: color.alphaComponent
      )
    }
  }
#endif
