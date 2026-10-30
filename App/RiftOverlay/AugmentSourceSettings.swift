import RiftCore
import SwiftUI

struct AugmentSourceSettings: View {
    @ObservedObject private var stats = AugmentStatsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AugmentSourceStrings.text("海克斯数据来源")).font(.headline)
            Picker(AugmentSourceStrings.text("主要来源"), selection: $stats.primarySource) {
                Text(AugmentSourceStrings.text("综合多个来源")).tag("pooled")
                ForEach(AugmentStatsProvider.statProviders.filter(\.isChampionSpecific)) { provider in
                    Text(provider.displayName).tag(provider.rawValue)
                }
            }
            .frame(maxWidth: 320)
            GamePlanSettings()
            ForEach(AugmentStatsProvider.allCases) { provider in
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(get: { stats.isEnabled(provider) }, set: { stats.setEnabled(provider, $0) })) {
                        HStack(spacing: 6) {
                            Link(provider.displayName, destination: provider.website)
                            Text(AugmentSourceStrings.text(provider.isEditorial ? "攻略推荐" : provider.isChampionSpecific ? "英雄专属" : "全局"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let status = stats.statuses[provider], stats.isEnabled(provider) {
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if stats.isEnabled(.aramgg) {
                HStack {
                    SecureField(L10n.text("API Key"), text: $stats.apiKeyDraft).textFieldStyle(.roundedBorder)
                    Button(L10n.text("保存 API Key")) { stats.saveKey() }
                }
                HStack(spacing: 12) {
                    Link(AugmentSourceStrings.text("获取免费 API Key"), destination: URL(string: "https://data.dtodo.cn/developer.html")!)
                    if stats.hasSavedKey {
                        Label(AugmentSourceStrings.text("密钥已保存在 Keychain"), systemImage: "checkmark.shield.fill")
                            .foregroundStyle(.secondary)
                    }
                    if !stats.keyStatus.isEmpty { Text(stats.keyStatus).foregroundStyle(.secondary) }
                }
                .font(.caption)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct GamePlanSettings: View {
    @ObservedObject private var planner = GamePlanStore.shared

    var body: some View {
        Picker(AugmentSourceStrings.text("AI 对局计划"), selection: $planner.engine) {
            Text(AugmentSourceStrings.text("关闭")).tag(GamePlanEngine.off)
            Text("Claude Haiku").tag(GamePlanEngine.claude)
            Text("Codex Luna").tag(GamePlanEngine.codex)
        }
        .frame(maxWidth: 320)
        if planner.engine != .off {
            Text(AugmentSourceStrings.text("使用本机 CLI；只发送英雄、海克斯和装备名称"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Stats lines under an augment in the guide list: one line per provider in Mayhem, upstream text elsewhere.
struct AugmentSourceLines: View {
    @ObservedObject private var stats = AugmentStatsStore.shared
    let augment: AugmentRating

    var body: some View {
        let guide = stats.guide
        let records = guide?.mode == .mayhem ? stats.snapshot.records(for: augment.id) : []
        let recommended = guide?.mode == .mayhem && stats.recommended.contains(augment.id)
        if recommended {
            line("★ " + AugmentSourceStrings.text("攻略推荐") + " · " + AugmentStatsProvider.caoviethoang.displayName)
        }
        let patch = guide?.patch ?? "—"
        if guide?.mode == .mayhem, let boost = GamePlanStore.shared.boost(for: augment.id), boost.value != 0 {
            line(String(format: "AI%+d · ", boost.value) + boost.reason)
        }
        let headline = guide?.mode == .mayhem ? stats.headline(for: augment.id, guidePatch: patch) : nil
        if let combo = stats.comboText(for: augment.id) { line(combo) }
        if records.isEmpty && headline == nil {
            upstreamLine
        } else {
            let lead = stats.leadSummary(for: augment.id, guidePatch: patch)
            if let headline { line(headline.joined(separator: " · ")).fontWeight(.semibold) }
            if lead?.providerID != nil, let pooled = stats.consensusSummary(for: augment.id, guidePatch: patch) {
                line(pooled.joined(separator: " · "))
            }
            ForEach(records.filter { $0.providerID != lead?.providerID }, id: \.providerID) { record in
                line(stats.summary(record, guidePatch: guide?.patch ?? "—").joined(separator: " · "))
            }
        }
    }

    @ViewBuilder private var upstreamLine: some View {
        if let winRate = augment.winRate, let pickRate = augment.pickRate {
            if let games = augment.games {
                line(L10n.text("胜率 %.1f%% · 选用率 %.1f%% · %d 场", winRate, pickRate, games))
            } else {
                line(L10n.text("胜率 %.1f%% · 选用率 %.1f%%", winRate, pickRate))
            }
        } else if let pickRate = augment.pickRate {
            line(L10n.text("选用率 %.1f%%", pickRate))
        }
    }

    private func line(_ text: String) -> some View {
        Text(text).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
    }
}
