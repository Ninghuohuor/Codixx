import AppKit
import SwiftUI
import XCTest
import CodixxCore
@testable import CodixxApp

@MainActor
final class BalanceMonitorLayoutTests: XCTestCase {
    func testPageFitsDashboardWithEitherSavedAuthentication() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = AppState(paths: CodixxPaths(home: directory))
        for mode in [BalanceAuthenticationMode.modelAPIKey, .accessToken] {
            let id = UUID()
            let account = CodixxAccount(
                id: id, alias: "Relay", fingerprint: "test", credentialKind: .apiProvider,
                apiProvider: APIProviderAccount(providerName: "Relay", baseURL: URL(string: "https://example.com/v1")!, defaultModel: nil, keyFingerprint: "test", balanceQuery: APIBalanceQueryConfig(authenticationMode: mode)),
                createdAt: Date(), updatedAt: Date(), lastUsedAt: nil,
                quota: .unknown(accountId: id.uuidString, alias: "Relay"), isEnabled: true, priority: 0
            )
            let host = NSHostingController(rootView: BalanceMonitorPage(state: state, account: account, onClose: {}).frame(width: 560, height: 470).codixxAppearance())
            AppAppearancePolicy.apply(to: host.view)
            let size = host.view.fittingSize
            XCTAssertEqual(size.height, 470, accuracy: 1)
            XCTAssertLessThan(size.height, 650, "Keep the dialog usable on smaller displays")
            XCTAssertEqual(size.width, 560, accuracy: 1)
        }
    }
}
