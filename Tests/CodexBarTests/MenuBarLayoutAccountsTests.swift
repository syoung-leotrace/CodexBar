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
    func `appends personal Claude after Work GPT with a dot and icon`() throws {
        // Arrange
        let workIcon = NSImage(size: NSSize(width: 12, height: 12))
        let personalIcon = NSImage(size: NSSize(width: 12, height: 12))
        let work = self.rendered("81%", icon: workIcon)
        let personal = MenuBarLayoutAccountSegment(
            label: "Personal",
            rendered: self.rendered("13%", icon: personalIcon))

        // Act
        let title = try #require(StatusItemController.appendingMenuBarLayoutAccounts(
            to: work,
            segments: [personal]))

        // Assert
        #expect(title.attributedTitle.string == "81%  ·  \u{FFFC}\u{2009}13%")
        #expect(title.accessibilityLabel == "Weekly 81%; Personal: Weekly 13%")
        #expect(title.leadingIcon === workIcon)
    }

    @Test
    func `keeps multiple extra accounts unlabeled in the title`() throws {
        // Arrange
        let work = self.rendered("81%")
        let segments = [
            MenuBarLayoutAccountSegment(label: "Personal", rendered: self.rendered("13%")),
            MenuBarLayoutAccountSegment(label: "Second", rendered: self.rendered("34%")),
        ]

        // Act
        let title = try #require(StatusItemController.appendingMenuBarLayoutAccounts(
            to: work,
            segments: segments))

        // Assert
        #expect(title.attributedTitle.string == "81%  ·  13%  34%")
        #expect(title.accessibilityLabel == "Weekly 81%; Personal: Weekly 13%; Second: Weekly 34%")
    }

    @Test
    func `omits extra accounts for unsupported layouts`() {
        // Arrange
        let work = self.rendered("81%")
        let empty: [MenuBarLayoutAccountSegment] = []
        let stacked = [MenuBarLayoutAccountSegment(label: "Personal", rendered: self.rendered("S 1%\nW 13%"))]
        let imageOnly = self.rendered("", statusImage: NSImage())

        // Act
        let emptyResult = StatusItemController.appendingMenuBarLayoutAccounts(to: work, segments: empty)
        let stackedResult = StatusItemController.appendingMenuBarLayoutAccounts(to: work, segments: stacked)
        let imageResult = StatusItemController.appendingMenuBarLayoutAccounts(
            to: imageOnly,
            segments: [MenuBarLayoutAccountSegment(label: "Personal", rendered: self.rendered("13%"))])

        // Assert
        #expect(emptyResult == nil)
        #expect(stackedResult == nil)
        #expect(imageResult == nil)
    }
}
