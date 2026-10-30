import XCTest
@testable import RiftCore

final class AugmentPicksTests: XCTestCase {
    private let triple = [RecognizedCard(id: 1, anchor: HintAnchor(x: 0.25, y: 0.6)),
                          RecognizedCard(id: 2, anchor: HintAnchor(x: 0.5, y: 0.6)),
                          RecognizedCard(id: 3, anchor: HintAnchor(x: 0.75, y: 0.6))]
    private let start = Date(timeIntervalSince1970: 1_000)

    private func pick(pointer: HintAnchor?, settle: TimeInterval = 2) -> [Int] {
        var tracker = AugmentPickTracker()
        tracker.observe(cards: triple, champion: "jax", level: 3, pointer: pointer, now: start)
        tracker.observe(cards: [], champion: "jax", level: 3, pointer: HintAnchor(x: 0.9, y: 0.1), now: start.addingTimeInterval(0.4))
        tracker.observe(cards: [], champion: "jax", level: 3, pointer: nil, now: start.addingTimeInterval(0.4 + settle))
        return tracker.taken
    }

    func testCardUnderPointerWhenTripleDisappearsIsTaken() {
        XCTAssertEqual(pick(pointer: HintAnchor(x: 0.52, y: 0.45)), [2])
    }

    func testPointerAwayFromEveryCardRecordsNothing() {
        XCTAssertEqual(pick(pointer: HintAnchor(x: 0.375, y: 0.6)), [])
        XCTAssertEqual(pick(pointer: HintAnchor(x: 0.5, y: 0.05)), [])
        XCTAssertEqual(pick(pointer: nil), [])
    }

    func testFlickerShorterThanSettleIntervalRecordsNothing() {
        var tracker = AugmentPickTracker()
        let pointer = HintAnchor(x: 0.25, y: 0.6)
        tracker.observe(cards: triple, champion: "jax", level: 3, pointer: pointer, now: start)
        tracker.observe(cards: [], champion: "jax", level: 3, pointer: pointer, now: start.addingTimeInterval(0.3))
        tracker.observe(cards: triple, champion: "jax", level: 3, pointer: pointer, now: start.addingTimeInterval(0.8))
        tracker.observe(cards: [], champion: "jax", level: 3, pointer: pointer, now: start.addingTimeInterval(1.0))
        tracker.observe(cards: [], champion: "jax", level: 3, pointer: pointer, now: start.addingTimeInterval(2.0))
        XCTAssertEqual(tracker.taken, [])
        tracker.observe(cards: [], champion: "jax", level: 3, pointer: pointer, now: start.addingTimeInterval(2.6))
        XCTAssertEqual(tracker.taken, [1])
    }

    func testPartialTripleIsNeverInferred() {
        var tracker = AugmentPickTracker()
        tracker.observe(cards: Array(triple.prefix(2)), champion: "jax", level: 3, pointer: HintAnchor(x: 0.25, y: 0.6), now: start)
        tracker.observe(cards: [], champion: "jax", level: 3, pointer: nil, now: start.addingTimeInterval(3))
        XCTAssertEqual(tracker.taken, [])
    }

    func testNewGameOrChampionClearsTakenAugments() {
        var tracker = AugmentPickTracker()
        tracker.observe(cards: [], champion: "jax", level: 12, pointer: nil, now: start)
        tracker.add(7)
        tracker.observe(cards: [], champion: "jax", level: 13, pointer: nil, now: start)
        XCTAssertEqual(tracker.taken, [7])
        tracker.observe(cards: [], champion: "jax", level: 3, pointer: nil, now: start)
        XCTAssertEqual(tracker.taken, [])
        tracker.add(7)
        tracker.observe(cards: [], champion: "ahri", level: 3, pointer: nil, now: start)
        XCTAssertEqual(tracker.taken, [])
    }

    func testManualCorrectionAddsOnceAndRemoves() {
        var tracker = AugmentPickTracker()
        tracker.add(5); tracker.add(5); tracker.add(6)
        tracker.remove(5)
        XCTAssertEqual(tracker.taken, [6])
    }

    private typealias Candidate = AugmentChoiceAdvice.Candidate

    func testSynergyBeatsRawWinRate() {
        let verdicts = AugmentChoiceAdvice.verdicts([
            Candidate(id: 1, tier: 2, score: 1, synergy: 3), Candidate(id: 2, tier: 0, score: 4, synergy: 0),
            Candidate(id: 3, tier: 1, score: 3, synergy: 0)
        ])
        XCTAssertEqual(verdicts, [1: .best])
    }

    func testCloseScoresMarkNothingBest() {
        let verdicts = AugmentChoiceAdvice.verdicts([
            Candidate(id: 1, tier: 1, score: 2.0, synergy: 0), Candidate(id: 2, tier: 1, score: 1.2, synergy: 0),
            Candidate(id: 3, tier: 1, score: -1.5, synergy: 0)
        ])
        XCTAssertEqual(verdicts, [3: .weak])
    }

    func testClearLeadAndWeakCard() {
        let verdicts = AugmentChoiceAdvice.verdicts([
            Candidate(id: 1, tier: 1, score: 5, synergy: 0), Candidate(id: 2, tier: 1, score: 2, synergy: 0),
            Candidate(id: 3, tier: 1, score: 3.5, synergy: 0)
        ])
        XCTAssertEqual(verdicts, [1: .best, 2: .weak])
    }

    func testWithoutCommonScoreFallsBackToTier() {
        let verdicts = AugmentChoiceAdvice.verdicts([
            Candidate(id: 1, tier: 0, score: 5, synergy: 0), Candidate(id: 2, tier: 1, score: nil, synergy: 0),
            Candidate(id: 3, tier: 3, score: 1, synergy: 0)
        ])
        XCTAssertEqual(verdicts, [1: .best, 3: .weak])
    }

    func testSingleCardGetsNoVerdict() {
        XCTAssertEqual(AugmentChoiceAdvice.verdicts([Candidate(id: 1, tier: 0, score: 9, synergy: 1)]), [:])
    }
}
