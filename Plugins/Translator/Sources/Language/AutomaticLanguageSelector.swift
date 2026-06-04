import Foundation

struct TranslatorLanguageSelection: Equatable, Sendable {
    var source: TranslatorLanguage?
    var target: TranslatorLanguage

    var sourceIsAutomatic: Bool {
        source == nil
    }

    var sourceDisplayName: String {
        source?.displayName ?? "自动检测"
    }
}

struct AutomaticLanguageSelector: Sendable {
    private let detector: any LanguageDetecting
    private let preferredPair: TranslatorLanguagePair

    init(
        detector: any LanguageDetecting = LanguageDetector(),
        preferredPair: TranslatorLanguagePair
    ) {
        self.detector = detector
        self.preferredPair = preferredPair
    }

    func select(text: String) -> TranslatorLanguageSelection {
        guard let source = detector.detect(text) else {
            return TranslatorLanguageSelection(source: nil, target: preferredPair.first)
        }

        if source == preferredPair.first {
            return TranslatorLanguageSelection(source: source, target: preferredPair.second)
        }

        return TranslatorLanguageSelection(source: source, target: preferredPair.first)
    }

    func select(for text: String) -> TranslatorLanguageSelection {
        select(text: text)
    }
}
