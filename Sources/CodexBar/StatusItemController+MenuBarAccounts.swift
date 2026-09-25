import AppKit
import CodexBarCore
import Foundation

struct MenuBarLayoutAccountSegment {
    let label: String
    let rendered: MenuBarLayoutRenderedTitle
}

extension StatusItemController {
    func menuBarLayoutAccountSnapshots(provider: UsageProvider) -> [(label: String, snapshot: UsageSnapshot?)]? {
        guard self.settings.menuBarShowAllAccounts else { return nil }
        let accounts = self.store.tokenAccounts(for: provider)
        guard accounts.count > 1 else { return nil }
        let cached = self.store.validTokenAccountSnapshots(provider: provider, accounts: accounts)
        guard !cached.isEmpty else { return nil }
        return accounts.enumerated().map { index, account in
            let label = self.settings.hidePersonalInfo ? "\(index + 1)" : account.label
            return (label, cached.first { $0.account.id == account.id }?.snapshot)
        }
    }

    func renderMenuBarLayoutAccounts(
        provider: UsageProvider,
        layout: MenuBarLayout,
        icon: NSImage?,
        warningFlash: Bool,
        options: MenuBarLayoutRenderOptions)
        -> MenuBarLayoutRenderedTitle?
    {
        guard let accounts = self.menuBarLayoutAccountSnapshots(provider: provider) else { return nil }
        let segments = accounts.map { account in
            let data = self.menuBarLayoutRenderData(
                provider: provider,
                snapshot: account.snapshot,
                warningFlash: warningFlash,
                now: options.now)
            return MenuBarLayoutAccountSegment(
                label: account.label,
                rendered: self.menuBarLayoutRenderer.render(
                    layout: layout,
                    data: data,
                    icon: icon,
                    options: options))
        }
        return Self.combinedMenuBarLayoutAccounts(segments)
    }

    static func menuBarAccountInitial(_ label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first.map { String($0).uppercased() } ?? "?"
    }

    static func combinedMenuBarLayoutAccounts(_ segments: [MenuBarLayoutAccountSegment])
    -> MenuBarLayoutRenderedTitle? {
        guard segments.count > 1,
              segments.allSatisfy({
                  $0.rendered.statusImage == nil && !$0.rendered.attributedTitle.string.contains("\n")
              })
        else { return nil }

        let attachmentCharacter = "\u{FFFC}"
        let result = NSMutableAttributedString()
        for (index, segment) in segments.enumerated() {
            let title = segment.rendered.attributedTitle
            let attributes = title.length > 0 ? title.attributes(at: title.length - 1, effectiveRange: nil) : [:]
            let initial = Self.menuBarAccountInitial(segment.label)
            if index > 0 {
                result.append(NSAttributedString(string: "  ", attributes: attributes))
            }
            let piece = NSMutableAttributedString(attributedString: title)
            if index > 0, let icon = segment.rendered.leadingIcon {
                let attachment = NSTextAttachment()
                let tint = attributes[.foregroundColor] as? NSColor ?? .controlTextColor
                let capHeight = (attributes[.font] as? NSFont)?.capHeight ?? icon.size.height
                attachment.image = MenuBarLayoutRenderer.attachmentImage(icon, tint: tint)
                attachment.bounds = NSRect(
                    x: 0,
                    y: ((capHeight - icon.size.height) / 2).rounded(),
                    width: icon.size.width,
                    height: icon.size.height)
                piece.insert(NSAttributedString(string: "\u{2009}", attributes: attributes), at: 0)
                piece.insert(NSAttributedString(attachment: attachment), at: 0)
            }
            if piece.string.hasPrefix(attachmentCharacter) {
                piece.insert(NSAttributedString(string: "\u{2009}\(initial)", attributes: attributes), at: 1)
            } else {
                piece.insert(NSAttributedString(string: "\(initial)\u{2009}", attributes: attributes), at: 0)
            }
            result.append(piece)
        }

        let accessibilityLabel = segments
            .map { "\($0.label): \($0.rendered.accessibilityLabel)" }
            .joined(separator: "; ")
        return MenuBarLayoutRenderedTitle(
            attributedTitle: result,
            accessibilityLabel: accessibilityLabel,
            leadingIcon: segments[0].rendered.leadingIcon)
    }

    func storedMenuBarLayoutAccountsSignature(for provider: UsageProvider) -> String? {
        guard let accounts = self.menuBarLayoutAccountSnapshots(provider: provider) else { return nil }
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
