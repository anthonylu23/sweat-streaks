import Foundation
import SweatStreaksCore
import SweatStreaksProviderSupport

public struct LeetCodeProvider: ActivityProvider {
    public let source: ActivitySource = .leetcode

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

        for year in years {
            let response = try await fetchCalendar(year: year)
            activeDays.formUnion(response)
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
            warning: nil
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
            variables: LeetCodeGraphQLVariables(username: username, year: year),
            operationName: "userProfileCalendar"
        )
        request.httpBody = try JSONEncoder().encode(payload)

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

        guard let calendar = parsed.data?.matchedUser?.userCalendar?.submissionCalendar else {
            throw ProviderError.unknown(message: "LeetCode user calendar was unavailable.")
        }

        return try Self.parseSubmissionCalendar(calendar)
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
}

private struct LeetCodeGraphQLRequest: Encodable {
    let query: String
    let variables: LeetCodeGraphQLVariables
    let operationName: String
}

private struct LeetCodeGraphQLVariables: Encodable {
    let username: String
    let year: Int
}

private struct LeetCodeGraphQLResponse: Decodable {
    let data: LeetCodeGraphQLData?
    let errors: [LeetCodeGraphQLError]?
}

private struct LeetCodeGraphQLData: Decodable {
    let matchedUser: LeetCodeMatchedUser?
}

private struct LeetCodeMatchedUser: Decodable {
    let userCalendar: LeetCodeUserCalendar?
}

private struct LeetCodeUserCalendar: Decodable {
    let submissionCalendar: String?
}

private struct LeetCodeGraphQLError: Decodable {
    let message: String
}
