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
        case .mayhemmeta:
            return .stats(try await cachedHTML("mayhemmeta/\(championKey).html", url: "https://mayhemmeta.com/champions/\(championKey)") {
                try MayhemMetaParser.championAugments($0, championID: championID, championKey: championKey)
            })
        case .playaram:
            return .stats(try await cachedHTML("playaram/\(championKey).html", url: "https://playaram.gg/tuong/\(championKey)") {
                try PlayAramParser.championAugments($0, championID: championID, championKey: championKey)
            })
        case .caoviethoang:
            return .picks(try await cachedHTML("caoviethoang/\(championKey).html",
                                               url: "https://aram.caoviethoang.me/tuong/\(championKey)/") {
                try CaoVietHoangParser.recommendedAugments($0)
            })
        case .hexmayhem:
            let html = String(decoding: try await get(URL(string: "https://hexmayhem.com/augments")!), as: UTF8.self)
            return .stats(HexMayhemRecords.records(from: try MayhemStatsParser.parse(html)))
        }
    }

    /// Parse a recent cached page when it still parses, else download, parse, then cache it.
    private static func cachedHTML<T>(_ path: String, url: String, parse: (String) throws -> T) async throws -> T {
        let file = cacheFile(path)
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let modified, Date().timeIntervalSince(modified) < htmlCacheAge,
           let cached = try? String(contentsOf: file, encoding: .utf8), let result = try? parse(cached) {
            return result
        }
        let data = try await get(URL(string: url)!)
        let result = try parse(String(decoding: data, as: UTF8.self))
        write(data, to: file)
        return result
    }

    private static func aramgg(championID: Int, key: String, allowNetwork: Bool) async throws -> [Int: AugmentStatRecord] {
        let version: String
        do {
            version = try AramggParser.dataVersion(fromConfig: try await get(URL(string: "\(aramggBase)/config.json")!))
            UserDefaults.standard.set(version, forKey: aramggVersionKey)
        } catch {
            guard let lastVersion = UserDefaults.standard.string(forKey: aramggVersionKey) else { throw error }
            version = lastVersion
        }
        let file = cacheFile("aramgg/\(version.filter { $0.isNumber || $0 == "." })/\(championID).json")
        if let cached = try? Data(contentsOf: file),
           let records = try? AramggParser.championAugments(cached, championID: championID) { return records }
        guard allowNetwork else { throw URLError(.resourceUnavailable) }
        let data = try await get(URL(string: "\(aramggBase)/data/champion-augments/\(championID).json")!, key: key)
        let records = try AramggParser.championAugments(data, championID: championID)
        write(data, to: file)
        return records
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
