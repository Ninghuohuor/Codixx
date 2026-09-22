import XCTest
@testable import CodixxCore

final class ChatGPTCredentialRefresherTests: XCTestCase {
    func testRefreshRequestUsesOfficialOAuthGrant() throws {
        let snapshot = try AuthSnapshot(jsonData: Data(#"{"auth_mode":"chatgpt","tokens":{"account_id":"acct","access_token":"old-access","refresh_token":"old-refresh"}}"#.utf8))
        let request = try ChatGPTCredentialRefresher.request(snapshot: snapshot)
        XCTAssertEqual(request.url, ChatGPTCredentialRefresher.officialEndpoint)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(body["client_id"], ChatGPTCredentialRefresher.officialClientID)
        XCTAssertEqual(body["grant_type"], "refresh_token")
        XCTAssertEqual(body["refresh_token"], "old-refresh")
    }

    func testRefreshRequestRequiresRefreshToken() throws {
        let snapshot = try AuthSnapshot(jsonData: Data(#"{"tokens":{"account_id":"acct","access_token":"old-access"}}"#.utf8))
        XCTAssertThrowsError(try ChatGPTCredentialRefresher.request(snapshot: snapshot)) { error in
            XCTAssertEqual(error as? ChatGPTCredentialRefresher.RefreshError, .missingRefreshToken)
        }
    }

    func testRefreshResponseRotatesTokensAndPreservesAccount() throws {
        let snapshot = try AuthSnapshot(jsonData: Data(#"{"auth_mode":"chatgpt","tokens":{"account_id":"acct","id_token":"old-id","access_token":"old-access","refresh_token":"old-refresh"},"other":"kept"}"#.utf8))
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let refreshed = try ChatGPTCredentialRefresher.updatedSnapshot(
            from: snapshot,
            responseData: Data(#"{"id_token":"new-id","access_token":"new-access","refresh_token":"new-refresh"}"#.utf8),
            refreshedAt: date
        )
        XCTAssertEqual(refreshed.stringValue(for: "account_id"), "acct")
        XCTAssertEqual(refreshed.stringValue(for: "id_token"), "new-id")
        XCTAssertEqual(refreshed.stringValue(for: "access_token"), "new-access")
        XCTAssertEqual(refreshed.stringValue(for: "refresh_token"), "new-refresh")
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: refreshed.jsonData) as? [String: Any])
        XCTAssertEqual(root["other"] as? String, "kept")
        XCTAssertNotNil(root["last_refresh"] as? String)
    }

    func testRefreshResponseKeepsRefreshTokenWhenServerOmitsRotation() throws {
        let snapshot = try AuthSnapshot(jsonData: Data(#"{"tokens":{"account_id":"acct","access_token":"old-access","refresh_token":"old-refresh"}}"#.utf8))
        let refreshed = try ChatGPTCredentialRefresher.updatedSnapshot(
            from: snapshot,
            responseData: Data(#"{"access_token":"new-access"}"#.utf8),
            refreshedAt: Date()
        )
        XCTAssertEqual(refreshed.stringValue(for: "access_token"), "new-access")
        XCTAssertEqual(refreshed.stringValue(for: "refresh_token"), "old-refresh")
    }
}
