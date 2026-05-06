import SwiftUI
import CodixxCore

struct AccountListView: View {
    @ObservedObject var state: AppState
    @State private var newAlias = ""
    @State private var editedAliases: [UUID: String] = [:]
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        TextField(state.strings.alias, text: Binding(
                            get: { editedAliases[account.id] ?? account.alias },
                            set: { editedAliases[account.id] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)

                        Button {
                            state.renameAccount(account, alias: editedAliases[account.id] ?? account.alias)
                            editedAliases[account.id] = nil
                        } label: {
                            Label(state.strings.renameAccount, systemImage: "checkmark")
                        }
                        .labelStyle(.iconOnly)
                        .help(state.strings.renameAccount)
                        .disabled((editedAliases[account.id] ?? account.alias).trimmingCharacters(in: .whitespacesAndNewlines) == account.alias)

                        if account.id == state.currentAccount?.id {
                            Text(state.strings.current)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.14), in: Capsule())
                        }
                    }
                    Text(quotaText(for: account))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    state.switchToAccount(account)
                } label: {
                    Label(state.strings.switchAccount, systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(account.id == state.currentAccount?.id)
                .help(state.strings.switchToThisAccount)

                Button(role: .destructive) {
                    state.deleteAccount(account)
                    editedAliases[account.id] = nil
                } label: {
                    Label(state.strings.deleteAccount, systemImage: "trash")
                }
                .help(state.strings.deleteAccount)
            }

            Text(membershipText(for: account))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            quotaProgressRows(for: account)

            HStack {
                Toggle(state.strings.enabled, isOn: Binding(
                    get: { account.isEnabled },
                    set: { state.setAccount(account, isEnabled: $0) }
                ))
                Spacer()
                Stepper(state.strings.priority(account.priority), value: Binding(
                    get: { account.priority },
                    set: { state.setAccount(account, priority: $0) }
                ), in: 0...100)
                .frame(width: 138)
            }
            .font(.caption)

            HStack(spacing: 8) {
                DatePicker(
                    state.strings.membershipExpires,
                    selection: Binding(
                        get: { account.membershipExpiresAt ?? Date() },
                        set: { state.setAccount(account, membershipExpiresAt: $0) }
                    ),
                    displayedComponents: .date
                )
                .font(.caption)

                Button {
                    state.setAccount(account, membershipExpiresAt: nil)
                } label: {
                    Label(state.strings.clearMembershipExpiration, systemImage: "xmark.circle")
                }
                .labelStyle(.iconOnly)
                .help(state.strings.clearMembershipExpiration)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
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
        let expiration = account.membershipExpiresAt.map(state.strings.expires) ?? state.strings.neverExpires
        return "\(state.strings.membership): \(plan) / \(expiration)"
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
