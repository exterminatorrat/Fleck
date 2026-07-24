import Testing
@testable import MenuBarNotesCore

@Test func bulletListCanBeAppliedAndRemoved() {
    let source = "Milk\nBread"
    let formatted = MarkdownEditing.togglingList(in: source, style: .bullets)

    #expect(formatted == "- Milk\n- Bread")
    #expect(MarkdownEditing.togglingList(in: formatted, style: .bullets) == source)
}

@Test func numberedListRenumbersEveryLine() {
    let source = "One\nTwo\nThree"
    #expect(
        MarkdownEditing.togglingList(in: source, style: .numbers)
            == "1. One\n2. Two\n3. Three"
    )
}
