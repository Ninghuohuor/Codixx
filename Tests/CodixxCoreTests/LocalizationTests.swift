import XCTest
@testable import CodixxCore

final class LocalizationTests: XCTestCase {
    func testEnglishStringsExplainUnsavedCurrentAccount() {
        let strings = CodixxStrings(language: .english)

        XCTAssertEqual(strings.noActiveAccountTitle, "No saved current account")
        XCTAssertEqual(strings.noActiveAccountDetail, "Save the current Codex auth in Accounts to show account quota here.")
        XCTAssertEqual(strings.languageLabel, "Language")
        XCTAssertEqual(strings.confidenceLabel(.unknown), "Quota unknown")
        XCTAssertEqual(strings.switchSuccessTitle(target: "Main"), "Switched to Main")
    }

    func testChineseStringsExplainUnsavedCurrentAccount() {
        let strings = CodixxStrings(language: .chinese)

        XCTAssertEqual(strings.noActiveAccountTitle, "尚未保存当前账号")
        XCTAssertEqual(strings.noActiveAccountDetail, "请先在“账号”里保存当前 Codex 登录，之后这里会显示账号额度。")
        XCTAssertEqual(strings.languageLabel, "语言")
        XCTAssertEqual(strings.confidenceLabel(.unknown), "额度未知")
        XCTAssertEqual(strings.switchSuccessTitle(target: "Main"), "已切换到 Main")
    }
}
