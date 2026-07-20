import Foundation

enum L10n {
    static func text(_ key: String, language: AppLanguage, bundle: Bundle = .main) -> String {
        String(
            localized: String.LocalizationValue(key),
            table: "Localizable",
            bundle: bundle,
            locale: language.locale
        )
    }
}

