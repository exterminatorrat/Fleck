#if os(macOS)
  import SwiftUI

  enum FormattingToolbarItem: Int, CaseIterable, Identifiable {
    case dictation
    case undo
    case redo
    case bold
    case italic
    case underline
    case strikethrough
    case font
    case fontSize
    case fontColor
    case highlight
    case bullets
    case numbers
    case checklist
    case textStyles
    case text
    case paragraph
    case tools
    case delete

    var id: Self { self }

    var hasSeparatorBefore: Bool {
      self == .undo || self == .bold || self == .textStyles || self == .text
        || self == .paragraph || self == .tools
    }
  }

  enum FormattingToolbarOverflowPolicy {
    static func candidateVisibleCounts(itemCount: Int) -> [Int] {
      Array(stride(from: max(itemCount, 0), through: 0, by: -1))
    }

    static func visibleCount(
      itemWidths: [CGFloat],
      overflowWidth: CGFloat,
      spacing: CGFloat,
      available: CGFloat
    ) -> Int {
      var prefixWidths: [CGFloat] = [0]
      for (index, width) in itemWidths.enumerated() {
        prefixWidths.append(prefixWidths[index] + width + (index == 0 ? 0 : spacing))
      }
      return candidateVisibleCounts(itemCount: itemWidths.count).first { count in
        let extras = count == itemWidths.count ? 0 : overflowWidth + (count == 0 ? 0 : spacing)
        return prefixWidths[count] + extras <= available
      } ?? 0
    }
  }

  private struct FormattingToolbarWidths: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
      value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
  }

  struct MeasuredTrailingToolbarOverflow<Item: View, Overflow: View, Trailing: View>: View {
    let itemCount: Int
    let spacing: CGFloat
    let minimumTrailingSpacing: CGFloat
    let onVisibleCountChange: (Int) -> Void
    @ViewBuilder let item: (Int, Bool) -> Item
    @ViewBuilder let overflow: (Range<Int>) -> Overflow
    @ViewBuilder let trailing: (Bool) -> Trailing
    @State private var widths: [Int: CGFloat] = [:]

    init(
      itemCount: Int,
      spacing: CGFloat,
      minimumTrailingSpacing: CGFloat,
      onVisibleCountChange: @escaping (Int) -> Void = { _ in },
      @ViewBuilder item: @escaping (Int, Bool) -> Item,
      @ViewBuilder overflow: @escaping (Range<Int>) -> Overflow,
      @ViewBuilder trailing: @escaping (Bool) -> Trailing
    ) {
      self.itemCount = itemCount
      self.spacing = spacing
      self.minimumTrailingSpacing = minimumTrailingSpacing
      self.onVisibleCountChange = onVisibleCountChange
      self.item = item
      self.overflow = overflow
      self.trailing = trailing
    }

    var body: some View {
      GeometryReader { geometry in
        let count = visibleCount(at: geometry.size.width)
        HStack(spacing: 0) {
          HStack(spacing: spacing) {
            ForEach(0..<count, id: \.self) { item($0, false) }
            if count < itemCount { overflow(count..<itemCount) }
          }
          .fixedSize(horizontal: true, vertical: false)
          Spacer(minLength: minimumTrailingSpacing)
          trailing(false).fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxHeight: .infinity)
        .onChange(of: count, initial: true) { _, count in onVisibleCountChange(count) }
      }
      .background(alignment: .leading) {
        HStack(spacing: 0) {
          ForEach(0..<itemCount, id: \.self) { index in
            measure(index, item(index, true))
          }
          if itemCount > 0 { measure(itemCount, overflow(0..<itemCount)) }
          measure(itemCount + 1, trailing(true))
        }
        .fixedSize(horizontal: true, vertical: false)
        .disabled(true)
        .hidden()
        .accessibilityHidden(true)
      }
      .onPreferenceChange(FormattingToolbarWidths.self) { widths = $0 }
    }

    private func measure<Content: View>(_ index: Int, _ content: Content) -> some View {
      content.fixedSize(horizontal: true, vertical: false).background {
        GeometryReader { geometry in
          Color.clear.preference(key: FormattingToolbarWidths.self, value: [index: geometry.size.width])
        }
      }
    }

    private func visibleCount(at width: CGFloat) -> Int {
      let itemWidths = (0..<itemCount).compactMap { widths[$0] }
      guard itemWidths.count == itemCount,
        let overflowWidth = widths[itemCount], let trailingWidth = widths[itemCount + 1]
      else { return 0 }
      return FormattingToolbarOverflowPolicy.visibleCount(
        itemWidths: itemWidths, overflowWidth: overflowWidth, spacing: spacing,
        available: width - trailingWidth - minimumTrailingSpacing
      )
    }
  }
#endif
