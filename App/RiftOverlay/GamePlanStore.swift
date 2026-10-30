import Foundation
import RiftCore

/// Enemy-aware item swaps every few seconds, plus a model-written plan whenever the matchup or taken augments change.
@MainActor final class GamePlanStore: ObservableObject {
    static let shared = GamePlanStore()
    static let pollInterval: TimeInterval = 5
    static let promptAugmentLimit = 30
    /// One plan boost step counts as this many win-rate points when judging offered cards.
    static let boostWeight = 1.0

    @Published var engine: GamePlanEngine {
        didSet { UserDefaults.standard.set(engine.rawValue, forKey: "GamePlan.engine"); plan = nil; lastPrompt = ""; status = "" }
    }
    @Published private(set) var plan: GamePlan?
    @Published private(set) var swaps: [SituationalItemSwap] = []
    @Published private(set) var status = ""
    private(set) var items: [Int: SituationalItem] = [:]
    private var champions: [String: SituationalChampion] = [:]
    private var dataVersion = ""
    private let live = LiveClient()
    private var polling = false
    private var nextPoll = Date.distantPast
    private var planTask: Task<Void, Never>?
    private var lastPrompt = ""
    private var matchup = ""

    init() {
        engine = UserDefaults.standard.string(forKey: "GamePlan.engine").flatMap(GamePlanEngine.init) ?? .claude
    }

    var model: String { UserDefaults.standard.string(forKey: "GamePlan.\(engine.rawValue).model") ?? engine.defaultModel }

    func boost(for augmentID: Int) -> GamePlan.Boost? { plan?.boosts[augmentID] }

    /// The model's swaps when it planned this game, else the rule-based ones, as "add ← replace · reason".
    var swapLines: [String] {
        if let plan, !plan.itemSwaps.isEmpty {
            return plan.itemSwaps.map { "\(items[$0.add]?.name ?? "#\($0.add)") ← \(items[$0.replace]?.name ?? "#\($0.replace)") · \($0.reason)" }
        }
        return swaps.map { "\($0.itemToAdd.name) ← \($0.itemToReplace.name) · " + AugmentSourceStrings.text($0.reason.label) }
    }

    /// Call on every overlay refresh; work runs at most every `pollInterval` and never while cards are offered.
    func tick(guide: GuideStore, recognition: AutoRecognition) {
        guard guide.mode == .mayhem, recognition.detectedChampion == guide.championKey else {
            if !swaps.isEmpty || plan != nil { swaps = []; plan = nil; lastPrompt = ""; matchup = "" }
            return
        }
        guard Date() >= nextPoll, !polling, guide.recognized.isEmpty else { return }
        nextPoll = Date().addingTimeInterval(Self.pollInterval)
        polling = true
        let owned = recognition.ownedItemIDs
        Task { [weak self] in
            guard let self else { return }
            defer { self.polling = false }
            if self.items.isEmpty, guide.recognized.isEmpty { await self.loadDataDragon() }
            guard let roster = try? await self.live.roster() else { return }
            self.update(roster.players, team: roster.team, riotID: roster.riotID, guide: guide, owned: owned)
        }
    }

    private func update(_ players: [LiveRosterPlayer], team: String?, riotID: String?, guide: GuideStore, owned: [Int]) {
        guard let team else { return }
        let enemies = players.filter { $0.team != nil && $0.team != team }
        let allies = players.filter { $0.team == team }
        let key = guide.championKey + "|" + players.map(\.championName).sorted().joined(separator: ",")
        if key != matchup { matchup = key; plan = nil; lastPrompt = "" }
        let profile = SituationalItems.enemyProfile(roster: players, myTeam: team, champions: champions, items: items)
        let nextSwaps = SituationalItems.suggestions(from: guide.itemBuilds, ownedItemIDs: owned, profile: profile,
                                                     items: items, dataDragonVersion: dataVersion)
        if nextSwaps != swaps { swaps = nextSwaps }
        guard engine != .off, !enemies.isEmpty, guide.recognized.isEmpty, planTask == nil,
              let ownIndex = allies.firstIndex(where: { riotID != nil && $0.riotId == riotID })
                ?? allies.firstIndex(where: { Self.championKey($0) == guide.championKey }) else { return }
        var mates = allies
        let own = mates.remove(at: ownIndex)
        let request = GamePlanRequest(
            champion: own.championName, allies: mates.map(\.championName),
            enemies: enemies.map(\.championName),
            taken: AugmentPickStore.shared.taken.compactMap { id in guide.augments.first { $0.id == id }?.name },
            augments: promptAugments(guide), build: buildItems(guide, owned: owned), counters: counterItems(),
            language: LanguageSettings.shared.selection.promptLanguage
        )
        guard request.prompt != lastPrompt else { return }
        lastPrompt = request.prompt
        start(request)
    }

    private func start(_ request: GamePlanRequest) {
        let engine = engine, model = model
        let augmentIDs = Set(request.augments.map(\.id)), buildIDs = Set(request.build.map(\.id))
        let counterIDs = Set(request.counters.map(\.id))
        status = AugmentSourceStrings.text("正在生成对局计划…")
        planTask = Task { [weak self] in
            let result: Result<GamePlan, Error>
            do {
                let data = try await GamePlanCLI.run(engine, model: model, prompt: request.prompt)
                result = .success(try GamePlan.decode(data, augmentIDs: augmentIDs, buildItemIDs: buildIDs, counterItemIDs: counterIDs))
            } catch { result = .failure(error) }
            guard let self else { return }
            self.planTask = nil
            guard self.engine == engine, self.lastPrompt == request.prompt else { return }
            switch result {
            case .success(let plan):
                self.plan = plan
                self.status = AugmentSourceStrings.text("对局计划已更新 · %@ · %@",
                                                        Date().formatted(date: .omitted, time: .shortened), model)
            case .failure(let error):
                self.status = Self.message(for: error)
            }
        }
    }

    private static func championKey(_ player: LiveRosterPlayer) -> String? {
        guard let raw = player.rawChampionName?.lowercased(), raw.hasPrefix("game_character_displayname_") else { return nil }
        let key = String(raw.dropFirst("game_character_displayname_".count))
        return key == "monkeyking" ? "wukong" : key
    }

    private func promptAugments(_ guide: GuideStore) -> [GamePlanRequest.Augment] {
        let stats = AugmentStatsStore.shared
        let patch = guide.patch == "—" ? nil : guide.patch
        let combos = stats.playaram.playstyles.flatMap(\.combos)
        let deltas = Dictionary(uniqueKeysWithValues: guide.augments.compactMap { augment in
            stats.snapshot.consensus(for: augment.id, patch: patch).map { (augment.id, $0.delta) }
        })
        let top = deltas.sorted { $0.value > $1.value }.prefix(Self.promptAugmentLimit).map(\.key)
        let wanted = Set(top + combos.flatMap(\.augmentIDs) + AugmentPickStore.shared.taken)
        return guide.augments.filter { wanted.contains($0.id) }.map { augment in
            let notes = combos.filter { $0.augmentIDs.contains(augment.id) }.map { combo in
                combo.tier + " with " + combo.augmentIDs.filter { $0 != augment.id }.map(String.init).joined(separator: "+")
            }
            return .init(id: augment.id, name: augment.name, delta: deltas[augment.id], combos: notes)
        }
    }

    private func buildItems(_ guide: GuideStore, owned: [Int]) -> [GamePlanRequest.Item] {
        let build = ItemBuildRecommendation.choose(from: guide.itemBuilds, ownedItemIDs: owned)?.items ?? []
        return build.filter { !owned.contains($0.id) }.map { .init(id: $0.id, name: items[$0.id]?.name ?? $0.name) }
    }

    private func counterItems() -> [GamePlanRequest.Item] {
        SituationalItems.counterCandidates.sorted { $0.key < $1.key }.compactMap { id, reasons in
            guard let item = items[id], item.availableOnHowlingAbyss else { return nil }
            return .init(id: id, name: item.name, role: reasons.map(\.rawValue).joined(separator: "/"))
        }
    }

    /// Load Data Dragon items and champions in the interface language, cached for a day.
    private func loadDataDragon() async {
        let locale = LanguageSettings.shared.selection.dataDragonLocale
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WexiLoL/DataDragon/\(locale)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let versionFile = folder.appendingPathComponent("version.txt")
        let modified = (try? versionFile.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        var version = (try? String(contentsOf: versionFile, encoding: .utf8)) ?? ""
        if version.isEmpty || Date().timeIntervalSince(modified ?? .distantPast) > 86_400,
           let data = try? await URLSession.shared.data(from: URL(string: "https://ddragon.leagueoflegends.com/api/versions.json")!).0,
           let latest = (try? JSONSerialization.jsonObject(with: data) as? [String])?.first {
            version = latest
        }
        guard !version.isEmpty else { return }
        func file(_ name: String) async -> Data? {
            let cached = folder.appendingPathComponent("\(version)-\(name)")
            if let data = try? Data(contentsOf: cached) { return data }
            let url = URL(string: "https://ddragon.leagueoflegends.com/cdn/\(version)/data/\(locale)/\(name)")!
            guard let data = try? await URLSession.shared.data(from: url).0 else { return nil }
            try? data.write(to: cached)
            return data
        }
        guard let itemData = await file("item.json"), let parsedItems = try? SituationalDataDragon.items(from: itemData),
              let championData = await file("champion.json"),
              let parsedChampions = try? SituationalDataDragon.champions(from: championData) else { return }
        try? version.write(to: versionFile, atomically: true, encoding: .utf8)
        items = parsedItems; champions = parsedChampions; dataVersion = version
    }

    private static func message(for error: Error) -> String {
        switch error {
        case GamePlanCLIError.notFound: return AugmentSourceStrings.text("找不到命令行工具")
        case GamePlanCLIError.timedOut: return AugmentSourceStrings.text("对局计划超时")
        default: return AugmentSourceStrings.text("对局计划生成失败")
        }
    }
}

extension SituationalItemReason {
    var label: String {
        switch self {
        case .armor: return "护甲"
        case .magicResist: return "魔抗"
        case .antiHeal: return "重伤"
        }
    }
}

extension AppLanguage {
    var promptLanguage: String {
        switch self {
        case .vietnamese: return "Vietnamese"
        case .chinese: return "Simplified Chinese"
        case .traditionalChinese: return "Traditional Chinese"
        default: return "English"
        }
    }

    var dataDragonLocale: String {
        switch self {
        case .vietnamese: return "vi_VN"
        case .chinese: return "zh_CN"
        case .traditionalChinese: return "zh_TW"
        default: return "en_US"
        }
    }
}
