import AppKit
import Combine
import SwiftUI

@main
struct CodixxApp: App {
    @StateObject private var state: AppState
    @StateObject private var lifecycle: AppLifecycleCoordinator
    private let singleInstanceGuard: SingleInstanceGuard?
    private let statusItemController: StatusItemController

    init() {
        let appState = AppState()
        let coordinator = AppLifecycleCoordinator(state: appState)
        self.singleInstanceGuard = SingleInstanceGuard.acquire(paths: appState.paths)
        self.statusItemController = StatusItemController(state: appState)
        _state = StateObject(wrappedValue: appState)
        _lifecycle = StateObject(wrappedValue: coordinator)

        if singleInstanceGuard == nil {
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        } else {
            coordinator.start()
        }
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
private final class StatusItemController: NSObject, NSPopoverDelegate {
    private static let statusItemLength: CGFloat = 19
    private static let iconPointSize: CGFloat = 15

    private let state: AppState
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var cancellables: Set<AnyCancellable> = []
    private var outsideClickMonitors: [Any] = []
    private var menuOpenRefreshTask: Task<Void, Never>?

    init(state: AppState) {
        self.state = state
        self.statusItem = NSStatusBar.system.statusItem(withLength: Self.statusItemLength)
        self.popover = NSPopover()
        super.init()

        popover.behavior = .transient
        popover.contentSize = DashboardLayout.popoverContentSize
        popover.contentViewController = NSHostingController(rootView: DashboardView(state: state))
        popover.delegate = self

        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyUpOrDown
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        updateIcon()
        state.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateIcon()
                }
            }
            .store(in: &cancellables)
    }

    @objc
    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            closePopover(sender)
            return
        }

        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        startOutsideClickMonitors(statusButton: sender)
        scheduleMenuOpenRefresh()
    }

    func popoverDidClose(_ notification: Notification) {
        menuOpenRefreshTask?.cancel()
        menuOpenRefreshTask = nil
        stopOutsideClickMonitors()
    }

    private func scheduleMenuOpenRefresh() {
        menuOpenRefreshTask?.cancel()
        menuOpenRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard let self, !Task.isCancelled, self.popover.isShown else { return }
            self.state.refreshFromMenuOpen()
        }
    }

    private func startOutsideClickMonitors(statusButton: NSStatusBarButton) {
        stopOutsideClickMonitors()
        let mask: NSEvent.EventTypeMask = [
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ]
        if let localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self, weak statusButton] event in
            self?.closePopoverIfNeeded(for: event, statusButton: statusButton)
            return event
        }) {
            outsideClickMonitors.append(localMonitor)
        }
        if let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self, weak statusButton] event in
            self?.closePopoverIfNeeded(for: event, statusButton: statusButton)
        }) {
            outsideClickMonitors.append(globalMonitor)
        }
    }

    private func stopOutsideClickMonitors() {
        outsideClickMonitors.forEach(NSEvent.removeMonitor)
        outsideClickMonitors.removeAll()
    }

    private func closePopoverIfNeeded(for event: NSEvent, statusButton: NSStatusBarButton?) {
        guard popover.isShown else {
            stopOutsideClickMonitors()
            return
        }
        let popoverWindow = popover.contentViewController?.view.window
        guard PopoverDismissalPolicy.shouldClosePopover(
            eventWindow: event.window,
            popoverWindow: popoverWindow,
            statusButtonWindow: statusButton?.window
        ) else {
            return
        }
        closePopover(event)
    }

    private func closePopover(_ sender: Any?) {
        popover.performClose(sender)
        stopOutsideClickMonitors()
    }

    private static let menuBarIconImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        let displaySize = iconPointSize
        let scale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2
        let pixelSize = Int(displaySize * scale)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return image }
        bitmap.size = NSSize(width: displaySize, height: displaySize)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(
            in: NSRect(x: 0, y: 0, width: displaySize, height: displaySize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()
        let scaled = NSImage(size: NSSize(width: displaySize, height: displaySize))
        scaled.addRepresentation(bitmap)
        scaled.isTemplate = false
        return scaled
    }()

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        button.image = Self.menuBarIconImage ?? Self.systemIcon(named: state.menuBarSystemImage)
        button.toolTip = state.menuBarHelpText
    }

    private static func systemIcon(named name: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: iconPointSize, weight: .medium)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Codixx")?
            .withSymbolConfiguration(configuration)
        image?.size = NSSize(width: iconPointSize, height: iconPointSize)
        image?.isTemplate = true
        return image
    }
}
