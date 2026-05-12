import Foundation
import SweatStreaksCore

public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.network
        }
        return (data, httpResponse)
    }
}

public enum ProviderHTTP {
    public static func requireHTTPS(endpoint: URL, providerName: String) throws {
        guard endpoint.scheme == "https" else {
            throw ProviderError.unknown(message: "\(providerName) endpoint must use HTTPS.")
        }
    }

    public static func parseRateLimitDate(response: HTTPURLResponse, fallbackNow: Date) -> Date? {
        if let retryAfterString = response.value(forHTTPHeaderField: "Retry-After"),
           let retrySeconds = TimeInterval(retryAfterString) {
            return fallbackNow.addingTimeInterval(retrySeconds)
        }

        if let resetString = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
           let resetEpoch = TimeInterval(resetString) {
            return Date(timeIntervalSince1970: resetEpoch)
        }

        if let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
           remaining == "0" {
            return fallbackNow.addingTimeInterval(TimeInterval(SyncDefaults.rateLimitCooldownMinutes * 60))
        }

        return nil
    }
}
