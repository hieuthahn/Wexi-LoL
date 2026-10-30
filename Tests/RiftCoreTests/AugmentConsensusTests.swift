import XCTest
@testable import RiftCore

final class AugmentConsensusTests: XCTestCase {
    private func record(_ provider: String, champion: Int? = 24, augment: Int, winRate: Double?, games: Int?,
                        pickRate: Double? = nil) -> AugmentStatRecord {
        AugmentStatRecord(providerID: provider, championID: champion, augmentID: augment, patch: "16.21", region: nil,
                          winRate: winRate, pickRate: pickRate, sampleSize: games, updatedAt: nil, sourceURL: nil)
    }

    /// A champion page whose sample-weighted mean win rate is `baseline`, plus the augment under test.
    private func page(_ provider: String, baseline: Double, games: Int, augment: (id: Int, winRate: Double, games: Int),
                      pickRate: Double? = nil) -> [Int: AugmentStatRecord] {
        var records: [Int: AugmentStatRecord] = [:]
        for id in 0..<AugmentConsensus.minimumRecords { records[id] = record(provider, augment: id, winRate: baseline, games: games) }
        records[augment.id] = record(provider, augment: augment.id, winRate: augment.winRate, games: augment.games, pickRate: pickRate)
        return records
    }

    private func snapshot(_ providers: [String: [Int: AugmentStatRecord]]) -> AugmentStatsSnapshot {
        AugmentStatsSnapshot(championID: 24, order: providers.keys.sorted(), providers: providers)
    }

    func testEmptySnapshotHasNoConsensus() {
        XCTAssertNil(snapshot([:]).consensus(for: 1))
    }

    func testSingleSourceKeepsItsOwnDeltaFromChampionAverage() throws {
        let result = try XCTUnwrap(snapshot(["aramhex": page("aramhex", baseline: 50, games: 100_000,
                                                             augment: (1, 56, 100_000))]).consensus(for: 1))
        XCTAssertEqual(result.delta, 6, accuracy: 0.3)
        XCTAssertEqual(result.providerIDs, ["aramhex"])
    }

    func testSourcesWithDifferentAveragesAgreeOnTheSameDelta() throws {
        let result = try XCTUnwrap(snapshot([
            "aramhex": page("aramhex", baseline: 50, games: 100_000, augment: (1, 53, 100_000)),
            "mayhemmeta": page("mayhemmeta", baseline: 54, games: 800, augment: (1, 57, 800))
        ]).consensus(for: 1))
        XCTAssertEqual(result.delta, 3, accuracy: 0.3)
        XCTAssertEqual(result.providerIDs, ["aramhex", "mayhemmeta"])
    }

    func testWinRateUsesOneChampionBaselineForEveryCard() throws {
        var aramhex = page("aramhex", baseline: 50, games: 100_000, augment: (1, 52, 100_000))
        aramhex[2] = record("aramhex", augment: 2, winRate: 51, games: 100_000)
        let snapshot = snapshot([
            "aramhex": aramhex,
            "mayhemmeta": page("mayhemmeta", baseline: 56, games: 800, augment: (1, 58, 800))
        ])
        let both = try XCTUnwrap(snapshot.consensus(for: 1))
        let aramhexOnly = try XCTUnwrap(snapshot.consensus(for: 2))
        XCTAssertEqual(both.winRate - aramhexOnly.winRate, both.delta - aramhexOnly.delta, accuracy: 0.001)
        XCTAssertGreaterThan(both.winRate, aramhexOnly.winRate)
    }

    func testDisagreeingSourcesStopTheLargestSampleFromDominating() throws {
        let result = try XCTUnwrap(snapshot([
            "aramhex": page("aramhex", baseline: 50, games: 200_000, augment: (1, 50, 200_000)),
            "mayhemmeta": page("mayhemmeta", baseline: 50, games: 1_500, augment: (1, 58, 1_500)),
            "aramgg": page("aramgg", baseline: 50, games: 1_500, augment: (1, 57, 1_500))
        ]).consensus(for: 1))
        XCTAssertGreaterThan(result.delta, 3)
    }

    func testSourcesWithoutSamplesTopListsAndGlobalStatsAreLeftOut() {
        var topOnly: [Int: AugmentStatRecord] = [:]
        for id in 1...3 { topOnly[id] = record("arammeta", augment: id, winRate: 60, games: 500) }
        let result = snapshot([
            "playaram": [1: record("playaram", augment: 1, winRate: 58, games: nil)],
            "arammeta": topOnly,
            "hexmayhem": [1: record("hexmayhem", champion: nil, augment: 1, winRate: 55, games: 90_000)]
        ]).consensus(for: 1)
        XCTAssertNil(result)
    }

    func testSourcesOnAnotherPatchAreLeftOut() throws {
        var stale = page("mayhemmeta", baseline: 50, games: 800, augment: (1, 60, 800))
        stale = stale.mapValues { AugmentStatRecord(providerID: $0.providerID, championID: $0.championID, augmentID: $0.augmentID,
                                                    patch: "16.19", region: nil, winRate: $0.winRate, pickRate: nil,
                                                    sampleSize: $0.sampleSize, updatedAt: nil, sourceURL: nil) }
        let snapshot = snapshot(["mayhemmeta": stale,
                                 "aramhex": page("aramhex", baseline: 50, games: 100_000, augment: (1, 52, 100_000))])
        XCTAssertEqual(try XCTUnwrap(snapshot.consensus(for: 1, patch: "26.21")).providerIDs, ["aramhex"])
        XCTAssertEqual(try XCTUnwrap(snapshot.consensus(for: 1)).providerIDs, ["aramhex", "mayhemmeta"])
    }

    func testTinySamplesAreIgnored() {
        let result = snapshot(["aramgg": page("aramgg", baseline: 50, games: 500,
                                              augment: (1, 90, AugmentConsensus.minimumGames - 1))]).consensus(for: 1)
        XCTAssertNil(result)
    }

    func testPickRateAveragesOnlySourcesThatReportIt() throws {
        let result = try XCTUnwrap(snapshot([
            "aramhex": page("aramhex", baseline: 50, games: 100_000, augment: (1, 53, 100_000)),
            "mayhemmeta": page("mayhemmeta", baseline: 50, games: 800, augment: (1, 53, 800), pickRate: 8)
        ]).consensus(for: 1))
        XCTAssertEqual(result.pickRate, 8)
    }

    func testThreeCardConsensusStaysUnderFiveMilliseconds() {
        var providers: [String: [Int: AugmentStatRecord]] = [:]
        for provider in ["aramgg", "aramhex", "mayhemmeta", "playaram"] {
            providers[provider] = Dictionary(uniqueKeysWithValues: (0..<200).map {
                ($0, record(provider, augment: $0, winRate: 45 + Double($0 % 10), games: 1_000 + $0))
            })
        }
        let snapshot = snapshot(providers)
        let start = Date()
        for _ in 0..<100 { _ = [1, 2, 3].map { snapshot.consensus(for: $0) } }
        XCTAssertLessThan(Date().timeIntervalSince(start) / 100, 0.005)
    }
}
