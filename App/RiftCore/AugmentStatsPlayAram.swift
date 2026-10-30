import Foundation

/// An editorial playstyle from a playaram.gg champion page; its tier is the editor's rating, not a win rate.
public struct PlayAramPlaystyle: Equatable, Sendable {
    public struct Combo: Equatable, Sendable {
        public let tier: String
        public let name: String
        public let augmentIDs: [Int]
        /// Augment names as the page labels them, aligned with `augmentIDs`.
        public let augmentNames: [String]
        public let text: String
    }

    public struct Tip: Equatable, Sendable {
        public let title: String
        public let text: String
    }

    public let tier: String
    public let title: String
    public let summary: String
    public let combos: [Combo]
    public let items: [String]
    public let tips: [Tip]
}

/// playaram.gg's global augment tier list entry.
public struct PlayAramTier: Equatable, Sendable {
    public let augmentID: Int
    public let tier: String
    public let rarity: String
    public let categories: [String]
    public let winRate: Double?
    public let pickRate: Double?
}

/// A biggest win-rate move against the previous patch, for one augment or one champion and augment pair.
public struct PlayAramPatchChange: Equatable, Sendable {
    public let augmentID: Int
    public let championKey: String?
    public let winRate: Double?
    /// Signed change in percentage points.
    public let delta: Double
    public let games: Int?
}

/// Everything the playaram.gg pages add beyond per-champion augment rates.
public struct PlayAramGuide: Equatable, Sendable {
    public var playstyles: [PlayAramPlaystyle]
    public var tiers: [Int: PlayAramTier]
    public var changes: [PlayAramPatchChange]

    public init(playstyles: [PlayAramPlaystyle] = [], tiers: [Int: PlayAramTier] = [:], changes: [PlayAramPatchChange] = []) {
        self.playstyles = playstyles; self.tiers = tiers; self.changes = changes
    }
}

extension PlayAramParser {
    /// Parse the "Lối chơi & combo lõi" tabs of a champion page.
    public static func playstyles(_ html: String) -> [PlayAramPlaystyle] {
        let starts = HTMLScan.ranges(of: #"id="playstyle-panel-\d+""#, in: html)
        return starts.enumerated().compactMap { index, start in
            let tail = html[start.upperBound...]
            let end = [index + 1 < starts.count ? starts[index + 1].lowerBound : nil, tail.range(of: "<h2")?.lowerBound]
                .compactMap { $0 }.min() ?? html.endIndex
            let panel = String(html[start.lowerBound..<end])
            guard let title = HTMLScan.first(#"bt-panel__name">(.*?)</h3>"#, in: panel).map(HTMLScan.text) else { return nil }
            let combos = HTMLScan.all(#"<li class="ps-combo[^"]*">(.*?)</li>"#, in: panel).compactMap(combo)
            guard !combos.isEmpty else { return nil }
            let items = HTMLScan.first(#"ps-items">(.*?)</ul>"#, in: panel)
                .map { HTMLScan.all(#"bt-slot__name">([^<]+)<"#, in: $0).map(HTMLScan.text) } ?? []
            let tips = HTMLScan.first(#"ps-tips">(.*?)</ul>"#, in: panel).map { list in
                HTMLScan.all(#"<li class="ps-tip">(.*?)</li>"#, in: list).compactMap { tip -> PlayAramPlaystyle.Tip? in
                    guard let title = HTMLScan.first(#"ps-tip__title">(.*?)</p>"#, in: tip) else { return nil }
                    return .init(title: HTMLScan.text(title),
                                 text: HTMLScan.first(#"ps-text">(.*?)</div>"#, in: tip).map(HTMLScan.text) ?? "")
                }
            } ?? []
            let tab = HTMLScan.first(#"id="playstyle-tab-\#(index)"(.*?)</button>"#, in: html)
            return PlayAramPlaystyle(
                tier: tab.flatMap { HTMLScan.first(#"cb-tier[^"]*">([^<]+)<"#, in: $0) } ?? combos[0].tier,
                title: HTMLScan.text(title),
                summary: HTMLScan.first(#"bt-panel__sub">(.*?)</div>"#, in: panel).map(HTMLScan.text) ?? "",
                combos: combos, items: items, tips: tips
            )
        }
    }

    private static func combo(_ markup: String) -> PlayAramPlaystyle.Combo? {
        guard let icons = HTMLScan.first(#"ps-combo__icons">(.*?)<span class="cb-tier"#, in: markup),
              let tier = HTMLScan.first(#"cb-tier[^"]*">([^<]+)<"#, in: markup) else { return nil }
        let augments = HTMLScan.groups(#"<img[^>]*alt="([^"]*)"[^>]*data-tooltip-id="(\d+)" data-tooltip-type="augment""#, in: icons)
        guard augments.count >= 2 else { return nil }
        return .init(tier: tier, name: HTMLScan.first(#"ps-combo__name">(.*?)</p>"#, in: markup).map(HTMLScan.text) ?? "",
                     augmentIDs: augments.compactMap { Int($0[1]) }, augmentNames: augments.map { HTMLScan.text($0[0]) },
                     text: HTMLScan.first(#"ps-text">(.*?)</div>"#, in: markup).map(HTMLScan.text) ?? "")
    }

    /// Parse https://playaram.gg/loi-aram-hon-loan, where each band heading (S+ to D) precedes its augment cards.
    public static func tierList(_ html: String) throws -> [Int: PlayAramTier] {
        let bands = HTMLScan.matches(#"class="sp__band[^"]*"><span[^>]*>([^<]+)</span>"#, in: html)
        var tiers: [Int: PlayAramTier] = [:]
        let card = #"<li data-core-name="[^"]*" data-core-rarity="(\w+)" data-core-cats="([^"]*)" data-tooltip-id="(\d+)""#
            + #" data-tooltip-type="augment".*?core-card__wr">([\d.]+)%</span><span[^>]*core-card__pick">([\d.]+)%"#
        for match in HTMLScan.matches(card, in: html) {
            guard let band = bands.last(where: { $0.range.lowerBound < match.range.lowerBound }),
                  let augmentID = Int(match.groups[2]) else { continue }
            tiers[augmentID] = PlayAramTier(augmentID: augmentID, tier: band.groups[0], rarity: match.groups[0],
                                            categories: match.groups[1].split(separator: " ").map(String.init),
                                            winRate: Double(match.groups[3]), pickRate: Double(match.groups[4]))
        }
        guard !tiers.isEmpty else { throw AugmentStatsParseError.unexpectedStructure }
        return tiers
    }

    /// Parse the augment rows of https://playaram.gg/thay-doi-phien-ban; champion rows link to `/tuong/<slug>`.
    public static func patchChanges(_ html: String) throws -> [PlayAramPatchChange] {
        let changes = HTMLScan.all(#"<li class="pc-row">(.*?)</li>"#, in: html).compactMap { row -> PlayAramPatchChange? in
            guard let augmentID = HTMLScan.first(#"data-tooltip-id="(\d+)" data-tooltip-type="augment""#, in: row).flatMap({ Int($0) }),
                  let delta = HTMLScan.groups(#"pc-row__delta pc--(up|down)">(?:<span[^>]*>[^<]*</span>)*([\d.]+)"#, in: row).first,
                  let magnitude = Double(delta[1]) else { return nil }
            return PlayAramPatchChange(
                augmentID: augmentID, championKey: HTMLScan.first(#"href="/tuong/([a-z0-9]+)""#, in: row),
                winRate: HTMLScan.first(#"pc-row__wr">([\d.]+)%"#, in: row).flatMap { Double($0) },
                delta: delta[0] == "down" ? -magnitude : magnitude,
                games: HTMLScan.first(#"pc-row__meta">([\d.,]+)"#, in: row).flatMap { Int($0.filter(\.isNumber)) }
            )
        }
        guard !changes.isEmpty else { throw AugmentStatsParseError.unexpectedStructure }
        return changes
    }
}

enum HTMLScan {
    struct Match { let range: Range<String.Index>; let groups: [String] }

    static func matches(_ pattern: String, in text: String) -> [Match] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { result in
            guard let range = Range(result.range, in: text) else { return nil }
            let groups = (1..<result.numberOfRanges).map { Range(result.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
            return Match(range: range, groups: groups)
        }
    }

    static func ranges(of pattern: String, in text: String) -> [Range<String.Index>] { matches(pattern, in: text).map(\.range) }
    static func groups(_ pattern: String, in text: String) -> [[String]] { matches(pattern, in: text).map(\.groups) }
    static func all(_ pattern: String, in text: String) -> [String] { matches(pattern, in: text).compactMap(\.groups.first) }
    static func first(_ pattern: String, in text: String) -> String? { matches(pattern, in: text).first?.groups.first }

    /// Strip tags, decode common entities and collapse whitespace.
    static func text(_ markup: String) -> String {
        var text = markup.replacingOccurrences(of: #"<kbd[^>]*>([^<]*)</kbd>"#, with: " ($1)", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (entity, value) in [("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&lt;", "<"), ("&gt;", ">"),
                                ("&nbsp;", " "), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
