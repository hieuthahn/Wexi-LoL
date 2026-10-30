import Foundation

/// Parse the champion page of https://mayhemmeta.com, whose public HTML embeds per-augment rows.
public enum MayhemMetaParser {
    public static let providerID = "mayhemmeta"

    public static func championAugments(_ html: String, championID: Int, championKey: String) throws -> [Int: AugmentStatRecord] {
        var patch: String?
        var rows: [[String: Any]] = []
        func walk(_ object: Any) {
            if let dict = object as? [String: Any] {
                if patch == nil, let value = dict["defaultPatch"] as? String,
                   value.range(of: #"^\d+\.\d+$"#, options: .regularExpression) != nil { patch = value }
                if rows.isEmpty, dict["columnLabel"] as? String == "Augment",
                   let candidates = dict["rows"] as? [[String: Any]] { rows = candidates }
                dict.values.forEach(walk)
            } else if let array = object as? [Any] {
                array.forEach(walk)
            }
        }
        NextFlight.objects(in: html).forEach(walk)
        let sourceURL = URL(string: "https://mayhemmeta.com/champions/\(championKey)")
        var records: [Int: AugmentStatRecord] = [:]
        for row in rows where row["withheld"] as? Bool != true {
            guard let augmentID = row["id"] as? Int else { continue }
            let winRate = NextFlight.percentage(row["win_rate"])
            let pickRate = NextFlight.percentage(row["pick_rate"])
            guard winRate != nil || pickRate != nil else { continue }
            records[augmentID] = AugmentStatRecord(
                providerID: providerID, championID: championID, augmentID: augmentID, patch: patch,
                region: nil, winRate: winRate, pickRate: pickRate, sampleSize: row["games"] as? Int,
                updatedAt: nil, sourceURL: sourceURL
            )
        }
        guard !records.isEmpty else { throw AugmentStatsParseError.unexpectedStructure }
        return records
    }
}

public enum HexMayhemRecords {
    public static let providerID = "hexmayhem"

    /// Convert HexMayhem's global page into records that carry no champion.
    public static func records(from page: MayhemAugmentStatsPage) -> [Int: AugmentStatRecord] {
        let sourceURL = URL(string: "https://hexmayhem.com/augments")
        return page.stats.mapValues { stats in
            AugmentStatRecord(providerID: providerID, championID: nil, augmentID: stats.id, patch: page.patch,
                              region: nil, winRate: stats.winRate, pickRate: stats.pickRate,
                              sampleSize: stats.games, updatedAt: nil, sourceURL: sourceURL)
        }
    }
}

/// Provider results for one champion, looked up by augment without merging providers.
public struct AugmentStatsSnapshot: Equatable, Sendable {
    public let championID: Int?
    public let order: [String]
    public let providers: [String: [Int: AugmentStatRecord]]

    public init(championID: Int?, order: [String], providers: [String: [Int: AugmentStatRecord]]) {
        self.championID = championID; self.order = order; self.providers = providers
    }

    /// Every provider's record for the augment, in priority order.
    public func records(for augmentID: Int) -> [AugmentStatRecord] {
        order.compactMap { providers[$0]?[augmentID] }
    }

    /// The highest-priority champion-specific record, else the highest-priority global one.
    public func primary(for augmentID: Int) -> AugmentStatRecord? {
        let records = records(for: augmentID)
        return records.first { $0.championID != nil && $0.championID == championID } ?? records.first { $0.championID == nil }
    }
}

enum NextFlight {
    static func objects(in html: String) -> [Any] {
        guard let regex = try? NSRegularExpression(pattern: #"<script[^>]*>\s*self\.__next_f\.push\((.*?)\)\s*;?\s*</script>"#,
                                                   options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = html as NSString
        var flight = ""
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            guard let array = try? JSONSerialization.jsonObject(with: Data(ns.substring(with: match.range(at: 1)).utf8)) as? [Any],
                  array.count > 1, array[0] as? Int == 1, let value = array[1] as? String else { continue }
            flight += value
        }
        return flight.split(separator: "\n").compactMap { line in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            return try? JSONSerialization.jsonObject(with: Data(line[line.index(after: colon)...].utf8), options: .fragmentsAllowed)
        }
    }

    static func percentage(_ value: Any?) -> Double? {
        let number = (value as? String).flatMap(Double.init) ?? (value as? NSNumber)?.doubleValue
        guard let number, (0...100).contains(number) else { return nil }
        return number
    }
}
