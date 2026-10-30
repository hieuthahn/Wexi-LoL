import RiftCore
import SwiftUI

extension AugmentStatsStore {
    private static let tierRank = ["S+", "S", "A", "B", "C", "D"]

    /// The lead stats, else playaram's global tier, followed by this patch's win-rate move.
    func headline(for augmentID: Int, guidePatch: String) -> [String]? {
        let current = { (patch: String?) in guidePatch == "—" || patch.map { AugmentPatch.same($0, guidePatch) } ?? false }
        var parts = leadSummary(for: augmentID, guidePatch: guidePatch)?.parts
            ?? (current(playaram.tiersPatch) ? globalTierSummary(for: augmentID) : [])
        if current(playaram.changesPatch), let trend = trendText(for: augmentID) { parts.insert(trend, at: min(1, parts.count)) }
        return parts.isEmpty ? nil : parts
    }

    /// The best-rated editorial combo containing the augment, named in the catalog's language.
    func comboText(for augmentID: Int) -> String? {
        guard guide?.mode == .mayhem, let combo = bestCombo(for: augmentID) else { return nil }
        return "⚡" + combo.tier + " " + comboNames(combo).joined(separator: " + ")
    }

    func comboNames(_ combo: PlayAramPlaystyle.Combo) -> [String] {
        let taken = Set(AugmentPickStore.shared.taken)
        return zip(combo.augmentIDs, combo.augmentNames).map { id, name in
            (taken.contains(id) ? "✓" : "") + (guide?.augments.first { $0.id == id }?.name ?? name)
        }
    }

    /// Prefer the combo with the most augments already taken, then the editor's tier.
    private func bestCombo(for augmentID: Int) -> PlayAramPlaystyle.Combo? {
        let taken = Set(AugmentPickStore.shared.taken)
        let rank = { (combo: PlayAramPlaystyle.Combo) in
            (-combo.augmentIDs.filter(taken.contains).count, Self.tierRank.firstIndex(of: combo.tier) ?? 9)
        }
        return playaram.playstyles.flatMap(\.combos).filter { $0.augmentIDs.contains(augmentID) }.min { rank($0) < rank($1) }
    }

    private func globalTierSummary(for augmentID: Int) -> [String] {
        guard isEnabled(.playaram), let tier = playaram.tiers[augmentID] else { return [] }
        var parts = [AugmentSourceStrings.text("评级 %@", tier.tier)]
        if let winRate = tier.winRate { parts.append(AugmentSourceStrings.text("胜率 %.1f%%", winRate)) }
        parts.append(AugmentStatsProvider.playaram.displayName + " " + AugmentSourceStrings.text("全局"))
        return parts
    }

    /// Prefer the champion-specific move; fall back to the augment's move across all champions.
    private func trendText(for augmentID: Int) -> String? {
        let championKey = guide?.championKey
        let moves = playaram.changes.filter { $0.augmentID == augmentID }
        guard let move = moves.first(where: { $0.championKey == championKey }) ?? moves.first(where: { $0.championKey == nil })
        else { return nil }
        return String(format: move.delta >= 0 ? "▲%.1f" : "▼%.1f", abs(move.delta))
    }
}

/// The augment section of the guide: playaram playstyles above the rated augment list.
struct AugmentGuideList: View {
    @ObservedObject private var stats = AugmentStatsStore.shared
    @ObservedObject private var picks = AugmentPickStore.shared
    let augments: [AugmentRating]

    var body: some View {
        let mayhem = stats.guide?.mode == .mayhem
        if mayhem, !picks.taken.isEmpty {
            HStack(spacing: 6) {
                Text(AugmentSourceStrings.text("已选海克斯")).font(.system(size: 11, weight: .semibold))
                ForEach(picks.taken, id: \.self) { id in
                    Button((stats.guide?.augments.first { $0.id == id }?.name ?? "#\(id)") + " ✕") { picks.toggle(id) }
                        .buttonStyle(.bordered).controlSize(.small)
                        .help(AugmentSourceStrings.text("移除"))
                }
            }
        }
        if mayhem, !stats.playaram.playstyles.isEmpty {
            PlayAramPlaystylesView(playstyles: stats.playaram.playstyles)
        }
        LazyVStack(spacing: 5) {
            ForEach(augments) { augment in
                AugmentRow(augment: augment, pinned: mayhem && picks.taken.contains(augment.id))
                    .padding(8).background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 9))
                    .contextMenu {
                        if mayhem {
                            Button(AugmentSourceStrings.text(picks.taken.contains(augment.id) ? "取消标记已选" : "标记为已选")) {
                                picks.toggle(augment.id)
                            }
                        }
                    }
            }
        }
    }
}

private struct PlayAramPlaystylesView: View {
    @ObservedObject private var stats = AugmentStatsStore.shared
    let playstyles: [PlayAramPlaystyle]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(AugmentSourceStrings.text("玩法与海克斯组合")).font(.title3.bold())
                Spacer()
                Link(AugmentStatsProvider.playaram.displayName + " ↗", destination: AugmentStatsProvider.playaram.website)
                    .font(.caption)
            }
            Text(AugmentSourceStrings.text("评级由编辑给出，并非胜率")).font(.system(size: 10)).foregroundStyle(.secondary)
            ForEach(Array(playstyles.enumerated()), id: \.offset) { _, style in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        if !style.summary.isEmpty { Text(style.summary).font(.system(size: 11)) }
                        ForEach(Array(style.combos.enumerated()), id: \.offset) { _, combo in
                            if !combo.text.isEmpty { Text(combo.text).font(.system(size: 11)).foregroundStyle(.secondary) }
                        }
                        if !style.items.isEmpty {
                            Text(AugmentSourceStrings.text("推荐装备") + ": " + style.items.joined(separator: ", "))
                                .font(.system(size: 11))
                        }
                        ForEach(Array(style.tips.enumerated()), id: \.offset) { _, tip in
                            (Text(tip.title).bold() + Text(" " + tip.text)).font(.system(size: 11))
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("[\(style.tier)] " + style.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                        ForEach(Array(style.combos.enumerated()), id: \.offset) { _, combo in
                            Text("⚡" + combo.tier + " " + stats.comboNames(combo).joined(separator: " + "))
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(8).background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 9))
            }
        }
    }
}
