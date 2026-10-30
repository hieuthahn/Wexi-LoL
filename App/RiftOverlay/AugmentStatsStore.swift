import Combine
import Foundation
import RiftCore

enum AugmentStatsProvider: String, CaseIterable, Identifiable {
    case aramgg, mayhemmeta, hexmayhem

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .aramgg: return "aramgg"
        case .mayhemmeta: return "Mayhem:Meta"
        case .hexmayhem: return "HexMayhem"
        }
    }
    var isChampionSpecific: Bool { self != .hexmayhem }
    var needsKey: Bool { self == .aramgg }
    var website: URL {
        switch self {
        case .aramgg: return URL(string: "https://aramgg.com")!
        case .mayhemmeta: return URL(string: "https://mayhemmeta.com")!
        case .hexmayhem: return URL(string: "https://hexmayhem.com")!
        }
    }
    fileprivate var enabledKey: String { "AugmentStats.\(rawValue).enabled" }
    fileprivate var enabledByDefault: Bool { !needsKey }
}

/// Champion-specific and global augment stats from remote providers, fetched only when the guide's champion loads.
@MainActor final class AugmentStatsStore: ObservableObject {
    static let shared = AugmentStatsStore()

    @Published private(set) var snapshot = AugmentStatsSnapshot(championID: nil, order: [], providers: [:])
    @Published private(set) var statuses: [AugmentStatsProvider: String] = [:]
    @Published private(set) var hasSavedKey = !AramggKeychain.read().isEmpty
    @Published var apiKeyDraft = ""
    @Published var keyStatus = ""

    private(set) weak var guide: GuideStore?
    private var guideObservation: AnyCancellable?
    private var requests: [AugmentStatsProvider: Task<Void, Never>] = [:]
    private var inFlight: [AugmentStatsProvider: Int] = [:]
    private var loadedAt: [AugmentStatsProvider: (championID: Int?, date: Date)] = [:]
    private var target: (id: Int, key: String)?
    private var quotaBlockedUntil: Date?

    func isEnabled(_ provider: AugmentStatsProvider) -> Bool {
        UserDefaults.standard.object(forKey: provider.enabledKey) as? Bool ?? provider.enabledByDefault
    }

    func setEnabled(_ provider: AugmentStatsProvider, _ enabled: Bool) {
        objectWillChange.send()
        UserDefaults.standard.set(enabled, forKey: provider.enabledKey)
        if enabled { refresh(provider) } else { drop(provider) }
    }

    /// Observe the guide once; call from any frequently updated owner of it.
    func attach(_ guide: GuideStore) {
        guard self.guide !== guide else { return }
        self.guide = guide
        guideObservation = guide.$augments.receive(on: RunLoop.main).sink { [weak self] _ in self?.guideChanged() }
    }

    func saveKey() {
        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AramggKeychain.save(key) else { keyStatus = AugmentSourceStrings.text("无法保存 API Key"); return }
        apiKeyDraft = ""
        hasSavedKey = !key.isEmpty
        keyStatus = AugmentSourceStrings.text(key.isEmpty ? "API Key 已删除" : "API Key 已保存到 macOS Keychain")
        quotaBlockedUntil = nil
        if hasSavedKey { refresh(.aramgg) } else { drop(.aramgg) }
    }

    /// Compose the augment badge from the primary provider, or nil to keep the upstream badge.
    func overlayText(for augment: AugmentRating, guide: GuideStore) -> String? {
        guard guide.mode == .mayhem, snapshot.championID == Self.championID(in: guide),
              let record = snapshot.primary(for: augment.id) else { return nil }
        return ([augment.tierLabel] + summary(record, guidePatch: guide.patch)).joined(separator: " · ")
    }

    /// Describe one record as compact parts: win rate, sample, pick rate, provider and scope.
    func summary(_ record: AugmentStatRecord, guidePatch: String) -> [String] {
        var parts: [String] = []
        if let winRate = record.winRate { parts.append(AugmentSourceStrings.text("胜率 %.1f%%", winRate)) }
        if let games = record.sampleSize {
            parts.append(games >= 1000 ? String(format: "n%.1fk", Double(games) / 1000) : "n\(games)")
        }
        if let pickRate = record.pickRate { parts.append(AugmentSourceStrings.text("选用率 %.1f%%", pickRate)) }
        var source = AugmentStatsProvider(rawValue: record.providerID)?.displayName ?? record.providerID
        if record.championID == nil { source += " " + AugmentSourceStrings.text("全局") }
        if let patch = record.patch, patch != guidePatch, guidePatch != "—" { source += " \(patch)" }
        parts.append(source)
        return parts
    }

    private static func championID(in guide: GuideStore) -> Int? {
        guide.champions.first { $0.id == guide.championKey }?.numericID
    }

    private func guideChanged() {
        // Cards on screen mean augment selection; network waits for the next guide update.
        guard let guide, guide.mode == .mayhem, guide.recognized.isEmpty,
              let championID = Self.championID(in: guide) else { return }
        if target?.id != championID {
            target = (championID, guide.championKey)
            for provider in AugmentStatsProvider.allCases where provider.isChampionSpecific { drop(provider) }
            publish(championID: championID)
        }
        AugmentStatsProvider.allCases.forEach(refresh)
    }

    private func refresh(_ provider: AugmentStatsProvider) {
        guard isEnabled(provider), let target else { return }
        let championID = provider.isChampionSpecific ? target.id : nil
        if let championID, inFlight[provider] == championID { return }
        if championID == nil, inFlight[provider] != nil { return }
        if let loaded = loadedAt[provider], loaded.championID == championID,
           Date().timeIntervalSince(loaded.date) < Self.ttl(provider) { return }
        let key = provider.needsKey ? AramggKeychain.read() : ""
        if provider.needsKey, key.isEmpty { statuses[provider] = AugmentSourceStrings.text("需要 API Key"); return }
        if provider == .aramgg, let quotaBlockedUntil, Date() < quotaBlockedUntil {
            statuses[provider] = AugmentSourceStrings.text("今日额度已用完")
        }
        requests[provider]?.cancel()
        inFlight[provider] = championID ?? -1
        let allowNetwork = provider != .aramgg || (quotaBlockedUntil.map { Date() >= $0 } ?? true)
        let championKey = target.key
        requests[provider] = Task { [weak self] in
            do {
                let records = try await AugmentStatsLoader.load(provider, championID: target.id, championKey: championKey,
                                                                key: key, allowNetwork: allowNetwork)
                guard !Task.isCancelled, let self else { return }
                self.inFlight[provider] = nil
                self.loadedAt[provider] = (championID, Date())
                self.store(records, for: provider)
                self.statuses[provider] = AugmentSourceStrings.text("已加载 %d 个海克斯 · %@", records.count,
                                                                    records.values.first?.patch ?? "—")
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.inFlight[provider] = nil
                if (error as? URLError)?.code == .resourceUnavailable, provider == .aramgg {
                    self.quotaBlockedUntil = Self.nextUTCMidnight()
                }
                self.statuses[provider] = Self.message(for: error)
            }
        }
    }

    private func drop(_ provider: AugmentStatsProvider) {
        requests[provider]?.cancel()
        requests[provider] = nil; inFlight[provider] = nil; loadedAt[provider] = nil
        store([:], for: provider)
        statuses[provider] = nil
    }

    private func store(_ records: [Int: AugmentStatRecord], for provider: AugmentStatsProvider) {
        var providers = snapshot.providers
        providers[provider.rawValue] = records.isEmpty ? nil : records
        snapshot = AugmentStatsSnapshot(championID: target?.id, order: AugmentStatsProvider.allCases.map(\.rawValue),
                                        providers: providers)
    }

    private func publish(championID: Int) {
        snapshot = AugmentStatsSnapshot(championID: championID, order: AugmentStatsProvider.allCases.map(\.rawValue),
                                        providers: snapshot.providers)
    }

    private static func ttl(_ provider: AugmentStatsProvider) -> TimeInterval {
        switch provider {
        case .aramgg: return 3600
        case .mayhemmeta: return 6 * 3600
        case .hexmayhem: return 1800
        }
    }

    private static func nextUTCMidnight() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.nextDate(after: Date(), matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime)
            ?? Date().addingTimeInterval(86_400)
    }

    private static func message(for error: Error) -> String {
        switch (error as? URLError)?.code {
        case .userAuthenticationRequired: return AugmentSourceStrings.text("API Key 无效")
        case .resourceUnavailable: return AugmentSourceStrings.text("今日额度已用完")
        default: return AugmentSourceStrings.text("暂不可用")
        }
    }
}
