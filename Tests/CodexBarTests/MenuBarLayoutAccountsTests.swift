import AppKit
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct MenuBarLayoutAccountsTests {
    private func rendered(_ text: String, statusImage: NSImage? = nil) -> MenuBarLayoutRenderedTitle {
        MenuBarLayoutRenderedTitle(
            attributedTitle: NSAttributedString(string: text),
            accessibilityLabel: "Weekly \(text)",
            leadingIcon: nil,
            statusImage: statusImage)
    }

    @Test
    func `combines each account behind its initial`() throws {
        // Arrange
        let segments = [
            MenuBarLayoutAccountSegment(label: "Work", rendered: self.rendered("100%")),
            MenuBarLayoutAccountSegment(label: "personal", rendered: self.rendered("12%")),
        ]

        // Act
        let combined = try #require(StatusItemController.combinedMenuBarLayoutAccounts(segments))

        // Assert
        #expect(combined.attributedTitle.string == "W\u{2009}100%  P\u{2009}12%")
        #expect(combined.accessibilityLabel == "Work: Weekly 100%; personal: Weekly 12%")
    }

    @Test
    func `places the initial after an inline icon`() throws {
        // Arrange
        let segments = [
            MenuBarLayoutAccountSegment(label: "Work", rendered: self.rendered("\u{FFFC}\u{2009}100%")),
            MenuBarLayoutAccountSegment(label: "Personal", rendered: self.rendered("12%")),
        ]

        // Act
        let combined = try #require(StatusItemController.combinedMenuBarLayoutAccounts(segments))

        // Assert
        #expect(combined.attributedTitle.string == "\u{FFFC}\u{2009}W\u{2009}100%  P\u{2009}12%")
    }

    @Test
    func `falls back for a single account or stacked layouts`() {
        // Arrange
        let single = [MenuBarLayoutAccountSegment(label: "Work", rendered: self.rendered("100%"))]
        let stacked = [
            MenuBarLayoutAccountSegment(label: "Work", rendered: self.rendered("S 1%\nW 100%")),
            MenuBarLayoutAccountSegment(label: "Personal", rendered: self.rendered("12%")),
        ]

        // Act
        let singleResult = StatusItemController.combinedMenuBarLayoutAccounts(single)
        let stackedResult = StatusItemController.combinedMenuBarLayoutAccounts(stacked)

        // Assert
        #expect(singleResult == nil)
        #expect(stackedResult == nil)
    }
}
