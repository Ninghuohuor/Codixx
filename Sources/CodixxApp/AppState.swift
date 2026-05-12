import AppKit
import Foundation
import SwiftUI
import CodixxCore

enum AccountSaveStatus: Equatable {
    case success(alias: String)
    case failure(message: String)
}

@MainActor
protocol LifecycleStateManaging: AnyObject {
    var config: CodixxConfig { get }
    var strings: CodixxStrings { get }
    var paths: CodixxPaths { get }
    var errorMessage: String? { get set }
    var onNotificationsEnabled: (() -> Void)? { get set }

    func refreshNow()
    func refreshQuotaNow()
    func refreshUsageNow()
    func refreshAPIBalancesNow()
}

@MainActor
final class AppState: ObservableObject, LifecycleStateManaging {
    @Published private(set) var config: CodixxConfig
    @Published private(set) var accounts: [CodixxAccount] = []
    @Published private(set) var currentAccount: CodixxAccount?
    @Published private(set) var usageSnapshot = ThreadUsageSnapshot(
        threads: [],
        totalTokens: 0,
        activeThread: nil
    )
    @Published private(set) var topThreads: [ThreadUsage] = []
    @Published private(set) var switchEvents: [SwitchAuditEvent] = []
    @Published private(set) var appLogEvents: [AppLogEvent] = []
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var hasLoadedFullUsageSnapshot = false
    @Published private(set) var isLoadingFullUsageSnapshot = false
    @Published private(set) var accountSaveStatus: AccountSaveStatus?
    @Published private(set) var postSwitchRestartMessage: String?
    @Published var errorMessage: String?

    let paths: CodixxPaths

    private let configStore: CodixxConfigStore
    private let metadataStore: AccountMetadataStore
    private let rateLimitReader: RateLimitReader
    private let threadUsageReader: ThreadUsageReader
    private let auditLog: SwitchAuditLog
    private let appActivityLog: AppActivityLog
    private let accountStore: AccountStore
    private let switcher: AccountSwitcher
    private let vault: AuthSnapshotVault
    private let apiKeyVault: APIKeyVault
    private let codexDesktopManager: CodexDesktopManaging
    private let connectivityTester: APIProviderConnectivityTesting
    private let balanceQueryTester: APIBalanceQueryTesting
    private let now: () -> Date
    private var isRefreshInProgress = false
    private var isSwitchInProgress = false
    private var usageRefreshTask: Task<Void, Never>?
    private var errorDismissWork: DispatchWorkItem?
    private var lastRefreshStartedAt: Date?
    private let menuRefreshThrottleSeconds: TimeInterval = 30
    private let manualSwitchAutoSuppressionSeconds: TimeInterval = 300
    private var autoSwitchSuppressedUntil: Date?
    var onNotificationsEnabled: (() -> Void)?

    init(
        paths: CodixxPaths = CodixxPaths(),
        vault: AuthSnapshotVault = KeychainVault(),
        apiKeyVault: APIKeyVault = KeychainAPIKeyVault(),
        codexDesktopState: CodexDesktopStateCleaning? = nil,
        codexDesktopManager: CodexDesktopManaging? = nil,
        connectivityTester: APIProviderConnectivityTesting = APIProviderConnectivityTester(),
        balanceQueryTester: APIBalanceQueryTesting = APIBalanceQueryTester(),
        now: @escaping () -> Date = Date.init
    ) {
        self.paths = paths
        self.vault = vault
        self.apiKeyVault = apiKeyVault
        self.codexDesktopManager = codexDesktopManager ?? SystemCodexDesktopManager()
        self.connectivityTester = connectivityTester
        self.balanceQueryTester = balanceQueryTester
        self.now = now
        self.configStore = CodixxConfigStore(paths: paths)
        self.metadataStore = AccountMetadataStore(paths: paths)
        self.rateLimitReader = RateLimitReader(paths: paths)
        self.threadUsageReader = ThreadUsageReader(
            databaseURL: paths.latestStateDatabaseURL(),
            trendCacheStore: TrendCacheStore(paths: paths)
        )
        self.auditLog = SwitchAuditLog(paths: paths)
        self.appActivityLog = AppActivityLog(paths: paths)
        self.accountStore = AccountStore(
            paths: paths,
            metadataStore: metadataStore,
            vault: vault,
            apiKeyVault: apiKeyVault,
            now: now
        )
        let resolvedCodexDesktopState = codexDesktopState ?? FileSystemCodexDesktopStateCleaner(
            paths: paths,
            isRunning: {
                !NSRunningApplication.runningApplications(
                    withBundleIdentifier: CodexActivation.bundleIdentifier
                ).isEmpty
            }
        )
        self.switcher = AccountSwitcher(
            paths: paths,
            metadataStore: metadataStore,
            vault: vault,
            backupManager: SwitchBackupManager(paths: paths),
            auditLog: auditLog,
            now: now,
            apiKeyVault: apiKeyVault,
            codexDesktopState: resolvedCodexDesktopState,
            threadProviderSync: SQLiteCodexThreadProviderSync(paths: paths),
            apiSwitchThreadSyncScope: {
                ((try? CodixxConfigStore(paths: paths).load()) ?? .default(paths: paths)).apiSwitchThreadSyncScope
            }
        )
        self.config = (try? configStore.load()) ?? .default(paths: paths)
    }

    var menuBarTitle: String {
        guard let account = currentAccount else { return "Codixx" }
        if let used = account.quota.primaryUsedPercent {
            return "Codixx \(Self.percentFormatter.string(from: NSNumber(value: used / 100)) ?? "")"
        }
        return "Codixx"
    }

    var menuBarHelpText: String {
        guard let account = currentAccount else {
            return strings.noActiveAccountTitle
        }

        let primaryPercent = quotaPercentText(account.quota.primaryUsedPercent)
        let secondaryPercent = quotaPercentText(account.quota.secondaryUsedPercent)
        let primaryReset = account.quota.primaryResetsAt.map(strings.resets) ?? strings.resetUnknown
        let secondaryReset = account.quota.secondaryResetsAt.map(strings.weeklyResets) ?? strings.resetUnknown
        let primaryThreshold = "\(Int(config.primaryThresholdPercent.rounded()))%"
        let secondaryThreshold = "\(Int(config.secondaryThresholdPercent.rounded()))%"

        return [
            account.alias,
            "\(strings.fiveHourQuota): \(primaryPercent) · \(primaryReset)",
            "\(strings.weeklyQuota): \(secondaryPercent) · \(secondaryReset)",
            "\(strings.threshold): \(primaryThreshold)",
            "\(strings.weeklyThreshold): \(secondaryThreshold)"
        ].joined(separator: "\n")
    }

    var menuBarSystemImage: String {
        guard currentAccount != nil else { return "bolt.slash.circle.fill" }
        let primaryAtThreshold = currentAccount?.quota.primaryUsedPercent.map { $0 >= config.primaryThresholdPercent } ?? false
        let secondaryAtThreshold = currentAccount?.quota.secondaryUsedPercent.map { $0 >= config.secondaryThresholdPercent } ?? false
        return primaryAtThreshold || secondaryAtThreshold ? "exclamationmark.triangle.fill" : "bolt.circle.fill"
    }

    var candidateAccounts: [CodixxAccount] {
        SwitchPolicy(
            primaryThresholdPercent: config.primaryThresholdPercent,
            secondaryThresholdPercent: config.secondaryThresholdPercent
        )
            .orderedCandidates(from: accounts.filter { $0.id != currentAccount?.id }) { _ in true }
    }

    var canEnableAutoSwitch: Bool {
        accounts.filter { $0.isEnabled && $0.isChatGPT }.count >= 2
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

    func refreshQuotaNow() {
        refresh(
            applyRateLimitObservations: true,
            allowAutoSwitch: true,
            preservingError: nil,
            throttled: false,
            refreshUsage: true,
            refreshUsageActivityOnly: true
        )
    }

    func refreshUsageNow() {
        refresh(
            applyRateLimitObservations: false,
            allowAutoSwitch: true,
            preservingError: nil,
            throttled: false
        )
    }

    func refreshAPIBalancesNow() {
        Task {
            await refreshDueAPIBalances(force: true)
        }
    }

    func refreshTrendsIfNeeded() {
        guard !hasLoadedFullUsageSnapshot else { return }
        refreshUsageNow()
    }

    func refreshFromMenuOpen() {
        refresh(
            applyRateLimitObservations: true,
            allowAutoSwitch: false,
            preservingError: nil,
            throttled: true,
            refreshUsage: false,
            refreshUsageIfEmpty: false
        )
    }

    private func refresh(
        applyRateLimitObservations: Bool,
        allowAutoSwitch: Bool,
        preservingError preservedError: String?,
        throttled: Bool,
        refreshUsage: Bool = true,
        refreshUsageIfEmpty: Bool = true,
        refreshUsageActivityOnly: Bool = false
    ) {
        guard !isRefreshInProgress else { return }
        let refreshStartedAt = now()
        if throttled,
           !usageSnapshot.threads.isEmpty,
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
        do {
            switchEvents = try auditLog.loadEvents().sorted { $0.timestamp > $1.timestamp }
        } catch {
            refreshErrors.append(error.localizedDescription)
        }
        do {
            appLogEvents = try appActivityLog.loadEvents().sorted { $0.timestamp > $1.timestamp }
        } catch {
            refreshErrors.append(error.localizedDescription)
        }

        let shouldRefreshUsage = refreshUsage || (refreshUsageIfEmpty && usageSnapshot.threads.isEmpty)
        if shouldRefreshUsage, !refreshUsageActivityOnly {
            isLoadingFullUsageSnapshot = true
            let usageReader = threadUsageReader
            let usageNow = refreshStartedAt
            let usageAccountWindows = Self.accountUsageWindows(
                accounts: loadedAccounts,
                switchEvents: switchEvents,
                currentAccount: currentAccount
            )
            let previousSnapshot = usageSnapshot
            let currentStrings = strings
            let baseErrors = refreshErrors

            usageRefreshTask?.cancel()
            usageRefreshTask = Task.detached(priority: .utility) {
                let latestUsageSnapshot = usageReader.readSnapshot(
                    now: usageNow,
                    accountWindows: usageAccountWindows
                )

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    var finalErrors = baseErrors
                    if latestUsageSnapshot.isDegraded, !previousSnapshot.threads.isEmpty {
                        finalErrors.append(latestUsageSnapshot.errorSummary ?? currentStrings.usageReadFailed)
                    } else {
                        self.applyUsageSnapshot(latestUsageSnapshot)
                    }
                    self.hasLoadedFullUsageSnapshot = true
                    self.isLoadingFullUsageSnapshot = false
                    self.finishRefresh(
                        errors: finalErrors,
                        preservedError: preservedError,
                        allowAutoSwitch: allowAutoSwitch
                    )
                }
            }
            return
        } else if shouldRefreshUsage {
            let latestUsageSnapshot = threadUsageReader.readActivitySnapshot(now: refreshStartedAt)
            if latestUsageSnapshot.isDegraded, !usageSnapshot.threads.isEmpty {
                refreshErrors.append(latestUsageSnapshot.errorSummary ?? strings.usageReadFailed)
            } else {
                applyUsageSnapshot(latestUsageSnapshot, preservingTokenBuckets: refreshUsageActivityOnly)
            }
            if !refreshUsageActivityOnly {
                hasLoadedFullUsageSnapshot = true
                isLoadingFullUsageSnapshot = false
            }
        }

        if let usageError = usageSnapshot.errorSummary {
            refreshErrors.append(usageError)
        }

        finishRefresh(
            errors: refreshErrors,
            preservedError: preservedError,
            allowAutoSwitch: allowAutoSwitch
        )
    }

    private func finishRefresh(
        errors refreshErrors: [String],
        preservedError: String?,
        allowAutoSwitch: Bool
    ) {
        var refreshErrors = refreshErrors
        if let preservedError {
            refreshErrors.insert(preservedError, at: 0)
        }

        let newError = refreshErrors.isEmpty ? nil : refreshErrors.joined(separator: "\n")
        errorMessage = newError
        if newError != nil {
            errorDismissWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.errorMessage = nil
            }
            errorDismissWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
        }
        lastUpdatedAt = now()
        isRefreshing = false
        isRefreshInProgress = false

        if allowAutoSwitch {
            attemptAutoSwitchIfNeeded()
        }
    }

    private func applyUsageSnapshot(_ snapshot: ThreadUsageSnapshot, preservingTokenBuckets: Bool = false) {
        if preservingTokenBuckets {
            usageSnapshot = ThreadUsageSnapshot(
                threads: snapshot.threads,
                totalTokens: snapshot.totalTokens,
                activeThread: snapshot.activeThread,
                dailyTokenUsage: usageSnapshot.dailyTokenUsage,
                hourlyTokenUsage: usageSnapshot.hourlyTokenUsage,
                monthlyTokenUsage: usageSnapshot.monthlyTokenUsage,
                accountUsageSummaries: usageSnapshot.accountUsageSummaries,
                errorSummary: snapshot.errorSummary
            )
        } else {
            usageSnapshot = snapshot
        }
        topThreads = Array(snapshot.threads.sorted { $0.tokensUsed > $1.tokensUsed }.prefix(10))
    }

    func attemptAutoSwitchIfNeeded() {
        guard config.autoSwitchEnabled, !isSwitchInProgress else { return }
        let timestamp = now()
        if let autoSwitchSuppressedUntil {
            guard timestamp >= autoSwitchSuppressedUntil else { return }
            self.autoSwitchSuppressedUntil = nil
        }
        let policy = SwitchPolicy(
            primaryThresholdPercent: config.primaryThresholdPercent,
            secondaryThresholdPercent: config.secondaryThresholdPercent
        )
        if currentAccount?.isAPIProvider == true {
            let latestUsageSnapshot = threadUsageReader.readActivitySnapshot(now: timestamp)
            if latestUsageSnapshot.isDegraded, !usageSnapshot.threads.isEmpty {
                errorMessage = latestUsageSnapshot.errorSummary ?? strings.usageReadFailed
                return
            }
            applyUsageSnapshot(latestUsageSnapshot, preservingTokenBuckets: true)
        }
        let context = SwitchSafetyContext(
            now: timestamp,
            activeThreadUpdatedAt: usageSnapshot.activeThread?.updatedAt,
            lastSwitchAt: lastSuccessfulSwitchAt
        )
        guard policy.shouldAutoSwitch(currentAccount: currentAccount, allAccounts: accounts, context: context),
              let target = candidateAccounts.first
        else {
            return
        }

        isSwitchInProgress = true
        defer { isSwitchInProgress = false }
        accountSaveStatus = nil

        do {
            if target.isChatGPT {
                codexDesktopManager.quitForCleanSwitch()
            }
            _ = try switcher.switchToAccount(target.id, trigger: .autoPrimaryThreshold)
            refresh(
                applyRateLimitObservations: false,
                allowAutoSwitch: false,
                preservingError: nil,
                throttled: false,
                refreshUsage: false,
                refreshUsageIfEmpty: false
            )
            if target.isChatGPT {
                postSwitchRestartMessage = nil
                try codexDesktopManager.restart()
            } else {
                handlePostSwitchAction()
            }
        } catch {
            let preservedError = pauseAutoSwitchIfRollbackFailed(error)
            refresh(
                applyRateLimitObservations: false,
                allowAutoSwitch: false,
                preservingError: preservedError,
                throttled: false,
                refreshUsage: false,
                refreshUsageIfEmpty: false
            )
        }
    }

    func saveCurrentAccount(alias: String) {
        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedAlias = trimmedAlias.isEmpty ? "Codex Account" : trimmedAlias
        do {
            let account = try accountStore.saveCurrentAuth(alias: savedAlias)
            accountSaveStatus = .success(alias: account.alias)
            recordAppLog(kind: .accountSaved, account: account)
            refreshNow()
        } catch {
            accountSaveStatus = .failure(message: error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func importAuthSnapshot(alias: String, fileURL: URL) {
        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAlias.isEmpty else {
            errorMessage = strings.aliasRequired
            accountSaveStatus = .failure(message: strings.aliasRequired)
            return
        }

        do {
            let account = try accountStore.importAuthSnapshot(from: fileURL, alias: trimmedAlias)
            accountSaveStatus = .success(alias: account.alias)
            recordAppLog(kind: .authImported, account: account)
            refreshNow()
        } catch {
            accountSaveStatus = .failure(message: error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func saveAPIProviderAccount(
        alias: String,
        baseURLText: String,
        apiKey: String,
        defaultModel: String
    ) {
        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAlias.isEmpty else {
            errorMessage = strings.aliasRequired
            accountSaveStatus = .failure(message: strings.aliasRequired)
            return
        }

        guard let baseURL = URL(string: baseURLText),
              baseURL.scheme?.hasPrefix("http") == true
        else {
            errorMessage = strings.invalidBaseURL
            accountSaveStatus = .failure(message: strings.invalidBaseURL)
            return
        }

        let trimmedModel = defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let account = try accountStore.saveAPIProvider(
                alias: trimmedAlias,
                providerName: trimmedAlias,
                baseURL: baseURL,
                apiKey: apiKey,
                defaultModel: trimmedModel.isEmpty ? nil : trimmedModel
            )
            accountSaveStatus = .success(alias: account.alias)
            recordAppLog(kind: .apiProviderSaved, account: account)
            refreshNow()
        } catch {
            accountSaveStatus = .failure(message: error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func updateAPIProviderAccount(
        _ account: CodixxAccount,
        alias: String,
        baseURLText: String,
        apiKey: String,
        defaultModel: String,
        balanceQuery: APIBalanceQueryConfig? = nil
    ) {
        accountSaveStatus = nil
        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAlias.isEmpty else {
            errorMessage = strings.aliasRequired
            accountSaveStatus = .failure(message: strings.aliasRequired)
            return
        }

        guard let baseURL = URL(string: baseURLText),
              baseURL.scheme?.hasPrefix("http") == true
        else {
            errorMessage = strings.invalidBaseURL
            accountSaveStatus = .failure(message: strings.invalidBaseURL)
            return
        }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKeyToSave = trimmedKey == maskedAPIKey(for: account) ? nil : trimmedKey
        let trimmedModel = defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let updatedAccount = try accountStore.updateAPIProvider(
                account.id,
                alias: trimmedAlias,
                baseURL: baseURL,
                apiKey: apiKeyToSave?.isEmpty == true ? nil : apiKeyToSave,
                defaultModel: trimmedModel.isEmpty ? nil : trimmedModel,
                balanceQuery: balanceQuery
            )
            if let index = accounts.firstIndex(where: { $0.id == updatedAccount.id }) {
                accounts[index] = updatedAccount
            }
            if currentAccount?.id == updatedAccount.id {
                currentAccount = updatedAccount
            }
            recordAppLog(kind: .apiProviderUpdated, account: updatedAccount)
            refresh(
                applyRateLimitObservations: false,
                allowAutoSwitch: false,
                preservingError: nil,
                throttled: false
            )
        } catch {
            accountSaveStatus = .failure(message: error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func maskedAPIKey(for account: CodixxAccount) -> String? {
        guard let fingerprint = account.apiProvider?.keyFingerprint else { return nil }
        if let apiKey = try? apiKeyVault.load(fingerprint: fingerprint) {
            return Self.maskAPIKey(apiKey)
        }
        return Self.maskAPIKeyFingerprint(fingerprint)
    }

    func resolveAPIKeyForTesting(account: CodixxAccount?, apiKeyText: String) -> String? {
        let trimmedKey = apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let account else { return trimmedKey.isEmpty ? nil : trimmedKey }
        if trimmedKey == maskedAPIKey(for: account),
           let fingerprint = account.apiProvider?.keyFingerprint,
           let storedKey = try? apiKeyVault.load(fingerprint: fingerprint)
        {
            return storedKey
        }
        return trimmedKey.isEmpty ? nil : trimmedKey
    }

    func testAPIProviderConnection(
        account: CodixxAccount?,
        baseURLText: String,
        apiKeyText: String,
        defaultModel: String
    ) async -> APIProviderConnectivityResult {
        guard let baseURL = URL(string: baseURLText),
              baseURL.scheme?.hasPrefix("http") == true
        else {
            return APIProviderConnectivityResult(isSuccess: false, message: strings.invalidBaseURL)
        }
        guard let apiKey = resolveAPIKeyForTesting(account: account, apiKeyText: apiKeyText), !apiKey.isEmpty else {
            return APIProviderConnectivityResult(isSuccess: false, message: strings.requiredField(strings.apiKeyAccount))
        }
        let trimmedModel = defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = await connectivityTester.testConnection(
            baseURL: baseURL,
            apiKey: apiKey,
            defaultModel: trimmedModel.isEmpty ? nil : trimmedModel
        )
        if result.isSuccess {
            return APIProviderConnectivityResult(isSuccess: true, message: strings.connectionSucceeded)
        }
        return result
    }

    func testAPIBalanceQuery(account: CodixxAccount, config balanceQuery: APIBalanceQueryConfig) async -> APIBalanceQueryResult {
        guard let url = URL(string: balanceQuery.urlText),
              url.scheme?.hasPrefix("http") == true
        else {
            return APIBalanceQueryResult(isSuccess: false, message: strings.invalidBaseURL)
        }
        guard let fingerprint = account.apiProvider?.keyFingerprint,
              let apiKey = try? apiKeyVault.load(fingerprint: fingerprint)
        else {
            return APIBalanceQueryResult(isSuccess: false, message: strings.noAPIAccountForBalance)
        }
        let result = await balanceQueryTester.queryBalance(
            url: url,
            apiKey: apiKey,
            jsonPath: balanceQuery.jsonPath
        )
        return result
    }

    @discardableResult
    func refreshAPIBalance(for account: CodixxAccount) async -> APIBalanceQueryResult {
        guard var balanceQuery = account.apiProvider?.balanceQuery else {
            return APIBalanceQueryResult(isSuccess: false, message: strings.noAPIAccountForBalance)
        }

        let result = await testAPIBalanceQuery(account: account, config: balanceQuery)
        guard result.isSuccess else {
            recordAppLog(
                kind: .apiBalanceRefreshFailed,
                accountID: account.id,
                accountAlias: account.alias,
                detail: result.message
            )
            return result
        }

        balanceQuery.lastBalanceText = result.balanceText ?? result.message
        balanceQuery.lastRefreshedAt = now()
        do {
            let updatedAccount = try accountStore.updateAPIBalanceQuery(account.id, balanceQuery: balanceQuery)
            if let index = accounts.firstIndex(where: { $0.id == updatedAccount.id }) {
                accounts[index] = updatedAccount
            }
            if currentAccount?.id == updatedAccount.id {
                currentAccount = updatedAccount
            }
        } catch {
            errorMessage = error.localizedDescription
            recordAppLog(
                kind: .apiBalanceRefreshFailed,
                accountID: account.id,
                accountAlias: account.alias,
                detail: error.localizedDescription
            )
            return APIBalanceQueryResult(isSuccess: false, message: error.localizedDescription)
        }
        recordAppLog(
            kind: .apiBalanceRefreshed,
            accountID: account.id,
            accountAlias: account.alias,
            detail: result.balanceText ?? result.message
        )
        return result
    }

    func refreshDueAPIBalances(force: Bool = false) async {
        let timestamp = now()
        var didRefresh = false
        for account in accounts where account.isAPIProvider {
            guard let balanceQuery = account.apiProvider?.balanceQuery,
                  balanceQuery.isEnabled
            else {
                continue
            }
            if !force,
               let lastRefreshedAt = balanceQuery.lastRefreshedAt,
               timestamp.timeIntervalSince(lastRefreshedAt) < balanceQuery.refreshIntervalSeconds
            {
                continue
            }
            let result = await refreshAPIBalance(for: account)
            didRefresh = didRefresh || result.isSuccess
        }
        if didRefresh {
            attemptAutoSwitchIfNeeded()
        }
    }

    func switchToAccount(_ account: CodixxAccount) {
        accountSaveStatus = nil
        guard account.isAPIProvider else {
            switchToAccountAndRestartCodex(account)
            return
        }
        guard !isSwitchInProgress else { return }
        isSwitchInProgress = true
        defer { isSwitchInProgress = false }

        let codexActivation = codexDesktopManager.currentActivation()
        refresh(
            applyRateLimitObservations: true,
            allowAutoSwitch: false,
            preservingError: nil,
            throttled: false,
            refreshUsage: false,
            refreshUsageIfEmpty: false
        )

        do {
            _ = try switcher.switchToAccount(account.id, trigger: .manual)
            suppressAutoSwitchAfterManualSwitch()
            refresh(
                applyRateLimitObservations: false,
                allowAutoSwitch: false,
                preservingError: nil,
                throttled: false,
                refreshUsage: false,
                refreshUsageIfEmpty: false
            )
            handlePostSwitchAction()
            codexDesktopManager.restoreActivationIfNeeded(codexActivation)
        } catch {
            let preservedError = pauseAutoSwitchIfRollbackFailed(error)
            refresh(
                applyRateLimitObservations: false,
                allowAutoSwitch: false,
                preservingError: preservedError,
                throttled: false,
                refreshUsage: false,
                refreshUsageIfEmpty: false
            )
        }
    }

    func switchToAccountAndRestartCodex(_ account: CodixxAccount) {
        guard !isSwitchInProgress else { return }
        isSwitchInProgress = true
        defer { isSwitchInProgress = false }
        accountSaveStatus = nil

        refresh(
            applyRateLimitObservations: true,
            allowAutoSwitch: false,
            preservingError: nil,
            throttled: false,
            refreshUsage: false,
            refreshUsageIfEmpty: false
        )

        do {
            codexDesktopManager.quitForCleanSwitch()
            _ = try switcher.switchToAccount(account.id, trigger: .manual)
            suppressAutoSwitchAfterManualSwitch()
            refresh(
                applyRateLimitObservations: false,
                allowAutoSwitch: false,
                preservingError: nil,
                throttled: false,
                refreshUsage: false,
                refreshUsageIfEmpty: false
            )
            postSwitchRestartMessage = nil
            try codexDesktopManager.restart()
        } catch {
            let preservedError = pauseAutoSwitchIfRollbackFailed(error)
            refresh(
                applyRateLimitObservations: false,
                allowAutoSwitch: false,
                preservingError: preservedError,
                throttled: false,
                refreshUsage: false,
                refreshUsageIfEmpty: false
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

    func moveAccount(_ account: CodixxAccount, before target: CodixxAccount) {
        guard account.id != target.id,
              let sourceIndex = accounts.firstIndex(where: { $0.id == account.id }),
              let targetIndex = accounts.firstIndex(where: { $0.id == target.id })
        else { return }

        var reorderedAccounts = accounts
        let movedAccount = reorderedAccounts.remove(at: sourceIndex)
        let insertionIndex = reorderedAccounts.firstIndex(where: { $0.id == target.id }) ?? targetIndex
        reorderedAccounts.insert(movedAccount, at: insertionIndex)

        do {
            try metadataStore.save(AccountMetadataList(accounts: reorderedAccounts))
            accounts = reorderedAccounts
            recordAppLog(kind: .accountReordered, account: movedAccount)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renameAccount(_ account: CodixxAccount, alias: String) {
        accountSaveStatus = nil
        do {
            let renamed = try accountStore.renameAccount(account.id, alias: alias)
            recordAppLog(
                kind: .accountRenamed,
                accountID: account.id,
                accountAlias: account.alias,
                secondaryAlias: renamed.alias
            )
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
        accountSaveStatus = nil
        do {
            try accountStore.deleteAccount(account.id)
            recordAppLog(kind: .accountDeleted, account: account)
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
        if config.notificationsEnabled {
            onNotificationsEnabled?()
        }
    }

    func setPrimaryThresholdPercent(_ percent: Double) {
        updateConfig { $0.primaryThresholdPercent = percent }
    }

    func setSecondaryThresholdPercent(_ percent: Double) {
        updateConfig { $0.secondaryThresholdPercent = percent }
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

    func setAPISwitchThreadSyncScope(_ scope: APISwitchThreadSyncScope) {
        updateConfig { $0.apiSwitchThreadSyncScope = scope }
    }

    func restartCodexNow() {
        do {
            postSwitchRestartMessage = nil
            try codexDesktopManager.restart()
            recordAppLog(kind: .codexRestarted)
        } catch {
            errorMessage = "\(strings.restartCodexFailed): \(error.localizedDescription)"
            recordAppLog(kind: .codexRestartFailed, detail: error.localizedDescription)
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

    private func suppressAutoSwitchAfterManualSwitch() {
        autoSwitchSuppressedUntil = now().addingTimeInterval(manualSwitchAutoSuppressionSeconds)
    }

    private func quotaPercentText(_ percent: Double?) -> String {
        percent.map { "\(Int($0.rounded()))%" } ?? "--"
    }

    static func accountUsageWindows(
        accounts: [CodixxAccount],
        switchEvents: [SwitchAuditEvent],
        currentAccount: CodixxAccount? = nil
    ) -> [AccountUsageWindow] {
        let accountIds = Set(accounts.map(\.id))
        let successfulSwitches = switchEvents
            .filter { $0.result == .success && $0.targetAccountId != nil }
            .sorted { $0.timestamp < $1.timestamp }

        if successfulSwitches.isEmpty {
            let account = currentAccount.flatMap { accountIds.contains($0.id) ? $0 : nil }
                ?? accounts
                    .filter { accountIds.contains($0.id) }
                    .max { ($0.lastUsedAt ?? $0.updatedAt) < ($1.lastUsedAt ?? $1.updatedAt) }
            if let account {
                return [AccountUsageWindow(accountId: account.id, start: .distantPast, end: nil)]
            }
        }

        var windows: [AccountUsageWindow] = []
        if let firstSwitch = successfulSwitches.first,
           let sourceId = firstSwitch.sourceAccountId,
           accountIds.contains(sourceId)
        {
            if Date.distantPast < firstSwitch.timestamp {
                windows.append(AccountUsageWindow(accountId: sourceId, start: .distantPast, end: firstSwitch.timestamp))
            }
        }

        for (index, event) in successfulSwitches.enumerated() {
            guard let accountId = event.targetAccountId, accountIds.contains(accountId) else { continue }
            let end = successfulSwitches.indices.contains(index + 1) ? successfulSwitches[index + 1].timestamp : nil
            windows.append(AccountUsageWindow(accountId: accountId, start: event.timestamp, end: end))
        }

        if let currentAccount,
           accountIds.contains(currentAccount.id),
           let latestSwitchAt = successfulSwitches.last?.timestamp
        {
            let currentStart = currentAccount.lastUsedAt ?? currentAccount.updatedAt
            let currentWindowIsOpen = windows.last { $0.end == nil }?.accountId == currentAccount.id
            if currentStart > latestSwitchAt, !currentWindowIsOpen {
                windows = windows.map { window in
                    guard window.end == nil,
                          window.start < currentStart
                    else { return window }

                    var updated = window
                    updated.end = currentStart
                    return updated
                }
                windows.append(AccountUsageWindow(accountId: currentAccount.id, start: currentStart, end: nil))
            }
        }

        return windows
    }

    private func handlePostSwitchAction() {
        switch config.postSwitchAction {
        case .none:
            break
        case .notifyRestartRecommended:
            postSwitchRestartMessage = strings.restartCodexHint
        case .restartCodexApp:
            postSwitchRestartMessage = strings.restartCodexHint
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
            if accounts[index].isEnabled != account.isEnabled {
                recordAppLog(
                    kind: accounts[index].isEnabled ? .accountEnabled : .accountDisabled,
                    account: accounts[index]
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recordAppLog(
        kind: AppLogEventKind,
        account: CodixxAccount? = nil,
        detail: String? = nil
    ) {
        recordAppLog(
            kind: kind,
            accountID: account?.id,
            accountAlias: account?.alias,
            detail: detail
        )
    }

    private func recordAppLog(
        kind: AppLogEventKind,
        accountID: UUID? = nil,
        accountAlias: String? = nil,
        secondaryAlias: String? = nil,
        detail: String? = nil
    ) {
        let event = AppLogEvent(
            timestamp: now(),
            kind: kind,
            accountId: accountID,
            accountAlias: accountAlias,
            secondaryAlias: secondaryAlias,
            detail: detail
        )
        do {
            try appActivityLog.append(event)
            appLogEvents = try appActivityLog.loadEvents().sorted { $0.timestamp > $1.timestamp }
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
        let minimumObservedAt = current.lastUsedAt
        let observations = try rateLimitReader.readNewObservations().filter { observation in
            guard let minimumObservedAt else { return true }
            return observation.observedAt >= minimumObservedAt
        }
        guard let observation = Self.preferredRateLimitObservation(in: observations) else {
            if didRefreshCachedQuota {
                try metadataStore.save(AccountMetadataList(accounts: accounts))
            }
            return
        }

        let profile = currentAuthProfile()
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

    static func preferredRateLimitObservation(in observations: [RateLimitObservation]) -> RateLimitObservation? {
        observations.last { $0.limitID == "codex" } ?? observations.last { $0.limitID == nil }
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
        return accounts.first { account in
            account.fingerprint == fingerprint || account.apiProvider?.keyFingerprint == fingerprint
        }
    }

    private func currentAuthProfile() -> AuthProfile? {
        guard let data = try? Data(contentsOf: paths.authJSON),
              let snapshot = try? AuthSnapshot(jsonData: data)
        else {
            return nil
        }
        return AuthProfileReader.profile(from: snapshot)
    }

    private var lastSuccessfulSwitchAt: Date? {
        switchEvents
            .filter { $0.result == .success }
            .map(\.timestamp)
            .max()
    }

    private static func maskAPIKey(_ apiKey: String) -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedKey.count > 8 else { return "••••" }
        let prefix = trimmedKey.prefix(6)
        let suffix = trimmedKey.suffix(4)
        return "\(prefix)...\(suffix)"
    }

    private static func maskAPIKeyFingerprint(_ fingerprint: String) -> String {
        let hash = fingerprint.replacingOccurrences(of: "api-key:", with: "")
        guard hash.count >= 8 else { return "sk-..." }
        return "sk-\(hash.prefix(4))...\(hash.suffix(4))"
    }

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
