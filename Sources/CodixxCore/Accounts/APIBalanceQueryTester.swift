import Foundation

public struct APIBalanceQueryResult: Equatable, Sendable {
    public let isSuccess: Bool
    public let message: String
    public let balanceText: String?

    public init(isSuccess: Bool, message: String, balanceText: String? = nil) {
        self.isSuccess = isSuccess
        self.message = message
        self.balanceText = balanceText
    }
}

public protocol APIBalanceQueryTesting: Sendable {
    func queryBalance(url: URL, apiKey: String, jsonPath: String) async -> APIBalanceQueryResult
}

public struct APIBalanceQueryTester: APIBalanceQueryTesting {
    private let session: URLSession
    private let timeout: TimeInterval

    public init(session: URLSession = .shared, timeout: TimeInterval = 12) {
        self.session = session
        self.timeout = timeout
    }

    public func queryBalance(url: URL, apiKey: String, jsonPath: String) async -> APIBalanceQueryResult {
        let trimmedPath = jsonPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return APIBalanceQueryResult(isSuccess: false, message: "JSON field path is required")
        }

        let requestSpec = Self.requestSpec(
            baseURL: url,
            apiKey: apiKey,
            configText: trimmedPath
        )
        var request = URLRequest(url: requestSpec.url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        requestSpec.headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return APIBalanceQueryResult(isSuccess: false, message: "Invalid response")
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                return APIBalanceQueryResult(isSuccess: false, message: "Balance query failed: HTTP \(httpResponse.statusCode)")
            }
            guard let json = try? JSONSerialization.jsonObject(with: data),
                  let value = Self.balanceValue(configText: trimmedPath, in: json)
            else {
                return APIBalanceQueryResult(isSuccess: false, message: "Balance field not found: \(trimmedPath)")
            }
            let balanceText = String(describing: value)
            return APIBalanceQueryResult(isSuccess: true, message: "Balance: \(balanceText)", balanceText: balanceText)
        } catch {
            return APIBalanceQueryResult(isSuccess: false, message: "Balance query failed: \(error.localizedDescription)")
        }
    }

    private static func value(at path: String, in json: Any) -> Any? {
        path.split(separator: ".").reduce(Optional(json)) { current, key in
            guard let current else { return nil }
            if let dictionary = current as? [String: Any] {
                return dictionary[String(key)]
            }
            if let array = current as? [Any], let index = Int(key), array.indices.contains(index) {
                return array[index]
            }
            return nil
        }
    }

    private static func balanceValue(configText: String, in json: Any) -> Any? {
        if configText.contains("extractor:") || configText.contains("request:") {
            return value(at: "remaining", in: json)
                ?? value(at: "quota.remaining", in: json)
                ?? value(at: "balance", in: json)
                ?? value(at: "data.remaining", in: json)
                ?? value(at: "data.balance", in: json)
        }
        return value(at: configText, in: json)
    }

    private static func requestSpec(baseURL: URL, apiKey: String, configText: String) -> (url: URL, headers: [String: String]) {
        guard configText.contains("request:") else {
            return (baseURL, [:])
        }

        let urlPattern = #""([^"]*\{\{baseUrl\}\}[^"]*)""#
        let urlTemplate = firstMatch(in: configText, pattern: urlPattern)
        let resolvedURLText = urlTemplate?
            .replacingOccurrences(of: "{{baseUrl}}", with: baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            .replacingOccurrences(of: "{{apiKey}}", with: apiKey)

        let resolvedURL = resolvedURLText.flatMap(URL.init(string:)) ?? baseURL
        var headers: [String: String] = [:]
        if configText.contains("Authorization") {
            headers["Authorization"] = "Bearer \(apiKey)"
        }
        return (resolvedURL, headers)
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[swiftRange])
    }
}
