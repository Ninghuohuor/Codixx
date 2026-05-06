import CodixxCore
import Foundation
import UserNotifications

@MainActor
final class NotificationCoordinator {
    private var throttle = NotificationThrottle()
    private var didRequestAuthorization = false
    private var lastObservedSwitchEventId: UUID?
    private let notificationCenter: UNUserNotificationCenter

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    func evaluate(state: AppState) {
        sendQuotaWarningIfNeeded(state: state)
        sendProtectionModeIfNeeded(state: state)
        sendSwitchEventIfNeeded(state: state)
    }

    private func sendQuotaWarningIfNeeded(state: AppState) {
        guard state.config.notificationsEnabled,
              let account = state.currentAccount,
              let primaryUsedPercent = account.quota.primaryUsedPercent,
              primaryUsedPercent >= 80,
              throttle.shouldSend(
                .quotaWarning(accountId: account.id.uuidString, quotaKind: .primary),
                at: Date()
              )
        else {
            return
        }

        send(
            title: state.strings.codixxQuotaWarning,
            body: state.strings.quotaWarningBody(alias: account.alias, percent: Int(primaryUsedPercent.rounded()))
        )
    }

    private func sendProtectionModeIfNeeded(state: AppState) {
        guard let account = state.currentAccount,
              let primaryUsedPercent = account.quota.primaryUsedPercent,
              primaryUsedPercent >= state.config.primaryThresholdPercent,
              state.candidateAccounts.isEmpty,
              throttle.shouldSend(.protectionModeEntered, at: Date())
        else {
            return
        }

        send(
            title: state.strings.codixxProtectionMode,
            body: state.strings.noAccountAvailableForAutoSwitch
        )
    }

    private func sendSwitchEventIfNeeded(state: AppState) {
        guard let event = state.switchEvents.first,
              event.id != lastObservedSwitchEventId
        else {
            return
        }
        lastObservedSwitchEventId = event.id

        switch event.result {
        case .success:
            guard throttle.shouldSend(.generic(type: "switch-success"), at: Date()) else { return }
            send(
                title: state.strings.codixxSwitchedAccount,
                body: state.strings.switchedAccountBody(target: event.targetAlias ?? state.strings.selectedAccountFallback)
            )
        case .rolledBack, .rollbackFailed, .failedBeforeWrite, .failedDuringWrite, .failedValidation:
            guard throttle.shouldSend(.generic(type: "switch-failure"), at: Date()) else { return }
            send(
                title: state.strings.codixxSwitchNeedsAttention,
                body: event.errorSummary ?? state.strings.switchDidNotCompleteCleanly
            )
        case .skippedNoCandidate:
            guard throttle.shouldSend(.protectionModeEntered, at: Date()) else { return }
            send(
                title: state.strings.codixxProtectionMode,
                body: state.strings.noAccountAvailableForAutoSwitch
            )
        }
    }

    private func send(title: String, body: String) {
        ensureAuthorization {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "codixx-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            self.notificationCenter.add(request)
        }
    }

    private func ensureAuthorization(send: @escaping @MainActor () -> Void) {
        guard !didRequestAuthorization else {
            send()
            return
        }

        didRequestAuthorization = true
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            Task { @MainActor in
                send()
            }
        }
    }
}
