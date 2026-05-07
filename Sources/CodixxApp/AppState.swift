import AppKit
import Foundation
import SwiftUI
import CodixxCore

enum AccountSaveStatus: Equatable {
    case success(alias: String)
    case failure(message: String)
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var config: CodixxConfig
    @Published private(set) var accounts: [CodixxAccount] = []
    @Published private(set) var currentAccount: CodixxAccount?
    @Published private(set) var usageSnapshot = ThreadUsageSnapshot(
        threads: [],
        totalTokens: 0,
        activeThread: nil
    )
    @Published private(set) var switchEvents: [SwitchAuditEvent] = []
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var accountSaveStatus: AccountSaveStatus?
    @Published private(set) var postSwitchRestartMessage: String?
    @Published var errorMessage: String?

    let paths: CodixxPaths

    private let configStore: CodixxConfigStore
    private let metadataStore: AccountMetadataStore
    private let rateLimitReader: RateLimitReader
    private let threadUsageReader: ThreadUsageReader
    private let auditLog: SwitchAuditLog
    private let accountStore: AccountStore
    private let switcher: AccountSwitcher
    private let vault: AuthSnapshotVault
    private let now: () -> Date
    private var isRefreshInProgress = false
    private var isSwitchInProgress = false
    private var lastRefreshStartedAt: Date?
    private let menuRefreshThrottleSeconds: TimeInterval = 30

    init(
        paths: CodixxPaths = CodixxPaths(),
        vault: AuthSnapshotVault = KeychainVault(),
        now: @escaping () -> Date = Date.init
    ) {
        self.paths = paths
        self.vault = vault
        self.now = now
        self.configStore = CodixxConfigStore(paths: paths)
        self.metadataStore = AccountMetadataStore(paths: paths)
        self.rateLimitReader = RateLimitReader(paths: paths)
        self.threadUsageReader = ThreadUsageReader(databaseURL: paths.latestStateDatabaseURL())
        self.auditLog = SwitchAuditLog(paths: paths)
        self.accountStore = AccountStore(paths: paths, metadataStore: metadataStore, vault: vault, now: now)
        self.switcher = AccountSwitcher(
            paths: paths,
            metadataStore: metadataStore,
            vault: vault,
            backupManager: SwitchBackupManager(paths: paths),
            auditLog: auditLog,
            now: now
        )
        self.config = (try? configStore.load()) ?? .default(paths: paths)
    }

    var menuBarTitle: String {
        guard let account = currentAccount else { return "Codixx" }
        if let used = account.quota.primaryUsedPercent {
            return "\(account.alias) \(Self.percentFormatter.string(from: NSNumber(value: used / 100)) ?? "")"
        }
        return account.alias
    }

    var menuBarSystemImage: String {
        guard let used = currentAccount?.quota.primaryUsedPercent else { return "bolt.circle" }
        return used >= config.primaryThresholdPercent ? "bolt.trianglebadge.exclamationmark" : "bolt.circle"
    }

    var topThreads: [ThreadUsage] {
        Array(usageSnapshot.threads.sorted { $0.tokensUsed > $1.tokensUsed }.prefix(10))
    }

    var candidateAccounts: [CodixxAccount] {
        SwitchPolicy(primaryThresholdPercent: config.primaryThresholdPercent)
            .orderedCandidates(from: accounts.filter { $0.id != currentAccount?.id }, snapshotExists: hasSnapshot)
    }

    var canEnableAutoSwitch: Bool {
        accounts.filter(\.isEnabled).count >= 2
    }

    var strings: CodixxStrings {
        CodixxStrings(language: config.language)
    }

    func refreshNow() {
        refresh(
            applyRateLimitObservations: true,
            allowAutoSwitch: true,
            preservingError: nil,
            throttled: false
        )
    }

    func refreshFromMenuOpen() {
        refresh(
            applyRateLimitObservations: true,
            allowAutoSwitch: true,
            preservingError: nil,
            throttled: true
        )
    }

    private func refresh(
        applyRateLimitObservations: Bool,
        allowAutoSwitch: Bool,
        preservingError preservedError: String?,
        throttled: Bool
    ) {
        guard !isRefreshInProgress else { return }
        let refreshStartedAt = now()
        if throttled,
           let lastRefreshStartedAt,
           refreshStartedAt.timeIntervalSince(lastRefreshStartedAt) < menuRefreshThrottleSeconds
        {
            return
        }

        isRefreshInProgress = true
        isRefreshing = true
        lastRefreshStartedAt = refreshStartedAt

        var refreshErrors: [String] = []
        do {
            config = try configStore.load()
        } catch {
            refreshErrors.append(error.localizedDescription)
        }

        var loadedAccounts: [CodixxAccount] = []
        do {
            loadedAccounts = try metadataStore.load().accounts
        } catch {
            refreshErrors.append(error.localizedDescription)
        }

        applySavedAuthProfiles(to: &loadedAccounts)

        if applyRateLimitObservations {
            do {
                try applyLatestRateLimitObservation(to: &loadedAccounts)
            } catch {
                refreshErrors.append(error.localizedDescription)
            }
        } else {
            do {
                if refreshQuotaConfidence(in: &loadedAccounts) {
                    try metadataStore.save(AccountMetadataList(accounts: loadedAccounts))
                }
            } catch {
                refreshErrors.append(error.localizedDescription)
            }
        }

        accounts = loadedAccounts
        currentAccount = currentAccount(in: loadedAccounts)
        usageSnapshot = threadUsageReader.readSnapshot(now: now())

        do {
            switchEvents = try auditLog.loadEvents().sorted { $0.timestamp > $1.timestamp }
        } catch {
            refreshErrors.append(error.localizedDescription)
        }

        if let usageError = usageSnapshot.errorSummary {
            refreshErrors.append(usageError)
        }

        if let preservedError {
            refreshErrors.insert(preservedError, at: 0)
        }

        errorMessage = refreshErrors.isEmpty ? nil : refreshErrors.joined(separator: "\n")
        lastUpdatedAt = now()
        isRefreshing = false
        isRefreshInProgress = false

        if allowAutoSwitch {
            attemptAutoSwitchIfNeeded()
        }
    }

    func attemptAutoSwitchIfNeeded() {
        guard config.autoSwitchEnabled, !isSwitchInProgress else { return }
        let timestamp = now()
        let policy = SwitchPolicy(primaryThresholdPercent: config.primaryThresholdPercent)
        let context = SwitchSafetyContext(
            now: timestamp,
            activeThreadUpdatedAt: usageSnapshot.activeThread?.updatedAt,
            lastSwitchAt: lastSuccessfulSwitchAt
        )
        guard policy.shouldAutoSwitch(currentAccount: currentAccount, context: context),
              let target = candidateAccounts.first
        else {
            return
        }

        isSwitchInProgress = true
        defer { isSwitchInProgress = false }

        do {
            _ = try switcher.switchToAccount(target.id, trigger: .autoPrimaryThreshold)
            refresh(
                applyRateLimitObservations: false,
                allowAutoSwitch: false,
                preservingError: nil,
                throttled: false
            )
            handlePostSwitchAction()
        } catch {
            let preservedError = pauseAutoSwitchIfRollbackFailed(error)
            refresh(
                applyRateLimitObservations: false,
                allowAutoSwitch: false,
                preservingError: preservedError,
                throttled: false
            )
        }
    }

    func saveCurrentAccount(alias: String) {
        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedAlias = trimmedAlias.isEmpty ? "Codex Account" : trimmedAlias
        do {
            let account = try accountStore.saveCurrentAuth(alias: savedAlias)
            accountSaveStatus = .success(alias: account.alias)
            refreshNow()
        } catch {
            accountSaveStatus = .failure(message: error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func switchToAccount(_ account: CodixxAccount) {
        guard !isSwitchInProgress else { return }
        isSwitchInProgress = true
        defer { isSwitchInProgress = false }

        refresh(
            applyRateLimitObservations: true,
            allowAutoSwitch: false,
            preservingError: nil,
            throttled: false
        )

        do {
            _ = try switcher.switchToAccount(account.id, trigger: .manual)
            refresh(
                applyRateLimitObservations: false,
                allowAutoSwitch: false,
                preservingError: nil,
                throttled: false
            )
            handlePostSwitchAction()
        } catch {
            let preservedError = pauseAutoSwitchIfRollbackFailed(error)
            refresh(
                applyRateLimitObservations: false,
                allowAutoSwitch: false,
                preservingError: preservedError,
                throttled: false
            )
        }
    }

    func setAccount(_ account: CodixxAccount, isEnabled: Bool) {
        updateAccount(account) { updated in
            updated.isEnabled = isEnabled
        }
    }

    func setAccount(_ account: CodixxAccount, priority: Int) {
        updateAccount(account) { updated in
            updated.priority = priority
        }
    }

    func renameAccount(_ account: CodixxAccount, alias: String) {
        do {
            _ = try accountStore.renameAccount(account.id, alias: alias)
            refresh(
                applyRateLimitObservations: false,
                allowAutoSwitch: false,
                preservingError: nil,
                throttled: false
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteAccount(_ account: CodixxAccount) {
        do {
            try accountStore.deleteAccount(account.id)
            refresh(
                applyRateLimitObservations: false,
                allowAutoSwitch: false,
                preservingError: nil,
                throttled: false
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setAutoSwitchEnabled(_ isEnabled: Bool) {
        updateConfig { $0.autoSwitchEnabled = isEnabled && canEnableAutoSwitch }
    }

    func setNotificationsEnabled(_ isEnabled: Bool) {
        updateConfig { $0.notificationsEnabled = isEnabled }
    }

    func setPrimaryThresholdPercent(_ percent: Double) {
        updateConfig { $0.primaryThresholdPercent = percent }
    }

    func setQuotaRefreshIntervalSeconds(_ seconds: TimeInterval) {
        updateConfig { $0.quotaRefreshIntervalSeconds = seconds }
    }

    func setUsageRefreshIntervalSeconds(_ seconds: TimeInterval) {
        updateConfig { $0.usageRefreshIntervalSeconds = seconds }
    }

    func setLanguage(_ language: CodixxLanguage) {
        updateConfig { $0.language = language }
    }

    func setPostSwitchAction(_ action: PostSwitchAction) {
        updateConfig { $0.postSwitchAction = action }
    }

    func restartCodexNow() {
        do {
            postSwitchRestartMessage = nil
            try restartCodexDesktop()
        } catch {
            errorMessage = "\(strings.restartCodexFailed): \(error.localizedDescription)"
        }
    }

    func dismissPostSwitchRestartMessage() {
        postSwitchRestartMessage = nil
    }

    private func updateConfig(_ mutate: (inout CodixxConfig) -> Void) {
        var updated = config
        mutate(&updated)
        do {
            try configStore.save(updated)
            config = updated
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handlePostSwitchAction() {
        switch config.postSwitchAction {
        case .none:
            break
        case .notifyRestartRecommended:
            postSwitchRestartMessage = strings.restartCodexHint
            errorMessage = strings.restartCodexHint
        case .restartCodexApp:
            restartCodexNow()
        }
    }

    private func restartCodexDesktop() throws {
        let bundleIdentifier = "com.openai.codex"
        let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            ?? URL(fileURLWithPath: "/Applications/Codex.app", isDirectory: true)

        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).forEach { application in
            application.terminate()
        }

        let configuration = NSWorkspace.OpenConfiguration()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { _, error in
                guard let error else { return }
                Task { @MainActor in
                    self?.errorMessage = "\(self?.strings.restartCodexFailed ?? "Could not restart Codex"): \(error.localizedDescription)"
                }
            }
        }
    }

    private func pauseAutoSwitchIfRollbackFailed(_ error: Error) -> String {
        guard case AccountSwitchError.rollbackFailed = error else {
            return error.localizedDescription
        }

        var updated = config
        updated.autoSwitchEnabled = false
        do {
            try configStore.save(updated)
            config = updated
            return "\(error.localizedDescription)\n\(strings.textForAutoSwitchPaused)"
        } catch {
            return "\(error.localizedDescription)\n\(strings.textForAutoSwitchCouldNotBePaused(error.localizedDescription))"
        }
    }

    private func updateAccount(_ account: CodixxAccount, mutate: (inout CodixxAccount) -> Void) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        var updatedAccounts = accounts
        mutate(&updatedAccounts[index])
        updatedAccounts[index].updatedAt = now()
        do {
            try metadataStore.save(AccountMetadataList(accounts: updatedAccounts))
            accounts = updatedAccounts
            currentAccount = currentAccount(in: updatedAccounts)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyLatestRateLimitObservation(to accounts: inout [CodixxAccount]) throws {
        let timestamp = now()
        let didRefreshCachedQuota = refreshQuotaConfidence(in: &accounts, timestamp: timestamp)

        guard let current = currentAccount(in: accounts),
              let currentIndex = accounts.firstIndex(where: { $0.id == current.id })
        else {
            if didRefreshCachedQuota {
                try metadataStore.save(AccountMetadataList(accounts: accounts))
            }
            return
        }
        guard let observation = try rateLimitReader.readNewObservations().last else {
            if didRefreshCachedQuota {
                try metadataStore.save(AccountMetadataList(accounts: accounts))
            }
            return
        }

        let profile = authProfile(for: accounts[currentIndex]) ?? currentAuthProfile()
        var quota = observation.accountQuotaState(
            accountId: accounts[currentIndex].id.uuidString,
            alias: accounts[currentIndex].alias,
            now: timestamp
        )
        quota.planType = profile?.planType ?? observation.planType
        accounts[currentIndex].quota = quota
        if let membershipExpiresAt = profile?.membershipExpiresAt ?? observation.membershipExpiresAt {
            accounts[currentIndex].membershipExpiresAt = membershipExpiresAt
        }
        accounts[currentIndex].updatedAt = timestamp
        try metadataStore.save(AccountMetadataList(accounts: accounts))
    }

    private func applySavedAuthProfiles(to accounts: inout [CodixxAccount]) {
        let timestamp = now()
        var didChange = false

        for index in accounts.indices {
            guard let profile = authProfile(for: accounts[index]) else { continue }
            didChange = apply(profile, to: &accounts[index], timestamp: timestamp) || didChange
        }

        guard didChange else { return }
        do {
            try metadataStore.save(AccountMetadataList(accounts: accounts))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ profile: AuthProfile, to account: inout CodixxAccount, timestamp: Date) -> Bool {
        var didChange = false

        if let planType = profile.planType,
           account.quota.planType != planType
        {
            account.quota.planType = planType
            didChange = true
        }
        if let membershipExpiresAt = profile.membershipExpiresAt,
           account.membershipExpiresAt != membershipExpiresAt
        {
            account.membershipExpiresAt = membershipExpiresAt
            didChange = true
        }

        if didChange {
            account.updatedAt = timestamp
        }
        return didChange
    }

    @discardableResult
    private func refreshQuotaConfidence(in accounts: inout [CodixxAccount], timestamp: Date? = nil) -> Bool {
        let refreshTime = timestamp ?? now()
        var didChange = false
        for index in accounts.indices {
            let previousQuota = accounts[index].quota
            accounts[index].quota.rollForwardExpiredWindows(now: refreshTime)
            accounts[index].quota.confidence = QuotaConfidence.observed(
                at: accounts[index].quota.lastObservedAt,
                now: refreshTime
            )
            if accounts[index].quota != previousQuota {
                accounts[index].updatedAt = refreshTime
                didChange = true
            }
        }
        return didChange
    }

    private func currentAccount(in accounts: [CodixxAccount]) -> CodixxAccount? {
        guard let data = try? Data(contentsOf: paths.authJSON),
              let snapshot = try? AuthSnapshot(jsonData: data),
              let fingerprint = try? AccountFingerprint.generate(from: snapshot)
        else {
            return nil
        }
        return accounts.first { $0.fingerprint == fingerprint }
    }

    private func currentAuthProfile() -> AuthProfile? {
        guard let data = try? Data(contentsOf: paths.authJSON),
              let snapshot = try? AuthSnapshot(jsonData: data)
        else {
            return nil
        }
        return AuthProfileReader.profile(from: snapshot)
    }

    private func authProfile(for account: CodixxAccount) -> AuthProfile? {
        guard let snapshot = try? vault.load(fingerprint: account.fingerprint) else {
            return nil
        }
        return AuthProfileReader.profile(from: snapshot)
    }

    private func hasSnapshot(for account: CodixxAccount) -> Bool {
        (try? vault.load(fingerprint: account.fingerprint)) != nil
    }

    private var lastSuccessfulSwitchAt: Date? {
        switchEvents
            .filter { $0.result == .success }
            .map(\.timestamp)
            .max()
    }

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
