import Foundation
import XCTest
@testable import SweatStreaksCore
@testable import SweatStreaksProviderGitHub
import SweatStreaksProviderSupport

final class GitHubProviderTests: XCTestCase {
    func testContributionMapping() async throws {
        let json = """
        {
          "data": {
            "user": {
              "contributionsCollection": {
                "contributionCalendar": {
                  "weeks": [
                    {
                      "contributionDays": [
                        { "date": "2026-02-17", "contributionCount": 0 },
                        { "date": "2026-02-18", "contributionCount": 3 }
                      ]
                    }
                  ]
                }
              }
            }
          }
        }
        """

        let client = StubHTTPClient { _ in
            (Data(json.utf8), Self.makeResponse(status: 200))
        }

        let provider = GitHubProvider(
            username: "me",
            token: "token",
            httpClient: client,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let now = Date()
        let result = try await provider.fetchActivityDays(range: now...now)

        XCTAssertFalse(result.authError)
        XCTAssertNil(result.rateLimitedUntil)
        XCTAssertEqual(result.days[LocalDay(isoDate: "2026-02-17")!], .inactive)
        XCTAssertEqual(result.days[LocalDay(isoDate: "2026-02-18")!], .active)
    }

    func testAuthErrorResponse() async throws {
        let client = StubHTTPClient { _ in
            (Data("{}".utf8), Self.makeResponse(status: 401))
        }

        let provider = GitHubProvider(
            username: "me",
            token: "bad-token",
            httpClient: client,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let now = Date()
        let result = try await provider.fetchActivityDays(range: now...now)

        XCTAssertTrue(result.authError)
        XCTAssertNil(result.rateLimitedUntil)
    }

    func testRateLimitResponseSetsRetryDate() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let retryAfterSeconds = 120
        let client = StubHTTPClient { _ in
            (
                Data("{}".utf8),
                Self.makeResponse(status: 403, headers: ["Retry-After": "\(retryAfterSeconds)"])
            )
        }

        let provider = GitHubProvider(
            username: "me",
            token: "token",
            httpClient: client,
            now: { now }
        )

        let result = try await provider.fetchActivityDays(range: now...now)

        XCTAssertFalse(result.authError)
        XCTAssertNotNil(result.rateLimitedUntil)
        XCTAssertEqual(result.rateLimitedUntil!.timeIntervalSince(now), TimeInterval(retryAfterSeconds), accuracy: 0.01)
    }

    func testRejectsNonHTTPSEndpoint() async {
        let client = StubHTTPClient { _ in
            XCTFail("HTTP client should not be called for insecure endpoint")
            return (Data("{}".utf8), Self.makeResponse(status: 200))
        }

        let provider = GitHubProvider(
            username: "me",
            token: "token",
            httpClient: client,
            endpoint: URL(string: "http://api.github.com/graphql")!
        )

        do {
            let now = Date()
            _ = try await provider.fetchActivityDays(range: now...now)
            XCTFail("Expected HTTPS enforcement error")
        } catch ProviderError.unknown(let message) {
            XCTAssertEqual(message, "GitHub endpoint must use HTTPS.")
        } catch {
            XCTFail("Expected HTTPS enforcement error, got \(error)")
        }
    }

    private static func makeResponse(status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.github.com/graphql")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: headers
        )!
    }
}

private struct StubHTTPClient: HTTPClient {
    let handler: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await handler(request)
    }
}
