import Foundation
import SweatStreaksCore

protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionHTTPClient: HTTPClient {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.network
        }
        return (data, httpResponse)
    }
}

struct GitHubProvider: ActivityProvider {
    let source: ActivitySource = .github

    private let username: String
    private let token: String
    private let httpClient: HTTPClient
    private let endpoint: URL
    private let now: @Sendable () -> Date

    init(
        username: String,
        token: String,
        httpClient: HTTPClient = URLSessionHTTPClient(),
        endpoint: URL = URL(string: "https://api.github.com/graphql")!,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.username = username
        self.token = token
        self.httpClient = httpClient
        self.endpoint = endpoint
        self.now = now
    }

    func fetchActivityDays(range: ClosedRange<Date>) async throws -> ProviderFetchResult {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let from = Self.formatGraphQLDateTime(range.lowerBound)
        let to = Self.formatGraphQLDateTime(range.upperBound)

        let query = """
        query($login: String!, $from: DateTime!, $to: DateTime!) {
          user(login: $login) {
            contributionsCollection(from: $from, to: $to) {
              contributionCalendar {
                weeks {
                  contributionDays {
                    date
                    contributionCount
                  }
                }
              }
            }
          }
        }
        """

        let payload = GraphQLRequest(
            query: query,
            variables: GraphQLVariables(login: username, from: from, to: to)
        )

        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await httpClient.send(request)
        } catch {
            throw ProviderError.network
        }

        if response.statusCode == 401 {
            return ProviderFetchResult(
                source: .github,
                days: [:],
                fetchedRange: range,
                rateLimitedUntil: nil,
                authError: true,
                warning: "GitHub authentication failed."
            )
        }

        if response.statusCode == 429 || response.statusCode == 403 {
            if let retryAfter = Self.parseRateLimitDate(response: response, fallbackNow: now()) {
                return ProviderFetchResult(
                    source: .github,
                    days: [:],
                    fetchedRange: range,
                    rateLimitedUntil: retryAfter,
                    authError: false,
                    warning: "GitHub rate limit reached."
                )
            }

            if response.statusCode == 403 {
                return ProviderFetchResult(
                    source: .github,
                    days: [:],
                    fetchedRange: range,
                    rateLimitedUntil: nil,
                    authError: true,
                    warning: "GitHub access forbidden. Check PAT scope and account access."
                )
            }
        }

        guard (200...299).contains(response.statusCode) else {
            throw ProviderError.unknown(message: "GitHub returned status \(response.statusCode)")
        }

        let parsed: GraphQLResponse
        do {
            parsed = try JSONDecoder().decode(GraphQLResponse.self, from: data)
        } catch {
            throw ProviderError.decoding
        }

        if let firstError = parsed.errors?.first?.message.lowercased() {
            if firstError.contains("bad credentials") || firstError.contains("authentication") {
                return ProviderFetchResult(
                    source: .github,
                    days: [:],
                    fetchedRange: range,
                    rateLimitedUntil: nil,
                    authError: true,
                    warning: "GitHub authentication failed."
                )
            }

            if firstError.contains("rate limit") {
                let retryAfter = Self.parseRateLimitDate(response: response, fallbackNow: now())
                return ProviderFetchResult(
                    source: .github,
                    days: [:],
                    fetchedRange: range,
                    rateLimitedUntil: retryAfter ?? now().addingTimeInterval(TimeInterval(SyncDefaults.rateLimitCooldownMinutes * 60)),
                    authError: false,
                    warning: "GitHub rate limit reached."
                )
            }
        }

        guard let weeks = parsed.data?.user?.contributionsCollection?.contributionCalendar?.weeks else {
            return ProviderFetchResult(
                source: .github,
                days: [:],
                fetchedRange: range,
                rateLimitedUntil: nil,
                authError: false,
                warning: "GitHub response had no contribution weeks."
            )
        }

        var dayStatuses: [LocalDay: DayStatus] = [:]
        for week in weeks {
            for contributionDay in week.contributionDays {
                guard let localDay = LocalDay(isoDate: contributionDay.date) else {
                    continue
                }
                dayStatuses[localDay] = contributionDay.contributionCount > 0 ? .active : .inactive
            }
        }

        return ProviderFetchResult(
            source: .github,
            days: dayStatuses,
            fetchedRange: range,
            rateLimitedUntil: nil,
            authError: false,
            warning: nil
        )
    }

    static func parseRateLimitDate(response: HTTPURLResponse, fallbackNow: Date) -> Date? {
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

    private static func formatGraphQLDateTime(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

private struct GraphQLRequest: Encodable {
    let query: String
    let variables: GraphQLVariables
}

private struct GraphQLVariables: Encodable {
    let login: String
    let from: String
    let to: String
}

private struct GraphQLResponse: Decodable {
    let data: GraphQLData?
    let errors: [GraphQLError]?
}

private struct GraphQLData: Decodable {
    let user: GraphQLUser?
}

private struct GraphQLUser: Decodable {
    let contributionsCollection: GraphQLContributionsCollection?
}

private struct GraphQLContributionsCollection: Decodable {
    let contributionCalendar: GraphQLContributionCalendar?
}

private struct GraphQLContributionCalendar: Decodable {
    let weeks: [GraphQLWeek]
}

private struct GraphQLWeek: Decodable {
    let contributionDays: [GraphQLContributionDay]
}

private struct GraphQLContributionDay: Decodable {
    let date: String
    let contributionCount: Int
}

private struct GraphQLError: Decodable {
    let message: String
}
