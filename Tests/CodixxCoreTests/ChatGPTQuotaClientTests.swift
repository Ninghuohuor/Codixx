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

    func testSuccessfulQueryUsesOneRequestWithDefaultTLS() async throws {
        let stub = QuotaRequestStub(outcomes: [.response(200, Self.usage)])
        let quota = try await query(using: stub)
        let attempts = await stub.attempts
        XCTAssertEqual(attempts.count, 1)
        XCTAssertTrue(attempts[0].usesDefaultTLS)
        XCTAssertEqual(quota.accountId, "saved-pro")
        XCTAssertEqual(quota.alias, "Pro")
        XCTAssertEqual(quota.primaryUsedPercent, 37)
    }

    func testHandshakeFailureRetriesTheSameRequestOnceWithTLS12Only() async throws {
        let stub = QuotaRequestStub(outcomes: [
            .failure(URLError(.secureConnectionFailed) as NSError), .response(200, Self.usage)
        ])
        let quota = try await query(using: stub)
        let attempts = await stub.attempts
        XCTAssertEqual(attempts.count, 2)
        XCTAssertTrue(attempts[0].usesDefaultTLS)
        XCTAssertTrue(attempts[1].usesTLS12Only)
        XCTAssertEqual(attempts[0].request, attempts[1].request)
        XCTAssertEqual(attempts[1].request.url?.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
        XCTAssertEqual(attempts[1].request.value(forHTTPHeaderField: "Authorization"), "Bearer test-access-token")
        XCTAssertEqual(attempts[1].request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "test-account")
        XCTAssertEqual(attempts[1].request.timeoutInterval, 20)
        XCTAssertEqual(quota.primaryWindowMinutes, 10080)
        XCTAssertEqual(quota.primaryUsedPercent, 37)
    }

    func testTLS12FailureIsReturnedWithoutAThirdAttempt() async throws {
        for code in [URLError.Code.secureConnectionFailed, .serverCertificateUntrusted] {
            let stub = QuotaRequestStub(outcomes: [
                .failure(URLError(.secureConnectionFailed) as NSError), .failure(URLError(code) as NSError)
            ])
            do {
                _ = try await query(using: stub)
                XCTFail("Expected the fallback error")
            } catch {
                XCTAssertEqual((error as NSError).domain, NSURLErrorDomain)
                XCTAssertEqual((error as NSError).code, code.rawValue)
            }
            let count = await stub.attempts.count
            XCTAssertEqual(count, 2)
        }
    }

    func testCertificateAndOtherNetworkErrorsDoNotTriggerTLSFallback() async throws {
        let codes: [URLError.Code] = [
            .serverCertificateHasBadDate, .serverCertificateUntrusted, .serverCertificateHasUnknownRoot,
            .serverCertificateNotYetValid, .clientCertificateRejected, .clientCertificateRequired,
            .timedOut, .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cancelled
        ]
        let errors = codes.map { URLError($0) as NSError }
            + [NSError(domain: "ExampleOtherDomain", code: URLError.secureConnectionFailed.rawValue)]
        for expected in errors {
            let stub = QuotaRequestStub(outcomes: [.failure(expected)])
            do {
                _ = try await query(using: stub)
                XCTFail("Expected the original network error")
            } catch {
                XCTAssertEqual((error as NSError).domain, expected.domain)
                XCTAssertEqual((error as NSError).code, expected.code)
            }
            let count = await stub.attempts.count
            XCTAssertEqual(count, 1)
        }
    }

    func testHTTPFailuresKeepExistingMeaningBeforeAndAfterTLSFallback() async throws {
        for fallback in [false, true] {
            for status in [401, 403, 429, 500] {
                var outcomes: [QuotaRequestStub.Outcome] = [.response(status, Data())]
                if fallback { outcomes.insert(.failure(URLError(.secureConnectionFailed) as NSError), at: 0) }
                let stub = QuotaRequestStub(outcomes: outcomes)
                do {
                    _ = try await query(using: stub)
                    XCTFail("Expected HTTP failure")
                } catch ChatGPTQuotaClient.QueryError.expiredLogin {
                    XCTAssertEqual(status, 401)
                } catch ChatGPTQuotaClient.QueryError.http(let actualStatus) {
                    XCTAssertEqual(actualStatus, status)
                    XCTAssertNotEqual(status, 401)
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
                let count = await stub.attempts.count
                XCTAssertEqual(count, fallback ? 2 : 1)
            }
        }
    }

    func testInvalidPayloadDoesNotTriggerTLSFallback() async throws {
        let stub = QuotaRequestStub(outcomes: [.response(200, Data("invalid JSON".utf8))])
        do {
            _ = try await query(using: stub)
            XCTFail("Expected invalid response")
        } catch ChatGPTQuotaClient.QueryError.invalidResponse {
            // Preserve response validation rather than retrying an HTTP success.
        }
        let count = await stub.attempts.count
        XCTAssertEqual(count, 1)
    }

    func testCancellationAfterHandshakeFailurePreventsRetry() async throws {
        let stub = QuotaRequestStub(outcomes: [.cancelDuringHandshake])
        let task = Task { try await self.query(using: stub) }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // The cancelled task must not issue the compatibility request.
        }
        let count = await stub.attempts.count
        XCTAssertEqual(count, 1)
    }

    private static let usage = Data(#"{"plan_type":"prolite","rate_limit":{"primary_window":{"used_percent":37,"limit_window_seconds":604800,"reset_at":1790000000}}}"#.utf8)

    private func query(using stub: QuotaRequestStub) async throws -> AccountQuotaState {
        let snapshot = try AuthSnapshot(jsonData: Data(#"{"auth_mode":"chatgpt","tokens":{"access_token":"test-access-token","account_id":"test-account"}}"#.utf8))
        let client = ChatGPTQuotaClient { request, configuration in
            try await stub.load(request, configuration: configuration)
        }
        return try await client.query(snapshot: snapshot, accountID: "saved-pro", alias: "Pro")
    }
}

private actor QuotaRequestStub {
    enum Outcome {
        case response(Int, Data)
        case failure(NSError)
        case cancelDuringHandshake
    }

    struct Attempt {
        let request: URLRequest
        let usesDefaultTLS: Bool
        let usesTLS12Only: Bool
    }

    private var outcomes: [Outcome]
    private(set) var attempts: [Attempt] = []

    init(outcomes: [Outcome]) { self.outcomes = outcomes }

    func load(_ request: URLRequest, configuration: URLSessionConfiguration) throws -> (Data, URLResponse) {
        let defaults = URLSessionConfiguration.ephemeral
        attempts.append(Attempt(
            request: request,
            usesDefaultTLS: configuration.tlsMinimumSupportedProtocolVersion == defaults.tlsMinimumSupportedProtocolVersion
                && configuration.tlsMaximumSupportedProtocolVersion == defaults.tlsMaximumSupportedProtocolVersion,
            usesTLS12Only: configuration.tlsMinimumSupportedProtocolVersion == .TLSv12
                && configuration.tlsMaximumSupportedProtocolVersion == .TLSv12
        ))
        guard !outcomes.isEmpty else { throw URLError(.badServerResponse) }
        switch outcomes.removeFirst() {
        case .response(let status, let data):
            return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        case .failure(let error):
            throw error
        case .cancelDuringHandshake:
            withUnsafeCurrentTask { $0?.cancel() }
            throw URLError(.secureConnectionFailed)
        }
    }
}
