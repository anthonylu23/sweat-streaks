import Foundation
import SweatStreaksCore

public enum LocalActivityLogScanner {
    public static func jsonlFiles(under roots: [URL], fileManager: FileManager = .default) -> [URL] {
        var files: [URL] = []

        for root in roots {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
                continue
            }

            if !isDirectory.boolValue {
                if root.pathExtension == "jsonl" {
                    files.append(root)
                }
                continue
            }

            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsPackageDescendants]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
                files.append(fileURL)
            }
        }

        return files.sorted { $0.path < $1.path }
    }

    public static func scanActivityDays(
        files: [URL],
        range: ClosedRange<Date>,
        timeZone: TimeZone = .current
    ) throws -> Set<LocalDay> {
        let localRange = localDayRange(for: range, in: timeZone)
        var activeDays: Set<LocalDay> = []

        for file in files {
            guard let handle = try? FileHandle(forReadingFrom: file) else {
                continue
            }

            defer {
                try? handle.close()
            }

            for line in jsonLines(from: handle) {
                guard let timestamp = parseTimestamp(fromJSONLine: String(line)) else {
                    continue
                }
                guard range.contains(timestamp) else {
                    continue
                }

                let day = LocalDay.from(date: timestamp, in: timeZone)
                if day >= localRange.lowerBound && day <= localRange.upperBound {
                    activeDays.insert(day)
                }
            }
        }

        return activeDays
    }

    public static func dayStatusMap(
        activeDays: Set<LocalDay>,
        range: ClosedRange<Date>,
        timeZone: TimeZone = .current
    ) -> [LocalDay: DayStatus] {
        let localRange = localDayRange(for: range, in: timeZone)
        var days: [LocalDay: DayStatus] = [:]
        var cursor = localRange.lowerBound.date(in: timeZone) ?? range.lowerBound
        let end = localRange.upperBound.date(in: timeZone) ?? range.upperBound
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        while cursor <= end {
            let day = LocalDay.from(date: cursor, in: timeZone)
            days[day] = activeDays.contains(day) ? .active : .inactive
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? end.addingTimeInterval(1)
        }

        return days
    }

    public static func parseTimestamp(fromJSONLine line: String) -> Date? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let timestamp = object["timestamp"] as? String else {
            return nil
        }

        return parseDate(timestamp)
    }

    private static func parseDate(_ rawValue: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: rawValue) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: rawValue)
    }

    private static func localDayRange(for range: ClosedRange<Date>, in timeZone: TimeZone) -> ClosedRange<LocalDay> {
        LocalDay.from(date: range.lowerBound, in: timeZone)...LocalDay.from(date: range.upperBound, in: timeZone)
    }

    private static func jsonLines(from handle: FileHandle) -> AnySequence<String> {
        AnySequence {
            var buffer = Data()
            var isEOF = false

            return AnyIterator {
                while true {
                    if let newlineIndex = buffer.firstIndex(of: 0x0A) {
                        let lineData = buffer[..<newlineIndex]
                        buffer.removeSubrange(...newlineIndex)
                        if lineData.isEmpty {
                            continue
                        }
                        return String(data: lineData, encoding: .utf8)
                    }

                    if isEOF {
                        guard !buffer.isEmpty else { return nil }
                        defer { buffer.removeAll(keepingCapacity: false) }
                        return String(data: buffer, encoding: .utf8)
                    }

                    let chunk = (try? handle.read(upToCount: 64 * 1024)) ?? Data()
                    if chunk.isEmpty {
                        isEOF = true
                    } else {
                        buffer.append(chunk)
                    }
                }
            }
        }
    }
}
