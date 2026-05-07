import Foundation

public struct CodixxStrings: Sendable {
    public let language: CodixxLanguage

    public init(language: CodixxLanguage) {
        self.language = language
    }

    public var overview: String { text(en: "Overview", zh: "概览") }
    public var trends: String { text(en: "Trends", zh: "趋势") }
    public var accounts: String { text(en: "Accounts", zh: "账号") }
    public var logs: String { text(en: "Logs", zh: "日志") }
    public var refresh: String { text(en: "Refresh", zh: "刷新") }
    public var settings: String { text(en: "Settings", zh: "设置") }
    public var generalSection: String { text(en: "General", zh: "通用") }
    public var autoSwitchSection: String { text(en: "Auto Switch", zh: "自动切换") }
    public var refreshIntervalSection: String { text(en: "Refresh Intervals", zh: "刷新频率") }
    public var quitCodixx: String { text(en: "Quit Codixx", zh: "退出 Codixx") }
    public var notRefreshedYet: String { text(en: "Not refreshed yet", zh: "尚未刷新") }
    public var saveCurrentAuth: String { text(en: "Save Current Auth", zh: "保存当前登录") }
    public var addAccount: String { text(en: "Add Account", zh: "添加账号") }
    public var alias: String { text(en: "Alias", zh: "别名") }
    public var save: String { text(en: "Save", zh: "保存") }
    public var saveCurrentCodexAuth: String { text(en: "Save current Codex auth", zh: "保存当前 Codex 登录") }
    public var noSavedAccounts: String { text(en: "No saved accounts", zh: "尚未保存账号") }
    public var current: String { text(en: "Current", zh: "当前") }
    public var switchAccount: String { text(en: "Switch to account", zh: "切换到此账号") }
    public var switchToThisAccount: String { text(en: "Switch to this account", zh: "切换到这个账号") }
    public var renameAccount: String { text(en: "Rename account", zh: "重命名账号") }
    public var cancelEdit: String { text(en: "Cancel edit", zh: "取消编辑") }
    public var deleteAccount: String { text(en: "Delete account", zh: "删除账号") }
    public var confirmDeleteTitle: String { text(en: "Confirm Delete", zh: "确认删除") }
    public var cancel: String { text(en: "Cancel", zh: "取消") }
    public var delete: String { text(en: "Delete", zh: "删除") }

    public func confirmDeleteMessage(alias: String) -> String {
        text(en: "Delete account \"\(alias)\"? This cannot be undone.", zh: "确定要删除账号「\(alias)」吗？此操作不可撤销。")
    }

    public var membership: String { text(en: "Membership", zh: "会员") }
    public var membershipExpires: String { text(en: "Membership expires", zh: "会员到期") }
    public var neverExpires: String { text(en: "Expiration unavailable locally", zh: "本地未提供到期时间") }
    public var enabled: String { text(en: "Enabled", zh: "启用") }
    public var autoSwitch: String { text(en: "Auto switch", zh: "自动切换") }
    public var autoSwitchNeedsTwoAccounts: String {
        text(
            en: "Save a second enabled account to use auto switch.",
            zh: "请先保存第二个已启用账号，再使用自动切换。"
        )
    }
    public var notifications: String { text(en: "Notifications", zh: "通知") }
    public var threshold: String { text(en: "Threshold", zh: "阈值") }
    public var thresholdHint: String {
        text(
            en: "Auto switch triggers when the 5-hour quota reaches this percentage.",
            zh: "当 5 小时额度达到此百分比时，自动切换将触发。"
        )
    }
    public var quotaRefresh: String { text(en: "Quota refresh", zh: "额度刷新") }
    public var usageRefresh: String { text(en: "Usage refresh", zh: "用量刷新") }
    public var usageReadFailed: String { text(en: "Could not refresh usage data", zh: "无法刷新用量数据") }
    public var codexHome: String { text(en: "Codex Home", zh: "Codex 目录") }
    public var languageLabel: String { text(en: "Language", zh: "语言") }
    public var postSwitchAction: String { text(en: "After switch", zh: "切换后动作") }
    public var codexRestartRequired: String { text(en: "Restart Codex required", zh: "需要重启 Codex") }
    public var restartCodexNow: String { text(en: "Restart Codex now", zh: "立即重启 Codex") }
    public var restartCodexFailed: String { text(en: "Could not restart Codex", zh: "无法重启 Codex") }
    public var topThreads: String { text(en: "Top Threads", zh: "高用量会话") }
    public var activeThread: String { text(en: "Active thread", zh: "活跃会话") }
    public var noActiveThread: String { text(en: "No active thread", zh: "暂无活跃会话") }
    public var noThreadUsageYet: String { text(en: "No thread usage yet", zh: "暂无会话用量") }
    public var switchLog: String { text(en: "Switch Log", zh: "切换日志") }
    public var noSwitchEvents: String { text(en: "No switch events", zh: "暂无切换事件") }
    public var unknown: String { text(en: "unknown", zh: "未知") }
    public var rolledBack: String { text(en: "Rolled back", zh: "已回滚") }
    public var rollbackFailed: String { text(en: "Rollback failed", zh: "回滚失败") }
    public var noCandidate: String { text(en: "No candidate", zh: "无候选账号") }
    public var failedBeforeWrite: String { text(en: "Failed before write", zh: "写入前失败") }
    public var failedDuringWrite: String { text(en: "Failed during write", zh: "写入时失败") }
    public var validationFailed: String { text(en: "Validation failed", zh: "校验失败") }
    public var errorSummaryLabel: String { text(en: "Error", zh: "错误") }
    public var backupPathLabel: String { text(en: "Backup", zh: "备份") }
    public var total: String { text(en: "Total Tokens", zh: "Token 总量") }
    public var todayTokens: String { text(en: "Today", zh: "今日 Token 用量") }
    public var yesterdayTokens: String { text(en: "Yesterday", zh: "昨日 Token 用量") }
    public var threads: String { text(en: "Threads", zh: "会话") }
    public var tokens: String { text(en: "Tokens", zh: "Token") }
    public var day: String { text(en: "Day", zh: "日期") }
    public var hour: String { text(en: "Hour", zh: "小时") }
    public var threadsUpdatedSevenDays: String { text(en: "Threads updated, 7 days", zh: "近 7 天更新的会话") }
    public var threadsUpdatedTwentyFourHours: String { text(en: "Threads updated, 24 hours", zh: "近 24 小时更新的会话") }
    public var noActiveAccountTitle: String { text(en: "No saved current account", zh: "尚未保存当前账号") }
    public var noActiveAccountDetail: String {
        text(
            en: "Save the current Codex auth in Accounts to show account quota here.",
            zh: "请先在“账号”里保存当前 Codex 登录，之后这里会显示账号额度。"
        )
    }
    public var weeklyUnknown: String { text(en: "Weekly quota --", zh: "每周额度 --") }
    public var resetUnknown: String { text(en: "Reset unknown", zh: "重置时间未知") }
    public var fiveHourQuota: String { text(en: "5-hour quota", zh: "5 小时额度") }
    public var weeklyQuota: String { text(en: "Weekly quota", zh: "周额度") }
    public var unknownPlan: String { text(en: "Unknown plan", zh: "未知会员") }
    public var freshQuota: String { text(en: "Fresh quota", zh: "额度信息新鲜") }
    public var recentQuota: String { text(en: "Recent quota", zh: "额度信息较新") }
    public var staleQuota: String { text(en: "Stale quota", zh: "额度信息已过期") }
    public var quotaUnknown: String { text(en: "Quota unknown", zh: "额度未知") }
    public var codixxQuotaWarning: String { text(en: "Codixx quota warning", zh: "Codixx 额度提醒") }
    public var codixxProtectionMode: String { text(en: "Codixx protection mode", zh: "Codixx 保护模式") }
    public var codixxSwitchedAccount: String { text(en: "Codixx switched account", zh: "Codixx 已切换账号") }
    public var codixxSwitchNeedsAttention: String { text(en: "Codixx switch needs attention", zh: "Codixx 切换需要处理") }
    public var noAccountAvailableForAutoSwitch: String {
        text(
            en: "No saved account is available for automatic switching.",
            zh: "没有可用于自动切换的已保存账号。"
        )
    }
    public var selectedAccountFallback: String { text(en: "the selected account", zh: "选中的账号") }
    public var switchDidNotCompleteCleanly: String {
        text(
            en: "The account switch did not complete cleanly.",
            zh: "账号切换没有顺利完成。"
        )
    }
    public var textForAutoSwitchPaused: String { text(en: "Auto switch has been paused.", zh: "已暂停自动切换。") }
    public var restartCodexHint: String {
        text(
            en: "Codex Desktop keeps auth in memory. Restart Codex after switching for the account to take effect.",
            zh: "Codex Desktop 会缓存登录状态。切换账号后需要重启 Codex 才会真正生效。"
        )
    }

    public func secondsInterval(_ seconds: Int) -> String {
        text(en: "\(seconds)s", zh: "\(seconds) 秒")
    }

    public func minutesInterval(_ minutes: Int) -> String {
        text(en: "\(minutes)m", zh: "\(minutes) 分钟")
    }

    public func updated(_ date: Date) -> String {
        text(
            en: "Updated \(date.formatted(date: .omitted, time: .shortened))",
            zh: "已更新 \(date.formatted(date: .omitted, time: .shortened))"
        )
    }

    public func weeklyPercent(_ percent: Int) -> String {
        text(en: "Weekly quota \(percent)%", zh: "每周额度 \(percent)%")
    }

    public func resets(_ date: Date) -> String {
        text(
            en: "Resets \(date.formatted(date: .omitted, time: .shortened))",
            zh: "\(date.formatted(date: .omitted, time: .shortened)) 重置"
        )
    }

    public func weeklyResets(_ date: Date) -> String {
        text(
            en: "Resets \(date.formatted(date: .numeric, time: .shortened))",
            zh: "\(date.formatted(date: .numeric, time: .shortened)) 重置"
        )
    }

    public func expires(_ date: Date) -> String {
        text(
            en: "Expires \(date.formatted(date: .abbreviated, time: .omitted))",
            zh: "\(date.formatted(date: .abbreviated, time: .omitted)) 到期"
        )
    }

    public var priorityHint: String {
        text(en: "Higher = preferred for auto switch", zh: "数值越高，自动切换时越优先")
    }
    public func priority(_ value: Int) -> String {
        text(en: "Priority \(value)", zh: "优先级 \(value)")
    }

    public func primaryQuota(primary: String, confidence: String) -> String {
        text(en: "5-hour \(primary) / \(confidence)", zh: "5 小时 \(primary) / \(confidence)")
    }

    public func fiveHourQuotaWithConfidence(_ confidence: String) -> String {
        text(en: "5-hour quota / \(confidence)", zh: "5 小时额度 / \(confidence)")
    }

    public func confidenceLabel(_ confidence: QuotaConfidence) -> String {
        switch confidence {
        case .fresh:
            return freshQuota
        case .recent:
            return recentQuota
        case .stale:
            return staleQuota
        case .unknown:
            return quotaUnknown
        }
    }

    public func switchSuccessTitle(target: String) -> String {
        text(en: "Switched to \(target)", zh: "已切换到 \(target)")
    }

    public func switchTriggerLabel(_ trigger: SwitchTrigger) -> String {
        switch trigger {
        case .manual:
            return text(en: "Manual", zh: "手动切换")
        case .autoPrimaryThreshold:
            return text(en: "Automatic", zh: "自动切换")
        case .recovery:
            return text(en: "Recovery", zh: "恢复")
        }
    }

    public func switchResultLabel(_ result: SwitchAuditResult) -> String {
        switch result {
        case .success:
            return text(en: "Success", zh: "成功")
        case .skippedNoCandidate:
            return noCandidate
        case .failedBeforeWrite:
            return failedBeforeWrite
        case .failedDuringWrite:
            return failedDuringWrite
        case .failedValidation:
            return validationFailed
        case .rolledBack:
            return rolledBack
        case .rollbackFailed:
            return rollbackFailed
        }
    }

    public func postSwitchActionLabel(_ action: PostSwitchAction) -> String {
        switch action {
        case .none:
            return text(en: "Do nothing", zh: "不处理")
        case .notifyRestartRecommended:
            return text(en: "Remind to restart", zh: "提醒重启")
        case .restartCodexApp:
            return text(en: "Show restart button", zh: "显示重启按钮")
        }
    }

    public func quotaWarningBody(alias: String, percent: Int) -> String {
        text(
            en: "\(alias) is at \(percent)% of the 5-hour quota.",
            zh: "\(alias) 已使用 5 小时额度的 \(percent)% 。"
        )
    }

    public func switchedAccountBody(target: String) -> String {
        text(en: "Now using \(target).", zh: "当前正在使用 \(target)。")
    }

    public func savedCurrentAccount(alias: String) -> String {
        text(en: "Saved \(alias).", zh: "已保存 \(alias)。")
    }

    public func couldNotSaveCurrentAccount(_ error: String) -> String {
        text(en: "Could not save current account: \(error)", zh: "无法保存当前账号：\(error)")
    }

    public func textForAutoSwitchCouldNotBePaused(_ error: String) -> String {
        text(
            en: "Auto switch could not be paused: \(error)",
            zh: "无法暂停自动切换：\(error)"
        )
    }

    private func text(en: String, zh: String) -> String {
        switch language {
        case .english:
            return en
        case .chinese:
            return zh
        }
    }
}
