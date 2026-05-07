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
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isShowingSaveAccount.toggle()
                        }
                    } label: {
                        Label(state.strings.addAccount, systemImage: isShowingSaveAccount ? "chevron.up" : "person.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                if isShowingSaveAccount {
                    saveCurrentAccount
                }

                if let accountToSwitch {
                    switchConfirmation(for: accountToSwitch)
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    accountToSwitch = account
                }
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

    private func switchConfirmation(for account: CodixxAccount) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(state.strings.confirmSwitchTitle(alias: account.alias), systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline.weight(.semibold))
            Text(state.strings.confirmSwitchMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(state.strings.cancel) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        accountToSwitch = nil
                    }
                }
                Spacer()
                Button(state.strings.switchAndRestartCodex) {
                    state.switchToAccountAndRestartCodex(account)
                    accountToSwitch = nil
                }
                .buttonStyle(.borderedProminent)
            }
            .font(.caption)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        )
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
                Text("\(title) · \(resetText)")
                    .lineLimit(1)
                Spacer()
                Text(percent.map { "\(Int($0.rounded()))%" } ?? "--")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ProgressView(value: min(max((percent ?? 0) / 100, 0), 1))
                .tint(tint)
        }
    }

    private func quotaText(for account: CodixxAccount) -> String {
        let primary = account.quota.primaryUsedPercent.map { "\(Int($0.rounded()))%" } ?? "--"
        let confidence = state.strings.confidenceLabel(account.quota.confidence)
        return state.strings.primaryQuota(primary: primary, confidence: confidence)
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
