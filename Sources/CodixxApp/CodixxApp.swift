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
                        .frame(width: 18, height: 18)
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
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        return image
    }()
}
