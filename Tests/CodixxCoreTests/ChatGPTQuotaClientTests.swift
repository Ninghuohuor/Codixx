import XCTest
@testable import CodixxCore

final class ChatGPTQuotaClientTests: XCTestCase {
    func testWeeklyOnlyUsageResponse() throws {
        let data = Data(#"{"plan_type":"prolite","rate_limit":{"primary_window":{"used_percent":37,"limit_window_seconds":604800,"reset_at":1790000000},"secondary_window":null}}"#.utf8)
        let quota = try ChatGPTQuotaClient.parse(data, accountID: "saved-pro", alias: "Pro", now: Date())
        XCTAssertEqual(quota.accountId, "saved-pro")
        XCTAssertEqual(quota.primaryUsedPercent, 37)
        XCTAssertEqual(quota.primaryWindowMinutes, 10080)
        XCTAssertEqual(quota.primaryResetsAt, Date(timeIntervalSince1970: 1790000000))
        XCTAssertNil(quota.secondaryUsedPercent)
        XCTAssertEqual(quota.planType, "prolite")
    }

    func testTwoWindowsAndMissingQuotaAreDistinctFromZeroUsage() throws {
        let data = Data(#"{"rate_limit":{"primary_window":{"used_percent":0,"limit_window_seconds":18000,"reset_at":1790000000},"secondary_window":{"used_percent":20,"limit_window_seconds":604800,"reset_at":1790000000}}}"#.utf8)
        let quota = try ChatGPTQuotaClient.parse(data, accountID: "plus", alias: "Plus", now: Date())
        XCTAssertEqual(quota.primaryUsedPercent, 0)
        XCTAssertEqual(quota.primaryWindowMinutes, 300)
        XCTAssertEqual(quota.secondaryUsedPercent, 20)
        XCTAssertThrowsError(try ChatGPTQuotaClient.parse(Data(#"{"rate_limit":null}"#.utf8), accountID: "pro", alias: "Pro", now: Date()))
    }

    func testRequestUsesOfficialEndpointAndRejectsAPIKey() throws {
        let snapshot = try AuthSnapshot(jsonData: Data(#"{"auth_mode":"chatgpt","tokens":{"access_token":"test-access-token","account_id":"test-account"}}"#.utf8))
        let request = try ChatGPTQuotaClient.request(snapshot: snapshot)
        XCTAssertEqual(request.url?.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
        XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "test-account")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-access-token")
        XCTAssertThrowsError(try ChatGPTQuotaClient.request(snapshot: .apiKey("test-key")))
    }
}
