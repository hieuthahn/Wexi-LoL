import Foundation

/// Champion-specific providers pooled by DerSimonian-Laird random effects on each source's
/// win-rate delta from its own champion average, so regional or rank offsets cancel out.
public struct AugmentConsensus: Equatable, Sendable {
    public static let minimumGames = 100
    public static let minimumRecords = 20

    public let augmentID: Int
    /// Pooled win rate minus the champion average, in percentage points.
    public let delta: Double
    /// The champion average across eligible providers plus `delta`, so every card shares one baseline.
    public let winRate: Double
    public let pickRate: Double?
    public let games: Int
    public let providerIDs: [String]
}

extension AugmentStatsSnapshot {
    /// Pool every eligible provider on `patch` (any patch when nil), or nil when none has a sampled champion page.
    public func consensus(for augmentID: Int, patch: String? = nil) -> AugmentConsensus? {
        guard let championID else { return nil }
        var samples: [(provider: String, delta: Double, variance: Double, record: AugmentStatRecord)] = []
        var baselines: [Double] = []
        for provider in order {
            guard let page = providers[provider], let sample = page.values.first, sample.championID == championID,
                  patch.map({ current in sample.patch.map { AugmentPatch.same($0, current) } ?? true }) ?? true,
                  let baseline = Self.baseline(of: page) else { continue }
            baselines.append(baseline)
            guard let record = page[augmentID], let sampled = Self.sampled(record) else { continue }
            samples.append((provider, sampled.winRate - baseline, Self.variance(sampled.winRate, games: sampled.games), record))
        }
        guard !samples.isEmpty else { return nil }
        let weights = Self.randomEffectWeights(deltas: samples.map(\.delta), variances: samples.map(\.variance))
        let delta = zip(samples.map(\.delta), weights).map(*).reduce(0, +) / weights.reduce(0, +)
        let pickRates = samples.compactMap(\.record.pickRate)
        return AugmentConsensus(
            augmentID: augmentID, delta: delta, winRate: baselines.reduce(0, +) / Double(baselines.count) + delta,
            pickRate: pickRates.isEmpty ? nil : pickRates.reduce(0, +) / Double(pickRates.count),
            games: samples.compactMap(\.record.sampleSize).reduce(0, +), providerIDs: samples.map(\.provider)
        )
    }

    private static func sampled(_ record: AugmentStatRecord) -> (winRate: Double, games: Int)? {
        guard let winRate = record.winRate, let games = record.sampleSize, games >= AugmentConsensus.minimumGames else { return nil }
        return (winRate, games)
    }

    /// The sample-weighted mean win rate of a full champion page; top-N lists cannot stand for the average.
    private static func baseline(of page: [Int: AugmentStatRecord]) -> Double? {
        let rows = page.values.compactMap(sampled)
        guard rows.count >= AugmentConsensus.minimumRecords else { return nil }
        let games = rows.reduce(0) { $0 + Double($1.games) }
        return rows.reduce(0) { $0 + $1.winRate * Double($1.games) } / games
    }

    private static func variance(_ winRate: Double, games: Int) -> Double {
        let ratio = min(max(winRate / 100, 0.01), 0.99)
        return ratio * (1 - ratio) / Double(games) * 10_000
    }

    private static func randomEffectWeights(deltas: [Double], variances: [Double]) -> [Double] {
        let fixed = variances.map { 1 / $0 }
        let sum = fixed.reduce(0, +)
        let mean = zip(deltas, fixed).map(*).reduce(0, +) / sum
        let q = zip(deltas, fixed).map { $1 * ($0 - mean) * ($0 - mean) }.reduce(0, +)
        let c = sum - fixed.map { $0 * $0 }.reduce(0, +) / sum
        let tau2 = c > 0 ? max(0, (q - Double(deltas.count - 1)) / c) : 0
        return variances.map { 1 / ($0 + tau2) }
    }
}
