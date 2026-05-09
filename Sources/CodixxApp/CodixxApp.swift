import AppKit
import SwiftUI

@main
struct CodixxApp: App {
    @StateObject private var state: AppState
    @StateObject private var lifecycle: AppLifecycleCoordinator
    private let singleInstanceGuard: SingleInstanceGuard?

    init() {
        let appState = AppState()
        let coordinator = AppLifecycleCoordinator(state: appState)
        self.singleInstanceGuard = SingleInstanceGuard.acquire(paths: appState.paths)
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
        MenuBarExtra {
            DashboardView(state: state)
        } label: {
            Label {
                Text(state.menuBarTitle)
            } icon: {
                if let image = Self.menuBarIconImage {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: state.menuBarSystemImage)
                }
            }
                .help(state.menuBarHelpText)
        }
        .menuBarExtraStyle(.window)
    }

    private static let menuBarIconImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        let displaySize: CGFloat = 20
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
}
