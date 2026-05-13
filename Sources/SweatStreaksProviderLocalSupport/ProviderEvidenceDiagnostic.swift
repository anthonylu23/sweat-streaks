import Foundation
import SweatStreaksCore

public struct ProviderEvidenceDiagnostic: Equatable, Sendable {
    public let source: ActivitySource
    public let items: [ProviderEvidenceItem]

    public init(source: ActivitySource, items: [ProviderEvidenceItem]) {
        self.source = source
        self.items = items
    }

    public var totalEvidenceCount: Int {
        items.reduce(0) { $0 + $1.evidenceCount }
    }

    public var latestEvidenceDay: LocalDay? {
        items.compactMap(\.latestEvidenceDay).max()
    }
}

public struct ProviderEvidenceItem: Equatable, Sendable {
    public let rootLabel: String
    public let evidenceType: String
    public let rootPath: String
    public let rootExists: Bool
    public let evidenceCount: Int
    public let latestEvidenceDay: LocalDay?

    public init(
        rootLabel: String,
        evidenceType: String,
        rootPath: String,
        rootExists: Bool,
        evidenceCount: Int,
        latestEvidenceDay: LocalDay?
    ) {
        self.rootLabel = rootLabel
        self.evidenceType = evidenceType
        self.rootPath = rootPath
        self.rootExists = rootExists
        self.evidenceCount = evidenceCount
        self.latestEvidenceDay = latestEvidenceDay
    }
}
