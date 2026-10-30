import Foundation

/// One provider's statistics for one augment, normalized to percentages; absent values stay nil.
public struct AugmentStatRecord: Equatable, Sendable {
    public let providerID: String
    public let championID: Int?
    public let augmentID: Int
    public let patch: String?
    public let region: String?
    public let winRate: Double?
    public let pickRate: Double?
    public let sampleSize: Int?
    public let updatedAt: String?
    public let sourceURL: URL?

    public init(providerID: String, championID: Int?, augmentID: Int, patch: String?, region: String?,
                winRate: Double?, pickRate: Double?, sampleSize: Int?, updatedAt: String?, sourceURL: URL?) {
        self.providerID = providerID; self.championID = championID; self.augmentID = augmentID
        self.patch = patch; self.region = region; self.winRate = winRate; self.pickRate = pickRate
        self.sampleSize = sampleSize; self.updatedAt = updatedAt; self.sourceURL = sourceURL
    }
}

public enum AugmentStatsParseError: Error, Equatable { case unexpectedStructure }

/// Parse responses of the aramgg Data API (https://data.dtodo.cn/api/v1/en/docs/cf-data-api.md).
public enum AramggParser {
    public static let providerID = "aramgg"

    public static func dataVersion(fromConfig data: Data) throws -> String {
        guard let config = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = config["dataVersion"] as? String, !version.isEmpty else {
            throw AugmentStatsParseError.unexpectedStructure
        }
        return version
    }

    /// Parse `/data/champion-augments/{championId}.json`, a list of `[championId, statsJSON]` tuples.
    public static func championAugments(_ data: Data, championID: Int) throws -> [Int: AugmentStatRecord] {
        let tuples = try JSONSerialization.jsonObject(with: data) as? [[Any]] ?? []
        guard let tuple = tuples.first(where: { tuple in
                  tuple.count >= 2 && (tuple[0] as? String ?? (tuple[0] as? Int).map(String.init)) == String(championID)
              }),
              let statsJSON = tuple[1] as? String,
              let stats = try JSONSerialization.jsonObject(with: Data(statsJSON.utf8)) as? [String: Any],
              let augments = stats["augments"] as? [String: [String: Any]] else {
            throw AugmentStatsParseError.unexpectedStructure
        }
        let sourceURL = URL(string: "https://aramgg.com/en/champion-stats/\(championID)")
        var records: [Int: AugmentStatRecord] = [:]
        for (key, row) in augments {
            guard let augmentID = Int(key) else { continue }
            let winRate = ratio(row["win_rate"])
            let pickRate = ratio(row["pick_rate"])
            guard winRate != nil || pickRate != nil else { continue }
            records[augmentID] = AugmentStatRecord(
                providerID: providerID, championID: championID, augmentID: augmentID,
                patch: row["win_rate_game_patch"] as? String, region: row["win_rate_region"] as? String,
                winRate: winRate, pickRate: pickRate, sampleSize: integer(row["num_games"]),
                updatedAt: row["win_rate_date"] as? String, sourceURL: sourceURL
            )
        }
        guard !records.isEmpty else { throw AugmentStatsParseError.unexpectedStructure }
        return records
    }

    private static func ratio(_ value: Any?) -> Double? {
        let number = (value as? String).flatMap(Double.init) ?? (value as? NSNumber)?.doubleValue
        guard let number, (0...1).contains(number) else { return nil }
        return number * 100
    }

    private static func integer(_ value: Any?) -> Int? {
        (value as? String).flatMap(Int.init) ?? (value as? NSNumber)?.intValue
    }
}
