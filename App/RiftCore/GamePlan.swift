import Foundation

/// A model's plan for one game, already restricted to the augment and item IDs the app offered it.
public struct GamePlan: Equatable, Sendable {
    public struct Boost: Equatable, Sendable {
        public let value: Int
        public let reason: String
    }

    public struct ItemSwap: Equatable, Sendable {
        public let add: Int
        public let replace: Int
        public let reason: String
    }

    public static let maxBoost = 3
    public static let maxSwaps = 2

    public let boosts: [Int: Boost]
    public let itemSwaps: [ItemSwap]
    public let notes: [String]

    /// Decode the model's JSON, dropping unknown IDs, clamping boosts and keeping at most `maxSwaps` swaps.
    public static func decode(_ data: Data, augmentIDs: Set<Int>, buildItemIDs: Set<Int>, counterItemIDs: Set<Int>) throws -> GamePlan {
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        var boosts: [Int: Boost] = [:]
        for row in raw.augmentPriorities where augmentIDs.contains(row.id) && boosts[row.id] == nil {
            boosts[row.id] = Boost(value: min(max(row.boost, -maxBoost), maxBoost), reason: row.reason)
        }
        var swaps: [ItemSwap] = []
        for swap in raw.itemSwaps where counterItemIDs.contains(swap.add) && buildItemIDs.contains(swap.replace)
            && !swaps.contains(where: { $0.add == swap.add || $0.replace == swap.replace }) && swaps.count < maxSwaps {
            swaps.append(ItemSwap(add: swap.add, replace: swap.replace, reason: swap.reason))
        }
        return GamePlan(boosts: boosts, itemSwaps: swaps, notes: Array(raw.notes.prefix(3)))
    }

    /// The JSON Schema both CLIs enforce on the reply.
    public static let schema = """
    {"type":"object","additionalProperties":false,"required":["augmentPriorities","itemSwaps","notes"],"properties":{
    "augmentPriorities":{"type":"array","maxItems":16,"items":{"type":"object","additionalProperties":false,
    "required":["id","boost","reason"],"properties":{"id":{"type":"integer"},"boost":{"type":"integer","minimum":-3,"maximum":3},
    "reason":{"type":"string","maxLength":120}}}},
    "itemSwaps":{"type":"array","maxItems":2,"items":{"type":"object","additionalProperties":false,"required":["add","replace","reason"],
    "properties":{"add":{"type":"integer"},"replace":{"type":"integer"},"reason":{"type":"string","maxLength":120}}}},
    "notes":{"type":"array","maxItems":3,"items":{"type":"string","maxLength":140}}}}
    """

    private struct Raw: Decodable {
        struct Priority: Decodable { let id: Int; let boost: Int; let reason: String }
        struct Swap: Decodable { let add: Int; let replace: Int; let reason: String }
        let augmentPriorities: [Priority]
        let itemSwaps: [Swap]
        let notes: [String]
    }
}

/// Everything a model needs to plan one game; names only, never player identities.
public struct GamePlanRequest: Equatable, Sendable {
    public struct Augment: Equatable, Sendable {
        public let id: Int
        public let name: String
        public let delta: Double?
        public let combos: [String]

        public init(id: Int, name: String, delta: Double?, combos: [String]) {
            self.id = id; self.name = name; self.delta = delta; self.combos = combos
        }
    }

    public struct Item: Equatable, Sendable {
        public let id: Int
        public let name: String
        public let role: String

        public init(id: Int, name: String, role: String = "") { self.id = id; self.name = name; self.role = role }
    }

    public let champion: String
    public let allies: [String]
    public let enemies: [String]
    public let taken: [String]
    public let augments: [Augment]
    public let build: [Item]
    public let counters: [Item]
    public let language: String

    public init(champion: String, allies: [String], enemies: [String], taken: [String], augments: [Augment],
                build: [Item], counters: [Item], language: String) {
        self.champion = champion; self.allies = allies; self.enemies = enemies; self.taken = taken
        self.augments = augments; self.build = build; self.counters = counters; self.language = language
    }

    /// Identical inputs give identical prompts, so the store can skip a call whose answer it already has.
    public var prompt: String {
        var lines = [
            "Plan one ARAM Mayhem game. Use only the IDs listed below. Write reason and notes in \(language).",
            "Allies and enemies are separate teams; never treat an ally as an enemy.",
            "Player: \(champion). Allies: \(allies.joined(separator: ", ")). Enemies: \(enemies.joined(separator: ", ")).",
            "Augments already taken: \(taken.isEmpty ? "none" : taken.joined(separator: ", ")).",
            "Augments (id name | win-rate delta vs the champion average | editor combos):"
        ]
        lines += augments.map { augment in
            let delta = augment.delta.map { String(format: "%+.1f", $0) } ?? "?"
            return "\(augment.id) \(augment.name) | \(delta) | \(augment.combos.isEmpty ? "-" : augment.combos.joined(separator: "; "))"
        }
        if !build.isEmpty {
            lines.append("Most played build: " + build.map { "\($0.id) \($0.name)" }.joined(separator: ", "))
            lines.append("Counter items (id name role): " + counters.map { "\($0.id) \($0.name) \($0.role)" }.joined(separator: ", "))
        }
        lines.append("Give augments a boost from -3 to 3 for this matchup and the taken augments; leave neutral ones out.")
        lines.append("Suggest at most 2 item swaps, each replacing one build item with one counter item, only when the enemy team calls for it.")
        return lines.joined(separator: "\n")
    }
}
