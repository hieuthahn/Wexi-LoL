import XCTest
@testable import RiftCore

final class AugmentStatsVietnamTests: XCTestCase {
    private func playAramCore(_ id: Int, winRate: String, pickRate: String) -> String {
        #"<li data-cb-core data-tooltip-id="\#(id)" data-tooltip-type="augment" class="cb-core"><img src="x.png" />"#
            + #"<span class="cb-core__name">Name</span><span class="cb-stats"><span title="Tỉ lệ thắng" class="sp-stat cb-stats__wr">\#(winRate)%</span>"#
            + #"<span title="Tỉ lệ chọn" class="sp-stat cb-stats__pick">\#(pickRate)%</span></span></li>"#
    }

    private func playAramPage(champion: Int, cores: [String]) -> String {
        #"<img src="/assets/champion/\#(champion).png"><dl><div><dt>Phiên bản</dt><dd>26.21</dd></div>"#
            + #"<div><dt>Cập nhật</dt><dd><time datetime="2026-10-30T07:17:05Z">7 giờ trước</time></dd></div></dl>"#
            + cores.joined()
    }

    func testPlayAramReadsRiotIDsRatesAndProvenanceWithoutInventingSamples() throws {
        let html = playAramPage(champion: 24, cores: [playAramCore(2141, winRate: "59.58", pickRate: "5.4"),
                                                      playAramCore(1058, winRate: "158", pickRate: "10.2")])
        let records = try PlayAramParser.championAugments(html, championID: 24, championKey: "jax")
        XCTAssertEqual(records[2141]?.winRate, 59.58)
        XCTAssertEqual(records[2141]?.pickRate, 5.4)
        XCTAssertNil(records[2141]?.sampleSize)
        XCTAssertEqual(records[2141]?.patch, "26.21")
        XCTAssertEqual(records[2141]?.updatedAt, "2026-10-30T07:17:05Z")
        XCTAssertNil(records[1058]?.winRate)
        XCTAssertEqual(records[1058]?.pickRate, 10.2)
    }

    func testPlayAramRejectsAnotherChampionsPageAndChangedMarkup() {
        let jaxPage = playAramPage(champion: 24, cores: [playAramCore(2141, winRate: "59.58", pickRate: "5.4")])
        XCTAssertThrowsError(try PlayAramParser.championAugments(jaxPage, championID: 266, championKey: "aatrox"))
        XCTAssertThrowsError(try PlayAramParser.championAugments(playAramPage(champion: 24, cores: []), championID: 24, championKey: "jax"))
    }

    func testPlayAramParsesRealPageWhenFixtureProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["RIFT_PLAYARAM_FIXTURE"] else {
            throw XCTSkip("Set RIFT_PLAYARAM_FIXTURE to a saved playaram.gg/tuong/jax page")
        }
        let records = try PlayAramParser.championAugments(String(contentsOfFile: path), championID: 24, championKey: "jax")
        XCTAssertGreaterThan(records.count, 30)
        XCTAssertEqual(records[2141]?.patch, "26.21")
    }

    func testCaoVietHoangReadsRiotIDsAndSlugsOnce() throws {
        let html = #"<li data-top-aug="mystic-punch"></li><li data-top-aug="riot-3078"></li><li data-top-aug="mystic-punch"></li>"#
        XCTAssertEqual(try CaoVietHoangParser.recommendedAugments(html), [.slug("mystic-punch"), .riotID(3078)])
        XCTAssertThrowsError(try CaoVietHoangParser.recommendedAugments("<html></html>"))
    }

    func testCaoVietHoangParsesRealPageWhenFixtureProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["RIFT_CAOVIETHOANG_FIXTURE"] else {
            throw XCTSkip("Set RIFT_CAOVIETHOANG_FIXTURE to a saved aram.caoviethoang.me/tuong/jax page")
        }
        let references = try CaoVietHoangParser.recommendedAugments(String(contentsOfFile: path))
        XCTAssertEqual(references.count, 18)
        XCTAssertTrue(references.contains(.riotID(3078)))
    }

    func testReferencesResolveOnlyExactUniqueMatches() {
        let catalog = [
            AugmentRating(id: 1058, name: "Cú Đấm Thần Bí", key: "ARAM_MysticPunch", tier: 1, rarity: 8, englishName: "Mystic Punch"),
            AugmentRating(id: 2141, name: "Siêu Mãng Xà", key: "ARAM_UltraHydra", tier: 1, rarity: 8, englishName: "Ultra Hydra"),
            AugmentRating(id: 1103, name: "A", key: "ARAM_Twin", tier: 2, rarity: 4, englishName: "Twin"),
            AugmentRating(id: 1104, name: "B", key: "ARAM_TwinB", tier: 2, rarity: 4, englishName: "Twin")
        ]
        XCTAssertEqual(AugmentReference.slug("mystic-punch").resolve(in: catalog), 1058)
        XCTAssertEqual(AugmentReference.slug("ultrahydra").resolve(in: catalog), 2141)
        XCTAssertNil(AugmentReference.slug("twin").resolve(in: catalog))
        XCTAssertNil(AugmentReference.slug("mystic-punc").resolve(in: catalog))
        XCTAssertEqual(AugmentReference.riotID(2141).resolve(in: catalog), 2141)
        XCTAssertNil(AugmentReference.riotID(3078).resolve(in: catalog))
    }

    func testYearBasedPatchMatchesClientPatch() {
        XCTAssertTrue(AugmentPatch.same("26.21", "16.21"))
        XCTAssertTrue(AugmentPatch.same("16.21", "16.21"))
        XCTAssertFalse(AugmentPatch.same("26.20", "16.21"))
        XCTAssertFalse(AugmentPatch.same("16.21", "—"))
    }
}
