import Foundation
import XCTest
@testable import RiftCore

final class SituationalItemsTests: XCTestCase {
    func testChampionParserPreservesIdentityRatingsAndTags() throws {
        let champions = try championCatalog()
        let champion = try XCTUnwrap(champions["Ashe"])
        XCTAssertEqual(champion.key, "22")
        XCTAssertEqual(champion.name, "Ashe")
        XCTAssertEqual(champion.attack, 9)
        XCTAssertEqual(champion.magic, 1)
        XCTAssertEqual(champion.tags, ["Marksman"])
        XCTAssertTrue(try SituationalDataDragon.champions(from: Data(#"{"data":{}}"#.utf8)).isEmpty)
    }

    func testItemParserPreservesCostRecipesAndMapAvailability() throws {
        let items = try itemCatalog()
        let item = try XCTUnwrap(items[3031])
        XCTAssertEqual(item.name, "Infinity Edge")
        XCTAssertEqual(item.tags, ["Damage", "CriticalStrike"])
        XCTAssertEqual(item.totalGold, 3600)
        XCTAssertEqual(item.from, [1038])
        XCTAssertEqual(item.into, [223031])
        XCTAssertTrue(item.availableOnHowlingAbyss)
        XCTAssertTrue(item.purchasable)
        XCTAssertFalse(try XCTUnwrap(items[6333]).availableOnHowlingAbyss)
        XCTAssertEqual(items[3157]?.into, [])
        XCTAssertTrue(try SituationalDataDragon.items(from: Data(#"{"data":{}}"#.utf8)).isEmpty)
    }

    func testEmptyEnemyTeamHasNeutralProfileAndNoSwap() throws {
        let profile = try profile([player("Ashe", team: "ORDER"), player("Lux", team: nil)])
        XCTAssertEqual(profile.enemyCount, 0)
        XCTAssertEqual(profile.physicalShare, 0.5)
        XCTAssertEqual(profile.magicShare, 0.5)
        XCTAssertEqual(profile.healingThreatCount, 0)
        XCTAssertTrue(try suggestions(profile: profile).isEmpty)
        XCTAssertEqual(try self.profile([], myTeam: nil).enemyCount, 0)
        XCTAssertEqual(try self.profile([player("Ashe")], myTeam: "").enemyCount, 0)
    }

    func testBalancedTeamDoesNotSuggestSwap() throws {
        let profile = try profile([player("Ashe"), player("Lux"), player("Ashe", team: "ORDER")])
        XCTAssertEqual(profile.enemyCount, 2)
        XCTAssertEqual(profile.physicalShare, 0.5, accuracy: 0.0001)
        XCTAssertEqual(profile.magicShare, 0.5, accuracy: 0.0001)
        XCTAssertTrue(try suggestions(profile: profile).isEmpty)
    }

    func testHeavyADUsesAvailableADArmorAndReplacesUnownedItem() throws {
        let profile = try profile([player("Ashe"), player("Ashe")])
        let swaps = try suggestions(profile: profile, owned: [3031])
        XCTAssertEqual(swaps.count, 1)
        XCTAssertEqual(swaps.first?.reason, .armor)
        XCTAssertEqual(swaps.first?.itemToAdd.id, 3026)
        XCTAssertEqual(swaps.first?.itemToAdd.name, "Guardian Angel")
        XCTAssertEqual(swaps.first?.itemToAdd.imageURL,
                       "https://ddragon.leagueoflegends.com/cdn/15.1.1/img/item/3026.png")
        XCTAssertEqual(swaps.first?.itemToReplace.id, 3085)
    }

    func testHeavyAPUsesADMagicResist() throws {
        let swaps = try suggestions(profile: profile([player("Lux"), player("Lux")]))
        XCTAssertEqual(swaps.map(\.reason), [.magicResist])
        XCTAssertEqual(swaps.first?.itemToAdd.id, 3156)
    }

    func testAPAndTankBuildsReceiveMatchingCounterClasses() throws {
        let physical = try profile([player("Ashe")])
        let magic = try profile([player("Lux")])
        XCTAssertEqual(try suggestions(profile: physical, buildIDs: [3089, 3135]).first?.itemToAdd.id, 3157)
        XCTAssertEqual(try suggestions(profile: magic, buildIDs: [3089, 3135]).first?.itemToAdd.id, 3102)
        XCTAssertEqual(try suggestions(profile: physical, buildIDs: [3083, 3068]).first?.itemToAdd.id, 3143)
        XCTAssertEqual(try suggestions(profile: magic, buildIDs: [3083, 3068]).first?.itemToAdd.id, 4401)
    }

    func testHealingThreatCountsEachEnemyOnceAndIgnoresAllies() throws {
        let profile = try profile([
            player("Soraka", itemIDs: [1053, 1053, 4401]),
            player("Ashe", itemIDs: [1053, 4401]),
            player("Lux", team: "ORDER", itemIDs: [1053])
        ])
        XCTAssertEqual(profile.healingThreatCount, 2)
        let swaps = try suggestions(profile: profile)
        XCTAssertEqual(swaps.map(\.reason), [.antiHeal])
        XCTAssertEqual(swaps.first?.itemToAdd.id, 3033)
        XCTAssertEqual(try suggestions(profile: profile, buildIDs: [3089, 3135]).first?.itemToAdd.id, 3165)
        XCTAssertEqual(try suggestions(profile: profile, buildIDs: [3083, 3068]).first?.itemToAdd.id, 3075)
    }

    func testHealingTagsRecognizeLifeStealSpellVampOmnivampAndHealing() throws {
        for tag in ["LifeSteal", "SpellVamp", "Omnivamp", "Heal", "HealthRegen"] {
            let json = """
            {"data":{"9000":{"name":"Sustain","tags":["\(tag)"],"gold":{"total":1000},"maps":{"12":true}}}}
            """
            let items = try SituationalDataDragon.items(from: Data(json.utf8))
            let profile = SituationalItems.enemyProfile(
                roster: [player("Unknown", itemIDs: [9000])], myTeam: "ORDER",
                champions: try championCatalog(), items: items
            )
            XCTAssertEqual(profile.healingThreatCount, 1, tag)
        }
    }

    func testHealingAndHeavyDamageProduceAtMostTwoDistinctSwaps() throws {
        let profile = try profile([player("Ashe", itemIDs: [1053]), player("Ashe", itemIDs: [1053])])
        let swaps = try suggestions(profile: profile)
        XCTAssertEqual(swaps.count, SituationalItems.maximumSwaps)
        XCTAssertEqual(swaps.map(\.reason), [.antiHeal, .armor])
        XCTAssertEqual(Set(swaps.map(\.itemToAdd.id)).count, 2)
        XCTAssertEqual(Set(swaps.map(\.itemToReplace.id)).count, 2)
        XCTAssertEqual(try suggestions(profile: profile, owned: [3031, 3085]).count, 0)
        XCTAssertEqual(try suggestions(profile: profile, owned: [3031]).count, 1)
    }

    func testOwnedOrPlannedCounterDoesNotGetSuggestedAgain() throws {
        let physical = try profile([player("Ashe")])
        XCTAssertTrue(try suggestions(profile: physical, owned: [3026]).isEmpty)
        XCTAssertTrue(try suggestions(profile: physical, buildIDs: [3031, 3026]).isEmpty)
        let healing = try profile([player("Soraka"), player("Nami")])
        XCTAssertTrue(try suggestions(profile: healing, owned: [3033, 3156]).isEmpty)
    }

    func testTankThornmailCoversBothHealingAndArmor() throws {
        let profile = try profile([player("Ashe", itemIDs: [1053]), player("Ashe", itemIDs: [1053])])
        let swaps = try suggestions(profile: profile, buildIDs: [3083, 3068])
        XCTAssertEqual(swaps.count, 1)
        XCTAssertEqual(swaps.first?.itemToAdd.id, 3075)
    }

    func testExistingAntiHealIsPreservedWhenAddingArmor() throws {
        let profile = try profile([player("Ashe", itemIDs: [1053]), player("Ashe", itemIDs: [1053])])
        let swaps = try suggestions(profile: profile, buildIDs: [3031, 3033])
        XCTAssertEqual(swaps.map(\.reason), [.armor])
        XCTAssertEqual(swaps.first?.itemToReplace.id, 3031)
    }

    func testExistingMagicResistIsPreservedWhenAddingAntiHeal() throws {
        let profile = try profile([player("Soraka"), player("Nami")])
        let swaps = try suggestions(profile: profile, buildIDs: [3031, 3156])
        XCTAssertEqual(swaps.map(\.reason), [.antiHeal])
        XCTAssertEqual(swaps.first?.itemToReplace.id, 3031)
    }

    func testEnemyItemsNudgeDamageShareWithoutOverridingChampion() throws {
        let base = try profile([player("Hybrid")])
        let ad = try profile([player("Hybrid", itemIDs: [3031, 3085])])
        let ap = try profile([player("Hybrid", itemIDs: [3089, 3135])])
        XCTAssertEqual(ad.physicalShare, base.physicalShare + 0.1, accuracy: 0.0001)
        XCTAssertEqual(ap.magicShare, base.magicShare + 0.1, accuracy: 0.0001)
        let duplicate = try profile([player("Hybrid", itemIDs: [3031, 3031])])
        XCTAssertEqual(duplicate.physicalShare, 0.55, accuracy: 0.0001)
        let capped = try profile([player("Lux", itemIDs: [3031, 3085, 3026, 3156])])
        XCTAssertEqual(capped.physicalShare, 0.25, accuracy: 0.0001)
        XCTAssertEqual(capped.magicShare + capped.physicalShare, 1, accuracy: 0.0001)
    }

    func testChampionLookupSupportsNumericKeyDisplayNameAndRawName() throws {
        XCTAssertEqual(try profile([player("22")]).physicalShare, 0.9, accuracy: 0.0001)
        XCTAssertEqual(try profile([player("ashe")]).physicalShare, 0.9, accuracy: 0.0001)
        let raw = LiveRosterPlayer(riotId: nil, summonerName: nil,
                                   rawChampionName: "game_character_displayname_Ashe",
                                   championName: "Localized", level: 18, team: "CHAOS", items: nil)
        XCTAssertEqual(try profile([raw]).physicalShare, 0.9, accuracy: 0.0001)
        XCTAssertEqual(try profile([player("Unknown")]).physicalShare, 0.5)
    }

    func testThresholdsAreInclusive() throws {
        let below = SituationalEnemyProfile(enemyCount: 5, physicalShare: 0.699, magicShare: 0.301,
                                            healingThreatCount: 1)
        let boundary = SituationalEnemyProfile(enemyCount: 5, physicalShare: SituationalItems.highDamageShare,
                                               magicShare: 0.3, healingThreatCount: 0)
        XCTAssertTrue(try suggestions(profile: below).isEmpty)
        XCTAssertEqual(try suggestions(profile: boundary).map(\.reason), [.armor])
    }

    func testUnavailableUnpurchasableAndMissingCountersProduceNoSwap() throws {
        var items = try itemCatalog()
        items.removeValue(forKey: 3026)
        let profile = try profile([player("Ashe")])
        XCTAssertTrue(SituationalItems.suggestions(
            for: build([3031, 3085]), ownedItemIDs: [], profile: profile,
            items: items, dataDragonVersion: "15.1.1"
        ).isEmpty)
        let magic = try self.profile([player("Lux")])
        XCTAssertTrue(try suggestions(profile: magic, buildIDs: [3083, 3068], owned: [4401]).isEmpty)
        items[3156] = try SituationalDataDragon.items(from: Data(#"""
        {"data":{"3156":{"name":"Maw","tags":["Damage","SpellBlock"],
        "gold":{"total":2800,"purchasable":false},"maps":{"12":true}}}}
        """#.utf8))[3156]
        XCTAssertTrue(SituationalItems.suggestions(
            for: build([3031]), ownedItemIDs: [], profile: magic, items: items, dataDragonVersion: "15.1.1"
        ).isEmpty)
    }

    func testBootsAndOwnedItemsAreNeverReplaced() throws {
        let profile = try profile([player("Ashe")])
        XCTAssertTrue(try suggestions(profile: profile, buildIDs: [3031, 1001], owned: [3031]).isEmpty)
        XCTAssertTrue(try suggestions(profile: profile, buildIDs: []).isEmpty)
        XCTAssertTrue(try suggestions(profile: profile, buildIDs: [9999]).isEmpty)
    }

    func testBuildSelectionReusesExistingRecommendation() throws {
        let items = try itemCatalog()
        let builds = [build([3089, 3135], games: 10), build([3031, 3085], games: 100)]
        let swaps = SituationalItems.suggestions(
            from: builds, ownedItemIDs: [3089], profile: try profile([player("Ashe")]),
            items: items, dataDragonVersion: "15.1.1"
        )
        XCTAssertEqual(swaps.first?.itemToAdd.id, 3157)
        XCTAssertEqual(swaps.first?.itemToReplace.id, 3135)
        XCTAssertTrue(SituationalItems.suggestions(
            from: [], ownedItemIDs: [], profile: try profile([player("Ashe")]),
            items: items, dataDragonVersion: "15.1.1"
        ).isEmpty)
        XCTAssertEqual(builds[0].items.map(\.id), [3089, 3135])
    }

    func testMalformedJSONThrowsInsteadOfReturningPartialCatalog() {
        for json in ["", "[]", "{}", #"{"data":[]}"#,
                     #"{"data":{"Ashe":{"id":"Ashe","key":"22","name":"Ashe","tags":[],"info":{"attack":"9","magic":1}}}}"#,
                     #"{"data":{"Ashe":{"id":"Ashe","key":"22","name":"Ashe","tags":[],"info":{"attack":-1,"magic":1}}}}"#] {
            XCTAssertThrowsError(try SituationalDataDragon.champions(from: Data(json.utf8)), json)
        }
        for json in ["", "[]", "{}", #"{"data":[]}"#,
                     #"{"data":{"x":{"name":"Bad","tags":[],"gold":{"total":1},"maps":{"12":true}}}}"#,
                     #"{"data":{"1":{"name":"Bad","tags":[],"gold":{"total":1},"maps":{"12":"true"}}}}"#,
                     #"{"data":{"1":{"name":"Bad","tags":[],"gold":{"total":1,"purchasable":null},"maps":{"12":true}}}}"#,
                     #"{"data":{"1":{"name":"Bad","tags":[],"gold":{"total":1},"maps":{},"from":["x"]}}}"#,
                     #"{"data":{"1":{"name":"Bad","tags":[],"gold":{"total":1},"maps":{},"into":null}}}"#] {
            XCTAssertThrowsError(try SituationalDataDragon.items(from: Data(json.utf8)), json)
        }
    }

    func testOddItemEntriesAreSkippedLikeTheRealCatalog() throws {
        let json = #"{"data":{"1":{"name":"Good","tags":[],"gold":{"total":1},"maps":{}},"2":{},"2008":{"name":"","tags":[],"gold":{"total":0},"maps":{}}}}"#
        XCTAssertEqual(try SituationalDataDragon.items(from: Data(json.utf8)).keys.sorted(), [1])
    }

    private func player(_ champion: String, team: String? = "CHAOS", itemIDs: [Int] = []) -> LiveRosterPlayer {
        LiveRosterPlayer(riotId: nil, summonerName: nil, rawChampionName: nil,
                         championName: champion, level: 18, team: team,
                         items: itemIDs.map { LivePlayerItem(itemID: $0, count: 1) })
    }

    private func build(_ ids: [Int], games: Int = 100) -> ItemBuild {
        ItemBuild(items: ids.map { BuildItem(id: $0, name: "Item \($0)", imageURL: "") },
                  winRate: 0.5, pickRate: 0.5, games: games)
    }

    private func profile(_ roster: [LiveRosterPlayer], myTeam: String? = "ORDER") throws -> SituationalEnemyProfile {
        SituationalItems.enemyProfile(roster: roster, myTeam: myTeam,
                                      champions: try championCatalog(), items: try itemCatalog())
    }

    private func suggestions(
        profile: SituationalEnemyProfile, buildIDs: [Int] = [3031, 3085], owned: [Int] = []
    ) throws -> [SituationalItemSwap] {
        SituationalItems.suggestions(for: build(buildIDs), ownedItemIDs: owned, profile: profile,
                                    items: try itemCatalog(), dataDragonVersion: "15.1.1")
    }

    private func championCatalog() throws -> [String: SituationalChampion] {
        try SituationalDataDragon.champions(from: Data(#"""
        {"data":{
          "Ashe":{"id":"Ashe","key":"22","name":"Ashe","info":{"attack":9,"magic":1},"tags":["Marksman"]},
          "Lux":{"id":"Lux","key":"99","name":"Lux","info":{"attack":1,"magic":9},"tags":["Mage"]},
          "Hybrid":{"id":"Hybrid","key":"999","name":"Hybrid","info":{"attack":5,"magic":5},"tags":["Fighter"]},
          "Soraka":{"id":"Soraka","key":"16","name":"Soraka","info":{"attack":1,"magic":9},"tags":["Support"]},
          "Nami":{"id":"Nami","key":"267","name":"Nami","info":{"attack":1,"magic":9},"tags":["Support"]}
        }}
        """#.utf8))
    }

    private func itemCatalog() throws -> [Int: SituationalItem] {
        try SituationalDataDragon.items(from: Data(#"""
        {"data":{
          "1001":{"name":"Boots","tags":["Boots"],"gold":{"total":300},"maps":{"12":true}},
          "1053":{"name":"Vampiric Scepter","tags":["Damage","LifeSteal"],"gold":{"total":900},"maps":{"12":true}},
          "3031":{"name":"Infinity Edge","tags":["Damage","CriticalStrike"],"gold":{"total":3600},"from":["1038"],"into":["223031"],"maps":{"12":true}},
          "3085":{"name":"Hurricane","tags":["Damage","AttackSpeed"],"gold":{"total":2600},"maps":{"12":true}},
          "3089":{"name":"Deathcap","tags":["SpellDamage"],"gold":{"total":3600},"maps":{"12":true}},
          "3135":{"name":"Void Staff","tags":["SpellDamage"],"gold":{"total":3000},"maps":{"12":true}},
          "3083":{"name":"Warmog","tags":["Health"],"gold":{"total":3300},"maps":{"12":true}},
          "3068":{"name":"Sunfire","tags":["Health","Armor"],"gold":{"total":2700},"maps":{"12":true}},
          "6333":{"name":"Death's Dance","tags":["Damage","Armor"],"gold":{"total":3300},"maps":{"12":false}},
          "3026":{"name":"Guardian Angel","tags":["Damage","Armor"],"gold":{"total":3200},"maps":{"12":true}},
          "3157":{"name":"Zhonya","tags":["SpellDamage","Armor"],"gold":{"total":3250},"maps":{"12":true}},
          "3143":{"name":"Randuin","tags":["Health","Armor"],"gold":{"total":2700},"maps":{"12":true}},
          "3156":{"name":"Maw","tags":["Damage","SpellBlock"],"gold":{"total":2800},"maps":{"12":true}},
          "3102":{"name":"Banshee","tags":["SpellDamage","SpellBlock"],"gold":{"total":3100},"maps":{"12":true}},
          "4401":{"name":"Force of Nature","tags":["Health","SpellBlock"],"gold":{"total":2800},"maps":{"12":true}},
          "3065":{"name":"Spirit Visage","tags":["Health","SpellBlock","HealthRegen"],"gold":{"total":2700,"purchasable":false},"maps":{"12":true}},
          "3033":{"name":"Mortal Reminder","tags":["Damage"],"gold":{"total":3000},"maps":{"12":true}},
          "3165":{"name":"Morellonomicon","tags":["SpellDamage"],"gold":{"total":2850},"maps":{"12":true}},
          "3075":{"name":"Thornmail","tags":["Health","Armor"],"gold":{"total":2450},"maps":{"12":true}}
        }}
        """#.utf8))
    }
}
