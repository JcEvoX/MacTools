import Foundation

enum AppLanguagePreference: String, CaseIterable, Identifiable {
    case system
    case zhHans = "zh-Hans"
    case en

    static let userDefaultsKey = "app.languagePreference"
    static let didChangeNotification = Notification.Name("AppLanguagePreferenceDidChange")

    private static let appleLanguagesKey = "AppleLanguages"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return AppL10n.settings("language.system", defaultValue: "跟随系统")
        case .zhHans:
            return AppL10n.settings("language.zh-Hans", defaultValue: "简体中文")
        case .en:
            return AppL10n.settings("language.en", defaultValue: "English")
        }
    }

    var appleLanguagesOverride: [String]? {
        switch self {
        case .system:
            return nil
        case .zhHans:
            return ["zh-Hans"]
        case .en:
            return ["en"]
        }
    }

    func store(in userDefaults: UserDefaults = .standard) {
        userDefaults.set(rawValue, forKey: Self.userDefaultsKey)
        applyAppleLanguagesOverride(in: userDefaults)
        userDefaults.synchronize()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    func applyAppleLanguagesOverride(in userDefaults: UserDefaults = .standard) {
        if let appleLanguagesOverride {
            userDefaults.set(appleLanguagesOverride, forKey: Self.appleLanguagesKey)
        } else {
            userDefaults.removeObject(forKey: Self.appleLanguagesKey)
        }
    }

    static func stored(in userDefaults: UserDefaults = .standard) -> AppLanguagePreference {
        guard
            let rawValue = userDefaults.string(forKey: userDefaultsKey),
            let preference = AppLanguagePreference(rawValue: rawValue)
        else {
            return .system
        }

        return preference
    }

    static func applyStoredPreference(userDefaults: UserDefaults = .standard) {
        stored(in: userDefaults).applyAppleLanguagesOverride(in: userDefaults)
    }
}
