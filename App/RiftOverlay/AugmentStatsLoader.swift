import Foundation
import RiftCore
import Security

enum AramggKeychain {
    static let service = "dev.local.wexilol.aramgg"
    static let account = "api-key"

    static func read() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func save(_ value: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        guard !value.isEmpty else {
            let status = SecItemDelete(base as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let update = SecItemUpdate(base as CFDictionary, [kSecValueData as String: Data(value.utf8)] as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        var item = base
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}

enum AugmentStatsResult {
    case stats([Int: AugmentStatRecord])
    case picks([AugmentReference])
    case playaram([Int: AugmentStatRecord], PlayAramGuide)
}

/// Network and disk-cache access for augment stat providers; never runs on the main actor.
enum AugmentStatsLoader {
    private static let aramggBase = "https://data.dtodo.cn/api/v1/en"
    private static let aramggVersionKey = "AugmentStats.aramgg.lastDataVersion"
    private static let htmlCacheAge: TimeInterval = 6 * 3600

    static func load(_ provider: AugmentStatsProvider, championID: Int, championKey: String, key: String,
                     allowNetwork: Bool) async throws -> AugmentStatsResult {
        switch provider {
        case .aramgg: return .stats(try await aramgg(championID: championID, key: key, allowNetwork: allowNetwork))
        case .aramhex: return .stats(try await aramhex(championID: championID))
        case .arammeta:
            return .stats(try await cachedPage("arammeta/tier-list.json", url: "https://arammeta.com/api/tier-list.json") {
                try AramMetaParser.championAugments(Data($0.utf8), championID: championID)
            })
        case .mayhemmeta:
            return .stats(try await cachedPage("mayhemmeta/\(championKey).html", url: "https://mayhemmeta.com/champions/\(championKey)") {
                try MayhemMetaParser.championAugments($0, championID: championID, championKey: championKey)
            })
        case .playaram:
            // Start all three pages together so none begins after augment cards appear.
            async let tiers = try? cachedPage("playaram/tier-list.html", url: "https://playaram.gg/loi-aram-hon-loan") {
                (try PlayAramParser.tierList($0), PlayAramParser.pagePatch($0))
            }
            async let changes = try? cachedPage("playaram/patch-changes.html", url: "https://playaram.gg/thay-doi-phien-ban") {
                (try PlayAramParser.patchChanges($0), PlayAramParser.pagePatch($0))
            }
            let (records, playstyles) = try await cachedPage("playaram/\(championKey).html",
                                                             url: "https://playaram.gg/tuong/\(championKey)") {
                (try PlayAramParser.championAugments($0, championID: championID, championKey: championKey),
                 PlayAramParser.playstyles($0))
            }
            let (tierList, changeList) = await (tiers, changes)
            return .playaram(records, PlayAramGuide(playstyles: playstyles, tiers: tierList?.0 ?? [:], changes: changeList?.0 ?? [],
                                                    tiersPatch: tierList?.1, changesPatch: changeList?.1))
        case .caoviethoang:
            return .picks(try await cachedPage("caoviethoang/\(championKey).html",
                                               url: "https://aram.caoviethoang.me/tuong/\(championKey)/") {
                try CaoVietHoangParser.recommendedAugments($0)
            })
        case .hexmayhem:
            let html = String(decoding: try await get(URL(string: "https://hexmayhem.com/augments")!), as: UTF8.self)
            return .stats(HexMayhemRecords.records(from: try MayhemStatsParser.parse(html)))
        }
    }

    /// Use a recent cached page, else download it; when offline, fall back to any cached copy that still parses.
    private static func cachedPage<T>(_ path: String, url: String, parse: (String) throws -> T) async throws -> T {
        let file = cacheFile(path)
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let modified, Date().timeIntervalSince(modified) < htmlCacheAge,
           let cached = try? String(contentsOf: file, encoding: .utf8), let result = try? parse(cached) {
            return result
        }
        do {
            let data = try await get(URL(string: url)!)
            let result = try parse(String(decoding: data, as: UTF8.self))
            write(data, to: file)
            return result
        } catch {
            guard let cached = try? String(contentsOf: file, encoding: .utf8), let result = try? parse(cached) else { throw error }
            return result
        }
    }

    /// Follow AramHex's `latest.json` pointer, keep one dataset per release, and fall back to the last complete one.
    private static func aramhex(championID: Int) async throws -> [Int: AugmentStatRecord] {
        let pointer = cacheFile("aramhex/latest.json")
        do {
            let latest = try await get(URL(string: "https://raw.githubusercontent.com/czgreat/aramhex-data/main/latest.json")!)
            let release = try AramHexParser.release(latest)
            let file = cacheFile("aramhex/\(release.seq)/hero_augments.json")
            if let cached = try? Data(contentsOf: file),
               let records = try? AramHexParser.championAugments(cached, championID: championID, release: release) {
                write(latest, to: pointer)
                return records
            }
            let tag = "https://raw.githubusercontent.com/czgreat/aramhex-data/data-v\(release.seq)"
            let data = try await get(URL(string: "\(tag)/\(release.path)/hero_augments.json")!)
            let records = try AramHexParser.championAugments(data, championID: championID, release: release)
            write(data, to: file)
            write(latest, to: pointer)
            return records
        } catch {
            guard let cached = try? Data(contentsOf: pointer), let release = try? AramHexParser.release(cached),
                  let data = try? Data(contentsOf: cacheFile("aramhex/\(release.seq)/hero_augments.json")) else { throw error }
            return try AramHexParser.championAugments(data, championID: championID, release: release)
        }
    }

    private static func aramgg(championID: Int, key: String, allowNetwork: Bool) async throws -> [Int: AugmentStatRecord] {
        let lastVersion = UserDefaults.standard.string(forKey: aramggVersionKey)
        let version: String
        if !allowNetwork, let lastVersion {
            version = lastVersion
        } else {
            do {
                version = try AramggParser.dataVersion(fromConfig: try await get(URL(string: "\(aramggBase)/config.json")!))
                UserDefaults.standard.set(version, forKey: aramggVersionKey)
            } catch {
                guard let lastVersion else { throw error }
                version = lastVersion
            }
        }
        let file = aramggFile(version, championID)
        if let records = try? aramggCache(version, championID) { return records }
        guard allowNetwork else { throw URLError(.resourceUnavailable) }
        let data = try await get(URL(string: "\(aramggBase)/data/champion-augments/\(championID).json")!, key: key)
        let records = try AramggParser.championAugments(data, championID: championID)
        write(data, to: file)
        return records
    }

    private static func aramggFile(_ version: String, _ championID: Int) -> URL {
        cacheFile("aramgg/\(version.filter { $0.isNumber || $0 == "." })/\(championID).json")
    }

    private static func aramggCache(_ version: String, _ championID: Int) throws -> [Int: AugmentStatRecord] {
        try AramggParser.championAugments(try Data(contentsOf: aramggFile(version, championID)), championID: championID)
    }

    private static func cacheFile(_ path: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WexiLoL/AugmentStats/\(path)")
    }

    private static func write(_ data: Data, to file: URL) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    private static func get(_ url: URL, key: String? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("WexiLoL/0.6.2", forHTTPHeaderField: "User-Agent")
        if let key { request.setValue(key, forHTTPHeaderField: "x-api-key") }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: return data
        case 401: throw URLError(.userAuthenticationRequired)
        case 429: throw URLError(.resourceUnavailable)
        default: throw URLError(.badServerResponse)
        }
    }
}
