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

    func testSubmissionCalendarTreatsEpochKeysAsUTCDayBuckets() throws {
        let originalTimeZone = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "America/New_York")!
        addTeardownBlock {
            NSTimeZone.default = originalTimeZone
        }

        let activeEpoch = Self.epochUTC(year: 2026, month: 5, day: 12)
        let days = try LeetCodeProvider.parseSubmissionCalendar("{\"\(activeEpoch)\": 1}")

        XCTAssertEqual(days, [LocalDay(year: 2026, month: 5, day: 12)])
    }

    func testRecentSubmissionsMapLateEveningUTCNextDayToCurrentLocalDay() async throws {
        let timeZone = TimeZone(identifier: "America/New_York")!
        let originalTimeZone = NSTimeZone.default
        NSTimeZone.default = timeZone
        addTeardownBlock {
            NSTimeZone.default = originalTimeZone
        }

        let utcNextDayEpoch = Self.epochUTC(year: 2026, month: 6, day: 3)
        let recentSubmissionEpoch = Self.epoch(
            year: 2026,
            month: 6,
            day: 2,
            hour: 21,
            minute: 52,
            second: 34,
            timeZone: timeZone
        )

        let client = LeetCodeStubHTTPClient { request in
            switch Self.operationName(from: request) {
            case "userProfileCalendar":
                return (
                    Data(Self.calendarResponse(epoch: utcNextDayEpoch, count: 2).utf8),
                    Self.makeResponse(status: 200)
                )
            case "recentSubmissions":
                return (
                    Data(Self.recentSubmissionsResponse(timestamps: [recentSubmissionEpoch]).utf8),
                    Self.makeResponse(status: 200)
                )
            default:
                XCTFail("Unexpected LeetCode operation")
                return (Data("{}".utf8), Self.makeResponse(status: 400))
            }
        }

        let provider = LeetCodeProvider(
            username: "me",
            httpClient: client,
            now: {
                Self.date(year: 2026, month: 6, day: 2, hour: 21, minute: 55, timeZone: timeZone)
            }
        )

        let start = Self.date(year: 2026, month: 6, day: 2, timeZone: timeZone)
        let end = Self.date(year: 2026, month: 6, day: 2, hour: 23, minute: 59, second: 59, timeZone: timeZone)
        let result = try await provider.fetchActivityDays(range: start...end)

        XCTAssertEqual(result.days[LocalDay(year: 2026, month: 6, day: 2)], .active)
        XCTAssertNil(result.days[LocalDay(year: 2026, month: 6, day: 3)])
    }

    func testRecentSubmissionsPreventYesterdayActivityFromCarryingIntoNewLocalDay() async throws {
        let timeZone = TimeZone(identifier: "America/New_York")!
        let originalTimeZone = NSTimeZone.default
        NSTimeZone.default = timeZone
        addTeardownBlock {
            NSTimeZone.default = originalTimeZone
        }

        let utcNextDayEpoch = Self.epochUTC(year: 2026, month: 6, day: 3)
        let recentSubmissionEpoch = Self.epoch(
            year: 2026,
            month: 6,
            day: 2,
            hour: 21,
            minute: 52,
            second: 34,
            timeZone: timeZone
        )

        let client = LeetCodeStubHTTPClient { request in
            switch Self.operationName(from: request) {
            case "userProfileCalendar":
                return (
                    Data(Self.calendarResponse(epoch: utcNextDayEpoch, count: 2).utf8),
                    Self.makeResponse(status: 200)
                )
            case "recentSubmissions":
                return (
                    Data(Self.recentSubmissionsResponse(timestamps: [recentSubmissionEpoch]).utf8),
                    Self.makeResponse(status: 200)
                )
            default:
                XCTFail("Unexpected LeetCode operation")
                return (Data("{}".utf8), Self.makeResponse(status: 400))
            }
        }

        let provider = LeetCodeProvider(
            username: "me",
            httpClient: client,
            now: {
                Self.date(year: 2026, month: 6, day: 3, hour: 0, minute: 30, timeZone: timeZone)
            }
        )

        let start = Self.date(year: 2026, month: 6, day: 2, timeZone: timeZone)
        let end = Self.date(year: 2026, month: 6, day: 3, hour: 23, minute: 59, second: 59, timeZone: timeZone)
        let result = try await provider.fetchActivityDays(range: start...end)

        XCTAssertEqual(result.days[LocalDay(year: 2026, month: 6, day: 2)], .active)
        XCTAssertEqual(result.days[LocalDay(year: 2026, month: 6, day: 3)], .inactive)
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

    private static func epoch(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Int,
        timeZone: TimeZone
    ) -> Int {
        Int(
            date(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute,
                second: second,
                timeZone: timeZone
            ).timeIntervalSince1970
        )
    }

    private static func epochUTC(year: Int, month: Int, day: Int) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return Int(calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: year, month: month, day: day))!.timeIntervalSince1970)
    }

    private static func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0,
        second: Int = 0,
        timeZone: TimeZone = .current
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute,
                second: second
            )
        )!
    }

    private static func operationName(from request: URLRequest) -> String {
        guard let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let operationName = json["operationName"] as? String else {
            return ""
        }
        return operationName
    }

    private static func calendarResponse(epoch: Int, count: Int) -> String {
        """
        {
          "data": {
            "matchedUser": {
              "userCalendar": {
                "submissionCalendar": "{\\"\(epoch)\\": \(count)}"
              }
            }
          }
        }
        """
    }

    private static func recentSubmissionsResponse(timestamps: [Int]) -> String {
        let items = timestamps.map { #"{"timestamp": "\#($0)"}"# }.joined(separator: ",")
        return """
        {
          "data": {
            "recentSubmissionList": [\(items)]
          }
        }
        """
    }
}

private struct LeetCodeStubHTTPClient: HTTPClient {
    let handler: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await handler(request)
    }
}
