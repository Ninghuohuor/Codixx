import AppKit
import SwiftUI
import CodixxCore

struct AccountListView: View {
    @ObservedObject var state: AppState
    @State private var newAlias = ""
    @State private var editedAliases: [UUID: String] = [:]
    @State private var editingAccountIds: Set<UUID> = []
    @State private var accountToDelete: CodixxAccount?
    @State private var accountToSwitch: CodixxAccount?
    @State private var isShowingSaveAccount = false

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
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isShowingSaveAccount.toggle()
                        }
                    } label: {
                        Image(systemName: isShowingSaveAccount ? "chevron.up" : "plus")
                    }
                    .buttonStyle(.borderless)
                    .help(state.strings.addAccount)
                }

                if isShowingSaveAccount {
                    saveCurrentAccount
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
                    ForEach(state.accounts) { account in
                        accountRow(account)
                    }
                }
            }
            .padding(14)
        }
        .alert(
            state.strings.confirmDeleteTitle,
            isPresented: Binding(
                get: { accountToDelete != nil },
                set: { if !$0 { accountToDelete = nil } }
            )
        ) {
            Button(state.strings.cancel, role: .cancel) {
                accountToDelete = nil
            }
            Button(state.strings.delete, role: .destructive) {
                if let account = accountToDelete {
                    state.deleteAccount(account)
                    editedAliases[account.id] = nil
                    editingAccountIds.remove(account.id)
                }
                accountToDelete = nil
            }
        } message: {
            if let account = accountToDelete {
                Text(state.strings.confirmDeleteMessage(alias: account.alias))
            }
        }
        .alert(
            accountToSwitch.map { state.strings.confirmSwitchTitle(alias: $0.alias) } ?? "",
            isPresented: Binding(
                get: { accountToSwitch != nil },
                set: { if !$0 { accountToSwitch = nil } }
            )
        ) {
            Button(state.strings.cancel, role: .cancel) {
                accountToSwitch = nil
            }
            Button(state.strings.switchAndRestartCodex) {
                if let account = accountToSwitch {
                    accountToSwitch = nil
                    NSApplication.shared.keyWindow?.close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        state.switchToAccountAndRestartCodex(account)
                    }
                }
            }
        } message: {
            Text(state.strings.confirmSwitchMessage)
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
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isShowingSaveAccount = false
                    }
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

                Text(membershipExpirationText(for: account))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
            if editingAccountIds.contains(account.id) {
                TextField(state.strings.alias, text: Binding(
                    get: { editedAliases[account.id] ?? account.alias },
                    set: { editedAliases[account.id] = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.headline)
                .frame(maxWidth: .infinity)

                Button {
                    state.renameAccount(account, alias: editedAliases[account.id] ?? account.alias)
                    editedAliases[account.id] = nil
                    editingAccountIds.remove(account.id)
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderless)
                .help(state.strings.renameAccount)
                .disabled((editedAliases[account.id] ?? account.alias).trimmingCharacters(in: .whitespacesAndNewlines) == account.alias)

                Button {
                    editedAliases[account.id] = nil
                    editingAccountIds.remove(account.id)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help(state.strings.cancelEdit)
            } else {
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
            }

            Button {
                accountToSwitch = account
            } label: {
                Label(state.strings.switchAccount, systemImage: "arrow.triangle.2.circlepath")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(account.id == state.currentAccount?.id)
            .help(state.strings.switchToThisAccount)

            Menu {
                Button {
                    editedAliases[account.id] = account.alias
                    editingAccountIds.insert(account.id)
                } label: {
                    Label(state.strings.renameAccount, systemImage: "pencil")
                }

                Divider()

                Button(role: .destructive) {
                    accountToDelete = account
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

    private var lastUpdatedText: String {
        guard let lastUpdatedAt = state.lastUpdatedAt else { return state.strings.notRefreshedYet }
        return state.strings.updated(lastUpdatedAt)
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

    private func planLabel(for account: CodixxAccount) -> String {
        account.quota.planType?.isEmpty == false ? account.quota.planType! : state.strings.unknownPlan
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
