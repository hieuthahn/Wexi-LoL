import Foundation

/// Read the AramHex open dataset (https://github.com/czgreat/aramhex-data, CC BY-NC 4.0) as documented in its AGENTS.md.
public enum AramHexParser {
    public static let providerID = "aramhex"

    public struct Release: Equatable, Sendable {
        public let path: String
        public let seq: Int
        public let patch: String?
        public let snapshotAt: String?
    }

    /// Parse `latest.json`, accepting only the regular rule set and a plain relative path.
    public static func release(_ data: Data) throws -> Release {
        guard let latest = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = latest["path"] as? String,
              path.range(of: #"^patches/[0-9A-Za-z.\-]+/normal$"#, options: .regularExpression) != nil,
              let seq = latest["seq"] as? Int else { throw AugmentStatsParseError.unexpectedStructure }
        return Release(path: path, seq: seq, patch: latest["patch"] as? String, snapshotAt: latest["snapshot_at"] as? String)
    }

    /// Parse `hero_augments.json` for one champion, dropping rows the dataset marks as low sample.
    public static func championAugments(_ data: Data, championID: Int, release: Release) throws -> [Int: AugmentStatRecord] {
        guard let heroes = try JSONSerialization.jsonObject(with: data) as? [String: [String: [String: Any]]] else {
            throw AugmentStatsParseError.unexpectedStructure
        }
        guard let augments = heroes[String(championID)] else { return [:] }
        let sourceURL = URL(string: "https://github.com/czgreat/aramhex-data")
        var records: [Int: AugmentStatRecord] = [:]
        for (key, row) in augments where row["low_sample"] as? Bool != true {
            guard let augmentID = Int(key), let ratio = (row["win_rate"] as? NSNumber)?.doubleValue,
                  (0...1).contains(ratio), let games = (row["games"] as? NSNumber)?.intValue, games > 0 else { continue }
            records[augmentID] = AugmentStatRecord(
                providerID: providerID, championID: championID, augmentID: augmentID, patch: release.patch, region: "CN",
                winRate: ratio * 100, pickRate: nil, sampleSize: games, updatedAt: release.snapshotAt, sourceURL: sourceURL
            )
        }
        return records
    }
}

/// Read arammeta's public tier-list payload (https://arammeta.com/api/tier-list.json); it lists only top augments per rarity.
public enum AramMetaParser {
    public static let providerID = "arammeta"

    public static func championAugments(_ data: Data, championID: Int) throws -> [Int: AugmentStatRecord] {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let champions = payload["champs"] as? [String: [String: Any]] else {
            throw AugmentStatsParseError.unexpectedStructure
        }
        guard let top = champions[String(championID)]?["top"] as? [String: [[String: Any]]] else { return [:] }
        let patch = payload["patch_prefix"] as? String
        let sourceURL = URL(string: "https://arammeta.com/")
        var records: [Int: AugmentStatRecord] = [:]
        for row in top.values.joined() {
            guard let augmentID = row["id"] as? Int else { continue }
            let winRate = (row["wr"] as? NSNumber).map { $0.doubleValue * 100 }.flatMap { (0...100).contains($0) ? $0 : nil }
            let pickRate = (row["pick"] as? NSNumber).map { $0.doubleValue * 100 }.flatMap { (0...100).contains($0) ? $0 : nil }
            guard winRate != nil || pickRate != nil else { continue }
            records[augmentID] = AugmentStatRecord(
                providerID: providerID, championID: championID, augmentID: augmentID, patch: patch, region: "TW",
                winRate: winRate, pickRate: pickRate, sampleSize: (row["g"] as? NSNumber)?.intValue,
                updatedAt: nil, sourceURL: sourceURL
            )
        }
        return records
    }
}
