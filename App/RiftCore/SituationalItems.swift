import Foundation

public struct SituationalChampion: Equatable, Sendable {
    public let id: String
    public let key: String
    public let name: String
    public let attack: Double
    public let magic: Double
    public let tags: [String]
}

public struct SituationalItem: Equatable, Sendable {
    public let id: Int
    public let name: String
    public let tags: [String]
    public let totalGold: Int
    public let into: [Int]
    public let from: [Int]
    public let availableOnHowlingAbyss: Bool
    public let purchasable: Bool
}

public enum SituationalDataDragon {
    public enum ParseError: Error, Equatable {
        case invalidChampion(String)
        case invalidItem(String)
    }

    public static func champions(from data: Data) throws -> [String: SituationalChampion] {
        let document = try JSONDecoder().decode(Document<ChampionRecord>.self, from: data)
        var champions: [String: SituationalChampion] = [:]
        for (id, record) in document.data {
            guard !id.isEmpty, record.id == id, Int(record.key) != nil, !record.name.isEmpty,
                  record.info.attack.isFinite, record.info.magic.isFinite,
                  record.info.attack >= 0, record.info.magic >= 0 else {
                throw ParseError.invalidChampion(id)
            }
            champions[id] = SituationalChampion(
                id: id, key: record.key, name: record.name,
                attack: record.info.attack, magic: record.info.magic, tags: record.tags
            )
        }
        return champions
    }

    /// Skip individual odd entries (Data Dragon ships some, such as 2008), but fail when nothing usable remains.
    public static func items(from data: Data) throws -> [Int: SituationalItem] {
        let document = try JSONDecoder().decode(Document<Lenient<ItemRecord>>.self, from: data)
        var items: [Int: SituationalItem] = [:]
        for (key, wrapper) in document.data {
            guard let record = wrapper.value, let id = Int(key), id > 0, items[id] == nil,
                  !record.name.isEmpty, record.gold.total >= 0,
                  let into = try? itemIDs(record.into, key: key), let from = try? itemIDs(record.from, key: key) else { continue }
            items[id] = SituationalItem(
                id: id, name: record.name, tags: record.tags, totalGold: record.gold.total,
                into: into, from: from, availableOnHowlingAbyss: record.maps["12"] == true,
                purchasable: record.gold.purchasable
            )
        }
        guard !items.isEmpty || document.data.isEmpty else { throw ParseError.invalidItem("") }
        return items
    }

    private struct Lenient<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
    }

    private static func itemIDs(_ values: [String], key: String) throws -> [Int] {
        try values.map {
            guard let id = Int($0), id > 0 else { throw ParseError.invalidItem(key) }
            return id
        }
    }

    private struct Document<Record: Decodable>: Decodable {
        let data: [String: Record]
    }

    private struct ChampionRecord: Decodable {
        let id: String
        let key: String
        let name: String
        let tags: [String]
        let info: Info

        struct Info: Decodable {
            let attack: Double
            let magic: Double
        }
    }

    private struct ItemRecord: Decodable {
        let name: String
        let tags: [String]
        let gold: Gold
        let maps: [String: Bool]
        let into: [String]
        let from: [String]

        struct Gold: Decodable {
            let total: Int
            let purchasable: Bool

            enum CodingKeys: String, CodingKey {
                case total, purchasable
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                total = try container.decode(Int.self, forKey: .total)
                purchasable = try container.contains(.purchasable)
                    ? container.decode(Bool.self, forKey: .purchasable) : true
            }
        }

        enum CodingKeys: String, CodingKey {
            case name, tags, gold, maps, into, from
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            tags = try container.decode([String].self, forKey: .tags)
            gold = try container.decode(Gold.self, forKey: .gold)
            maps = try container.decode([String: Bool].self, forKey: .maps)
            into = try container.contains(.into) ? container.decode([String].self, forKey: .into) : []
            from = try container.contains(.from) ? container.decode([String].self, forKey: .from) : []
        }
    }
}

public struct SituationalEnemyProfile: Equatable, Sendable {
    public let enemyCount: Int
    public let physicalShare: Double
    public let magicShare: Double
    public let healingThreatCount: Int
}

public enum SituationalItemReason: String, Equatable, Sendable {
    case armor
    case magicResist
    case antiHeal
}

public struct SituationalItemSwap: Equatable, Sendable {
    public let itemToAdd: BuildItem
    public let itemToReplace: BuildItem
    public let reason: SituationalItemReason
}

public enum SituationalItems {
    public static let highDamageShare = 0.70
    public static let healingThreatThreshold = 2
    public static let damageItemNudge = 0.05
    public static let maximumDamageItemNudge = 0.15
    public static let maximumSwaps = 2
    public static let minimumCounterGold = 2000
    public static let knownHealerChampionIDs: Set<String> = [
        "Soraka", "Sona", "Nami", "Yuumi", "Milio", "Seraphine", "Taric",
        "Vladimir", "Aatrox", "Swain", "Sylas", "Warwick", "DrMundo", "Briar", "Fiddlesticks", "Illaoi"
    ]

    public static func enemyProfile(
        roster: [LiveRosterPlayer], myTeam: String?,
        champions: [String: SituationalChampion], items: [Int: SituationalItem]
    ) -> SituationalEnemyProfile {
        guard let myTeam, !myTeam.isEmpty else { return emptyProfile }
        let enemies = roster.filter { player in
            guard let team = player.team, !team.isEmpty else { return false }
            return team != myTeam
        }
        guard !enemies.isEmpty else { return emptyProfile }
        var physicalTotal = 0.0
        var healingThreatCount = 0
        for enemy in enemies {
            let champion = matchingChampion(enemy, champions: champions)
            let enemyItems = Set((enemy.items ?? []).filter { ($0.count ?? 1) > 0 }.map(\.itemID))
                .compactMap { items[$0] }
            let attack = champion?.attack ?? 0
            let magic = champion?.magic ?? 0
            let total = attack + magic
            let baseShare = total > 0 ? attack / total : 0.5
            let damageBalance = enemyItems.reduce(0) { result, item in
                result + (item.tags.contains("Damage") ? 1 : 0)
                    - (item.tags.contains("SpellDamage") ? 1 : 0)
            }
            let nudge = max(-maximumDamageItemNudge,
                            min(maximumDamageItemNudge, Double(damageBalance) * damageItemNudge))
            physicalTotal += max(0, min(1, baseShare + nudge))
            if champion.map({ knownHealerChampionIDs.contains($0.id) }) == true ||
                enemyItems.contains(where: { hasHealingTags($0.tags) }) {
                healingThreatCount += 1
            }
        }
        let physicalShare = physicalTotal / Double(enemies.count)
        return SituationalEnemyProfile(
            enemyCount: enemies.count, physicalShare: physicalShare,
            magicShare: 1 - physicalShare, healingThreatCount: healingThreatCount
        )
    }

    public static func suggestions(
        for build: ItemBuild, ownedItemIDs: [Int], profile: SituationalEnemyProfile,
        items: [Int: SituationalItem], dataDragonVersion: String
    ) -> [SituationalItemSwap] {
        guard profile.enemyCount > 0, let buildClass = buildClass(build, items: items) else { return [] }
        let owned = Set(ownedItemIDs)
        let buildIDs = Set(build.items.map(\.id))
        var reasons: [SituationalItemReason] = []
        if profile.healingThreatCount >= healingThreatThreshold { reasons.append(.antiHeal) }
        if profile.physicalShare >= highDamageShare { reasons.append(.armor) }
        if profile.magicShare >= highDamageShare { reasons.append(.magicResist) }
        let protectedCounters = Set(reasons.flatMap { reason in
            BuildClass.allCases.flatMap { counterIDs(for: reason, buildClass: $0) }
        })
        var swaps: [SituationalItemSwap] = []
        var excluded = owned.union(buildIDs)
        var replaced = Set<Int>()
        for reason in reasons {
            guard swaps.count < maximumSwaps else { break }
            let allCounters = Set(BuildClass.allCases.flatMap { counterIDs(for: reason, buildClass: $0) })
            guard allCounters.isDisjoint(with: excluded) else { continue }
            let counter = counterIDs(for: reason, buildClass: buildClass).compactMap { items[$0] }
                .first {
                    $0.availableOnHowlingAbyss && $0.purchasable &&
                        $0.totalGold >= minimumCounterGold && !excluded.contains($0.id)
                }
            guard let counter,
                  let replacedItem = build.items.reversed().first(where: {
                      !owned.contains($0.id) && !replaced.contains($0.id) &&
                          !protectedCounters.contains($0.id) &&
                          !(items[$0.id]?.tags.contains("Boots") ?? false)
                  }) else { continue }
            let itemToAdd = BuildItem(
                id: counter.id, name: counter.name,
                imageURL: "https://ddragon.leagueoflegends.com/cdn/\(dataDragonVersion)/img/item/\(counter.id).png"
            )
            swaps.append(SituationalItemSwap(itemToAdd: itemToAdd, itemToReplace: replacedItem, reason: reason))
            replaced.insert(replacedItem.id)
            excluded.insert(counter.id)
        }
        return swaps
    }

    public static func suggestions(
        from builds: [ItemBuild], ownedItemIDs: [Int], profile: SituationalEnemyProfile,
        items: [Int: SituationalItem], dataDragonVersion: String
    ) -> [SituationalItemSwap] {
        guard let build = ItemBuildRecommendation.choose(from: builds, ownedItemIDs: ownedItemIDs) else {
            return []
        }
        return suggestions(for: build, ownedItemIDs: ownedItemIDs, profile: profile,
                           items: items, dataDragonVersion: dataDragonVersion)
    }

    private enum BuildClass: CaseIterable {
        case ad, ap, tank
    }

    private static var emptyProfile: SituationalEnemyProfile {
        SituationalEnemyProfile(enemyCount: 0, physicalShare: 0.5, magicShare: 0.5, healingThreatCount: 0)
    }

    private static func matchingChampion(
        _ player: LiveRosterPlayer, champions: [String: SituationalChampion]
    ) -> SituationalChampion? {
        let prefix = "game_character_displayname_"
        let raw = player.rawChampionName ?? ""
        let identity = raw.hasPrefix(prefix) ? String(raw.dropFirst(prefix.count)) : raw
        let names = Set([identity, player.championName].filter { !$0.isEmpty }.map(normalized))
        return champions.values.sorted { $0.id < $1.id }.first {
            !names.isDisjoint(with: [$0.id, $0.key, $0.name].map(normalized))
        }
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func hasHealingTags(_ tags: [String]) -> Bool {
        tags.contains {
            ["lifesteal", "spellvamp", "omnivamp", "heal", "healing", "healthregen"]
                .contains(normalized($0))
        }
    }

    private static func buildClass(_ build: ItemBuild, items: [Int: SituationalItem]) -> BuildClass? {
        let catalogItems = build.items.compactMap { items[$0.id] }.filter { !$0.tags.contains("Boots") }
        guard !catalogItems.isEmpty else { return nil }
        let ad = catalogItems.filter { $0.tags.contains("Damage") }.count
        let ap = catalogItems.filter { $0.tags.contains("SpellDamage") }.count
        let tank = catalogItems.filter {
            !$0.tags.contains("Damage") && !$0.tags.contains("SpellDamage") &&
                $0.tags.contains { ["Health", "Armor", "SpellBlock"].contains($0) }
        }.count
        if tank > max(ad, ap) { return .tank }
        if ad > ap { return .ad }
        if ap > ad { return .ap }
        return tank > 0 ? .tank : nil
    }

    private static func counterIDs(for reason: SituationalItemReason, buildClass: BuildClass) -> [Int] {
        switch (reason, buildClass) {
        case (.armor, .ad): return [6333, 3026]
        case (.armor, .ap): return [3157]
        case (.armor, .tank): return [3143, 3075]
        case (.magicResist, .ad): return [3156]
        case (.magicResist, .ap): return [3102]
        case (.magicResist, .tank): return [4401, 3065]
        case (.antiHeal, .ad): return [3033, 6609]
        case (.antiHeal, .ap): return [3165]
        case (.antiHeal, .tank): return [3075]
        }
    }
}
