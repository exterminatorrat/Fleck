#if os(macOS)
  import SwiftUI

  struct SettingsDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
      VStack(alignment: .leading, spacing: 0) {
        Button {
          configuration.isExpanded.toggle()
        } label: {
          HStack(spacing: 8) {
            Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
              .font(.system(size: 9, weight: .semibold))
              .frame(width: 8)
              .accessibilityHidden(true)
            configuration.label
            Spacer(minLength: 0)
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 6)
          .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")

        if configuration.isExpanded {
          configuration.content
        }
      }
    }
  }
#endif
