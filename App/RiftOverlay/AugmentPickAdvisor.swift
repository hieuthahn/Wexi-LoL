import AppKit
import RiftCore

/// Augments the player took this game, inferred from clicks on the card triple and correctable in the guide.
@MainActor final class AugmentPickStore: ObservableObject {
    static let shared = AugmentPickStore()

    @Published private(set) var tracker = AugmentPickTracker()
    var taken: [Int] { tracker.taken }

    func observe(cards: [RecognizedCard], guide: GuideStore, level: Int?, frame: CGRect) {
        // Tab hides the cards without a pick, so the scoreboard must not look like a choice.
        guard guide.mode == .mayhem, frame.width > 0, frame.height > 0,
              !CGEventSource.keyState(.combinedSessionState, key: 48) else { return }
        let mouse = NSEvent.mouseLocation
        let pointer = HintAnchor(x: (mouse.x - frame.minX) / frame.width, y: (mouse.y - frame.minY) / frame.height)
        var next = tracker
        next.observe(cards: cards, champion: guide.championKey, level: level, pointer: pointer, now: Date())
        if next != tracker { tracker = next }
    }

    func toggle(_ augmentID: Int) {
        if tracker.taken.contains(augmentID) { tracker.remove(augmentID) } else { tracker.add(augmentID) }
    }
}

extension AugmentStatsStore {
    private static let comboWeight = ["S+": 3, "S": 3, "A": 2, "B": 1]

    /// "Pick" or "weak" for one of the cards currently offered, judged against the other offered cards.
    func verdict(for augmentID: Int, guide: GuideStore) -> AugmentChoiceAdvice.Verdict? {
        let offered = guide.recognized.compactMap { id in guide.augments.first { $0.id == id } }
        guard offered.count >= 2, offered.contains(where: { $0.id == augmentID }) else { return nil }
        let pooled = offered.map { snapshot.consensus(for: $0.id, patch: guide.patch == "—" ? nil : guide.patch)?.delta }
        let lead = offered.map { snapshot.providers[primarySource]?[$0.id]?.winRate }
        let scores = !pooled.contains(nil) ? pooled : !lead.contains(nil) ? lead : offered.map { _ in nil }
        let candidates = zip(offered, scores).map { augment, score in
            AugmentChoiceAdvice.Candidate(id: augment.id, tier: augment.tier, score: score, synergy: synergy(for: augment.id))
        }
        return AugmentChoiceAdvice.verdicts(candidates)[augmentID]
    }

    /// Editorial combos the augment completes with augments already taken, weighted by combo tier.
    func synergy(for augmentID: Int) -> Int {
        let taken = Set(AugmentPickStore.shared.taken)
        return playaram.playstyles.flatMap(\.combos).filter { $0.augmentIDs.contains(augmentID) }.reduce(0) { total, combo in
            total + combo.augmentIDs.filter { $0 != augmentID && taken.contains($0) }.count * (Self.comboWeight[combo.tier] ?? 1)
        }
    }
}
