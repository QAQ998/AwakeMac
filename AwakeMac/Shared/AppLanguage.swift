import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case zhHans
    case english

    var id: String { rawValue }

    var locale: Locale {
        Locale(identifier: self == .zhHans ? "zh-Hans" : "en")
    }

    var displayName: String {
        self == .zhHans ? "简体中文" : "English"
    }

    static var systemDefault: AppLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return preferred.hasPrefix("zh") ? .zhHans : .english
    }
}

