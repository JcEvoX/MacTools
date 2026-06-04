import Foundation

enum TranslatorConstants {
    static let pluginID = "translator"

    enum PermissionID {
        static let accessibility = "accessibility"
        static let automation = "automation"
    }

    enum ShortcutID {
        static let selectTranslation = "translator.select-translation"
    }

    enum ActionID {
        static let selectTranslation = "select-translation"
    }

    enum StorageKey {
        static let shortcutEnabled = "translator.shortcut.enabled"
        static let openAIBaseURL = "translator.openai.base-url"
        static let openAIModel = "translator.openai.model"
        static let openAIPromptTemplate = "translator.openai.prompt-template"
        static let firstPreferredLanguage = "translator.language.first"
        static let secondPreferredLanguage = "translator.language.second"
    }

    enum Defaults {
        static let shortcutEnabled = true
    }
}
