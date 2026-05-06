import XCTest
@testable import CodixxCore

final class LocalizationTests: XCTestCase {
    func testEnglishStringsExplainUnsavedCurrentAccount() {
        let strings = CodixxStrings(language: .english)

        XCTAssertEqual(strings.noActiveAccountTitle, "No saved current account")
        XCTAssertEqual(strings.noActiveAccountDetail, "Save the current Codex auth in Accounts to show account quota here.")
        XCTAssertEqual(strings.languageLabel, "Language")
        XCTAssertEqual(strings.confidenceLabel(.unknown), "Quota unknown")
        XCTAssertEqual(strings.fiveHourQuotaWithConfidence("Fresh quota"), "5-hour quota / Fresh quota")
        XCTAssertEqual(strings.weeklyPercent(15), "Weekly quota 15%")
        XCTAssertEqual(strings.primaryQuota(primary: "94%", confidence: "Fresh quota"), "5-hour 94% / Fresh quota")
        XCTAssertEqual(strings.savedCurrentAccount(alias: "Main"), "Saved Main.")
        XCTAssertEqual(strings.couldNotSaveCurrentAccount("Missing token"), "Could not save current account: Missing token")
        XCTAssertEqual(strings.switchSuccessTitle(target: "Main"), "Switched to Main")
        XCTAssertEqual(strings.logs, "Logs")
        XCTAssertEqual(strings.switchTriggerLabel(.autoPrimaryThreshold), "Automatic")
        XCTAssertEqual(strings.switchTriggerLabel(.manual), "Manual")
        XCTAssertEqual(strings.switchTriggerLabel(.recovery), "Recovery")
        XCTAssertEqual(strings.switchResultLabel(.failedValidation), "Validation failed")
        XCTAssertEqual(strings.errorSummaryLabel, "Error")
        XCTAssertEqual(strings.backupPathLabel, "Backup")
        XCTAssertEqual(strings.renameAccount, "Rename account")
        XCTAssertEqual(strings.deleteAccount, "Delete account")
        XCTAssertEqual(strings.autoSwitchNeedsTwoAccounts, "Save a second enabled account to use auto switch.")
        XCTAssertEqual(strings.quotaRefresh, "Quota refresh")
        XCTAssertEqual(strings.usageRefresh, "Usage refresh")
        XCTAssertEqual(strings.secondsInterval(60), "60s")
        XCTAssertEqual(strings.minutesInterval(5), "5m")
    }

    func testChineseStringsExplainUnsavedCurrentAccount() {
        let strings = CodixxStrings(language: .chinese)

        XCTAssertEqual(strings.noActiveAccountTitle, "尚未保存当前账号")
        XCTAssertEqual(strings.noActiveAccountDetail, "请先在“账号”里保存当前 Codex 登录，之后这里会显示账号额度。")
        XCTAssertEqual(strings.languageLabel, "语言")
        XCTAssertEqual(strings.confidenceLabel(.unknown), "额度未知")
        XCTAssertEqual(strings.fiveHourQuotaWithConfidence("额度信息新鲜"), "5 小时额度 / 额度信息新鲜")
        XCTAssertEqual(strings.weeklyPercent(15), "每周额度 15%")
        XCTAssertEqual(strings.primaryQuota(primary: "94%", confidence: "额度信息新鲜"), "5 小时 94% / 额度信息新鲜")
        XCTAssertEqual(strings.savedCurrentAccount(alias: "Main"), "已保存 Main。")
        XCTAssertEqual(strings.couldNotSaveCurrentAccount("缺少令牌"), "无法保存当前账号：缺少令牌")
        XCTAssertEqual(strings.switchSuccessTitle(target: "Main"), "已切换到 Main")
        XCTAssertEqual(strings.logs, "日志")
        XCTAssertEqual(strings.switchTriggerLabel(.autoPrimaryThreshold), "自动切换")
        XCTAssertEqual(strings.switchTriggerLabel(.manual), "手动切换")
        XCTAssertEqual(strings.switchTriggerLabel(.recovery), "恢复")
        XCTAssertEqual(strings.switchResultLabel(.failedValidation), "校验失败")
        XCTAssertEqual(strings.errorSummaryLabel, "错误")
        XCTAssertEqual(strings.backupPathLabel, "备份")
        XCTAssertEqual(strings.renameAccount, "重命名账号")
        XCTAssertEqual(strings.deleteAccount, "删除账号")
        XCTAssertEqual(strings.autoSwitchNeedsTwoAccounts, "请先保存第二个已启用账号，再使用自动切换。")
        XCTAssertEqual(strings.quotaRefresh, "额度刷新")
        XCTAssertEqual(strings.usageRefresh, "用量刷新")
        XCTAssertEqual(strings.secondsInterval(60), "60 秒")
        XCTAssertEqual(strings.minutesInterval(5), "5 分钟")
    }
}
