import ApplicationServices
import Foundation

public actor DockItemInspector {
    public static let messagingTimeout: Float = 2
    public static let itemLimit = 256

    private static let statusLabelAttribute = "AXStatusLabel"
    private static let urlAttribute = "AXURL"
    private static let runningAttribute = "AXIsApplicationRunning"
    private static let dockItemRole = "AXDockItem"

    public init() {}

    public func read(processIdentifier: pid_t) -> DockItemList {
        guard AccessibilityAuthorization.isTrusted else { return .empty }
        let application = AXElement.application(processIdentifier, messagingTimeout: Self.messagingTimeout)
        guard let list = itemList(of: application) else { return .empty }

        var items: [DockItem] = []
        for (index, element) in list.children(kAXChildrenAttribute).prefix(Self.itemLimit).enumerated() {
            guard element.string(kAXRoleAttribute) == Self.dockItemRole else { continue }
            items.append(
                DockItem(
                    index: index,
                    kind: DockItemKind(subrole: element.string(kAXSubroleAttribute)),
                    title: element.string(kAXTitleAttribute),
                    badge: element.string(Self.statusLabelAttribute),
                    locator: element.url(Self.urlAttribute).map(DockItem.locator(for:)),
                    isRunning: element.flag(Self.runningAttribute) ?? false
                )
            )
        }
        return DockItemList(items: items)
    }

    private func itemList(of application: AXElement) -> AXElement? {
        application.children(kAXChildrenAttribute)
            .first { $0.string(kAXRoleAttribute) == kAXListRole }
    }
}
