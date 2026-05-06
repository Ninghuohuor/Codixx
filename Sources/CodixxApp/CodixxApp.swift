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
            Label(state.menuBarTitle, systemImage: state.menuBarSystemImage)
        }
        .menuBarExtraStyle(.window)
    }
}
