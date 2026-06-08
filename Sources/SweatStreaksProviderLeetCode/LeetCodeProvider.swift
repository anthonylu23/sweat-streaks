import Foundation
import SweatStreaksCore
import SweatStreaksProviderSupport

public struct LeetCodeProvider: ActivityProvider {
    public let source: ActivitySource = .leetcode

    private static let recentSubmissionLimit = 100

    private let username: String
    private let httpClient: HTTPClient
    private let endpoint: URL
    private let now: @Sendable () -> Date

    public init(
        username: String,
        httpClient: HTTPClient = URLSessionHTTPClient(),
        endpoint: URL = URL(string: "https://leetcode.com/graphql")!,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.username = username
        self.httpClient = httpClient
        self.endpoint = endpoint
        self.now = now
    }

    public func fetchActivityDays(range: ClosedRange<Date>) async throws -> ProviderFetchResult {
        let years = Self.years(in: range)
        var activeDays: Set<LocalDay> = []
        var warning: String?

        for year in years {
            let response = try await fetchCalendar(year: year)
            activeDays.formUnion(response)
        }

        do {
            let preciseRecentDays = try await fetchRecentSubmissionDays(range: range)
            activeDays.formUnion(preciseRecentDays)
            reconcileCurrentLocalDay(activeDays: &activeDays, preciseRecentDays: preciseRecentDays, range: range)
        } catch ProviderError.rateLimited(let retryAfter) {
            throw ProviderError.rateLimited(retryAfter: retryAfter)
        } catch {
            warning = "LeetCode recent submissions were unavailable; using profile calendar only."
        }

        var days = Self.inactiveDayMap(range: range)
        for day in activeDays {
            if days.keys.contains(day) {
                days[day] = .active
            }
        }

        return ProviderFetchResult(
            source: .leetcode,
            days: days,
            fetchedRange: range,
            rateLimitedUntil: nil,
            authError: false,
            warning: warning
        )
    }

    private func fetchCalendar(year: Int) async throws -> Set<LocalDay> {
        try ProviderHTTP.requireHTTPS(endpoint: endpoint, providerName: "LeetCode")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("SweatStreaks/1.0", forHTTPHeaderField: "User-Agent")

        let query = """
        query userProfileCalendar($username: String!, $year: Int) {
          matchedUser(username: $username) {
            userCalendar(year: $year) {
              submissionCalendar
            }
          }
        }
        """

        let payload = LeetCodeGraphQLRequest(
            query: query,
            variables: LeetCodeCalendarVariables(username: username, year: year),
            operationName: "userProfileCalendar"
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let parsed = try await sendGraphQLRequest(request)

        guard let calendar = parsed.data?.matchedUser?.userCalendar?.submissionCalendar else {
            throw ProviderError.unknown(message: "LeetCode user calendar was unavailable.")
        }

        return try Self.parseSubmissionCalendar(calendar)
    }

    private func fetchRecentSubmissionDays(range: ClosedRange<Date>) async throws -> Set<LocalDay> {
        try ProviderHTTP.requireHTTPS(endpoint: endpoint, providerName: "LeetCode")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("SweatStreaks/1.0", forHTTPHeaderField: "User-Agent")

        let query = """
        query recentSubmissions($username: String!, $limit: Int!) {
          recentSubmissionList(username: $username, limit: $limit) {
            timestamp
          }
        }
        """

        let payload = LeetCodeGraphQLRequest(
            query: query,
            variables: LeetCodeRecentSubmissionVariables(username: username, limit: Self.recentSubmissionLimit),
            operationName: "recentSubmissions"
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let parsed = try await sendGraphQLRequest(request)
        guard let recentSubmissions = parsed.data?.recentSubmissionList else {
            throw ProviderError.unknown(message: "LeetCode recent submissions were unavailable.")
        }

        return Self.parseRecentSubmissionDays(
            recentSubmissions.map(\.timestamp),
            range: range,
            timeZone: .current
        )
    }

    private func sendGraphQLRequest(_ request: URLRequest) async throws -> LeetCodeGraphQLResponse {
        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await httpClient.send(request)
        } catch {
            throw ProviderError.network
        }

        if response.statusCode == 429 {
            throw ProviderError.rateLimited(
                retryAfter: ProviderHTTP.parseRateLimitDate(response: response, fallbackNow: now())
            )
        }

        guard (200...299).contains(response.statusCode) else {
            throw ProviderError.unknown(message: "LeetCode returned status \(response.statusCode)")
        }

        let parsed: LeetCodeGraphQLResponse
        do {
            parsed = try JSONDecoder().decode(LeetCodeGraphQLResponse.self, from: data)
        } catch {
            throw ProviderError.decoding
        }

        if parsed.errors?.first != nil {
            throw ProviderError.unknown(message: "LeetCode returned a GraphQL error.")
        }

        return parsed
    }

    public static func parseSubmissionCalendar(
        _ calendar: String,
        timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!
    ) throws -> Set<LocalDay> {
        guard let data = calendar.data(using: .utf8) else {
            throw ProviderError.decoding
        }

        let raw: [String: Int]
        do {
            raw = try JSONDecoder().decode([String: Int].self, from: data)
        } catch {
            throw ProviderError.decoding
        }

        var days: Set<LocalDay> = []
        for (timestamp, count) in raw where count > 0 {
            guard let epoch = TimeInterval(timestamp) else {
                continue
            }
            let date = Date(timeIntervalSince1970: epoch)
            days.insert(LocalDay.from(date: date, in: timeZone))
        }
        return days
    }

    public static func parseRecentSubmissionDays(
        _ timestamps: [String],
        range: ClosedRange<Date>,
        timeZone: TimeZone = .current
    ) -> Set<LocalDay> {
        var days: Set<LocalDay> = []
        for timestamp in timestamps {
            guard let epoch = TimeInterval(timestamp) else {
                continue
            }

            let date = Date(timeIntervalSince1970: epoch)
            guard date >= range.lowerBound && date <= range.upperBound else {
                continue
            }

            days.insert(LocalDay.from(date: date, in: timeZone))
        }
        return days
    }

    private func reconcileCurrentLocalDay(
        activeDays: inout Set<LocalDay>,
        preciseRecentDays: Set<LocalDay>,
        range: ClosedRange<Date>
    ) {
        let currentLocalDay = LocalDay.from(date: now(), in: .current)
        guard Self.range(range, contains: currentLocalDay, timeZone: .current) else {
            return
        }

        if preciseRecentDays.contains(currentLocalDay) {
            activeDays.insert(currentLocalDay)
        } else {
            activeDays.remove(currentLocalDay)
        }
    }

    private static func inactiveDayMap(range: ClosedRange<Date>, timeZone: TimeZone = .current) -> [LocalDay: DayStatus] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let startDay = LocalDay.from(date: range.lowerBound, in: timeZone)
        let endDay = LocalDay.from(date: range.upperBound, in: timeZone)
        var cursor = startDay.date(in: timeZone) ?? range.lowerBound
        let end = endDay.date(in: timeZone) ?? range.upperBound

        var days: [LocalDay: DayStatus] = [:]
        while cursor <= end {
            days[LocalDay.from(date: cursor, in: timeZone)] = .inactive
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? end.addingTimeInterval(1)
        }
        return days
    }

    private static func years(in range: ClosedRange<Date>) -> [Int] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let startYear = calendar.component(.year, from: range.lowerBound)
        let endYear = calendar.component(.year, from: range.upperBound)
        return Array(startYear...endYear)
    }

    private static func range(_ range: ClosedRange<Date>, contains day: LocalDay, timeZone: TimeZone) -> Bool {
        let startDay = LocalDay.from(date: range.lowerBound, in: timeZone)
        let endDay = LocalDay.from(date: range.upperBound, in: timeZone)
        return day >= startDay && day <= endDay
    }
}

private struct LeetCodeGraphQLRequest<Variables: Encodable>: Encodable {
    let query: String
    let variables: Variables
    let operationName: String
}

private struct LeetCodeCalendarVariables: Encodable {
    let username: String
    let year: Int
}

private struct LeetCodeRecentSubmissionVariables: Encodable {
    let username: String
    let limit: Int
}

private struct LeetCodeGraphQLResponse: Decodable {
    let data: LeetCodeGraphQLData?
    let errors: [LeetCodeGraphQLError]?
}

private struct LeetCodeGraphQLData: Decodable {
    let matchedUser: LeetCodeMatchedUser?
    let recentSubmissionList: [LeetCodeRecentSubmission]?
}

private struct LeetCodeMatchedUser: Decodable {
    let userCalendar: LeetCodeUserCalendar?
}

private struct LeetCodeUserCalendar: Decodable {
    let submissionCalendar: String?
}

private struct LeetCodeRecentSubmission: Decodable {
    let timestamp: String
}

private struct LeetCodeGraphQLError: Decodable {
    let message: String
}
