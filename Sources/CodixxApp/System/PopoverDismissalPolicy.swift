import AppKit

enum PopoverDismissalPolicy {
    @MainActor
    static func shouldClosePopover(
        eventWindow: NSWindow?,
        popoverWindow: NSWindow?,
        statusButtonWindow: NSWindow?
    ) -> Bool {
        guard let popoverWindow else { return false }
        guard let eventWindow else {
            return popoverWindow.childWindows?.isEmpty ?? true
        }
        if eventWindow === popoverWindow || eventWindow === statusButtonWindow {
            return false
        }
        if eventWindow.parent === popoverWindow {
            return false
        }
        if popoverWindow.childWindows?.contains(where: { $0 === eventWindow }) == true {
            return false
        }
        return true
    }
}
