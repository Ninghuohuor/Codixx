import Foundation

/// Uses the same read-only usage endpoint as Codex's backend client.
/// This request never uses a configured relay URL or changes the active login.
public struct ChatGPTQuotaClient {
    public init() {}

    public enum QueryError: LocalizedError {
        case missingLogin, expiredLogin, http(Int), invalidResponse, noQuota
        public var errorDescription: String? {
            switch self {
            case .missingLogin: return "缺少 ChatGPT 登录凭据，请登录后重新保存账号。"
            case .expiredLogin: return "登录凭据已过期或失效，请在 Codex 登录后重新保存账号。"
            case .http(let status): return "额度查询失败（HTTP \(status)），请稍后重试。"
            case .invalidResponse: return "额度接口返回了无法识别的数据。"
            case .noQuota: return "服务端暂未返回可用的额度数据。"
            }
        }
    }

    public static func request(snapshot: AuthSnapshot) throws -> URLRequest {
        guard snapshot.stringValue(for: "auth_mode") != "apikey",
              let token = snapshot.stringValue(for: "access_token"), !token.isEmpty,
              let accountID = snapshot.stringValue(for: "account_id"), !accountID.isEmpty
        else { throw QueryError.missingLogin }
        if let expires = snapshot.accessTokenExpiresAt, expires <= Date() { throw QueryError.expiredLogin }
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!, timeoutInterval: 20)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    public func query(snapshot: AuthSnapshot, accountID: String, alias: String) async throws -> AccountQuotaState {
        let request = try Self.request(snapshot: snapshot)
        let configuration = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: configuration, delegate: NoQuotaRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw QueryError.invalidResponse }
        if http.statusCode == 401 { throw QueryError.expiredLogin }
        guard http.statusCode == 200 else { throw QueryError.http(http.statusCode) }
        return try Self.parse(data, accountID: accountID, alias: alias, now: Date())
    }

    public static func parse(_ data: Data, accountID: String, alias: String, now: Date) throws -> AccountQuotaState {
        struct Payload: Decodable {
            struct Limits: Decodable {
                struct Window: Decodable {
                    var used_percent: Double
                    var limit_window_seconds: Int
                    var reset_at: Double
                }
                var primary_window: Window?
                var secondary_window: Window?
            }
            var plan_type: String?
            var rate_limit: Limits?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { throw QueryError.invalidResponse }
        let primary = payload.rate_limit?.primary_window
        let secondary = payload.rate_limit?.secondary_window
        guard primary != nil || secondary != nil else { throw QueryError.noQuota }
        for window in [primary, secondary].compactMap({ $0 }) {
            guard window.used_percent.isFinite, window.used_percent >= 0,
                  window.limit_window_seconds > 0, window.reset_at > 0 else { throw QueryError.invalidResponse }
        }
        return AccountQuotaState(
            accountId: accountID, alias: alias, planType: payload.plan_type,
            primaryUsedPercent: primary?.used_percent,
            primaryWindowMinutes: primary.map { $0.limit_window_seconds / 60 },
            primaryResetsAt: primary.map { Date(timeIntervalSince1970: $0.reset_at) },
            secondaryUsedPercent: secondary?.used_percent,
            secondaryWindowMinutes: secondary.map { $0.limit_window_seconds / 60 },
            secondaryResetsAt: secondary.map { Date(timeIntervalSince1970: $0.reset_at) },
            lastObservedAt: now, confidence: .fresh
        )
    }
}

private final class NoQuotaRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
