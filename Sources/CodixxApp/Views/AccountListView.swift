import SwiftUI
import CodixxCore

struct AccountListView: View {
    @ObservedObject var state: AppState
    @State private var newAlias = ""
    @State private var editedAliases: [UUID: String] = [:]
    @State private var editingAccountIds: Set<UUID> = []
    @State private var expandedSettingsAccountIds: Set<UUID> = []
    @State private var isShowingSaveAccount = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isShowingSaveAccount.toggle()
                    }
                } label: {
                    Label(state.strings.addAccount, systemImage: isShowingSaveAccount ? "chevron.up" : "person.badge.plus")
                }
                .buttonStyle(.borderedProminent)

                if isShowingSaveAccount {
                    saveCurrentAccount
                }

                if !state.canEnableAutoSwitch {
                    Label(state.strings.autoSwitchNeedsTwoAccounts, systemImage: "person.crop.circle.badge.plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }

                Text(state.strings.accounts)
                    .font(.headline)

                if state.accounts.isEmpty {
                    Text(state.strings.noSavedAccounts)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    ForEach(state.accounts) { account in
                        accountRow(account)
                    }
                }
            }
        }
    }

    private var saveCurrentAccount: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.strings.saveCurrentAuth)
                .font(.headline)
            HStack {
                TextField(state.strings.alias, text: $newAlias)
                    .textFieldStyle(.roundedBorder)
                Button {
                    state.saveCurrentAccount(alias: newAlias)
                    newAlias = ""
                } label: {
                    Label(state.strings.save, systemImage: "key")
                }
                .help(state.strings.saveCurrentCodexAuth)
            }

            if let accountSaveStatus = state.accountSaveStatus {
                Label(saveStatusText(accountSaveStatus), systemImage: saveStatusIcon(accountSaveStatus))
                    .font(.caption)
                    .foregroundStyle(saveStatusColor(accountSaveStatus))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func accountRow(_ account: CodixxAccount) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                accountHeader(for: account)

                HStack(spacing: 8) {
                    if account.id == state.currentAccount?.id {
                        Text(state.strings.current)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.14), in: Capsule())
                    }

                    Text(quotaText(for: account))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Spacer(minLength: 0)
                }

                Text(membershipText(for: account))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(membershipExpirationText(for: account))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if expandedSettingsAccountIds.contains(account.id) {
                accountSettings(for: account)
            }

            quotaProgressRows(for: account)

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
            }
            .font(.caption)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func accountHeader(for account: CodixxAccount) -> some View {
        HStack(spacing: 8) {
            Text(account.alias)
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                state.switchToAccount(account)
            } label: {
                Label(state.strings.switchAccount, systemImage: "arrow.triangle.2.circlepath")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(account.id == state.currentAccount?.id)
            .help(state.strings.switchToThisAccount)

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if expandedSettingsAccountIds.contains(account.id) {
                        expandedSettingsAccountIds.remove(account.id)
                        editedAliases[account.id] = nil
                        editingAccountIds.remove(account.id)
                    } else {
                        expandedSettingsAccountIds.insert(account.id)
                    }
                }
            } label: {
                Label(state.strings.settings, systemImage: expandedSettingsAccountIds.contains(account.id) ? "gearshape.fill" : "gearshape")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help(state.strings.settings)
        }
    }

    @ViewBuilder
    private func accountSettings(for account: CodixxAccount) -> some View {
        if editingAccountIds.contains(account.id) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    TextField(state.strings.alias, text: Binding(
                        get: { editedAliases[account.id] ?? account.alias },
                        set: { editedAliases[account.id] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 0, maxWidth: .infinity)

                    Button {
                        state.renameAccount(account, alias: editedAliases[account.id] ?? account.alias)
                        editedAliases[account.id] = nil
                        editingAccountIds.remove(account.id)
                    } label: {
                        Label(state.strings.renameAccount, systemImage: "checkmark")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help(state.strings.renameAccount)
                    .disabled((editedAliases[account.id] ?? account.alias).trimmingCharacters(in: .whitespacesAndNewlines) == account.alias)

                    Button {
                        editedAliases[account.id] = nil
                        editingAccountIds.remove(account.id)
                    } label: {
                        Label(state.strings.cancelEdit, systemImage: "xmark")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help(state.strings.cancelEdit)
                }

                deleteAccountButton(account)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(state.strings.alias)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(account.alias)
                        .font(.caption)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        editedAliases[account.id] = account.alias
                        editingAccountIds.insert(account.id)
                    } label: {
                        Label(state.strings.renameAccount, systemImage: "pencil")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help(state.strings.renameAccount)
                }

                deleteAccountButton(account)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func deleteAccountButton(_ account: CodixxAccount) -> some View {
        Button(role: .destructive) {
            state.deleteAccount(account)
            editedAliases[account.id] = nil
            editingAccountIds.remove(account.id)
            expandedSettingsAccountIds.remove(account.id)
        } label: {
            Label(state.strings.deleteAccount, systemImage: "trash")
        }
        .help(state.strings.deleteAccount)
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
                tint: account.quota.secondaryUsedPercent.map { $0 >= 100 ? .red : .green } ?? .secondary
            )
        }
    }

    private func quotaProgressRow(
        title: String,
        percent: Double?,
        resetText: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(percent.map { "\(Int($0.rounded()))%" } ?? "--")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ProgressView(value: min(max((percent ?? 0) / 100, 0), 1))
                .tint(tint)

            Text(resetText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func quotaText(for account: CodixxAccount) -> String {
        let primary = account.quota.primaryUsedPercent.map { "\(Int($0.rounded()))%" } ?? "--"
        let confidence = state.strings.confidenceLabel(account.quota.confidence)
        return state.strings.primaryQuota(primary: primary, confidence: confidence)
    }

    private func membershipText(for account: CodixxAccount) -> String {
        let plan = account.quota.planType?.isEmpty == false ? account.quota.planType! : state.strings.unknownPlan
        return "\(state.strings.membership): \(plan)"
    }

    private func membershipExpirationText(for account: CodixxAccount) -> String {
        let expiration = account.membershipExpiresAt.map(state.strings.expires) ?? state.strings.neverExpires
        return "\(state.strings.membershipExpires): \(expiration)"
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
