import Foundation
import XCTest
@testable import CodixxCore

final class APIBalanceQueryTesterTests: XCTestCase {
    func testAccountIDHeaderAndMissingIDError() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BalanceAuthProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let tester = APIBalanceQueryTester(session: session)
        let url = URL(string: "https://relay.example/api/user/self")!
        let missing = await tester.queryBalance(url: url, apiKey: "test-token", jsonPath: "data.quota")
        XCTAssertFalse(missing.isSuccess)
        XCTAssertTrue(missing.message.contains("New-Api-User"))
        let valid = await tester.queryBalance(url: url, apiKey: "test-token", jsonPath: "data.quota", userID: "123")
        XCTAssertTrue(valid.isSuccess)
        XCTAssertEqual(valid.balanceText, "6170000")
    }
}

private final class BalanceAuthProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let valid = request.value(forHTTPHeaderField: "New-Api-User") == "123"
            && request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token"
        let data = Data((valid ? #"{"success":true,"data":{"quota":6170000}}"# : #"{"success":false,"message":"未提供 New-Api-User"}"#).utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: valid ? 200 : 401, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
