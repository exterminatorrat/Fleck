import AppKit
import SwiftUI
import Testing

@testable import FleckApp

@Test @MainActor func toolbarOverflowHostedFixtureUsesMeasuredExactAndOnePointBounds() async throws {
  let fixture = HostedToolbarOverflowFixture(itemWidths: [20, 20, 20, 20])
  defer { fixture.close() }
  let expectations: [(width: CGFloat, visibleCount: Int)] = [
    (160, 4), (137, 4), (136, 3),
    (127, 3), (126, 2),
    (103, 2), (102, 1),
    (74, 1), (73, 0), (50, 0),
  ]

  for expectation in expectations {
    let elements = await fixture.elements(at: expectation.width)
    let visibleLabels = (0..<expectation.visibleCount).map { "Item \($0)" }
    let expectedLabels = visibleLabels
      + (expectation.visibleCount == 4 ? [] : ["More formatting"])
      + ["Delete"]
    #expect(elements.map(\.label) == expectedLabels)
    #expect(Set(elements.map(\.label)).count == elements.count)
    #expect((expectation.visibleCount..<4).allSatisfy { hiddenIndex in
      !elements.contains(where: { $0.label == "Item \(hiddenIndex)" })
    })
    #expect(zip(elements, elements.dropFirst()).allSatisfy {
      $0.frame.minX < $1.frame.minX
    })
    let delete = try #require(elements.last)
    #expect(delete.label == "Delete")
    #expect(abs(delete.frame.maxX - fixture.expectedTrailingEdge) <= 0.5)
  }
}

@Test @MainActor func toolbarOverflowHostedFixtureRespondsToIntrinsicWidthAndIsMonotonic() async {
  let fixture = HostedToolbarOverflowFixture(itemWidths: [20, 20, 20, 20])
  defer { fixture.close() }

  let normal = await fixture.visibleCount(at: 127)
  fixture.update(itemWidths: [20, 36, 20, 20])
  let widerItem = await fixture.visibleCount(at: 127)
  #expect(normal == 3)
  #expect(widerItem == 2)

  fixture.update(itemWidths: [20, 20, 20, 20])
  var growing: [Int] = []
  for width in stride(from: CGFloat(50), through: 137, by: 1) {
    growing.append(await fixture.visibleCount(at: width))
  }
  #expect(zip(growing, growing.dropFirst()).allSatisfy { $1 >= $0 })
  #expect(Set(growing) == Set(0...4))

  var shrinking: [Int] = []
  for width in stride(from: CGFloat(137), through: 50, by: -1) {
    shrinking.append(await fixture.visibleCount(at: width))
  }
  #expect(zip(shrinking, shrinking.dropFirst()).allSatisfy { $1 <= $0 })
}

@Test func toolbarOverflowCandidatesRunFromAllVisibleToEllipsisOnly() {
  #expect(FormattingToolbarOverflowPolicy.candidateVisibleCounts(itemCount: 4) == [4, 3, 2, 1, 0])
  #expect(FormattingToolbarOverflowPolicy.candidateVisibleCounts(itemCount: 0) == [0])
}

private struct HostedToolbarOverflowView: View {
  let itemWidths: [CGFloat]

  var body: some View {
    MeasuredTrailingToolbarOverflow(
      itemCount: itemWidths.count,
      minimumTrailingSpacing: 4
    ) { visible, overflow in
      HStack(spacing: 4) {
        ForEach(Array(visible), id: \.self) { index in
          if index == 1 {
            Divider().frame(width: 1, height: 12)
          } else if index == 3 {
            Divider().frame(width: 2, height: 12)
          }
          Button("Item \(index)") {}
            .buttonStyle(.plain)
            .frame(width: itemWidths[index], height: 20)
            .accessibilityLabel("Item \(index)")
        }
        if !overflow.isEmpty {
          Button("More formatting") {}
            .buttonStyle(.plain)
            .frame(width: 16, height: 20)
            .accessibilityLabel("More formatting")
        }
      }
    } trailing: {
      Button("Delete") {}
        .buttonStyle(.plain)
        .frame(width: 20, height: 20)
        .accessibilityLabel("Delete")
    }
    .padding(.horizontal, 5)
  }
}

@MainActor
private final class HostedToolbarOverflowFixture {
  struct Element {
    let label: String
    let frame: CGRect
  }

  private let window: NSWindow
  private let host: NSHostingView<HostedToolbarOverflowView>

  var expectedTrailingEdge: CGFloat {
    window.convertToScreen(window.contentView?.bounds ?? .zero).maxX - 5
  }

  init(itemWidths: [CGFloat]) {
    NSApplication.shared.accessibilitySetValue(
      true,
      forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
    )
    host = NSHostingView(rootView: HostedToolbarOverflowView(itemWidths: itemWidths))
    window = NSWindow(
      contentRect: CGRect(x: 100, y: 100, width: 200, height: 40),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    window.contentView = host
    window.orderFront(nil)
  }

  func update(itemWidths: [CGFloat]) {
    host.rootView = HostedToolbarOverflowView(itemWidths: itemWidths)
  }

  func elements(at width: CGFloat) async -> [Element] {
    window.setContentSize(CGSize(width: width, height: 40))
    for _ in 0..<4 {
      host.layoutSubtreeIfNeeded()
      await Task.yield()
    }
    let labels = (0..<4).map { "Item \($0)" } + ["More formatting", "Delete"]
    return labels.compactMap { label in
      guard let object = accessibilityElement(in: host, label: label),
        let frame = object.value(forKey: "accessibilityFrame") as? NSValue
      else { return nil }
      return Element(label: label, frame: frame.rectValue)
    }.sorted { $0.frame.minX < $1.frame.minX }
  }

  func visibleCount(at width: CGFloat) async -> Int {
    await elements(at: width).filter { $0.label.hasPrefix("Item ") }.count
  }

  func close() {
    window.contentView = nil
    window.orderOut(nil)
  }

  private func accessibilityElement(in value: Any, label: String) -> NSObject? {
    guard let element = value as? NSObject else { return nil }
    let labelSelector = NSSelectorFromString("accessibilityLabel")
    let childrenSelector = NSSelectorFromString("accessibilityChildren")
    let name = element.responds(to: labelSelector)
      ? element.perform(labelSelector)?.takeUnretainedValue() as? String : nil
    if name == label { return element }
    let children = element.responds(to: childrenSelector)
      ? element.perform(childrenSelector)?.takeUnretainedValue() as? [Any] : nil
    for child in children ?? [] {
      if let match = accessibilityElement(in: child, label: label) { return match }
    }
    return nil
  }
}
