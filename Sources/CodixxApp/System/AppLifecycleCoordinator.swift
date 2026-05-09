import AppKit
import CodixxCore
import Darwin
import Foundation

@MainActor
final class AppLifecycleCoordinator: ObservableObject {
    private let state: LifecycleStateManaging
    private let notificationCoordinator: AppNotificationCoordinating
    private let initialRefreshDelaySeconds: TimeInterval
    private let shouldStartAuthFileObservation: Bool
    private var quotaTimer: Timer?
    private var usageTimer: Timer?
    private var apiBalanceTimer: Timer?
    private var authFileDescriptor: Int32 = -1
    private var authFileSource: DispatchSourceFileSystemObject?
    private var isStarted = false

    init(
        state: LifecycleStateManaging,
        notificationCoordinator: AppNotificationCoordinating? = nil,
        initialRefreshDelaySeconds: TimeInterval = 0.3,
        shouldStartAuthFileObservation: Bool = true
    ) {
        self.state = state
        self.notificationCoordinator = notificationCoordinator ?? NotificationCoordinator()
        self.initialRefreshDelaySeconds = initialRefreshDelaySeconds
        self.shouldStartAuthFileObservation = shouldStartAuthFileObservation
    }

    func stop() {
        isStarted = false
        quotaTimer?.invalidate()
        usageTimer?.invalidate()
        apiBalanceTimer?.invalidate()
        authFileSource?.cancel()
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        state.onNotificationsEnabled = nil
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        state.onNotificationsEnabled = { [weak self] in
            self?.sendNotificationsEnabledConfirmation()
        }
        scheduleTimers()
        observeSystemEvents()
        observeActivationRequests()
        if shouldStartAuthFileObservation {
            startAuthFileObservation()
        }
        scheduleInitialRefresh()
    }

    private func scheduleInitialRefresh() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(initialRefreshDelaySeconds * 1_000_000_000))
            guard self.isStarted else { return }
            self.refreshQuotaAndNotify()
        }
    }

    private func scheduleTimers() {
        quotaTimer?.invalidate()
        usageTimer?.invalidate()
        apiBalanceTimer?.invalidate()

        scheduleQuotaTimer()
        scheduleUsageTimer()
        scheduleAPIBalanceTimer()
    }

    private func scheduleQuotaTimer() {
        quotaTimer?.invalidate()
        quotaTimer = Timer.scheduledTimer(
            withTimeInterval: jitteredInterval(base: max(10, state.config.quotaRefreshIntervalSeconds), minimum: 10),
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isStarted else { return }
                self.refreshQuotaAndNotify()
                self.scheduleQuotaTimer()
            }
        }
    }

    private func scheduleUsageTimer() {
        usageTimer?.invalidate()
        usageTimer = Timer.scheduledTimer(
            withTimeInterval: jitteredInterval(base: max(60, state.config.usageRefreshIntervalSeconds), minimum: 60),
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isStarted else { return }
                self.refreshUsageAndNotify()
                self.scheduleUsageTimer()
            }
        }
    }

    private func scheduleAPIBalanceTimer() {
        apiBalanceTimer?.invalidate()
        apiBalanceTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isStarted else { return }
                self.state.refreshAPIBalancesNow()
                self.scheduleAPIBalanceTimer()
            }
        }
    }

    private func jitteredInterval(base: TimeInterval, minimum: TimeInterval) -> TimeInterval {
        max(minimum, base + TimeInterval.random(in: -15...15))
    }

    private func observeSystemEvents() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(workspaceWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(workspaceDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    private func observeActivationRequests() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(activateExistingInstance),
            name: SingleInstanceGuard.activationNotificationName,
            object: Bundle.main.bundleIdentifier
        )
    }

    private func startAuthFileObservation() {
        authFileSource?.cancel()
        authFileSource = nil
        authFileDescriptor = -1

        authFileDescriptor = open(state.paths.authJSON.path, O_EVTONLY)
        guard authFileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: authFileDescriptor,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: DispatchQueue.main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.refreshAndNotify()
                self?.startAuthFileObservation()
            }
        }
        source.setCancelHandler { [fd = authFileDescriptor] in
            if fd >= 0 {
                close(fd)
            }
        }
        authFileSource = source
        source.resume()
    }

    @objc private func workspaceWillSleep() {
        quotaTimer?.invalidate()
        usageTimer?.invalidate()
        apiBalanceTimer?.invalidate()
    }

    @objc private func workspaceDidWake() {
        scheduleTimers()
        refreshAndNotify()
        startAuthFileObservation()
    }

    @objc private func activateExistingInstance() {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func refreshAndNotify() {
        state.refreshNow()
        evaluateNotificationsIfPossible()
    }

    private func refreshQuotaAndNotify() {
        state.refreshQuotaNow()
        evaluateNotificationsIfPossible()
    }

    private func refreshUsageAndNotify() {
        state.refreshUsageNow()
        evaluateNotificationsIfPossible()
    }

    private func evaluateNotificationsIfPossible() {
        guard let appState = state as? AppState else { return }
        notificationCoordinator.evaluate(state: appState)
    }

    private func sendNotificationsEnabledConfirmation() {
        notificationCoordinator.sendNotificationsEnabledConfirmation(strings: state.strings) { [weak self] in
            self?.state.errorMessage = self?.state.strings.notificationsDenied
        }
    }
}
