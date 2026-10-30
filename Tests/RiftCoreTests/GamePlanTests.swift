import XCTest
@testable import RiftCore

final class GamePlanTests: XCTestCase {
    private func decode(_ json: String) throws -> GamePlan {
        try GamePlan.decode(Data(json.utf8), augmentIDs: [1, 2], buildItemIDs: [3047, 3053], counterItemIDs: [3111, 3033])
    }

    func testUnknownIDsAreDroppedAndBoostsClamped() throws {
        let plan = try decode("""
        {"augmentPriorities":[{"id":1,"boost":9,"reason":"a"},{"id":99,"boost":2,"reason":"x"},{"id":1,"boost":-1,"reason":"dup"},
        {"id":2,"boost":-7,"reason":"b"}],
        "itemSwaps":[{"add":3111,"replace":3047,"reason":"mr"},{"add":9999,"replace":3053,"reason":"fake"},
        {"add":3033,"replace":3999,"reason":"not in build"},{"add":3033,"replace":3047,"reason":"same slot"},
        {"add":3033,"replace":3053,"reason":"heal"}],
        "notes":["1","2","3","4"]}
        """)
        XCTAssertEqual(plan.boosts, [1: .init(value: 3, reason: "a"), 2: .init(value: -3, reason: "b")])
        XCTAssertEqual(plan.itemSwaps, [.init(add: 3111, replace: 3047, reason: "mr"), .init(add: 3033, replace: 3053, reason: "heal")])
        XCTAssertEqual(plan.notes, ["1", "2", "3"])
    }

    func testMalformedReplyThrows() {
        XCTAssertThrowsError(try decode(#"{"augmentPriorities":"oops"}"#))
        XCTAssertThrowsError(try decode("not json"))
    }

    func testEmptyPlanIsValid() throws {
        let plan = try decode(#"{"augmentPriorities":[],"itemSwaps":[],"notes":[]}"#)
        XCTAssertEqual(plan, GamePlan(boosts: [:], itemSwaps: [], notes: []))
    }

    func testSchemaIsValidJSON() throws {
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(GamePlan.schema.utf8)))
    }

    func testPromptSeparatesTeamsAndListsOnlyGivenIDs() {
        let request = GamePlanRequest(
            champion: "Jax", allies: ["Brand"], enemies: ["Soraka"], taken: ["Thức Tỉnh Tối Thượng"],
            augments: [.init(id: 2141, name: "Siêu Mãng Xà", delta: 5.6, combos: ["A with 1349"]),
                       .init(id: 1029, name: "Vũ Khí Siêu Nhiên", delta: nil, combos: [])],
            build: [.init(id: 3047, name: "Giày Thép Gai")], counters: [.init(id: 3111, name: "Giày Thủy Ngân", role: "MR")],
            language: "Vietnamese"
        )
        let prompt = request.prompt
        XCTAssertTrue(prompt.contains("Allies: Brand. Enemies: Soraka."))
        XCTAssertTrue(prompt.contains("2141 Siêu Mãng Xà | +5.6 | A with 1349"))
        XCTAssertTrue(prompt.contains("1029 Vũ Khí Siêu Nhiên | ? | -"))
        XCTAssertTrue(prompt.contains("3111 Giày Thủy Ngân MR"))
        XCTAssertTrue(prompt.contains("Augments already taken: Thức Tỉnh Tối Thượng."))
    }
}
