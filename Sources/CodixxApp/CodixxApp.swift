import SwiftUI
import CodixxCore

@main
struct CodixxApp: App {
    var body: some Scene {
        MenuBarExtra("Codixx", systemImage: "bolt.circle") {
            Text("Codixx")
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
