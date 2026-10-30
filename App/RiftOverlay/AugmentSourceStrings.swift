import Foundation

/// Translations for the remote augment-source strings, kept apart from upstream catalogs to ease merges.
@MainActor enum AugmentSourceStrings {
    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let language = LanguageSettings.shared.selection
        let format: String
        if let row = table[key] {
            switch language {
            case .chinese: format = key
            case .traditionalChinese: format = key.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? key
            case .vietnamese: format = row.vi
            default: format = row.en
            }
        } else {
            format = L10n.text(key)
        }
        return arguments.isEmpty ? format : String(format: format, locale: language.locale, arguments: arguments)
    }

    private static let table: [String: (en: String, vi: String)] = [
        "海克斯数据来源": ("Augment data sources", "Nguồn dữ liệu lõi"),
        "英雄专属": ("champion", "theo tướng"),
        "全局": ("global", "toàn cục"),
        "攻略推荐": ("guide pick", "được gợi ý"),
        "已匹配 %d / %d 个推荐海克斯": ("matched %d of %d picks", "khớp %d / %d lõi gợi ý"),
        "获取免费 API Key": ("Get a free API key", "Lấy API key miễn phí"),
        "无法保存 API Key": ("Couldn't save the API key", "Không lưu được API key"),
        "API Key 已保存到 macOS Keychain": ("API key saved to macOS Keychain", "Đã lưu API key vào Keychain macOS"),
        "API Key 已删除": ("API key deleted", "Đã xóa API key"),
        "密钥已保存在 Keychain": ("Key saved in Keychain", "Khóa đã lưu trong Keychain"),
        "需要 API Key": ("needs an API key", "cần API key"),
        "已加载 %d 个海克斯 · %@": ("%d augments · %@", "%d lõi · %@"),
        "API Key 无效": ("API key rejected", "API key bị từ chối"),
        "今日额度已用完": ("daily quota used up", "đã hết lượt gọi hôm nay"),
        "暂不可用": ("unavailable", "chưa lấy được dữ liệu")
    ]
}
