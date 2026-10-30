import XCTest
@testable import RiftCore

final class AugmentStatsSourcesTests: XCTestCase {
    private func flightPage(_ object: Any) throws -> String {
        let json = String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
        let data = try JSONSerialization.data(withJSONObject: [1, "27:" + json + "\n"])
        return "<script>self.__next_f.push(\(String(data: data, encoding: .utf8)!))</script>"
    }

    private func record(_ provider: String, champion: Int?, augment: Int, winRate: Double?) -> AugmentStatRecord {
        AugmentStatRecord(providerID: provider, championID: champion, augmentID: augment, patch: "16.21", region: nil,
                          winRate: winRate, pickRate: nil, sampleSize: nil, updatedAt: nil, sourceURL: nil)
    }

    func testMayhemMetaReadsAugmentTableAndSkipsWithheldRows() throws {
        let html = try flightPage(["defaultPatch": "16.21", "table": [
            "columnLabel": "Augment",
            "rows": [
                ["id": 2077, "games": 1519, "win_rate": "45.95", "pick_rate": "20.54", "withheld": false],
                ["id": 2157, "games": 12, "win_rate": "60.00", "pick_rate": "0.10", "withheld": true],
                ["id": 1007, "win_rate": "180", "pick_rate": "bad"]
            ]
        ]])
        let records = try MayhemMetaParser.championAugments(html, championID: 266, championKey: "aatrox")
        XCTAssertEqual(Set(records.keys), [2077])
        XCTAssertEqual(records[2077]?.winRate, 45.95)
        XCTAssertEqual(records[2077]?.pickRate, 20.54)
        XCTAssertEqual(records[2077]?.sampleSize, 1519)
        XCTAssertEqual(records[2077]?.patch, "16.21")
        XCTAssertEqual(records[2077]?.championID, 266)
    }

    func testMayhemMetaIgnoresOtherTablesAndFailsClosed() throws {
        let itemsOnly = try flightPage(["columnLabel": "Item", "rows": [["id": 3031, "win_rate": "50", "pick_rate": "9"]]])
        XCTAssertThrowsError(try MayhemMetaParser.championAugments(itemsOnly, championID: 266, championKey: "aatrox"))
        XCTAssertThrowsError(try MayhemMetaParser.championAugments("<html></html>", championID: 266, championKey: "aatrox"))
    }

    func testMayhemMetaParsesRealPageWhenFixtureProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["RIFT_MAYHEMMETA_FIXTURE"] else {
            throw XCTSkip("Set RIFT_MAYHEMMETA_FIXTURE to a saved mayhemmeta.com/champions/aatrox page")
        }
        let records = try MayhemMetaParser.championAugments(String(contentsOfFile: path), championID: 266, championKey: "aatrox")
        XCTAssertGreaterThan(records.count, 30)
        XCTAssertNotNil(records.values.first?.patch)
    }

    func testHexMayhemRecordsAreGlobal() {
        let page = MayhemAugmentStatsPage(patch: "16.21", stats: [1001: MayhemAugmentStats(id: 1001, winRate: 51, pickRate: 2, games: 900)])
        let record = HexMayhemRecords.records(from: page)[1001]
        XCTAssertNil(record?.championID)
        XCTAssertEqual(record?.winRate, 51)
        XCTAssertEqual(record?.sampleSize, 900)
    }

    func testSnapshotPrefersChampionSpecificThenGlobalWithoutMerging() {
        let snapshot = AugmentStatsSnapshot(championID: 266, order: ["aramgg", "mayhemmeta", "hexmayhem"], providers: [
            "aramgg": [1001: record("aramgg", champion: 266, augment: 1001, winRate: 46)],
            "mayhemmeta": [1001: record("mayhemmeta", champion: 266, augment: 1001, winRate: 48),
                           1002: record("mayhemmeta", champion: 266, augment: 1002, winRate: 50)],
            "hexmayhem": [1003: record("hexmayhem", champion: nil, augment: 1003, winRate: 52),
                          1001: record("hexmayhem", champion: nil, augment: 1001, winRate: 49)]
        ])
        XCTAssertEqual(snapshot.primary(for: 1001)?.providerID, "aramgg")
        XCTAssertEqual(snapshot.primary(for: 1002)?.providerID, "mayhemmeta")
        XCTAssertEqual(snapshot.primary(for: 1003)?.providerID, "hexmayhem")
        XCTAssertNil(snapshot.primary(for: 9999))
        XCTAssertEqual(snapshot.records(for: 1001).map(\.winRate), [46, 48, 49])
    }

    func testSnapshotIgnoresRecordsForAnotherChampion() {
        let snapshot = AugmentStatsSnapshot(championID: 17, order: ["aramgg"], providers: [
            "aramgg": [1001: record("aramgg", champion: 266, augment: 1001, winRate: 46)]
        ])
        XCTAssertNil(snapshot.primary(for: 1001))
    }

    func testThreeAugmentLookupStaysUnderFiveMilliseconds() {
        var providers: [String: [Int: AugmentStatRecord]] = [:]
        for provider in ["aramgg", "mayhemmeta", "hexmayhem"] {
            providers[provider] = Dictionary(uniqueKeysWithValues: (1000..<1250).map {
                ($0, record(provider, champion: provider == "hexmayhem" ? nil : 266, augment: $0, winRate: 50))
            })
        }
        let snapshot = AugmentStatsSnapshot(championID: 266, order: ["aramgg", "mayhemmeta", "hexmayhem"], providers: providers)
        let iterations = 10_000
        let start = DispatchTime.now().uptimeNanoseconds
        for index in 0..<iterations {
            for augment in [1000 + index % 250, 1100, 1200] { _ = snapshot.primary(for: augment); _ = snapshot.records(for: augment) }
        }
        let perLookupMs = Double(DispatchTime.now().uptimeNanoseconds - start) / Double(iterations) / 1_000_000
        print("Three-augment provider lookup: \(String(format: "%.4f", perLookupMs)) ms")
        XCTAssertLessThan(perLookupMs, 5)
    }
}
