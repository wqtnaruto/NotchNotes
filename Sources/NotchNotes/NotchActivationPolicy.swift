import AppKit

enum NotchActivationPolicy {
    static func shouldRevealForFileDrag(
        at location: NSPoint,
        in dropFrame: NSRect,
        isLeftMousePressed: Bool,
        containsFileURLs: Bool,
        pasteboardChangeCount: Int,
        completedDragChangeCount: Int
    ) -> Bool {
        isLeftMousePressed && containsFileURLs
            && pasteboardChangeCount != completedDragChangeCount
            && dropFrame.contains(location)
    }

    static func shouldExpand(
        for eventType: NSEvent.EventType,
        at location: NSPoint,
        in activationFrame: NSRect,
        mode: TriggerMode,
        isLeftMousePressed: Bool = false
    ) -> Bool {
        guard activationFrame.contains(location) else { return false }
        switch eventType {
        case .leftMouseDown:
            return true
        case .mouseMoved:
            return mode == .hover && !isLeftMousePressed
        default:
            return false
        }
    }

    @MainActor
    static func screenLocation(for event: NSEvent) -> NSPoint {
        // 全局监听的事件不属于本应用窗口，locationInWindow 已是屏幕坐标。
        event.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
    }
}
