import AppKit
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct MenuBarLayoutAccountsTests {
    private func rendered(
        _ text: String,
        icon: NSImage? = nil,
        statusImage: NSImage? = nil)
        -> MenuBarLayoutRenderedTitle
    {
        MenuBarLayoutRenderedTitle(
            attributedTitle: NSAttributedString(string: text),
            accessibilityLabel: "Weekly \(text)",
            leadingIcon: icon,
            statusImage: statusImage)
    }

    @Test
    func `puts the dot before the personal Claude icon without account initials`() throws {
        // Arrange
        let icon = NSImage(size: NSSize(width: 12, height: 12))
        let segments = [(label: "Personal", rendered: self.rendered("12%", icon: icon))]

        // Act
        let title = try #require(StatusItemController.accountStatusItemTitle(segments))

        // Assert
        #expect(title.attributedTitle.string == "\u{00B7} \u{FFFC}\u{2009}12%")
        #expect(title.accessibilityLabel == "Personal: Weekly 12%")
        #expect(title.leadingIcon == nil)
    }

    @Test
    func `keeps multiple extra accounts unlabeled in the title`() throws {
        // Arrange
        let segments = [
            (label: "Personal", rendered: self.rendered("12%")),
            (label: "Second", rendered: self.rendered("34%")),
        ]

        // Act
        let title = try #require(StatusItemController.accountStatusItemTitle(segments))

        // Assert
        #expect(title.attributedTitle.string == "\u{00B7} 12%  34%")
        #expect(title.accessibilityLabel == "Personal: Weekly 12%; Second: Weekly 34%")
    }

    @Test
    func `omits the extra item for unsupported layouts`() {
        // Arrange
        let empty: [(label: String, rendered: MenuBarLayoutRenderedTitle)] = []
        let stacked = [(label: "Personal", rendered: self.rendered("S 1%\nW 12%"))]
        let imageOnly = [(label: "Personal", rendered: self.rendered("", statusImage: NSImage()))]

        // Act
        let emptyResult = StatusItemController.accountStatusItemTitle(empty)
        let stackedResult = StatusItemController.accountStatusItemTitle(stacked)
        let imageResult = StatusItemController.accountStatusItemTitle(imageOnly)

        // Assert
        #expect(emptyResult == nil)
        #expect(stackedResult == nil)
        #expect(imageResult == nil)
    }
}
