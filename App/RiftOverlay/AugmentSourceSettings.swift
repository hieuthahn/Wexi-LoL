import RiftCore
import SwiftUI

struct AugmentSourceSettings: View {
    @ObservedObject private var stats = AugmentStatsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AugmentSourceStrings.text("海克斯数据来源")).font(.headline)
            ForEach(AugmentStatsProvider.allCases) { provider in
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(get: { stats.isEnabled(provider) }, set: { stats.setEnabled(provider, $0) })) {
                        HStack(spacing: 6) {
                            Link(provider.displayName, destination: provider.website)
                            Text(AugmentSourceStrings.text(provider.isEditorial ? "社区推荐" : provider.isChampionSpecific ? "英雄专属" : "全局"))
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

/// Stats lines under an augment in the guide list: one line per provider in Mayhem, upstream text elsewhere.
struct AugmentSourceLines: View {
    @ObservedObject private var stats = AugmentStatsStore.shared
    let augment: AugmentRating

    var body: some View {
        let guide = stats.guide
        let records = guide?.mode == .mayhem ? stats.snapshot.records(for: augment.id) : []
        let recommended = guide?.mode == .mayhem && stats.recommended.contains(augment.id)
        if recommended {
            line("★ " + AugmentSourceStrings.text("社区推荐") + " · " + AugmentStatsProvider.caoviethoang.displayName)
        }
        if records.isEmpty {
            upstreamLine
        } else {
            ForEach(records, id: \.providerID) { record in
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
