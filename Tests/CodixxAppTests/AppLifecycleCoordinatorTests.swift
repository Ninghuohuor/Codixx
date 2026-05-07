import XCTest
@testable import CodixxApp
import CodixxCore

@MainActor
final class AppLifecycleCoordinatorTests: XCTestCase {
    func testStartDefersInitialRefreshUntilAfterMenuBarCanRender() async throws {
        let state = LifecycleStateSpy()
        let coordinator = AppLifecycleCoordinator(
            state: state,
            notificationCoordinator: NotificationCoordinatorSpy(),
            initialRefreshDelaySeconds: 0.05,
            shouldStartAuthFileObservation: false
        )

        coordinator.start()

        XCTAssertEqual(state.refreshNowCallCount, 0)
        XCTAssertEqual(state.refreshQuotaNowCallCount, 0)

        try await Task.sleep(nanoseconds: 90_000_000)
        XCTAssertEqual(state.refreshNowCallCount, 0)
        XCTAssertEqual(state.refreshQuotaNowCallCount, 1)
    }
}

@MainActor
private final class LifecycleStateSpy: LifecycleStateManaging {
    var config: CodixxConfig
    var strings: CodixxStrings
    var paths: CodixxPaths
    var errorMessage: String?
    var onNotificationsEnabled: (() -> Void)?
    var refreshNowCallCount = 0
    var refreshQuotaNowCallCount = 0

    init() {
        let paths = CodixxPaths(home: URL(fileURLWithPath: NSTemporaryDirectory()))
        self.paths = paths
        self.config = .default(paths: paths)
        self.strings = CodixxStrings(language: .chinese)
    }

    func refreshNow() {
        refreshNowCallCount += 1
    }

    func refreshQuotaNow() {
        refreshQuotaNowCallCount += 1
    }

    func refreshUsageNow() {}
}

@MainActor
private final class NotificationCoordinatorSpy: AppNotificationCoordinating {
    func evaluate(state: AppState) {}

    func sendNotificationsEnabledConfirmation(strings: CodixxStrings, onDenied: @escaping @MainActor () -> Void) {}
}
