import ApplicationServices
import Foundation

struct AXElement {
    let element: AXUIElement

    init(_ element: AXUIElement) {
        self.element = element
    }

    static func application(_ processIdentifier: pid_t, messagingTimeout: Float) -> AXElement {
        let element = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return AXElement(element)
    }

    func child(_ attribute: String) -> AXElement? {
        guard let value = copy(attribute) else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        guard let elements = ([value] as CFArray) as? [AXUIElement], let first = elements.first else {
            return nil
        }
        return AXElement(first)
    }

    func children(_ attribute: String) -> [AXElement] {
        guard let value = copy(attribute), let elements = value as? [AXUIElement] else { return [] }
        return elements.map(AXElement.init)
    }

    func string(_ attribute: String) -> String? {
        copy(attribute) as? String
    }

    func integer(_ attribute: String) -> Int? {
        (copy(attribute) as? NSNumber)?.intValue
    }

    func flag(_ attribute: String) -> Bool? {
        copy(attribute) as? Bool
    }

    func perform(_ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    func clear(_ attribute: String) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, kCFBooleanFalse) == .success
    }

    private func copy(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }
}
