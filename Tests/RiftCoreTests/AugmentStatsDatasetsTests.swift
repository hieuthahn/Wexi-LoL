import XCTest
@testable import RiftCore

final class AugmentStatsDatasetsTests: XCTestCase {
    private let release = AramHexParser.Release(path: "patches/16.21/normal", seq: 10, patch: "16.21",
                                                snapshotAt: "2026-10-28T12:28:35+08:00")

    private func json(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object) }

    func testAramHexReleaseAcceptsOnlyRegularRelativePaths() throws {
        let latest = try json(["path": "patches/16.21/normal", "seq": 10, "patch": "16.21", "snapshot_at": "2026-10-28"])
        XCTAssertEqual(try AramHexParser.release(latest).path, "patches/16.21/normal")
        XCTAssertThrowsError(try AramHexParser.release(try json(["path": "patches/16.19/first-prismatic", "seq": 3])))
        XCTAssertThrowsError(try AramHexParser.release(try json(["path": "../../etc/normal", "seq": 3])))
    }

    func testAramHexKeepsSampleSizeAndDropsLowSampleRows() throws {
        let data = try json(["24": [
            "1002": ["games": 4619, "wins": 2109, "win_rate": 0.456592, "low_sample": false],
            "1003": ["games": 120, "wins": 90, "win_rate": 0.75, "low_sample": true],
            "1004": ["games": 0, "wins": 0, "win_rate": 0.5, "low_sample": false]
        ]])
        let records = try AramHexParser.championAugments(data, championID: 24, release: release)
        XCTAssertEqual(Set(records.keys), [1002])
        XCTAssertEqual(records[1002]?.winRate ?? 0, 45.6592, accuracy: 0.0001)
        XCTAssertEqual(records[1002]?.sampleSize, 4619)
        XCTAssertNil(records[1002]?.pickRate)
        XCTAssertEqual(records[1002]?.region, "CN")
        XCTAssertTrue(try AramHexParser.championAugments(data, championID: 17, release: release).isEmpty)
    }

    func testAramHexParsesRealDatasetWhenFixtureProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["RIFT_ARAMHEX_FIXTURE"] else {
            throw XCTSkip("Set RIFT_ARAMHEX_FIXTURE to a downloaded hero_augments.json")
        }
        let records = try AramHexParser.championAugments(Data(contentsOf: URL(fileURLWithPath: path)), championID: 24, release: release)
        XCTAssertGreaterThan(records.count, 30)
        XCTAssertTrue(records.values.allSatisfy { ($0.sampleSize ?? 0) > 0 })
    }

    func testAramMetaReadsTopAugmentsAcrossRarities() throws {
        let data = try json(["patch_prefix": "16.21", "champs": ["157": ["top": [
            "kPrismatic": [["id": 1058, "g": 8603, "wr": 0.6468, "pick": 0.1601]],
            "kGold": [["id": 3078, "g": 8631, "wr": 1.7, "pick": 0.0801]]
        ]]]])
        let records = try AramMetaParser.championAugments(data, championID: 157)
        XCTAssertEqual(records[1058]?.winRate ?? 0, 64.68, accuracy: 0.0001)
        XCTAssertEqual(records[1058]?.pickRate ?? 0, 16.01, accuracy: 0.0001)
        XCTAssertEqual(records[1058]?.sampleSize, 8603)
        XCTAssertEqual(records[1058]?.region, "TW")
        XCTAssertNil(records[3078]?.winRate)
        XCTAssertTrue(try AramMetaParser.championAugments(data, championID: 24).isEmpty)
        XCTAssertThrowsError(try AramMetaParser.championAugments(try json(["data": []]), championID: 157))
    }
}
