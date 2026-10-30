import Foundation

/// Parse the champion build page of https://playaram.gg, which tags each augment with its Riot ID.
public enum PlayAramParser {
    public static let providerID = "playaram"

    public static func championAugments(_ html: String, championID: Int, championKey: String) throws -> [Int: AugmentStatRecord] {
        guard html.contains("/champion/\(championID).png") else { throw AugmentStatsParseError.unexpectedStructure }
        let patch = firstMatch(#"<dt>Phiên bản</dt><dd>(\d+\.\d+)</dd>"#, in: html)
        let updatedAt = firstMatch(#"<time datetime="([^"]+)""#, in: html)
        let sourceURL = URL(string: "https://playaram.gg/tuong/\(championKey)")
        let pattern = #"data-tooltip-id="(\d+)" data-tooltip-type="augment"(?:(?!</li>).)*?cb-stats__wr">([\d.]+)%</span>"#
            + #"<span[^>]*cb-stats__pick">([\d.]+)%"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [:] }
        let ns = html as NSString
        var records: [Int: AugmentStatRecord] = [:]
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            guard let augmentID = Int(ns.substring(with: match.range(at: 1))), records[augmentID] == nil else { continue }
            let winRate = NextFlight.percentage(ns.substring(with: match.range(at: 2)))
            let pickRate = NextFlight.percentage(ns.substring(with: match.range(at: 3)))
            guard winRate != nil || pickRate != nil else { continue }
            records[augmentID] = AugmentStatRecord(
                providerID: providerID, championID: championID, augmentID: augmentID, patch: patch, region: nil,
                winRate: winRate, pickRate: pickRate, sampleSize: nil, updatedAt: updatedAt, sourceURL: sourceURL
            )
        }
        guard !records.isEmpty else { throw AugmentStatsParseError.unexpectedStructure }
        return records
    }

    private static func firstMatch(_ pattern: String, in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length)) else { return nil }
        return (html as NSString).substring(with: match.range(at: 1))
    }
}

/// An augment named by a guide site, either by Riot ID or by the site's English slug.
public enum AugmentReference: Equatable, Sendable {
    case riotID(Int)
    case slug(String)

    /// Resolve against the catalog by Riot ID or a unique exact English-name match; never fuzzy.
    public func resolve(in catalog: [AugmentRating]) -> Int? {
        switch self {
        case .riotID(let id): return catalog.contains { $0.id == id } ? id : nil
        case .slug(let slug):
            let target = Self.normalized(slug)
            let matches = catalog.filter { augment in
                [augment.name, augment.englishName ?? "",String(augment.key.dropFirst(augment.key.hasPrefix("ARAM_") ? 5 : 0))]
                    .contains { !$0.isEmpty && Self.normalized($0) == target }
            }
            return matches.count == 1 ? matches[0].id : nil
        }
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

/// Parse the "Lõi phù hợp" list on https://aram.caoviethoang.me champion pages: editorial picks, not statistics.
public enum CaoVietHoangParser {
    public static let providerID = "caoviethoang"

    public static func recommendedAugments(_ html: String) throws -> [AugmentReference] {
        guard let regex = try? NSRegularExpression(pattern: #"data-top-aug="([a-z0-9-]+)""#) else { return [] }
        let ns = html as NSString
        var references: [AugmentReference] = []
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let value = ns.substring(with: match.range(at: 1))
            let reference = value.hasPrefix("riot-") ? Int(value.dropFirst(5)).map(AugmentReference.riotID) : .slug(value)
            if let reference, !references.contains(reference) { references.append(reference) }
        }
        guard !references.isEmpty else { throw AugmentStatsParseError.unexpectedStructure }
        return references
    }
}

public enum AugmentPatch {
    /// Compare patch labels, treating year-based names (26.21) as the client version they replace (16.21).
    public static func same(_ left: String, _ right: String) -> Bool {
        guard left != right else { return true }
        let parts = [left, right].map { $0.split(separator: ".").compactMap { Int($0) } }
        guard parts.allSatisfy({ $0.count >= 2 }) else { return false }
        return parts[0][1] == parts[1][1] && abs(parts[0][0] - parts[1][0]) == 10
    }
}
