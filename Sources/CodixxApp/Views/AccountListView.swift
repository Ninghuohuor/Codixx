import AppKit
import SwiftUI
import CodixxCore
import UniformTypeIdentifiers

struct AccountSummaryMetrics: Equatable {
    var total: Int
    var available: Int
    var full: Int
    var unknown: Int
    var disabled: Int

    init(accounts: [CodixxAccount]) {
        total = accounts.count
        available = 0
        full = 0
        unknown = 0
        disabled = 0

        for account in accounts {
            guard account.isEnabled else {
                disabled += 1
                continue
            }

            if account.isAPIProvider {
                switch Self.apiProviderStatus(for: account) {
                case .available:
                    available += 1
                case .full:
                    full += 1
                case .unknown:
                    unknown += 1
                }
                continue
            }

            guard let primary = account.quota.primaryUsedPercent,
                  let secondary = account.quota.secondaryUsedPercent
            else {
                unknown += 1
                continue
            }

            if primary >= 100 || secondary >= 100 {
                full += 1
            } else {
                available += 1
            }
        }
    }

    private enum APIProviderSummaryStatus {
        case available
        case full
        case unknown
    }

    private static func apiProviderStatus(for account: CodixxAccount) -> APIProviderSummaryStatus {
        guard let balanceQuery = account.apiProvider?.balanceQuery,
              balanceQuery.isEnabled
        else {
            return .unknown
        }
        if balanceQuery.hasSufficientBalance {
            return .available
        }
        if balanceQuery.isBalanceDepleted || isInsufficientBalanceText(balanceQuery.lastBalanceText) {
            return .full
        }
        return .unknown
    }

    private static func isInsufficientBalanceText(_ text: String?) -> Bool {
        guard let text else { return false }
        let normalized = text.lowercased()
        return normalized.contains("insufficient balance")
            || normalized.contains("insufficient funds")
            || normalized.contains("insufficient quota")
            || normalized.contains("余额不足")
            || normalized.contains("额度不足")
    }
}

struct AccountListView: View {
    @ObservedObject var state: AppState
    @State private var addAccountPanel: AddAccountPanelController?
    @State private var editAccountPanel: EditAccountPanelController?
    @State private var balanceMonitorPanel: BalanceMonitorPanelController?
    @State private var parentWindow: NSWindow?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(state.strings.accounts)
                        .font(.headline)
                    Text(lastUpdatedText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        state.refreshNow()
                    } label: {
                        Image(systemName: state.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(state.strings.refresh)

                    Button {
                        showAddAccountPanel()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help(state.strings.addAccount)
                }

                if !state.accounts.isEmpty {
                    AccountSummaryView(
                        metrics: AccountSummaryMetrics(accounts: state.accounts),
                        strings: state.strings
                    )
                }

                if !state.canEnableAutoSwitch {
                    Label(state.strings.autoSwitchNeedsTwoAccounts, systemImage: "person.crop.circle.badge.plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }

                if state.accounts.isEmpty {
                    Text(state.strings.noSavedAccounts)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    AccountRowsView(
                        state: state,
                        onEdit: showEditAccountPanel,
                        onBalanceMonitor: showBalanceMonitorPanel,
                        parentWindow: presentationParentWindow
                    )
                }
            }
            .padding(14)
        }
        .background(WindowReader { window in
            parentWindow = window
        })
    }

    private var lastUpdatedText: String {
        guard let lastUpdatedAt = state.lastUpdatedAt else { return state.strings.notRefreshedYet }
        return state.strings.updated(lastUpdatedAt)
    }

    private func showAddAccountPanel() {
        if let addAccountPanel {
            addAccountPanel.show(attachedTo: presentationParentWindow)
            return
        }
        let panel = AddAccountPanelController(state: state) {
            addAccountPanel = nil
        }
        addAccountPanel = panel
        panel.show(attachedTo: presentationParentWindow)
    }

    private func showEditAccountPanel(_ account: CodixxAccount) {
        if let editAccountPanel {
            editAccountPanel.close()
            self.editAccountPanel = nil
        }
        let panel = EditAccountPanelController(state: state, account: account) {
            editAccountPanel = nil
        }
        editAccountPanel = panel
        panel.show(attachedTo: presentationParentWindow)
    }

    private func showBalanceMonitorPanel(_ account: CodixxAccount) {
        if let balanceMonitorPanel {
            balanceMonitorPanel.close()
            self.balanceMonitorPanel = nil
        }
        let panel = BalanceMonitorPanelController(state: state, account: account) {
            balanceMonitorPanel = nil
        }
        balanceMonitorPanel = panel
        panel.show(attachedTo: presentationParentWindow)
    }

    private var presentationParentWindow: NSWindow? {
        parentWindow ?? NSApplication.shared.keyWindow
    }
}

private struct AccountSummaryView: View {
    var metrics: AccountSummaryMetrics
    var strings: CodixxStrings

    var body: some View {
        HStack(spacing: 6) {
            summaryPill(label: strings.accountSummaryTotal, value: metrics.total, tint: .secondary)
            summaryPill(label: strings.accountSummaryAvailable, value: metrics.available, tint: .green)
            summaryPill(label: strings.accountSummaryFull, value: metrics.full, tint: .red)
            summaryPill(label: strings.accountSummaryUnknown, value: metrics.unknown, tint: .orange)
            if metrics.disabled > 0 {
                summaryPill(label: strings.accountSummaryDisabled, value: metrics.disabled, tint: .secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryPill(label: String, value: Int, tint: Color) -> some View {
        Text("\(label) \(value)")
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.10), in: Capsule())
            .help("\(label) \(value)")
    }
}

private enum AddAccountCredentialKind: Hashable {
    case currentCodexAuth
    case importedCodexAuth
    case apiProvider
}

private struct AddAccountDialog: View {
    @ObservedObject var state: AppState
    let onClose: () -> Void
    @State private var newAlias = ""
    @State private var credentialKind: AddAccountCredentialKind = .currentCodexAuth
    @State private var selectedAuthJSONURL: URL?
    @State private var baseURLText = ""
    @State private var apiKey = ""
    @State private var defaultModel = ""
    @State private var connectionTestStatus: ConnectionTestStatus?
    @State private var isTestingConnection = false
    @State private var dialogWindow: NSWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.strings.addAccount)
                .font(.headline)

            Picker("", selection: $credentialKind) {
                Text(state.strings.codexLoginAccount).tag(AddAccountCredentialKind.currentCodexAuth)
                Text(state.strings.importAuthJSONAccount).tag(AddAccountCredentialKind.importedCodexAuth)
                Text(state.strings.apiKeyAccount).tag(AddAccountCredentialKind.apiProvider)
            }
            .pickerStyle(.segmented)

            if credentialKind == .currentCodexAuth {
                apiProviderTextField(state.strings.alias, required: true, text: $newAlias)
            } else if credentialKind == .importedCodexAuth {
                apiProviderTextField(state.strings.alias, required: true, text: $newAlias)
                authJSONPicker
            } else {
                apiProviderTextField(state.strings.alias, required: true, text: $newAlias)
                apiProviderTextField(state.strings.baseURL, required: true, text: $baseURLText)
                apiProviderSecureField(state.strings.apiKeyAccount, required: true, text: $apiKey)
                apiProviderTextField(state.strings.defaultModel, required: false, text: $defaultModel)
            }

            if let accountSaveStatus = state.accountSaveStatus {
                Label(saveStatusText(accountSaveStatus), systemImage: saveStatusIcon(accountSaveStatus))
                    .font(.caption)
                    .foregroundStyle(saveStatusColor(accountSaveStatus))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let connectionTestStatus {
                Label(connectionTestStatus.message, systemImage: connectionTestStatus.icon)
                    .font(.caption)
                    .foregroundStyle(connectionTestStatus.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
                .padding(.top, 4)

            HStack {
                Button(state.strings.cancel) {
                    onClose()
                }
                Spacer()
                if credentialKind == .apiProvider {
                    Button {
                        testConnection()
                    } label: {
                        Label(
                            isTestingConnection ? state.strings.testingConnection : state.strings.testConnection,
                            systemImage: isTestingConnection ? "hourglass" : "network"
                        )
                    }
                    .disabled(!canTestConnection || isTestingConnection)
                }
                Button {
                    save()
                } label: {
                    Label(state.strings.save, systemImage: "key")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 420)
        .background(WindowReader { window in
            dialogWindow = window
        })
    }

    private var canSave: Bool {
        switch credentialKind {
        case .currentCodexAuth:
            return !newAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .importedCodexAuth:
            return !newAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                selectedAuthJSONURL != nil
        case .apiProvider:
            return !newAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !baseURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var canTestConnection: Bool {
        !baseURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func testConnection() {
        isTestingConnection = true
        connectionTestStatus = .info(state.strings.testingConnection)
        Task {
            let result = await state.testAPIProviderConnection(
                account: nil,
                baseURLText: baseURLText,
                apiKeyText: apiKey,
                defaultModel: defaultModel
            )
            await MainActor.run {
                isTestingConnection = false
                connectionTestStatus = result.isSuccess ? .success(result.message) : .failure(result.message)
            }
        }
    }

    private func save() {
        switch credentialKind {
        case .currentCodexAuth:
            state.saveCurrentAccount(alias: newAlias)
        case .importedCodexAuth:
            guard let selectedAuthJSONURL else { return }
            state.importAuthSnapshot(alias: newAlias, fileURL: selectedAuthJSONURL)
        case .apiProvider:
            state.saveAPIProviderAccount(
                alias: newAlias,
                baseURLText: baseURLText,
                apiKey: apiKey,
                defaultModel: defaultModel
            )
        }
        closeAfterSuccessfulSave()
    }

    private func closeAfterSuccessfulSave() {
        guard case .success = state.accountSaveStatus else { return }
        onClose()
    }

    fileprivate func reset() {
        newAlias = ""
        credentialKind = .currentCodexAuth
        selectedAuthJSONURL = nil
        baseURLText = ""
        apiKey = ""
        defaultModel = ""
    }

    private var authJSONPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(state.strings.chooseAuthJSON)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button {
                    chooseAuthJSON()
                } label: {
                    Label(state.strings.chooseAuthJSON, systemImage: "doc.badge.plus")
                }
                Text(selectedAuthJSONURL?.lastPathComponent ?? state.strings.noAuthJSONSelected)
                    .font(.caption)
                    .foregroundStyle(selectedAuthJSONURL == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func chooseAuthJSON() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [.json]
        panel.directoryURL = authJSONPickerDirectory
        panel.nameFieldStringValue = "auth.json"
        panel.message = state.strings.importAuthJSONPickerMessage
        panel.prompt = state.strings.chooseAuthJSON
        guard let parentWindow = dialogWindow ?? NSApplication.shared.keyWindow else {
            if PopoverPanelPresentation.runModal(panel, parent: nil) == .OK {
                selectedAuthJSONURL = panel.url
            }
            return
        }
        panel.beginSheetModal(for: parentWindow) { response in
            guard response == .OK else { return }
            selectedAuthJSONURL = panel.url
        }
    }

    private var authJSONPickerDirectory: URL {
        if let selectedAuthJSONURL {
            return selectedAuthJSONURL.deletingLastPathComponent()
        }
        if FileManager.default.fileExists(atPath: state.paths.codexHome.path) {
            return state.paths.codexHome
        }
        return state.paths.home
    }

    private func apiProviderTextField(_ label: String, required: Bool, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(apiProviderFieldLabel(label, required: required))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func apiProviderSecureField(_ label: String, required: Bool, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(apiProviderFieldLabel(label, required: required))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            SecureField(label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func apiProviderFieldLabel(_ label: String, required: Bool) -> String {
        required ? state.strings.requiredField(label) : state.strings.optionalField(label)
    }

    private func saveStatusText(_ status: AccountSaveStatus) -> String {
        switch status {
        case .success(let alias):
            return state.strings.savedCurrentAccount(alias: alias)
        case .failure(let message):
            return state.strings.couldNotSaveCurrentAccount(message)
        }
    }

    private func saveStatusIcon(_ status: AccountSaveStatus) -> String {
        switch status {
        case .success:
            return "checkmark.circle"
        case .failure:
            return "exclamationmark.triangle"
        }
    }

    private func saveStatusColor(_ status: AccountSaveStatus) -> Color {
        switch status {
        case .success:
            return .green
        case .failure:
            return .orange
        }
    }
}

private struct EditAccountDialog: View {
    @ObservedObject var state: AppState
    let account: CodixxAccount
    let onClose: () -> Void
    @State private var alias: String
    @State private var baseURLText: String
    @State private var apiKey = ""
    @State private var defaultModel: String
    @State private var connectionTestStatus: ConnectionTestStatus?
    @State private var isTestingConnection = false

    init(state: AppState, account: CodixxAccount, onClose: @escaping () -> Void) {
        self.state = state
        self.account = account
        self.onClose = onClose
        _alias = State(initialValue: account.alias)
        _baseURLText = State(initialValue: account.apiProvider?.baseURL.absoluteString ?? "")
        _apiKey = State(initialValue: state.maskedAPIKey(for: account) ?? "")
        _defaultModel = State(initialValue: account.apiProvider?.defaultModel ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.strings.editAccount)
                .font(.headline)

            Text(account.isAPIProvider ? state.strings.apiKeyAccount : state.strings.codexLoginAccount)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

            accountTextField(state.strings.alias, required: true, text: $alias)
            if account.isAPIProvider {
                accountTextField(state.strings.baseURL, required: true, text: $baseURLText)
                accountSecureField(state.strings.savedReplaceableAPIKey, text: $apiKey)
                accountTextField(state.strings.defaultModel, required: false, text: $defaultModel)
            }

            if let accountSaveStatus = state.accountSaveStatus {
                Label(saveStatusText(accountSaveStatus), systemImage: saveStatusIcon(accountSaveStatus))
                    .font(.caption)
                    .foregroundStyle(saveStatusColor(accountSaveStatus))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let connectionTestStatus {
                Label(connectionTestStatus.message, systemImage: connectionTestStatus.icon)
                    .font(.caption)
                    .foregroundStyle(connectionTestStatus.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
                .padding(.top, 4)

            HStack {
                Button(state.strings.cancel) {
                    onClose()
                }
                Spacer()
                if account.isAPIProvider {
                    Button {
                        testConnection()
                    } label: {
                        Label(
                            isTestingConnection ? state.strings.testingConnection : state.strings.testConnection,
                            systemImage: isTestingConnection ? "hourglass" : "network"
                        )
                    }
                    .disabled(!canTestConnection || isTestingConnection)
                }
                Button {
                    save()
                } label: {
                    Label(state.strings.save, systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 420)
    }

    private var canSave: Bool {
        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAlias.isEmpty else { return false }
        if account.isAPIProvider {
            return !baseURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return trimmedAlias != account.alias
    }

    private var canTestConnection: Bool {
        account.isAPIProvider &&
            !baseURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        if account.isAPIProvider {
            state.updateAPIProviderAccount(
                account,
                alias: alias,
                baseURLText: baseURLText,
                apiKey: apiKey,
                defaultModel: defaultModel
            )
        } else {
            state.renameAccount(account, alias: alias)
        }
        guard state.errorMessage == nil else { return }
        onClose()
    }

    private func testConnection() {
        isTestingConnection = true
        connectionTestStatus = .info(state.strings.testingConnection)
        Task {
            let result = await state.testAPIProviderConnection(
                account: account,
                baseURLText: baseURLText,
                apiKeyText: apiKey,
                defaultModel: defaultModel
            )
            await MainActor.run {
                isTestingConnection = false
                connectionTestStatus = result.isSuccess ? .success(result.message) : .failure(result.message)
            }
        }
    }

    private func accountTextField(_ label: String, required: Bool, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(fieldLabel(label, required: required))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func accountSecureField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            SecureField(label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func fieldLabel(_ label: String, required: Bool) -> String {
        required ? state.strings.requiredField(label) : state.strings.optionalField(label)
    }

    private func saveStatusText(_ status: AccountSaveStatus) -> String {
        switch status {
        case .success(let alias):
            return state.strings.savedCurrentAccount(alias: alias)
        case .failure(let message):
            return state.strings.couldNotSaveCurrentAccount(message)
        }
    }

    private func saveStatusIcon(_ status: AccountSaveStatus) -> String {
        switch status {
        case .success:
            return "checkmark.circle"
        case .failure:
            return "exclamationmark.triangle"
        }
    }

    private func saveStatusColor(_ status: AccountSaveStatus) -> Color {
        switch status {
        case .success:
            return .green
        case .failure:
            return .orange
        }
    }
}

private struct ConnectionTestStatus {
    let message: String
    let icon: String
    let color: Color

    static func info(_ message: String) -> ConnectionTestStatus {
        ConnectionTestStatus(message: message, icon: "hourglass", color: .secondary)
    }

    static func success(_ message: String) -> ConnectionTestStatus {
        ConnectionTestStatus(message: message, icon: "checkmark.circle", color: .green)
    }

    static func failure(_ message: String) -> ConnectionTestStatus {
        ConnectionTestStatus(message: message, icon: "exclamationmark.triangle", color: .orange)
    }
}

private struct BalanceMonitorDialog: View {
    @ObservedObject var state: AppState
    let account: CodixxAccount
    let onClose: () -> Void
    @State private var isEnabled: Bool
    @State private var urlText: String
    @State private var jsonPath: String
    @State private var refreshIntervalMinutes: Double
    @State private var minimumBalanceText: String
    @State private var status: ConnectionTestStatus?
    @State private var isTesting = false

    init(state: AppState, account: CodixxAccount, onClose: @escaping () -> Void) {
        self.state = state
        self.account = account
        self.onClose = onClose
        _isEnabled = State(initialValue: account.apiProvider?.balanceQuery?.isEnabled ?? false)
        _urlText = State(initialValue: account.apiProvider?.balanceQuery?.urlText ?? "")
        _jsonPath = State(initialValue: account.apiProvider?.balanceQuery?.jsonPath ?? "")
        _refreshIntervalMinutes = State(initialValue: max(1, (account.apiProvider?.balanceQuery?.refreshIntervalSeconds ?? 900) / 60))
        _minimumBalanceText = State(initialValue: Self.balanceFormatter.string(from: NSNumber(value: account.apiProvider?.balanceQuery?.minimumBalance ?? 0)) ?? "0")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.strings.apiBalanceSection)
                .font(.headline)
            Text(account.alias)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

            Toggle(state.strings.apiBalanceMonitoring, isOn: $isEnabled)

            Text(state.strings.balanceQueryHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            accountTextField(state.strings.balanceQueryURL, required: false, text: $urlText)
                .disabled(!isEnabled)

            accountTextField(state.strings.minimumAPIBalance, required: false, text: $minimumBalanceText)
                .disabled(!isEnabled)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(state.strings.balanceRefreshInterval): \(state.strings.minutesInterval(Int(refreshIntervalMinutes.rounded())))")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Slider(value: $refreshIntervalMinutes, in: 1...120, step: 1)
            }
            .disabled(!isEnabled)

            VStack(alignment: .leading, spacing: 4) {
                Text(state.strings.balanceJSONPath)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                TextEditor(text: $jsonPath)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 92)
                    .padding(4)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            }
            .disabled(!isEnabled)

            if let status {
                Label(status.message, systemImage: status.icon)
                    .font(.caption)
                    .foregroundStyle(status.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
                .padding(.top, 4)

            HStack {
                Button(state.strings.cancel) {
                    onClose()
                }
                Spacer()
                Button {
                    testBalanceQuery()
                } label: {
                    Label(
                        isTesting ? state.strings.testingBalanceQuery : state.strings.testBalanceQuery,
                        systemImage: isTesting ? "hourglass" : "creditcard"
                    )
                }
                .disabled(!canTest || isTesting)
                Button {
                    save()
                } label: {
                    Label(state.strings.save, systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 420)
    }

    private var isCCSwitchConfig: Bool {
        jsonPath.contains("request:") || jsonPath.contains("extractor:")
    }

    private var canTest: Bool {
        isEnabled &&
            !jsonPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (isCCSwitchConfig || !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func testBalanceQuery() {
        isTesting = true
        status = .info(state.strings.testingBalanceQuery)
        Task {
            let result = await state.testAPIBalanceQuery(account: account, config: config)
            await MainActor.run {
                isTesting = false
                status = result.isSuccess ? .success(result.message) : .failure(result.message)
            }
        }
    }

    private func save() {
        state.updateAPIProviderAccount(
            account,
            alias: account.alias,
            baseURLText: account.apiProvider?.baseURL.absoluteString ?? "",
            apiKey: state.maskedAPIKey(for: account) ?? "",
            defaultModel: account.apiProvider?.defaultModel ?? "",
            balanceQuery: config
        )
        guard state.errorMessage == nil else { return }
        onClose()
    }

    private var config: APIBalanceQueryConfig {
        let existing = account.apiProvider?.balanceQuery
        return APIBalanceQueryConfig(
            isEnabled: isEnabled,
            urlText: urlText,
            jsonPath: jsonPath,
            refreshIntervalSeconds: max(60, refreshIntervalMinutes.rounded() * 60),
            minimumBalance: minimumBalance,
            lastBalanceText: existing?.lastBalanceText,
            lastRefreshedAt: existing?.lastRefreshedAt
        )
    }

    private var minimumBalance: Double {
        APIBalanceQueryConfig.parseBalance(minimumBalanceText) ?? 0
    }

    private static let balanceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        formatter.numberStyle = .decimal
        return formatter
    }()

    private func accountTextField(_ label: String, required: Bool, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(required ? state.strings.requiredField(label) : state.strings.optionalField(label))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

@MainActor
private final class AccountPanelController<Content: View> {
    private let panel: NSPanel
    private let delegateBox: PanelDelegateBox
    private let onClose: () -> Void

    init(title: String, rootView: Content, onClose: @escaping () -> Void) {
        self.onClose = onClose
        self.delegateBox = PanelDelegateBox(onClose: onClose)
        let hostingController = NSHostingController(rootView: rootView)
        self.panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.contentViewController = hostingController
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = delegateBox
    }

    func show(attachedTo parent: NSWindow?) {
        PopoverPanelPresentation.show(panel, parent: parent)
    }

    func close() {
        panel.parent?.removeChildWindow(panel)
        panel.close()
    }

}

@MainActor
private final class AddAccountPanelController {
    private let controller: AccountPanelController<AddAccountDialog>

    init(state: AppState, onClose: @escaping () -> Void) {
        var controller: AccountPanelController<AddAccountDialog>?
        let closePanel = {
            controller?.close()
            return
        }
        let dialog = AddAccountDialog(state: state, onClose: closePanel)
        self.controller = AccountPanelController(
            title: state.strings.addAccount,
            rootView: dialog,
            onClose: onClose
        )
        controller = self.controller
    }

    func show(attachedTo parent: NSWindow?) {
        controller.show(attachedTo: parent)
    }

    func close() {
        controller.close()
    }
}

@MainActor
private final class EditAccountPanelController {
    private let controller: AccountPanelController<EditAccountDialog>

    init(state: AppState, account: CodixxAccount, onClose: @escaping () -> Void) {
        var controller: AccountPanelController<EditAccountDialog>?
        let closePanel = {
            controller?.close()
            return
        }
        self.controller = AccountPanelController(
            title: state.strings.editAccount,
            rootView: EditAccountDialog(
                state: state,
                account: account,
                onClose: closePanel
            ),
            onClose: onClose
        )
        controller = self.controller
    }

    func show(attachedTo parent: NSWindow?) {
        controller.show(attachedTo: parent)
    }

    func close() {
        controller.close()
    }
}

@MainActor
private final class BalanceMonitorPanelController {
    private let controller: AccountPanelController<BalanceMonitorDialog>

    init(state: AppState, account: CodixxAccount, onClose: @escaping () -> Void) {
        var controller: AccountPanelController<BalanceMonitorDialog>?
        let closePanel = {
            controller?.close()
            return
        }
        self.controller = AccountPanelController(
            title: state.strings.apiBalanceSection,
            rootView: BalanceMonitorDialog(
                state: state,
                account: account,
                onClose: closePanel
            ),
            onClose: onClose
        )
        controller = self.controller
    }

    func show(attachedTo parent: NSWindow?) {
        controller.show(attachedTo: parent)
    }

    func close() {
        controller.close()
    }
}

private final class PanelDelegateBox: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

enum PopoverPanelPresentation {
    static let minimumAttachedLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

    static func prepare(
        _ window: NSWindow,
        parent: NSWindow?,
        fallbackLevel: NSWindow.Level = minimumAttachedLevel
    ) {
        window.parent?.removeChildWindow(window)

        guard let parent else {
            window.level = fallbackLevel
            window.center()
            return
        }

        let level = presentationLevel(for: parent)
        window.level = level
        parent.addChildWindow(window, ordered: .above)
        window.level = level
        position(window, over: parent)
    }

    static func show(_ window: NSWindow, parent: NSWindow?) {
        prepare(window, parent: parent)
        window.orderFrontRegardless()
        restorePresentationOnNextRunLoop(window, parent: parent)
    }

    static func runModal(_ window: NSPanel, parent: NSWindow?) -> NSApplication.ModalResponse {
        show(window, parent: parent)
        return NSApplication.shared.runModal(for: window)
    }

    static func presentationLevel(for parent: NSWindow) -> NSWindow.Level {
        NSWindow.Level(
            rawValue: max(parent.level.rawValue + 1, minimumAttachedLevel.rawValue)
        )
    }

    private static func position(_ window: NSWindow, over parent: NSWindow) {
        let parentFrame = parent.frame
        let frame = window.frame
        let x = parentFrame.midX - frame.width / 2
        let y = parentFrame.maxY - frame.height - 20
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private static func restorePresentationOnNextRunLoop(_ window: NSWindow, parent: NSWindow?) {
        DispatchQueue.main.async {
            guard window.isVisible else { return }
            prepare(window, parent: parent)
            window.orderFrontRegardless()
        }
    }
}

struct AccountDragGridLayout {
    static func contentHeight(itemCount: Int) -> CGFloat {
        guard itemCount > 0 else { return 0 }
        let rows = (itemCount + DashboardLayout.accountColumnCount - 1) / DashboardLayout.accountColumnCount
        return CGFloat(rows) * DashboardLayout.accountCardMinHeight
            + CGFloat(max(0, rows - 1)) * DashboardLayout.accountColumnSpacing
    }

    static func frame(for index: Int, containerWidth: CGFloat) -> CGRect {
        let safeWidth = max(0, containerWidth)
        let columnCount = DashboardLayout.accountColumnCount
        let spacing = DashboardLayout.accountColumnSpacing
        let totalSpacing = CGFloat(columnCount - 1) * spacing
        let cardWidth = max(0, (safeWidth - totalSpacing) / CGFloat(columnCount))
        let row = max(0, index) / columnCount
        let column = max(0, index) % columnCount
        return CGRect(
            x: CGFloat(column) * (cardWidth + spacing),
            y: CGFloat(row) * (DashboardLayout.accountCardMinHeight + spacing),
            width: cardWidth,
            height: DashboardLayout.accountCardMinHeight
        )
    }

    static func insertionIndex(for point: CGPoint, itemCount: Int, containerWidth: CGFloat) -> Int {
        let upperBound = max(0, itemCount)
        var bestIndex = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for index in 0...upperBound {
            let frame = frame(for: index, containerWidth: containerWidth)
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let dx = center.x - point.x
            let dy = center.y - point.y
            let distance = dx * dx + dy * dy
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }

        return bestIndex
    }

    static func displaySlotIndex(forVisibleIndex visibleIndex: Int, reservedInsertionIndex: Int?) -> Int {
        guard let reservedInsertionIndex,
              visibleIndex >= reservedInsertionIndex
        else {
            return visibleIndex
        }

        return visibleIndex + 1
    }
}

struct WindowReader: NSViewRepresentable {
    let onWindowChange: (NSWindow?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onWindowChange: onWindowChange)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.publishIfNeeded(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.publishIfNeeded(nsView.window)
        }
    }

    final class Coordinator {
        private weak var lastWindow: NSWindow?
        private let onWindowChange: (NSWindow?) -> Void

        init(onWindowChange: @escaping (NSWindow?) -> Void) {
            self.onWindowChange = onWindowChange
        }

        func publishIfNeeded(_ window: NSWindow?) {
            guard lastWindow !== window else { return }
            lastWindow = window
            onWindowChange(window)
        }
    }
}

private struct AccountRowsView: View {
    @ObservedObject var state: AppState
    let onEdit: (CodixxAccount) -> Void
    let onBalanceMonitor: (CodixxAccount) -> Void
    let parentWindow: NSWindow?
    @State private var refreshingBalanceAccountIds: Set<UUID> = []
    @State private var draggingAccountID: UUID?
    @State private var dragOrigin: CGRect = .zero
    @State private var dragTranslation: CGSize = .zero
    @State private var lastInsertionIndex: Int?
    @State private var reservedInsertionIndex: Int?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                ForEach(state.accounts) { account in
                    let frame = frame(for: account, containerWidth: width)
                    accountRow(account)
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .offset(offset(for: account))
                        .opacity(opacity(for: account))
                        .scaleEffect(scale(for: account))
                        .shadow(
                            color: Color.black.opacity(shadowOpacity(for: account)),
                            radius: shadowRadius(for: account),
                            y: shadowYOffset(for: account)
                        )
                        .zIndex(draggingAccountID == account.id ? 10 : 0)
                        .gesture(dragGesture(for: account, containerWidth: width))
                }
            }
            .coordinateSpace(name: "accountRowsDragArea")
            .frame(
                height: AccountDragGridLayout.contentHeight(itemCount: layoutItemCount),
                alignment: .topLeading
            )
            .animation(
                .interactiveSpring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.08),
                value: state.accounts.map(\.id)
            )
        }
        .frame(height: AccountDragGridLayout.contentHeight(itemCount: layoutItemCount))
    }

    private func frame(for account: CodixxAccount, containerWidth: CGFloat) -> CGRect {
        if draggingAccountID == account.id {
            return dragOrigin
        }

        let visibleAccounts = state.accounts.filter { $0.id != draggingAccountID }
        let visibleIndex = visibleAccounts.firstIndex(where: { $0.id == account.id }) ?? 0
        let slotIndex = AccountDragGridLayout.displaySlotIndex(
            forVisibleIndex: visibleIndex,
            reservedInsertionIndex: reservedInsertionIndex
        )
        return AccountDragGridLayout.frame(for: slotIndex, containerWidth: containerWidth)
    }

    private var layoutItemCount: Int {
        reservedInsertionIndex == nil ? state.accounts.count : state.accounts.count + 1
    }

    private func offset(for account: CodixxAccount) -> CGSize {
        draggingAccountID == account.id ? dragTranslation : .zero
    }

    private func opacity(for account: CodixxAccount) -> Double {
        draggingAccountID == account.id ? DashboardLayout.draggingAccountOpacity : 1
    }

    private func scale(for account: CodixxAccount) -> CGFloat {
        draggingAccountID == account.id ? DashboardLayout.draggingAccountScale : 1
    }

    private func shadowOpacity(for account: CodixxAccount) -> Double {
        draggingAccountID == account.id ? 0.24 : 0
    }

    private func shadowRadius(for account: CodixxAccount) -> CGFloat {
        draggingAccountID == account.id ? DashboardLayout.draggingAccountShadowRadius : 0
    }

    private func shadowYOffset(for account: CodixxAccount) -> CGFloat {
        draggingAccountID == account.id ? 12 : 0
    }

    private func dragGesture(for account: CodixxAccount, containerWidth: CGFloat) -> some Gesture {
        DragGesture(
            minimumDistance: DashboardLayout.accountDragMinimumDistance,
            coordinateSpace: .named("accountRowsDragArea")
        )
        .onChanged { value in
            if draggingAccountID == nil {
                beginDrag(account, containerWidth: containerWidth)
            }
            guard draggingAccountID == account.id else { return }

            dragTranslation = value.translation
            updateOrderIfNeeded(for: account, location: draggedCenter, containerWidth: containerWidth)
        }
        .onEnded { _ in
            guard draggingAccountID == account.id else { return }
            state.scheduleAccountOrderCommit(movedAccountID: account.id)
            withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.84, blendDuration: 0.08)) {
                draggingAccountID = nil
                dragTranslation = .zero
                dragOrigin = .zero
                lastInsertionIndex = nil
                reservedInsertionIndex = nil
            }
        }
    }

    private var draggedCenter: CGPoint {
        CGPoint(
            x: dragOrigin.midX + dragTranslation.width,
            y: dragOrigin.midY + dragTranslation.height
        )
    }

    private func beginDrag(_ account: CodixxAccount, containerWidth: CGFloat) {
        guard let index = state.accounts.firstIndex(where: { $0.id == account.id }) else { return }
        dragOrigin = AccountDragGridLayout.frame(for: index, containerWidth: containerWidth)
        dragTranslation = .zero
        draggingAccountID = account.id
        lastInsertionIndex = index
        reservedInsertionIndex = nil
    }

    private func updateOrderIfNeeded(for account: CodixxAccount, location: CGPoint, containerWidth: CGFloat) {
        let visibleCount = max(0, state.accounts.count - 1)
        let insertionIndex = AccountDragGridLayout.insertionIndex(
            for: location,
            itemCount: visibleCount,
            containerWidth: containerWidth
        )
        guard insertionIndex != lastInsertionIndex else { return }
        lastInsertionIndex = insertionIndex
        reservedInsertionIndex = insertionIndex
        withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.82, blendDuration: 0.06)) {
            state.previewAccountMove(account, toVisibleIndex: insertionIndex)
        }
    }

    private func accountRow(_ account: CodixxAccount) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                accountHeader(for: account)

                if account.isAPIProvider {
                    apiProviderDetails(for: account)
                } else {
                    Text(membershipExpirationText(for: account))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !account.isAPIProvider {
                quotaProgressRows(for: account)
            }

            Spacer(minLength: DashboardLayout.accountCardFooterSpacerMinLength)

            HStack(alignment: .center, spacing: 12) {
                Toggle(state.strings.enabled, isOn: Binding(
                    get: { account.isEnabled },
                    set: { state.setAccount(account, isEnabled: $0) }
                ))
                Spacer()
                HStack(spacing: 8) {
                    Text(state.strings.priority(account.priority))
                        .font(.caption)
                    HStack(spacing: 2) {
                        Button {
                            state.setAccount(account, priority: max(0, account.priority - 1))
                        } label: {
                            Image(systemName: "arrow.down")
                        }
                        .disabled(account.priority <= 0)
                        .help(state.strings.decreasePriority)

                        Button {
                            state.setAccount(account, priority: min(100, account.priority + 1))
                        } label: {
                            Image(systemName: "arrow.up")
                        }
                        .disabled(account.priority >= 100)
                        .help(state.strings.increasePriority)
                    }
                    .buttonStyle(.borderless)
                }
                .help(state.strings.priorityHint)
            }
            .font(.caption)
        }
        .padding(12)
        .frame(height: DashboardLayout.accountCardMinHeight, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func accountHeader(for account: CodixxAccount) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(account.alias)
                    .font(.headline)
                    .lineLimit(1)
                Text(planLabel(for: account))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                if account.id == state.currentAccount?.id {
                    Text(state.strings.current)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.14), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                confirmSwitchAndRestart(account)
            } label: {
                Label(state.strings.switchAccount, systemImage: "arrow.triangle.2.circlepath")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(account.id == state.currentAccount?.id)
            .help(state.strings.switchToThisAccount)

            Menu {
                Button {
                    onEdit(account)
                } label: {
                    Label(state.strings.editAccount, systemImage: "pencil")
                }

                if account.isAPIProvider {
                    Button {
                        onBalanceMonitor(account)
                    } label: {
                        Label(state.strings.apiBalanceSection, systemImage: "creditcard")
                    }
                }

                Divider()

                Button(role: .destructive) {
                    confirmDelete(account)
                } label: {
                    Label(state.strings.deleteAccount, systemImage: "trash")
                }
            } label: {
                Label(state.strings.settings, systemImage: "gearshape")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(state.strings.settings)
        }
    }

    private func quotaProgressRows(for account: CodixxAccount) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            quotaProgressRow(
                title: state.strings.fiveHourQuota,
                percent: account.quota.primaryUsedPercent,
                resetText: account.quota.primaryResetsAt.map(state.strings.resets) ?? state.strings.resetUnknown,
                tint: account.quota.primaryUsedPercent.map { $0 >= state.config.primaryThresholdPercent ? .orange : .accentColor } ?? .secondary
            )

            quotaProgressRow(
                title: state.strings.weeklyQuota,
                percent: account.quota.secondaryUsedPercent,
                resetText: account.quota.secondaryResetsAt.map(state.strings.weeklyResets) ?? state.strings.resetUnknown,
                tint: account.quota.secondaryUsedPercent.map { $0 >= state.config.secondaryThresholdPercent ? .orange : .green } ?? .secondary
            )
        }
    }

    private func quotaProgressRow(
        title: String,
        percent: Double?,
        resetText: String,
        tint: Color
    ) -> some View {
        let percentText = percent.map { "\(Int($0.rounded()))%" } ?? "--"
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(title) · \(resetText)")
                    .lineLimit(1)
                Spacer()
                Text(percentText)
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ProgressView(value: min(max((percent ?? 0) / 100, 0), 1))
                .tint(tint)
        }
        .help("\(title): \(percentText) · \(resetText)")
    }

    private func apiProviderDetails(for account: CodixxAccount) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let model = account.apiProvider?.defaultModel, !model.isEmpty {
                Text(model)
            }
            if account.apiProvider?.balanceQuery?.isEnabled == true {
                HStack(spacing: 6) {
                    Text(balanceText(for: account))
                        .lineLimit(1)
                    Button {
                        refreshBalance(for: account)
                    } label: {
                        Image(systemName: refreshingBalanceAccountIds.contains(account.id) ? "hourglass" : "arrow.clockwise")
                            .imageScale(.small)
                    }
                    .buttonStyle(.borderless)
                    .disabled(refreshingBalanceAccountIds.contains(account.id))
                    .help(state.strings.refresh)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func balanceText(for account: CodixxAccount) -> String {
        guard let balance = account.apiProvider?.balanceQuery?.lastBalanceText,
              !balance.isEmpty
        else {
            return state.strings.currentBalanceUnavailable
        }
        return state.strings.currentBalance(balance)
    }

    private func refreshBalance(for account: CodixxAccount) {
        refreshingBalanceAccountIds.insert(account.id)
        Task {
            _ = await state.refreshAPIBalance(for: account)
            await MainActor.run { () -> Void in
                refreshingBalanceAccountIds.remove(account.id)
            }
        }
    }

    private func planLabel(for account: CodixxAccount) -> String {
        if account.isAPIProvider { return state.strings.apiKeyAccount }
        return account.quota.planType?.isEmpty == false ? account.quota.planType! : state.strings.unknownPlan
    }

    private func membershipExpirationText(for account: CodixxAccount) -> String {
        let expiration = account.membershipExpiresAt.map(state.strings.expires) ?? state.strings.neverExpires
        return "\(state.strings.membershipExpires): \(expiration)"
    }

    private func confirmSwitchAndRestart(_ account: CodixxAccount) {
        let windowToClose = parentWindow ?? NSApplication.shared.keyWindow
        let confirmed = IconlessConfirmationDialog.run(
            title: state.strings.confirmSwitchTitle(alias: account.alias),
            message: state.strings.confirmSwitchMessage,
            confirmTitle: state.strings.switchAndRestartCodex,
            cancelTitle: state.strings.cancel,
            parent: windowToClose
        )
        guard confirmed else { return }
        state.switchToAccountAndRestartCodex(account)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            windowToClose?.close()
        }
    }

    private func confirmDelete(_ account: CodixxAccount) {
        let confirmed = IconlessConfirmationDialog.run(
            title: state.strings.confirmDeleteTitle,
            message: state.strings.confirmDeleteMessage(alias: account.alias),
            confirmTitle: state.strings.delete,
            cancelTitle: state.strings.cancel,
            parent: parentWindow ?? NSApplication.shared.keyWindow
        )
        guard confirmed else { return }
        state.deleteAccount(account)
    }
}

final class IconlessConfirmationDialog {
    static func run(
        title: String,
        message: String,
        confirmTitle: String,
        cancelTitle: String,
        parent: NSWindow? = NSApplication.shared.keyWindow
    ) -> Bool {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 160),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        prepareForPresentation(window, parent: parent)

        let contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = contentView

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: 15)
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 2

        let messageLabel = NSTextField(wrappingLabelWithString: message)
        messageLabel.font = .systemFont(ofSize: 13)
        messageLabel.textColor = .secondaryLabelColor

        let confirmButton = NSButton(title: confirmTitle, target: nil, action: nil)
        confirmButton.bezelStyle = .rounded
        confirmButton.keyEquivalent = "\r"

        let cancelButton = NSButton(title: cancelTitle, target: nil, action: nil)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"

        let buttons = NSStackView(views: [cancelButton, confirmButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.alignment = .centerY
        buttons.distribution = .gravityAreas

        let stack = NSStackView(views: [titleLabel, messageLabel, buttons])
        stack.orientation = .vertical
        stack.spacing = 14
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),
            buttons.trailingAnchor.constraint(equalTo: stack.trailingAnchor)
        ])

        var didConfirm = false
        confirmButton.action = #selector(DialogActionHandler.confirm)
        cancelButton.action = #selector(DialogActionHandler.cancel)
        let handler = DialogActionHandler(
            onConfirm: {
                didConfirm = true
                NSApplication.shared.stopModal()
            },
            onCancel: {
                NSApplication.shared.stopModal()
            }
        )
        confirmButton.target = handler
        cancelButton.target = handler
        objc_setAssociatedObject(window, &dialogActionHandlerKey, handler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        _ = PopoverPanelPresentation.runModal(window, parent: parent)
        window.parent?.removeChildWindow(window)
        window.close()
        return didConfirm
    }

    static func prepareForPresentation(_ window: NSPanel, parent: NSWindow?) {
        PopoverPanelPresentation.prepare(window, parent: parent)
    }
}

private final class DialogActionHandler: NSObject {
    private let onConfirm: () -> Void
    private let onCancel: () -> Void

    init(onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    @objc func confirm() {
        onConfirm()
    }

    @objc func cancel() {
        onCancel()
    }
}

private var dialogActionHandlerKey: UInt8 = 0
