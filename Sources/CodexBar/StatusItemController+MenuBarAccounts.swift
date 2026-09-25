import AppKit
import CodexBarCore
import Foundation

struct MenuBarLayoutAccountSegment {
    let label: String
    let rendered: MenuBarLayoutRenderedTitle
}

extension StatusItemController {
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

    func menuBarLayoutExtraAccountSegments(
        provider: UsageProvider,
        layout: MenuBarLayout,
        icon: NSImage?,
        warningFlash: Bool,
        options: MenuBarLayoutRenderOptions)
        -> [MenuBarLayoutAccountSegment]
    {
        self.menuBarLayoutExtraAccountSnapshots(provider: provider).map { account in
            MenuBarLayoutAccountSegment(
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
    }

    static func appendingMenuBarLayoutAccounts(
        to base: MenuBarLayoutRenderedTitle,
        segments: [MenuBarLayoutAccountSegment])
        -> MenuBarLayoutRenderedTitle?
    {
        guard !segments.isEmpty,
              base.statusImage == nil,
              !base.attributedTitle.string.contains("\n"),
              segments.allSatisfy({
                  $0.rendered.statusImage == nil && !$0.rendered.attributedTitle.string.contains("\n")
              })
        else { return nil }

        let result = NSMutableAttributedString(attributedString: base.attributedTitle)
        for (index, segment) in segments.enumerated() {
            let title = segment.rendered.attributedTitle
            let attributes = title.length > 0 ? title.attributes(at: title.length - 1, effectiveRange: nil) : [:]
            result.append(NSAttributedString(string: index == 0 ? "  ·  " : "  ", attributes: attributes))
            if let icon = segment.rendered.leadingIcon {
                result.append(Self.inlineIcon(icon, attributes: attributes))
                result.append(NSAttributedString(string: "\u{2009}", attributes: attributes))
            }
            result.append(title)
        }

        return MenuBarLayoutRenderedTitle(
            attributedTitle: result,
            accessibilityLabel: ([base.accessibilityLabel] + segments.map {
                "\($0.label): \($0.rendered.accessibilityLabel)"
            }).joined(separator: "; "),
            leadingIcon: base.leadingIcon)
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
