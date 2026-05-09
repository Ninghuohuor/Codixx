import AppKit
import SwiftUI
import CodixxCore

struct AccountListView: View {
    @ObservedObject var state: AppState
    @State private var addAccountPanel: AddAccountPanelController?
    @State private var editAccountPanel: EditAccountPanelController?
    @State private var balanceMonitorPanel: BalanceMonitorPanelController?

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
                        onBalanceMonitor: showBalanceMonitorPanel
                    )
                }
            }
            .padding(14)
        }
    }

    private var lastUpdatedText: String {
        guard let lastUpdatedAt = state.lastUpdatedAt else { return state.strings.notRefreshedYet }
        return state.strings.updated(lastUpdatedAt)
    }

    private func showAddAccountPanel() {
        if let addAccountPanel {
            addAccountPanel.show(attachedTo: NSApplication.shared.keyWindow)
            return
        }
        let panel = AddAccountPanelController(state: state) {
            addAccountPanel = nil
        }
        addAccountPanel = panel
        panel.show(attachedTo: NSApplication.shared.keyWindow)
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
        panel.show(attachedTo: NSApplication.shared.keyWindow)
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
        panel.show(attachedTo: NSApplication.shared.keyWindow)
    }
}

private struct AddAccountDialog: View {
    @ObservedObject var state: AppState
    let onClose: () -> Void
    @State private var newAlias = ""
    @State private var credentialKind: CredentialKind = .chatgpt
    @State private var baseURLText = ""
    @State private var apiKey = ""
    @State private var defaultModel = ""
    @State private var connectionTestStatus: ConnectionTestStatus?
    @State private var isTestingConnection = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.strings.addAccount)
                .font(.headline)

            Picker("", selection: $credentialKind) {
                Text(state.strings.codexLoginAccount).tag(CredentialKind.chatgpt)
                Text(state.strings.apiKeyAccount).tag(CredentialKind.apiProvider)
            }
            .pickerStyle(.segmented)

            if credentialKind == .chatgpt {
                apiProviderTextField(state.strings.alias, required: true, text: $newAlias)
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
    }

    private var canSave: Bool {
        switch credentialKind {
        case .chatgpt:
            return !newAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        case .chatgpt:
            state.saveCurrentAccount(alias: newAlias)
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
        credentialKind = .chatgpt
        baseURLText = ""
        apiKey = ""
        defaultModel = ""
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
            lastBalanceText: existing?.lastBalanceText,
            lastRefreshedAt: existing?.lastRefreshedAt
        )
    }

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
        if let parent {
            parent.addChildWindow(panel, ordered: .above)
            position(above: parent)
            panel.orderFront(nil)
        } else {
            panel.center()
            panel.orderFrontRegardless()
        }
    }

    func close() {
        panel.parent?.removeChildWindow(panel)
        panel.close()
    }

    private func position(above parent: NSWindow) {
        let parentFrame = parent.frame
        let panelFrame = panel.frame
        let x = parentFrame.midX - panelFrame.width / 2
        let y = parentFrame.maxY - panelFrame.height - 20
        panel.setFrameOrigin(NSPoint(x: x, y: y))
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

private struct AccountRowsView: View {
    @ObservedObject var state: AppState
    let onEdit: (CodixxAccount) -> Void
    let onBalanceMonitor: (CodixxAccount) -> Void
    @State private var refreshingBalanceAccountIds: Set<UUID> = []

    var body: some View {
        ForEach(state.accounts) { account in
            accountRow(account)
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

            HStack(alignment: .center, spacing: 12) {
                Toggle(state.strings.enabled, isOn: Binding(
                    get: { account.isEnabled },
                    set: { state.setAccount(account, isEnabled: $0) }
                ))
                Spacer()
                HStack(spacing: 8) {
                    Text(state.strings.priority(account.priority))
                        .font(.caption)
                    Stepper("", value: Binding(
                        get: { account.priority },
                        set: { state.setAccount(account, priority: $0) }
                    ), in: 0...100)
                    .labelsHidden()
                }
                .help(state.strings.priorityHint)
            }
            .font(.caption)
        }
        .padding(12)
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
            Text(account.apiProvider?.baseURL.absoluteString ?? "")
                .lineLimit(1)
                .truncationMode(.middle)
            if let maskedAPIKey = state.maskedAPIKey(for: account) {
                Text(maskedAPIKey)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
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
        let confirmed = IconlessConfirmationDialog.run(
            title: state.strings.confirmSwitchTitle(alias: account.alias),
            message: state.strings.confirmSwitchMessage,
            confirmTitle: state.strings.switchAndRestartCodex,
            cancelTitle: state.strings.cancel
        )
        guard confirmed else { return }
        state.switchToAccountAndRestartCodex(account)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApplication.shared.keyWindow?.close()
        }
    }

    private func confirmDelete(_ account: CodixxAccount) {
        let alert = NSAlert()
        alert.messageText = state.strings.confirmDeleteTitle
        alert.informativeText = state.strings.confirmDeleteMessage(alias: account.alias)
        alert.alertStyle = .warning
        alert.addButton(withTitle: state.strings.delete)
        alert.addButton(withTitle: state.strings.cancel)

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        state.deleteAccount(account)
    }
}

private final class IconlessConfirmationDialog {
    static func run(
        title: String,
        message: String,
        confirmTitle: String,
        cancelTitle: String
    ) -> Bool {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 160),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true
        window.center()

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

        window.orderFrontRegardless()
        NSApplication.shared.runModal(for: window)
        window.close()
        return didConfirm
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
