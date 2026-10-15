import Combine
import XCTest
import CodixxCore
@testable import CodixxApp

@MainActor
final class DashboardPresentationStateTests: XCTestCase {
    func testBackgroundRefreshesDoNotInvalidateTheTabBarButLanguageStillUpdates() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = AppState(paths: CodixxPaths(home: directory))
        let presentation = DashboardPresentationState(state: state)
        var changes = 0
        let subscription = presentation.objectWillChange.sink { changes += 1 }
        for index in 0..<1_000 { state.errorMessage = "Example \(index)" }
        state.setQuotaRefreshIntervalSeconds(120)
        XCTAssertEqual(changes, 0)
        let nextLanguage: CodixxLanguage = presentation.language == .english ? .chinese : .english
        state.setLanguage(nextLanguage)
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(presentation.language, nextLanguage)
        XCTAssertEqual(presentation.strings.accounts, CodixxStrings(language: nextLanguage).accounts)
        withExtendedLifetime(subscription) {}
    }
}
