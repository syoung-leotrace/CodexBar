import AppKit
import CodexBarCore
import Foundation

extension StatusItemController {
    static let accountStatusItemSeparator = "\u{00B7}"

    func menuBarLayoutExtraAccountSnapshots(provider: UsageProvider) -> [(label: String, snapshot: UsageSnapshot?)] {
        guard self.settings.menuBarShowAllAccounts else { return [] }
        let accounts = self.store.tokenAccounts(for: provider)
        guard accounts.count > 1 else { return [] }
        let selectedID = self.settings.effectiveSelectedTokenAccount(for: provider)?.id ?? accounts[0].id
        let cached = self.store.validTokenAccountSnapshots(provider: provider, accounts: accounts)
        return accounts.enumerated().compactMap { index, account in
            guard account.id != selectedID else { return nil }
            let label = self.settings.hidePersonalInfo ? L("Account %d", index + 1) : account.label
            return (label, cached.first { $0.account.id == account.id }?.snapshot)
        }
    }

    func updateAccountStatusItem(
        provider: UsageProvider,
        layout: MenuBarLayout,
        icon: NSImage?,
        warningFlash: Bool,
        options: MenuBarLayoutRenderOptions)
    {
        let accounts = self.menuBarLayoutExtraAccountSnapshots(provider: provider)
        let segments = accounts.map { account in
            (
                label: account.label,
                rendered: self.menuBarLayoutRenderer.render(
                    layout: layout,
                    data: self.menuBarLayoutRenderData(
                        provider: provider,
                        snapshot: account.snapshot,
                        warningFlash: warningFlash,
                        now: options.now),
                    icon: icon,
                    options: options))
        }
        guard let rendered = Self.accountStatusItemTitle(segments) else {
            self.removeAccountStatusItem(for: provider.instanceID)
            return
        }
        let item = self.accountStatusItems[provider.instanceID] ?? self.makeAccountStatusItem(for: provider)
        guard let button = item.button else { return }
        item.length = Self.applyMenuBarLayoutContent(rendered, for: button, gap: self.settings.menuBarLayoutGap)
        button.toolTip = segments.map(\.label).joined(separator: ", ")
    }

    static func accountStatusItemTitle(
        _ segments: [(label: String, rendered: MenuBarLayoutRenderedTitle)])
        -> MenuBarLayoutRenderedTitle?
    {
        guard let first = segments.first,
              segments.allSatisfy({
                  $0.rendered.statusImage == nil && !$0.rendered.attributedTitle.string.contains("\n")
              })
        else { return nil }

        let result = NSMutableAttributedString()
        for (index, segment) in segments.enumerated() {
            let title = segment.rendered.attributedTitle
            let attributes = title.length > 0 ? title.attributes(at: title.length - 1, effectiveRange: nil) : [:]
            if index > 0 {
                result.append(NSAttributedString(string: "  ", attributes: attributes))
                if let icon = segment.rendered.leadingIcon {
                    result.append(Self.inlineIcon(icon, attributes: attributes))
                    result.append(NSAttributedString(string: "\u{2009}", attributes: attributes))
                }
            }
            result.append(title)
        }
        let separatorAttributes = result.length > 0 ? result.attributes(at: 0, effectiveRange: nil) : [:]
        if let icon = first.rendered.leadingIcon {
            result.insert(NSAttributedString(string: "\u{2009}", attributes: separatorAttributes), at: 0)
            return MenuBarLayoutRenderedTitle(
                attributedTitle: result,
                accessibilityLabel: segments
                    .map { "\($0.label): \($0.rendered.accessibilityLabel)" }
                    .joined(separator: "; "),
                leadingIcon: Self.separatorIcon(icon))
        } else {
            result.insert(NSAttributedString(
                string: "\(Self.accountStatusItemSeparator) ",
                attributes: separatorAttributes), at: 0)
        }

        return MenuBarLayoutRenderedTitle(
            attributedTitle: result,
            accessibilityLabel: segments
                .map { "\($0.label): \($0.rendered.accessibilityLabel)" }
                .joined(separator: "; "),
            leadingIcon: nil)
    }

    private static func separatorIcon(_ icon: NSImage) -> NSImage {
        let dotSize: CGFloat = 2.5
        let iconX: CGFloat = 11
        let height = max(icon.size.height, 18)
        let image = NSImage(size: NSSize(width: iconX + icon.size.width, height: height), flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 2, y: (height - dotSize) / 2, width: dotSize, height: dotSize)).fill()
            icon.draw(in: NSRect(x: iconX, y: (height - icon.size.height) / 2,
                                 width: icon.size.width, height: icon.size.height))
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func inlineIcon(_ icon: NSImage, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let tint = attributes[.foregroundColor] as? NSColor ?? .controlTextColor
        let capHeight = (attributes[.font] as? NSFont)?.capHeight ?? icon.size.height
        let attachment = NSTextAttachment()
        attachment.image = MenuBarLayoutRenderer.attachmentImage(icon, tint: tint)
        attachment.bounds = NSRect(
            x: 0,
            y: ((capHeight - icon.size.height) / 2).rounded(),
            width: icon.size.width,
            height: icon.size.height)
        return NSAttributedString(attachment: attachment)
    }

    private func makeAccountStatusItem(for provider: UsageProvider) -> NSStatusItem {
        let autosaveName = "codexbar-\(provider.rawValue)-extra-accounts"
        let key = MenuBarStatusItemPlacementPreflight.preferredPositionKey(autosaveName: autosaveName)
        if self.settings.userDefaults.object(forKey: key) == nil {
            self.settings.userDefaults.set(1, forKey: key)
        }
        let item = self.statusBar.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = autosaveName
        if let button = item.button {
            button.imageScaling = .scaleNone
            button.setAccessibilityIdentifier("\(Self.statusItemAccessibilityIdentifierPrefix).\(autosaveName)")
            button.target = self
            button.action = #selector(self.accountStatusItemClicked(_:))
            button.identifier = NSUserInterfaceItemIdentifier(provider.rawValue)
        }
        self.accountStatusItems[provider.instanceID] = item
        return item
    }

    @objc private func accountStatusItemClicked(_ sender: NSStatusBarButton) {
        guard let raw = sender.identifier?.rawValue, let provider = UsageProvider(rawValue: raw) else { return }
        self.statusItems[provider.instanceID]?.button?.performClick(nil)
    }

    func removeAccountStatusItem(for instanceID: ProviderInstanceID) {
        guard let item = self.accountStatusItems.removeValue(forKey: instanceID) else { return }
        self.statusBar.removeStatusItem(item)
    }

    func storedMenuBarLayoutAccountsSignature(for provider: UsageProvider) -> String? {
        let accounts = self.menuBarLayoutExtraAccountSnapshots(provider: provider)
        guard !accounts.isEmpty else { return nil }
        var hasher = Hasher()
        for account in accounts {
            hasher.combine(account.label)
            hasher.combine(account.snapshot?.updatedAt)
            hasher.combine(account.snapshot?.primary?.usedPercent)
            hasher.combine(account.snapshot?.secondary?.usedPercent)
        }
        return String(hasher.finalize())
    }
}
