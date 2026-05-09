import Foundation

public struct APIProviderConnectivityResult: Equatable, Sendable {
    public let isSuccess: Bool
    public let message: String

    public init(isSuccess: Bool, message: String) {
        self.isSuccess = isSuccess
        self.message = message
    }
}

public protocol APIProviderConnectivityTesting: Sendable {
    func testConnection(baseURL: URL, apiKey: String, defaultModel: String?) async -> APIProviderConnectivityResult
}

public struct APIProviderConnectivityTester: APIProviderConnectivityTesting {
    private let session: URLSession
    private let timeout: TimeInterval

    public init(session: URLSession = .shared, timeout: TimeInterval = 12) {
        self.session = session
        self.timeout = timeout
    }

    public func testConnection(baseURL: URL, apiKey: String, defaultModel: String?) async -> APIProviderConnectivityResult {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return APIProviderConnectivityResult(isSuccess: false, message: "API Key is required")
        }

        let modelsURL = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: modelsURL, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return APIProviderConnectivityResult(isSuccess: false, message: "Invalid response")
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                return APIProviderConnectivityResult(
                    isSuccess: false,
                    message: "Connection failed: HTTP \(httpResponse.statusCode)"
                )
            }

            let modelIDs = Self.modelIDs(from: data)
            let trimmedModel = defaultModel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmedModel.isEmpty else {
                return APIProviderConnectivityResult(isSuccess: true, message: "Connection succeeded")
            }
            guard modelIDs.contains(trimmedModel) else {
                return APIProviderConnectivityResult(
                    isSuccess: false,
                    message: "Model not found: \(trimmedModel)"
                )
            }
            return APIProviderConnectivityResult(isSuccess: true, message: "Connection succeeded")
        } catch {
            return APIProviderConnectivityResult(isSuccess: false, message: "Connection failed: \(error.localizedDescription)")
        }
    }

    private static func modelIDs(from data: Data) -> Set<String> {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let modelObjects = json["data"] as? [[String: Any]]
        else {
            return []
        }
        return Set(modelObjects.compactMap { $0["id"] as? String })
    }
}
