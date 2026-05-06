import SwiftUI

@main
struct CodixxApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            DashboardView(state: state)
        } label: {
            Label(state.menuBarTitle, systemImage: state.menuBarSystemImage)
        }
        .menuBarExtraStyle(.window)
    }
}
