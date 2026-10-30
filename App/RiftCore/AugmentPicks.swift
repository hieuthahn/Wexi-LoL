import Foundation

/// Infer which augment the player took: when a confirmed triple disappears for good, the card under the pointer wins.
public struct AugmentPickTracker: Equatable, Sendable {
    public static let settleInterval: TimeInterval = 1.5
    public static let maxHorizontalReach = 0.12
    public static let maxVerticalReach = 0.35

    public private(set) var taken: [Int] = []
    private var champion: String?
    private var level = 0
    private var visible: [RecognizedCard] = []
    private var pointer: HintAnchor?
    private var pending: (cards: [RecognizedCard], pointer: HintAnchor?, since: Date)?

    public init() {}

    /// Feed every overlay refresh; `pointer` is the mouse position normalized to the game frame like card anchors.
    public mutating func observe(cards: [RecognizedCard], champion: String, level: Int?, pointer: HintAnchor?, now: Date) {
        if champion != self.champion || (level ?? self.level) < self.level { self = AugmentPickTracker(); self.champion = champion }
        self.level = level ?? self.level
        if !cards.isEmpty {
            pending = nil
            visible = cards
            if cards.count == 3 { self.pointer = pointer }
            return
        }
        if pending == nil, visible.count == 3 { pending = (visible, self.pointer, now) }
        visible = []
        guard let waiting = pending, now.timeIntervalSince(waiting.since) >= Self.settleInterval else { return }
        pending = nil
        if let pick = Self.card(under: waiting.pointer, in: waiting.cards) { add(pick) }
    }

    public mutating func add(_ augmentID: Int) {
        if !taken.contains(augmentID) { taken.append(augmentID) }
    }

    public mutating func remove(_ augmentID: Int) {
        taken.removeAll { $0 == augmentID }
    }

    static func card(under pointer: HintAnchor?, in cards: [RecognizedCard]) -> Int? {
        guard let pointer, let nearest = cards.min(by: { abs($0.anchor.x - pointer.x) < abs($1.anchor.x - pointer.x) }),
              abs(nearest.anchor.x - pointer.x) <= maxHorizontalReach,
              abs(nearest.anchor.y - pointer.y) <= maxVerticalReach else { return nil }
        return nearest.id
    }

    public static func == (lhs: AugmentPickTracker, rhs: AugmentPickTracker) -> Bool {
        lhs.taken == rhs.taken && lhs.champion == rhs.champion && lhs.level == rhs.level && lhs.visible == rhs.visible
            && lhs.pointer == rhs.pointer && lhs.pending?.cards == rhs.pending?.cards && lhs.pending?.since == rhs.pending?.since
    }
}

/// Mark the clearly best and clearly weak cards of one augment choice; never pick when the evidence is close.
public enum AugmentChoiceAdvice {
    public static let bestMargin = 1.5
    public static let weakMargin = 3.0

    public enum Verdict: Equatable, Sendable { case best, weak }

    public struct Candidate: Equatable, Sendable {
        public let id: Int
        /// Upstream tier, 0 best.
        public let tier: Int
        /// A win-rate measure comparable across the offered cards, or nil when they lack a common source.
        public let score: Double?
        /// Weighted count of editorial combos this card completes with augments already taken.
        public let synergy: Int

        public init(id: Int, tier: Int, score: Double?, synergy: Int) {
            self.id = id; self.tier = tier; self.score = score; self.synergy = synergy
        }
    }

    public static func verdicts(_ candidates: [Candidate]) -> [Int: Verdict] {
        guard candidates.count >= 2 else { return [:] }
        let scored = candidates.allSatisfy { $0.score != nil }
        let ranked = candidates.sorted { lhs, rhs in
            if lhs.synergy != rhs.synergy { return lhs.synergy > rhs.synergy }
            if scored, lhs.score != rhs.score { return lhs.score! > rhs.score! }
            return lhs.tier < rhs.tier
        }
        let best = ranked[0], runnerUp = ranked[1]
        var result: [Int: Verdict] = [:]
        let clearlyBest = best.synergy > runnerUp.synergy
            || (best.synergy == runnerUp.synergy && (scored ? best.score! - runnerUp.score! >= bestMargin : best.tier < runnerUp.tier))
        if clearlyBest { result[best.id] = .best }
        for card in ranked.dropFirst() where card.synergy == 0 {
            let weak = scored ? best.score! - card.score! >= weakMargin : card.tier >= best.tier + 2
            if weak { result[card.id] = .weak }
        }
        return result
    }
}
