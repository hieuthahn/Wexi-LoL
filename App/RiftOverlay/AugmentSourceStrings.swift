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
        "评级 %@": ("Tier %@", "Hạng %@"),
        "玩法与海克斯组合": ("Playstyles & augment combos", "Lối chơi & combo lõi"),
        "评级由编辑给出，并非胜率": ("Editors set these ratings; they are not win rates.",
                              "Hạng do biên tập viên chấm, không phải tỉ lệ thắng."),
        "推荐装备": ("Items", "Đồ khuyên dùng"),
        "推荐选择": ("Pick", "Nên chọn"),
        "已选海克斯": ("Taken", "Đã lấy"),
        "移除": ("Remove", "Bỏ"),
        "标记为已选": ("Mark as taken", "Đánh dấu đã lấy"),
        "取消标记已选": ("Unmark as taken", "Bỏ đánh dấu đã lấy"),
        "对局计划": ("Game plan", "Kế hoạch trận"),
        "AI 对局计划": ("AI game plan", "Kế hoạch trận AI"),
        "关闭": ("Off", "Tắt"),
        "使用本机 CLI；只发送英雄、海克斯和装备名称": ("Runs your local CLI; sends only champion, augment and item names.",
                                         "Chạy CLI trên máy; chỉ gửi tên tướng, lõi và trang bị."),
        "正在生成对局计划…": ("Planning…", "Đang lập kế hoạch…"),
        "对局计划已更新 · %@ · %@": ("Plan updated · %@ · %@", "Đã cập nhật kế hoạch · %@ · %@"),
        "找不到命令行工具": ("CLI not found", "Không tìm thấy CLI"),
        "对局计划超时": ("Plan timed out", "Lập kế hoạch quá thời gian"),
        "对局计划生成失败": ("Plan failed", "Lập kế hoạch thất bại"),
        "护甲": ("armor", "giáp"),
        "魔抗": ("magic resist", "kháng phép"),
        "重伤": ("anti-heal", "chống hồi máu"),
        "主要来源": ("Primary source", "Nguồn chính"),
        "综合多个来源": ("Pool all sources", "Gộp các nguồn"),
        "综合 %d 个来源": ("%d sources pooled", "gộp %d nguồn"),
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
