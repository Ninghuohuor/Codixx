import Foundation

public struct CodixxStrings: Sendable {
    public let language: CodixxLanguage

    public init(language: CodixxLanguage) {
        self.language = language
    }

    public var overview: String { text(en: "Overview", zh: "概览") }
    public var allAccounts: String { text(en: "All", zh: "所有") }
    public var trends: String { text(en: "Trends", zh: "趋势") }
    public var accounts: String { text(en: "Accounts", zh: "账号") }
    public var logs: String { text(en: "Logs", zh: "日志") }
    public var refresh: String { text(en: "Refresh", zh: "刷新") }
    public var settings: String { text(en: "Settings", zh: "设置") }
    public var generalSection: String { text(en: "General", zh: "通用") }
    public var autoSwitchSection: String { text(en: "Auto Switch", zh: "自动切换") }
    public var refreshIntervalSection: String { text(en: "Refresh Intervals", zh: "刷新频率") }
    public var apiBalanceSection: String { text(en: "API Balance Monitoring", zh: "API 余额监测") }
    public var quitCodixx: String { text(en: "Quit Codixx", zh: "退出 Codixx") }
    public var quitCodixxMessage: String {
        text(en: "Quit Codixx now?", zh: "确定要退出 Codixx 吗？")
    }
    public var notRefreshedYet: String { text(en: "Not refreshed yet", zh: "尚未刷新") }
    public var saveCurrentAuth: String { text(en: "Save Current Auth", zh: "保存当前登录") }
    public var addAccount: String { text(en: "Add Account", zh: "添加账号") }
    public var codexLoginAccount: String { text(en: "Current login", zh: "当前登录") }
    public var importAuthJSONAccount: String { text(en: "Import auth.json", zh: "导入 auth.json") }
    public var chooseAuthJSON: String { text(en: "Choose auth.json", zh: "选择 auth.json") }
    public var noAuthJSONSelected: String { text(en: "No auth.json selected", zh: "尚未选择 auth.json") }
    public var importAuthJSONPickerMessage: String {
        text(
            en: "Choose an existing Codex auth.json file to save as an account snapshot.",
            zh: "选择已有的 Codex auth.json 文件，并保存为账号快照。"
        )
    }
    public var apiKeyAccount: String { text(en: "API key", zh: "API Key") }
    public var providerName: String { text(en: "Provider", zh: "服务商") }
    public var baseURL: String { text(en: "Base URL", zh: "Base URL") }
    public var defaultModel: String { text(en: "Default model", zh: "默认模型") }
    public var testConnection: String { text(en: "Test connection", zh: "测试连接") }
    public var testingConnection: String { text(en: "Testing connection...", zh: "正在测试连接...") }
    public var connectionSucceeded: String { text(en: "Connection succeeded", zh: "连接成功") }
    public var savedReplaceableAPIKey: String { text(en: "API key (saved, replaceable)", zh: "API Key（已保存，可替换）") }
    public var apiBalanceMonitoring: String { text(en: "Enable API balance monitoring", zh: "启用 API 余额监测") }
    public var balanceQueryURL: String { text(en: "Balance query URL", zh: "余额查询 URL") }
    public var balanceJSONPath: String { text(en: "Balance JSON field path", zh: "余额 JSON 字段路径") }
    public var balanceRefreshInterval: String { text(en: "Auto refresh interval", zh: "自动刷新间隔") }
    public var minimumAPIBalance: String { text(en: "Minimum usable balance", zh: "最低可用余额") }
    public var testBalanceQuery: String { text(en: "Test balance query", zh: "测试余额查询") }
    public var testingBalanceQuery: String { text(en: "Testing balance...", zh: "正在测试余额...") }
    public var balanceQueryURLRequired: String { text(en: "Enter the balance query URL to test or save monitoring.", zh: "请填写余额查询 URL，才能测试或保存监测配置。") }
    public var balanceJSONPathRequired: String { text(en: "Enter the balance JSON field path to test or save monitoring.", zh: "请填写余额 JSON 字段路径，才能测试或保存监测配置。") }
    public var noAPIAccountForBalance: String { text(en: "No API account available for balance query", zh: "暂无可用于余额查询的 API 账号") }
    public var currentBalanceUnavailable: String { text(en: "Current balance: --", zh: "当前余额：--") }
    public func currentBalance(_ balance: String) -> String {
        text(en: "Current balance: \(balance)", zh: "当前余额：\(balance)")
    }
    public var balanceAuthentication: String { text(en: "Query authentication", zh: "查询方式") }
    public var balanceUseAPIKey: String { text(en: "Model API Key", zh: "模型 API Key") }
    public var balanceUseAccessToken: String { text(en: "System access token", zh: "系统访问令牌") }
    public var balanceAPIKeyHint: String { text(en: "Uses this account’s model API key. Enter the provider’s balance URL and JSON field path below.", zh: "使用当前账号的模型 API Key，填写服务商提供的余额接口和 JSON 字段路径。") }
    public var balanceTokenRequired: String { text(en: "Enter a system access token for this query mode.", zh: "此查询方式需要填写系统访问令牌。") }
    public var balanceUserID: String { text(en: "Account ID (New-Api-User)", zh: "账号 ID（New-Api-User）") }
    public var balanceUserIDHint: String { text(en: "Required by some providers alongside the access token. Enter your numeric account ID from the provider; this is not your username.", zh: "部分服务商要求同时提供此项。填写服务商分配的数字账号 ID，不是昵称。") }
    public var pendingAccountRestart: String { text(en: "Pending restart", zh: "待重启生效") }
    public var balanceBack: String { text(en: "Back", zh: "返回") }
    public var balanceDiscardTitle: String { text(en: "Discard unsaved changes?", zh: "放弃未保存的修改？") }
    public var balanceDiscard: String { text(en: "Discard and go back", zh: "放弃修改并返回") }
    public var balanceToken: String { text(en: "Balance access token", zh: "余额查询访问令牌") }
    public var balanceTokenHint: String { text(en: "Optional. Uses the model API Key by default. Enter a separate token if required; leave blank to keep a saved token or enter a new one to replace it. Stored in Keychain.", zh: "默认使用模型 API Key；服务商要求独立令牌时填写。已保存令牌时留空保留，填写新令牌可替换。") }
    public var balanceTokenSaved: String { text(en: "Separate balance token saved", zh: "已保存独立余额查询令牌") }
    public var balanceDivisor: String { text(en: "Divide returned amount by", zh: "返回额度除以") }
    public var balanceCurrency: String { text(en: "Currency label", zh: "货币标识") }
    public var balanceDivisorInvalid: String { text(en: "The divisor must be a finite number greater than zero.", zh: "换算除数必须是大于零的有效数字。") }
    public var balanceNotNumeric: String { text(en: "The balance field is not a valid number.", zh: "余额字段不是有效数字。") }
    public var balanceConfigChanged: String { text(en: "Balance settings changed; refresh again.", zh: "余额配置已更改，请重新刷新。") }
    public var balanceUnitsHint: String { text(en: "Displayed balance and minimum balance use the converted amount. Use divisor 1 for no conversion.", zh: "显示余额和最低可用余额均按换算后的金额计算。不需换算时填 1。") }
    public var balanceQueryHint: String {
        text(
            en: "When monitoring is enabled, both fields are required: a balance endpoint URL that returns JSON (not a console page) and a balance field path, such as data.balance. Codixx uses the balance access token when provided.",
            zh: "启用监测后，必须填写返回 JSON 的余额接口 URL（不是控制台网页地址）和余额字段路径，例如 data.balance。可使用独立的访问令牌查询账户余额。"
        )
    }
    public func requiredField(_ label: String) -> String {
        text(en: "\(label) (required)", zh: "\(label)（必填）")
    }
    public func optionalField(_ label: String) -> String {
        text(en: "\(label) (optional)", zh: "\(label)（选填）")
    }
    public var invalidBaseURL: String { text(en: "Base URL is invalid", zh: "Base URL 无效") }
    public var aliasRequired: String { text(en: "Alias is required", zh: "别名为必填项") }
    public var alias: String { text(en: "Alias", zh: "别名") }
    public var save: String { text(en: "Save", zh: "保存") }
    public var saveCurrentCodexAuth: String { text(en: "Save current Codex auth", zh: "保存当前 Codex 登录") }
    public var noSavedAccounts: String { text(en: "No saved accounts", zh: "尚未保存账号") }
    public var noSavedAccountsDescription: String {
        text(
            en: "Add a Codex login, import auth.json, or add an API key to start tracking quota, switching accounts, and viewing usage trends.",
            zh: "添加 Codex 登录、导入 auth.json 或添加 API Key 后，即可查看额度、切换账号和用量趋势。"
        )
    }
    public var accountSummaryTotal: String { text(en: "Total", zh: "总计") }
    public var accountSummaryAvailable: String { text(en: "Available", zh: "可用") }
    public var accountSummaryFull: String { text(en: "Full", zh: "额度已满") }
    public var accountSummaryUnknown: String { text(en: "Unknown", zh: "未知") }
    public var accountSummaryDisabled: String { text(en: "Disabled", zh: "停用") }
    public var current: String { text(en: "Current", zh: "当前") }
    public var switchAccount: String { text(en: "Switch to account", zh: "切换到此账号") }
    public var switchToThisAccount: String { text(en: "Switch to this account", zh: "切换到这个账号") }
    public var switchAndRestartCodex: String { text(en: "Switch and restart Codex", zh: "切换并重启 Codex") }
    public var editAccount: String { text(en: "Edit account", zh: "编辑账号") }
    public var renameAccount: String { text(en: "Rename account", zh: "重命名账号") }
    public var cancelEdit: String { text(en: "Cancel edit", zh: "取消编辑") }
    public var deleteAccount: String { text(en: "Delete account", zh: "删除账号") }
    public var confirmDeleteTitle: String { text(en: "Confirm Delete", zh: "确认删除") }
    public var cancel: String { text(en: "Cancel", zh: "取消") }
    public var delete: String { text(en: "Delete", zh: "删除") }

    public func confirmDeleteMessage(alias: String) -> String {
        text(en: "Delete account \"\(alias)\"? This cannot be undone.", zh: "确定要删除账号「\(alias)」吗？此操作不可撤销。")
    }

    public func confirmSwitchTitle(alias: String) -> String {
        text(en: "Switch to \"\(alias)\"?", zh: "切换到「\(alias)」？")
    }

    public var confirmSwitchMessage: String {
        text(
            en: "Codex must restart for the account switch to take effect. Canceling will leave the current account unchanged.",
            zh: "账号切换需要重启 Codex 才会生效。取消则不会写入账号，当前账号保持不变。"
        )
    }

    public var membership: String { text(en: "Membership", zh: "会员") }
    public var membershipExpires: String { text(en: "Membership expires", zh: "会员到期") }
    public var membershipExpired: String { text(en: "Expired", zh: "已过期") }
    public var membershipExpirationNeedsUpdate: String {
        text(en: "Expiration needs update", zh: "到期待更新")
    }
    public var neverExpires: String { text(en: "Expiration unavailable locally", zh: "到期时间未知") }
    public var enabled: String { text(en: "Enabled", zh: "启用") }
    public var autoSwitch: String { text(en: "Auto switch", zh: "自动切换") }
    public var autoSwitchNeedsTwoAccounts: String {
        text(
            en: "Save a second enabled account to use auto switch.",
            zh: "请先保存第二个已启用账号，再使用自动切换。"
        )
    }
    public var notifications: String { text(en: "Notifications", zh: "通知") }
    public var notificationsEnabledTitle: String { text(en: "Codixx notifications enabled", zh: "Codixx 通知已开启") }
    public var notificationsEnabledBody: String {
        text(en: "You will receive quota and account switch alerts.", zh: "后续会收到额度和账号切换提醒。")
    }
    public var notificationsDenied: String {
        text(
            en: "Notifications are disabled in macOS System Settings. Enable Codixx notifications there first.",
            zh: "macOS 系统设置里未允许 Codixx 通知，请先在系统设置中开启。"
        )
    }
    public var threshold: String { text(en: "Short-window threshold", zh: "短周期额度阈值") }
    public var weeklyThreshold: String { text(en: "Weekly threshold", zh: "周额度阈值") }
    public var thresholdHint: String {
        text(
            en: "Applies only to reported short usage windows, such as five hours. Weekly-only accounts use the weekly threshold.",
            zh: "仅用于实际返回的短周期额度（如 5 小时）；只有周额度的账号使用周额度阈值。"
        )
    }
    public var weeklyThresholdHint: String {
        text(
            en: "Auto switch also triggers when the current weekly quota reaches this percentage; candidates at or above it are skipped.",
            zh: "当前账号周额度达到此百分比也会触发自动切换；候选账号达到后会被跳过。"
        )
    }
    public var quotaRefresh: String { text(en: "Quota refresh", zh: "额度刷新") }
    public var usageRefresh: String { text(en: "Usage refresh", zh: "用量刷新") }
    public var usageReadFailed: String { text(en: "Could not refresh usage data", zh: "无法刷新用量数据") }
    public var loadingTrendData: String { text(en: "Loading trend data...", zh: "正在加载趋势数据...") }
    public var codexHome: String { text(en: "Codex Home", zh: "Codex 目录") }
    public var languageLabel: String { text(en: "Language", zh: "语言") }
    public var postSwitchAction: String { text(en: "After switch", zh: "切换后动作") }
    public var apiSwitchThreadSyncScope: String { text(en: "Sync threads when switching API", zh: "切换 API 时同步线程") }
    public var apiSwitchThreadSyncScopeHint: String {
        text(
            en: "All threads is slower; use it only if history is still missing.",
            zh: "所有线程会更慢，仅在历史仍缺失时使用。"
        )
    }
    public var codexRestartRequired: String { text(en: "Restart Codex required", zh: "需要重启 Codex") }
    public var restartCodexNow: String { text(en: "Restart Codex now", zh: "立即重启 Codex") }
    public var restartCodexFailed: String { text(en: "Could not restart Codex", zh: "无法重启 Codex") }
    public var topThreads: String { text(en: "Top Threads", zh: "高用量会话") }
    public var activeThread: String { text(en: "Active thread", zh: "活跃会话") }
    public var noActiveThread: String { text(en: "No active thread", zh: "暂无活跃会话") }
    public var archivedThread: String { text(en: "Archived", zh: "已归档") }
    public var noThreadUsageYet: String { text(en: "No thread usage yet", zh: "暂无会话用量") }
    public var switchLog: String { text(en: "Switch Log", zh: "切换日志") }
    public var logFilter: String { text(en: "Log filter", zh: "日志筛选") }
    public var noLogEvents: String { text(en: "No log events", zh: "暂无日志") }
    public var allLogs: String { text(en: "All", zh: "全部") }
    public var switchLogs: String { text(en: "Switch", zh: "切换") }
    public var accountLogs: String { text(en: "Account", zh: "账号") }
    public var quotaLogs: String { text(en: "Quota", zh: "额度") }
    public var errorLogs: String { text(en: "Errors", zh: "错误") }
    public var systemLogs: String { text(en: "System", zh: "系统") }
    public var noSwitchEvents: String { text(en: "No switch events", zh: "暂无切换事件") }
    public var showMore: String { text(en: "Show more", zh: "展开更多") }
    public var showLess: String { text(en: "Show less", zh: "收起") }
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
    public var currentMonthTokens: String { text(en: "This month", zh: "本月 Token 用量") }
    public var previousMonthTokens: String { text(en: "Last month", zh: "上月 Token 用量") }
    public var threads: String { text(en: "Threads", zh: "会话") }
    public var tokens: String { text(en: "Tokens", zh: "Token") }
    public var day: String { text(en: "Day", zh: "日期") }
    public var hour: String { text(en: "Hour", zh: "小时") }
    public var tokenUsageSevenDays: String { text(en: "Token usage, 7 days", zh: "近 7 天 Token 用量") }
    public var tokenUsageTwentyFourHours: String { text(en: "Token usage, 24 hours", zh: "近 24 小时 Token 用量") }
    public var noActiveAccountTitle: String { text(en: "No saved current account", zh: "尚未保存当前账号") }
    public var noActiveAccountDetail: String {
        text(
            en: "Save the current Codex auth in Accounts to show account quota here.",
            zh: "请先在“账号”里保存当前 Codex 登录，之后这里会显示账号额度。"
        )
    }
    public var weeklyUnknown: String { text(en: "Weekly quota --", zh: "每周额度 --") }
    public var resetUnknown: String { text(en: "Reset unknown", zh: "重置时间未知") }
    public var quotaNotReported: String { text(en: "Quota data not received", zh: "暂未获取到额度数据") }

    public func quotaWindowTitle(minutes: Int?) -> String {
        guard let minutes, minutes > 0 else { return text(en: "Usage quota", zh: "使用额度") }
        if minutes == 10_080 { return weeklyQuota }
        if minutes % 1_440 == 0 { return text(en: "\(minutes / 1_440)-day quota", zh: "\(minutes / 1_440) 天额度") }
        if minutes % 60 == 0 { return text(en: "\(minutes / 60)-hour quota", zh: "\(minutes / 60) 小时额度") }
        return text(en: "\(minutes)-minute quota", zh: "\(minutes) 分钟额度")
    }

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
    public var apiProviderStillRouted: String {
        text(
            en: "Codex is still pointed at a relay provider, but the current login is not an API key. Your ChatGPT credential can be sent to that relay. Clean this up now.",
            zh: "Codex 仍指向中转站 provider，但当前登录并不是 API Key —— 你的 ChatGPT 凭据可能被发送到该中转站。建议立即清理。"
        )
    }
    public var signOutAPIProvider: String { text(en: "Exit API login", zh: "退出 API 登录") }

    /// 和 `apiProviderStillRouted` 是两回事：这里是"你主动选了 API 登录"，
    /// 不是凭据外发。所以文案不能带警告，否则就是假警报。
    public var apiProviderSignedIn: String {
        text(
            en: "Currently signed in with an API key, and Codex routes through a relay provider. To go back to your ChatGPT account, use the button below.",
            zh: "当前是 API Key 登录，请求会发往 config.toml 里的自定义 provider。想退回 ChatGPT 账号登录，点下面的按钮。"
        )
    }
    public var signOutAPIProviderConfirmTitle: String {
        text(en: "Exit API login?", zh: "确定退出 API 登录吗？")
    }
    public var signOutAPIProviderConfirmMessage: String {
        text(
            en: "Codixx removes the relay provider from config.toml and restores Codex to your ChatGPT account. Codex Desktop will be restarted.",
            zh: "Codixx 会从 config.toml 移除中转站 provider，并把 Codex 还原成走你的 ChatGPT 账号。过程中会重启 Codex Desktop。"
        )
    }
    /// API Key 登录态下的确认文案：此时没有 ChatGPT 快照可回退，
    /// 收尾结果一定是"删掉 auth.json，回到登录界面"，得说清楚。
    public var signOutAPIProviderConfirmMessageAPIKey: String {
        text(
            en: "Codixx removes the relay provider from config.toml and deletes the API key from auth.json. Codex returns to its login screen and you will need to sign in with your ChatGPT account again. Saved account snapshots are not affected. Codex Desktop will be restarted.",
            zh: "Codixx 会从 config.toml 移除中转站 provider，并删除 auth.json 里的 API Key。Codex 会回到登录界面，需要你重新用 ChatGPT 账号登录。已保存的账号快照不受影响。过程中会重启 Codex Desktop。"
        )
    }
    public var signOutAPIProviderSwitchedToAccount: String {
        text(
            en: "API login removed. Codex is back on your ChatGPT account.",
            zh: "已退出 API 登录，Codex 已回到你的 ChatGPT 账号。"
        )
    }
    public var signOutAPIProviderNeedsLogin: String {
        text(
            en: "API login removed. Sign in to Codex with your ChatGPT account to continue.\n\nTo switch back with one click next time: after signing in, save a snapshot via Add account → Codex login account.",
            zh: "已退出 API 登录。请在 Codex 里用 ChatGPT 账号重新登录以继续。\n\n想以后能一键切回：登录后回到 Codixx，用「添加账号 → Codex 登录账号」存一份快照。"
        )
    }
    /// `AccountStore` 拒绝把 API Key 登录态当成 ChatGPT 账号存时给用户的解释。
    public var cannotSaveAPIKeyAsCodexAccount: String {
        text(
            en: "The current Codex login is an API key, so it cannot be saved as a \"Codex login account\" snapshot. Use the \"API key account\" tab instead, or sign in to Codex with your ChatGPT account first.",
            zh: "当前 Codex 是 API Key 登录，不能存成「Codex 登录账号」快照。请改用「API Key 账号」这一档，或先用 ChatGPT 账号登录 Codex。"
        )
    }
    public var signOutAPIProviderCleanedConfig: String {
        text(
            en: "Relay provider config removed. Your current Codex login was left untouched.",
            zh: "已清理中转站 provider 配置，当前 Codex 登录保持不变。"
        )
    }
    public var credentialRevokedWarning: String {
        text(
            en: "Your Codex login has been revoked on the server. Codex still looks signed in locally, but every request fails. Sign in to Codex again.",
            zh: "你的 Codex 登录已在服务端失效。本地看着仍是已登录，但所有请求都会失败。请在 Codex 里重新登录。"
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
            en: date.formatted(date: .abbreviated, time: .omitted),
            zh: date.formatted(date: .abbreviated, time: .omitted)
        )
    }

    public var priorityHint: String {
        text(en: "Higher = preferred for auto switch", zh: "数值越高，自动切换时越优先")
    }
    public var decreasePriority: String { text(en: "Decrease priority", zh: "降低优先级") }
    public var increasePriority: String { text(en: "Increase priority", zh: "提高优先级") }
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

    public func appLogEventTitle(_ kind: AppLogEventKind, accountAlias: String?) -> String {
        let alias = accountAlias ?? unknown
        switch kind {
        case .accountSaved:
            return text(en: "Saved account \(alias)", zh: "已保存账号 \(alias)")
        case .authImported:
            return text(en: "Imported auth.json for \(alias)", zh: "已导入 auth.json 到 \(alias)")
        case .apiProviderSaved:
            return text(en: "Saved API account \(alias)", zh: "已保存 API 账号 \(alias)")
        case .apiProviderUpdated:
            return text(en: "Updated API account \(alias)", zh: "已更新 API 账号 \(alias)")
        case .accountRenamed:
            return text(en: "Renamed account", zh: "已重命名账号")
        case .accountDeleted:
            return text(en: "Deleted account \(alias)", zh: "已删除账号 \(alias)")
        case .accountEnabled:
            return text(en: "Enabled account \(alias)", zh: "已启用账号 \(alias)")
        case .accountDisabled:
            return text(en: "Disabled account \(alias)", zh: "已停用账号 \(alias)")
        case .accountReordered:
            return text(en: "Reordered account \(alias)", zh: "已调整账号顺序 \(alias)")
        case .codexRestarted:
            return text(en: "Restarted Codex", zh: "已重启 Codex")
        case .codexRestartFailed:
            return text(en: "Could not restart Codex", zh: "无法重启 Codex")
        case .refreshFailed:
            return text(en: "Refresh failed", zh: "刷新失败")
        case .apiBalanceRefreshed:
            return text(en: "Refreshed balance for \(alias)", zh: "已刷新余额 \(alias)")
        case .apiBalanceRefreshFailed:
            return text(en: "Could not refresh balance for \(alias)", zh: "无法刷新余额 \(alias)")
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

    public func apiSwitchThreadSyncScopeLabel(_ scope: APISwitchThreadSyncScope) -> String {
        switch scope {
        case .visibleDesktopThreads:
            return text(en: "Current main threads", zh: "当前主线程")
        case .allThreads:
            return text(en: "All threads", zh: "所有")
        }
    }

    public func quotaWarningBody(alias: String, percent: Int, minutes: Int? = nil) -> String {
        text(
            en: "\(alias) is at \(percent)% of the \(quotaWindowTitle(minutes: minutes)).",
            zh: "\(alias) 已使用\(quotaWindowTitle(minutes: minutes))的 \(percent)% 。"
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
