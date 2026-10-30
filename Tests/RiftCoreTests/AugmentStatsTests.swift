import XCTest
@testable import RiftCore

final class AugmentStatsTests: XCTestCase {
    private func championAugments(_ id: Any, _ augments: [String: Any]) throws -> Data {
        let stats = String(data: try JSONSerialization.data(withJSONObject: ["augments": augments]), encoding: .utf8)!
        return try JSONSerialization.data(withJSONObject: [[id, stats]])
    }

    func testAramggChampionAugmentsConvertsRatiosAndKeepsProvenance() throws {
        let data = try championAugments("266", [
            "1001": ["tier": "2", "win_rate": "0.4656", "num_games": "4686", "pick_rate": "0.0339",
                     "win_rate_region": "WORLD", "win_rate_game_patch": "16.21", "win_rate_date": "2026-10-29"]
        ])
        let record = try XCTUnwrap(AramggParser.championAugments(data, championID: 266)[1001])
        XCTAssertEqual(record.providerID, "aramgg")
        XCTAssertEqual(record.championID, 266)
        XCTAssertEqual(record.winRate ?? 0, 46.56, accuracy: 0.0001)
        XCTAssertEqual(record.pickRate ?? 0, 3.39, accuracy: 0.0001)
        XCTAssertEqual(record.sampleSize, 4_686)
        XCTAssertEqual(record.patch, "16.21")
        XCTAssertEqual(record.region, "WORLD")
        XCTAssertEqual(record.updatedAt, "2026-10-29")
    }

    func testAramggMissingValuesStayNilAndInvalidRowsAreDropped() throws {
        let data = try championAugments("266", [
            "1002": ["pick_rate": "0.0126"],
            "1003": ["win_rate": "1.7", "pick_rate": "-1"],
            "bad": ["win_rate": "0.5"]
        ])
        let records = try AramggParser.championAugments(data, championID: 266)
        XCTAssertEqual(Set(records.keys), [1002])
        XCTAssertNil(records[1002]?.winRate)
        XCTAssertNil(records[1002]?.sampleSize)
        XCTAssertNil(records[1002]?.patch)
    }

    func testAramggRejectsWrongChampionAndChangedStructure() throws {
        let otherChampion = try championAugments("17", ["1001": ["win_rate": "0.5"]])
        XCTAssertThrowsError(try AramggParser.championAugments(otherChampion, championID: 266))
        XCTAssertThrowsError(try AramggParser.championAugments(Data(#"{"data":[]}"#.utf8), championID: 266))
        XCTAssertThrowsError(try AramggParser.championAugments(try championAugments("266", [:]), championID: 266))
    }

    func testAramggConfigDataVersion() throws {
        let config = Data(#"{"service":"aramgg-data-api","dataVersion":"16.21.4"}"#.utf8)
        XCTAssertEqual(try AramggParser.dataVersion(fromConfig: config), "16.21.4")
        XCTAssertThrowsError(try AramggParser.dataVersion(fromConfig: Data(#"{"dataVersion":""}"#.utf8)))
    }

    func testAramggParsesRealResponseWhenFixtureProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["RIFT_ARAMGG_FIXTURE"] else {
            throw XCTSkip("Set RIFT_ARAMGG_FIXTURE to a downloaded champion-augments/266.json")
        }
        let records = try AramggParser.championAugments(Data(contentsOf: URL(fileURLWithPath: path)), championID: 266)
        XCTAssertGreaterThan(records.count, 50)
        XCTAssertTrue(records.values.allSatisfy { ($0.winRate ?? 0) <= 100 && ($0.pickRate ?? 0) <= 100 })
    }
}
