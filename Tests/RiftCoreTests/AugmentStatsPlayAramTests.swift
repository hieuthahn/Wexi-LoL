import XCTest
@testable import RiftCore

final class AugmentStatsPlayAramTests: XCTestCase {
    private let playstylePage = """
    <button type="button" role="tab" id="playstyle-tab-0" class="bt-tab"><span class="cb-tier cb-tier--a">A</span></button>
    <div role="tabpanel" id="playstyle-panel-0" class="bt-panel"><h3 class="bt-panel__name">Jax Tank &amp; R</h3>
    <div class="bt-panel__sub"><p><strong>Bậc Thầy Vũ Khí</strong><kbd class="ps-key">R</kbd> resets.</p></div>
    <ul class="ps-combos"><li class="ps-combo ps-tier--s"><div class="ps-combo__head"><span class="ps-combo__icons">
    <img src="a.png" alt="Trái Tim Sắt Đá" data-tooltip-id="1152" data-tooltip-type="augment" class="x" /><span class="ps-plus">+</span>
    <img src="b.png" alt="Thức Tỉnh Tối Thượng" data-tooltip-id="1349" data-tooltip-type="augment" class="x" /></span>
    <span class="cb-tier cb-tier--s">S</span></div><p class="ps-combo__name">Trái Tim Sắt Đá + Thức Tỉnh Tối Thượng</p>
    <div class="ps-text"><p>Tank up.</p></div></li></ul>
    <ul aria-label="Đồ khuyên dùng" class="bt-strip ps-items"><li class="bt-slot"><span class="bt-slot__name">Trái Tim Khổng Thần</span></li></ul>
    <ul class="ps-tips"><li class="ps-tip"><p class="ps-tip__title">Vào giao tranh sớm</p><div class="ps-text"><p>Stack it.</p></div></li></ul></div>
    <h2>Trang bị khác</h2><li class="ps-combo ps-tier--s">outside</li>
    """

    func testPlaystylesKeepEditorTierCombosItemsAndTips() throws {
        let style = try XCTUnwrap(PlayAramParser.playstyles(playstylePage).first)
        XCTAssertEqual(style.tier, "A")
        XCTAssertEqual(style.title, "Jax Tank & R")
        XCTAssertEqual(style.summary, "Bậc Thầy Vũ Khí (R) resets.")
        XCTAssertEqual(style.combos, [.init(tier: "S", name: "Trái Tim Sắt Đá + Thức Tỉnh Tối Thượng", augmentIDs: [1152, 1349],
                                           augmentNames: ["Trái Tim Sắt Đá", "Thức Tỉnh Tối Thượng"], text: "Tank up.")])
        XCTAssertEqual(style.items, ["Trái Tim Khổng Thần"])
        XCTAssertEqual(style.tips, [.init(title: "Vào giao tranh sớm", text: "Stack it.")])
    }

    func testPageWithoutPlaystylesYieldsNone() {
        XCTAssertEqual(PlayAramParser.playstyles("<h2>Build</h2>"), [])
    }

    func testTierListAssignsEachCardItsBand() throws {
        let html = """
        <h2 aria-label="Bậc S+" class="sp__band sp--splus"><span aria-hidden="true" class="sp__band-badge">S+</span></h2>
        <li data-core-name="a" data-core-rarity="prismatic" data-core-cats="ad amp" data-tooltip-id="1134" data-tooltip-type="augment" class="c">
        <span title="Tỉ lệ thắng" class="sp-stat core-card__wr">57.39%</span><span title="Tỉ lệ chọn" class="sp-stat core-card__pick">2.1%</span></li>
        <h2 aria-label="Bậc D" class="sp__band sp--d"><span aria-hidden="true" class="sp__band-badge">D</span></h2>
        <li data-core-name="b" data-core-rarity="silver" data-core-cats="" data-tooltip-id="2001" data-tooltip-type="augment" class="c">
        <span class="sp-stat core-card__wr">44.00%</span><span class="sp-stat core-card__pick">0.5%</span></li>
        """
        let tiers = try PlayAramParser.tierList(html)
        XCTAssertEqual(tiers[1134], PlayAramTier(augmentID: 1134, tier: "S+", rarity: "prismatic", categories: ["ad", "amp"],
                                                 winRate: 57.39, pickRate: 2.1))
        XCTAssertEqual(tiers[2001]?.tier, "D")
        XCTAssertEqual(tiers[2001]?.categories, [])
        XCTAssertThrowsError(try PlayAramParser.tierList("<html></html>"))
    }

    func testPatchChangesKeepSignAndChampionAndSkipItems() throws {
        let row = { (link: String, type: String, direction: String) in
            """
            <li class="pc-row"><span class="pc-row__icons"><img data-tooltip-id="1029" data-tooltip-type="\(type)" /></span>
            <span class="pc-row__text"><span class="pc-row__name">\(link)</span><span class="pc-row__meta">1.220 trận</span></span>
            <span class="pc-row__stats"><span class="pc-row__wr">52.8%</span><span class="pc-row__delta pc--\(direction)">
            """.replacingOccurrences(of: "\n", with: "") + #"<span aria-hidden="true">▲ </span><span class="sr-only">+</span>9.9</span></span></li>"#
        }
        let html = row(#"<a href="/tuong/kled">Kled</a>"#, "augment", "up") + row("Lõi", "augment", "down") + row("Đồ", "item", "up")
        XCTAssertEqual(try PlayAramParser.patchChanges(html), [
            PlayAramPatchChange(augmentID: 1029, championKey: "kled", winRate: 52.8, delta: 9.9, games: 1220),
            PlayAramPatchChange(augmentID: 1029, championKey: nil, winRate: 52.8, delta: -9.9, games: 1220)
        ])
    }

    func testRealPagesParseWhenFixturesProvided() throws {
        let env = ProcessInfo.processInfo.environment
        guard let champion = env["RIFT_PLAYARAM_FIXTURE"], let tiers = env["RIFT_PLAYARAM_TIERS_FIXTURE"],
              let changes = env["RIFT_PLAYARAM_CHANGES_FIXTURE"] else {
            throw XCTSkip("Set RIFT_PLAYARAM_FIXTURE, RIFT_PLAYARAM_TIERS_FIXTURE and RIFT_PLAYARAM_CHANGES_FIXTURE to saved pages")
        }
        let styles = PlayAramParser.playstyles(try String(contentsOfFile: champion, encoding: .utf8))
        XCTAssertFalse(styles.isEmpty)
        XCTAssertTrue(styles.allSatisfy { !$0.combos.isEmpty && !$0.title.isEmpty })
        XCTAssertNotNil(PlayAramParser.pagePatch(try String(contentsOfFile: changes, encoding: .utf8)))
        XCTAssertGreaterThan(try PlayAramParser.tierList(String(contentsOfFile: tiers, encoding: .utf8)).count, 100)
        let moves = try PlayAramParser.patchChanges(String(contentsOfFile: changes, encoding: .utf8))
        XCTAssertTrue(moves.contains { $0.championKey != nil } && moves.contains { $0.championKey == nil })
        print("playaram fixtures: \(styles.count) playstyles, \(styles.map(\.combos.count)) combos, \(moves.count) changes")
    }
}
