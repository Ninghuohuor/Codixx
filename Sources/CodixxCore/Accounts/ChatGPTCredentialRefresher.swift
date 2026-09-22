import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol ChatGPTCredentialRefreshing: Sendable {
    func refresh(snapshot: AuthSnapshot) async throws -> AuthSnapshot
}

/// Renews saved ChatGPT credentials for accounts that are not currently active
/// in Codex. Codex refreshes only the auth.json it is actively using; Codixx
/// keeps the other account snapshots alive so their quota can still be tracked.
public struct ChatGPTCredentialRefresher: ChatGPTCredentialRefreshing {
    public enum RefreshError: Error, Equatable {
        case missingRefreshToken
        case rejected(status: Int, code: String?)
        case invalidResponse
        case accountChanged
    }

    public static let officialEndpoint = URL(string: "https://auth.openai.com/oauth/token")!
    public static let officialClientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    private let endpoint: URL
    private let clientID: String
    private let now: @Sendable () -> Date

    public init(
        endpoint: URL = Self.officialEndpoint,
        clientID: String = Self.officialClientID,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.endpoint = endpoint
        self.clientID = clientID
        self.now = now
    }

    public static func request(
        snapshot: AuthSnapshot,
        endpoint: URL = officialEndpoint,
        clientID: String = officialClientID
    ) throws -> URLRequest {
        guard let refreshToken = snapshot.stringValue(for: "refresh_token"), !refreshToken.isEmpty else {
            throw RefreshError.missingRefreshToken
        }
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ], options: [.sortedKeys])
        return request
    }

    public func refresh(snapshot: AuthSnapshot) async throws -> AuthSnapshot {
        let oldFingerprint = try AccountFingerprint.generate(from: snapshot)
        let configuration = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: Self.request(
            snapshot: snapshot,
            endpoint: endpoint,
            clientID: clientID
        ))
        guard let http = response as? HTTPURLResponse else { throw RefreshError.invalidResponse }
        guard http.statusCode == 200 else {
            throw RefreshError.rejected(status: http.statusCode, code: Self.errorCode(in: data))
        }
        let refreshed = try Self.updatedSnapshot(from: snapshot, responseData: data, refreshedAt: now())
        guard try AccountFingerprint.generate(from: refreshed) == oldFingerprint else {
            throw RefreshError.accountChanged
        }
        return refreshed
    }

    public static func updatedSnapshot(
        from snapshot: AuthSnapshot,
        responseData: Data,
        refreshedAt: Date
    ) throws -> AuthSnapshot {
        struct Response: Decodable {
            var id_token: String?
            var access_token: String?
            var refresh_token: String?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: responseData),
              let accessToken = response.access_token,
              !accessToken.isEmpty
        else {
            throw RefreshError.invalidResponse
        }
        return try snapshot.replacingChatGPTTokens(
            idToken: response.id_token,
            accessToken: accessToken,
            refreshToken: response.refresh_token,
            refreshedAt: refreshedAt
        )
    }

    private static func errorCode(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let code = object["code"] as? String { return code }
        if let error = object["error"] as? [String: Any] {
            return error["code"] as? String ?? error["type"] as? String
        }
        return nil
    }
}
