import Foundation
import XCTest
@testable import SweatStreaksCore
@testable import SweatStreaksProviderLeetCode
import SweatStreaksProviderSupport

final class LeetCodeProviderTests: XCTestCase {
    func testSubmissionCalendarMappingFillsInactiveDays() async throws {
        let activeEpoch = Self.epoch(year: 2026, month: 2, day: 18)
        let json = """
        {
          "data": {
            "matchedUser": {
              "userCalendar": {
                "submissionCalendar": "{\\"\(activeEpoch)\\": 2}"
              }
            }
          }
        }
        """

        let client = LeetCodeStubHTTPClient { _ in
            (Data(json.utf8), Self.makeResponse(status: 200))
        }

        let provider = LeetCodeProvider(
            username: "me",
            httpClient: client,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let start = Self.date(year: 2026, month: 2, day: 17)
        let end = Self.date(year: 2026, month: 2, day: 19)
        let result = try await provider.fetchActivityDays(range: start...end)

        XCTAssertEqual(result.days[LocalDay(year: 2026, month: 2, day: 17)], .inactive)
        XCTAssertEqual(result.days[LocalDay(year: 2026, month: 2, day: 18)], .active)
        XCTAssertEqual(result.days[LocalDay(year: 2026, month: 2, day: 19)], .inactive)
    }

    func testRateLimitResponseThrowsRateLimitedError() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let client = LeetCodeStubHTTPClient { _ in
            (
                Data("{}".utf8),
                Self.makeResponse(status: 429, headers: ["Retry-After": "60"])
            )
        }

        let provider = LeetCodeProvider(
            username: "me",
            httpClient: client,
            now: { now }
        )

        do {
            _ = try await provider.fetchActivityDays(range: now...now)
            XCTFail("Expected rate-limit error")
        } catch ProviderError.rateLimited(let retryAfter) {
            XCTAssertNotNil(retryAfter)
            XCTAssertEqual(retryAfter!.timeIntervalSince(now), 60, accuracy: 0.01)
        } catch {
            XCTFail("Expected rate-limit error, got \(error)")
        }
    }

    func testRejectsNonHTTPSEndpoint() async {
        let client = LeetCodeStubHTTPClient { _ in
            XCTFail("HTTP client should not be called for insecure endpoint")
            return (Data("{}".utf8), Self.makeResponse(status: 200))
        }

        let provider = LeetCodeProvider(
            username: "me",
            httpClient: client,
            endpoint: URL(string: "http://leetcode.com/graphql")!
        )

        do {
            let now = Date()
            _ = try await provider.fetchActivityDays(range: now...now)
            XCTFail("Expected HTTPS enforcement error")
        } catch ProviderError.unknown(let message) {
            XCTAssertEqual(message, "LeetCode endpoint must use HTTPS.")
        } catch {
            XCTFail("Expected HTTPS enforcement error, got \(error)")
        }
    }

    func testGraphQLErrorMessageIsSanitized() async {
        let json = """
        {
          "errors": [
            { "message": "internal detail with username and query context" }
          ]
        }
        """
        let client = LeetCodeStubHTTPClient { _ in
            (Data(json.utf8), Self.makeResponse(status: 200))
        }

        let provider = LeetCodeProvider(username: "me", httpClient: client)

        do {
            let now = Date()
            _ = try await provider.fetchActivityDays(range: now...now)
            XCTFail("Expected sanitized GraphQL error")
        } catch ProviderError.unknown(let message) {
            XCTAssertEqual(message, "LeetCode returned a GraphQL error.")
        } catch {
            XCTFail("Expected sanitized GraphQL error, got \(error)")
        }
    }

    private static func makeResponse(status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://leetcode.com/graphql")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: headers
        )!
    }

    private static func epoch(year: Int, month: Int, day: Int) -> Int {
        Int(date(year: year, month: month, day: day).timeIntervalSince1970)
    }

    private static func date(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: year, month: month, day: day))!
    }
}

private struct LeetCodeStubHTTPClient: HTTPClient {
    let handler: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await handler(request)
    }
}
