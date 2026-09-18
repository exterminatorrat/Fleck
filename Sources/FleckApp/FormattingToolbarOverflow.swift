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
  }

  private struct FormattingToolbarVisibleCountPreferenceKey: PreferenceKey {
    static let defaultValue: Int? = nil

    static func reduce(value: inout Int?, nextValue: () -> Int?) {
      value = nextValue() ?? value
    }
  }

  struct MeasuredTrailingToolbarOverflow<Content: View, Trailing: View>: View {
    let itemCount: Int
    let minimumTrailingSpacing: CGFloat
    let onVisibleCountChange: (Int) -> Void
    @ViewBuilder let content: (Range<Int>, Range<Int>) -> Content
    @ViewBuilder let trailing: () -> Trailing

    init(
      itemCount: Int,
      minimumTrailingSpacing: CGFloat,
      onVisibleCountChange: @escaping (Int) -> Void = { _ in },
      @ViewBuilder content: @escaping (Range<Int>, Range<Int>) -> Content,
      @ViewBuilder trailing: @escaping () -> Trailing
    ) {
      self.itemCount = itemCount
      self.minimumTrailingSpacing = minimumTrailingSpacing
      self.onVisibleCountChange = onVisibleCountChange
      self.content = content
      self.trailing = trailing
    }

    var body: some View {
      HStack(spacing: 0) {
        ViewThatFits(in: .horizontal) {
          ForEach(
            FormattingToolbarOverflowPolicy.candidateVisibleCounts(itemCount: itemCount),
            id: \.self
          ) { visibleCount in
            content(0..<visibleCount, visibleCount..<itemCount)
              .fixedSize(horizontal: true, vertical: false)
              .preference(
                key: FormattingToolbarVisibleCountPreferenceKey.self,
                value: visibleCount
              )
          }
        }
        Spacer(minLength: minimumTrailingSpacing)
        trailing()
          .fixedSize(horizontal: true, vertical: false)
      }
      .onPreferenceChange(FormattingToolbarVisibleCountPreferenceKey.self) { visibleCount in
        if let visibleCount { onVisibleCountChange(visibleCount) }
      }
    }
  }
#endif
