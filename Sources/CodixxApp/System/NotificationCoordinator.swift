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
            title: "Codixx quota warning",
            body: "\(account.alias) is at \(Int(primaryUsedPercent.rounded()))% of the 5-hour quota."
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
            title: "Codixx protection mode",
            body: "No saved account is available for automatic switching."
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
                title: "Codixx switched account",
                body: "Now using \(event.targetAlias ?? "the selected account")."
            )
        case .rolledBack, .rollbackFailed, .failedBeforeWrite, .failedDuringWrite, .failedValidation:
            guard throttle.shouldSend(.generic(type: "switch-failure"), at: Date()) else { return }
            send(
                title: "Codixx switch needs attention",
                body: event.errorSummary ?? "The account switch did not complete cleanly."
            )
        case .skippedNoCandidate:
            guard throttle.shouldSend(.protectionModeEntered, at: Date()) else { return }
            send(
                title: "Codixx protection mode",
                body: "No saved account is available for automatic switching."
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
