import XCTest
@testable import CodixxCore

final class AuthProfileTests: XCTestCase {
    func testReadsPlanAndExpirationFromIDTokenAuthClaim() throws {
        let expiration = "2026-06-01T00:00:00Z"
        let snapshot = try AuthSnapshot(jsonData: Data(
            """
            {
              "tokens": {
                "id_token": "\(Self.jwt(auth: [
                    "chatgpt_plan_type": "pro",
                    "chatgpt_subscription_active_until": expiration
                ]))"
              }
            }
            """.utf8
        ))

        let profile = AuthProfileReader.profile(from: snapshot)

        XCTAssertEqual(profile?.planType, "pro")
        XCTAssertEqual(profile?.membershipExpiresAt, ISO8601DateFormatter().date(from: expiration))
    }

    func testFallsBackToAccessTokenWhenIDTokenIsMissing() throws {
        let snapshot = try AuthSnapshot(jsonData: Data(
            """
            {
              "tokens": {
                "access_token": "\(Self.jwt(auth: [
                    "chatgpt_plan_type": "plus",
                    "chatgpt_subscription_active_until": 1779000000
                ]))"
              }
            }
            """.utf8
        ))

        let profile = AuthProfileReader.profile(from: snapshot)

        XCTAssertEqual(profile?.planType, "plus")
        XCTAssertEqual(profile?.membershipExpiresAt, Date(timeIntervalSince1970: 1_779_000_000))
    }

    func testPrefersIDTokenPlanAndUsesAccessTokenOnlyForMissingFields() throws {
        let snapshot = try AuthSnapshot(jsonData: Data(
            """
            {
              "tokens": {
                "id_token": "\(Self.jwt(auth: ["chatgpt_plan_type": "pro"]))",
                "access_token": "\(Self.jwt(auth: [
                    "chatgpt_plan_type": "plus",
                    "chatgpt_subscription_active_until": "1779000000"
                ]))"
              }
            }
            """.utf8
        ))

        let profile = AuthProfileReader.profile(from: snapshot)

        XCTAssertEqual(profile?.planType, "pro")
        XCTAssertEqual(profile?.membershipExpiresAt, Date(timeIntervalSince1970: 1_779_000_000))
    }

    func testReturnsNilForAuthWithoutJWTProfileClaims() throws {
        let snapshot = try AuthSnapshot(jsonData: Data(#"{"tokens":{"access_token":"not-a-jwt"}}"#.utf8))

        XCTAssertNil(AuthProfileReader.profile(from: snapshot))
    }

    private static func jwt(auth: [String: Any]) -> String {
        let header = ["alg": "none"]
        let payload = ["https://api.openai.com/auth": auth]
        return [
            base64URL(header),
            base64URL(payload),
            "signature"
        ].joined(separator: ".")
    }

    private static func base64URL(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return data
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
