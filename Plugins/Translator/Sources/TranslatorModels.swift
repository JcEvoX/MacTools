import Foundation

enum TranslatorPanelPhase: Equatable, Sendable {
    case idle
    case capturing
    case translating
    case success
    case error(TranslatorPanelError)
}

enum TranslatorPanelError: Equatable, Sendable {
    case missingSelection
    case missingConfiguration
    case permissionRequired
    case requestFailed(String)

    var message: String {
        switch self {
        case .missingSelection:
            return "未找到选中文本"
        case .missingConfiguration:
            return "请先配置 OpenAI"
        case .permissionRequired:
            return "需要辅助功能授权"
        case let .requestFailed(message):
            return message
        }
    }
}

struct TranslatorPanelSnapshot: Equatable, Sendable {
    var phase: TranslatorPanelPhase
    var sourceText: String?
    var languageSelection: TranslatorLanguageSelection?
    var translation: TranslationResult?
    var providerResults: [TranslatorProviderResult] = []
    var errorMessage: String?

    static let idle = TranslatorPanelSnapshot(
        phase: .idle,
        sourceText: nil,
        languageSelection: nil,
        translation: nil,
        providerResults: [],
        errorMessage: nil
    )
}

enum TranslatorPanelAction: Equatable, Sendable {
    case retry
    case close
    case copySource
    case copyTranslation
    case copyProviderTranslation(String)
    case speakSource
    case speakTranslation
    case openSettings
}

enum TranslatorProviderResultPhase: Equatable, Sendable {
    case waiting
    case translating
    case success
    case error
}

struct TranslatorProviderResult: Equatable, Identifiable, Sendable {
    var id: String
    var providerTitle: String
    var phase: TranslatorProviderResultPhase
    var translation: TranslationResult?
    var errorMessage: String?

    var text: String? {
        translation?.text
    }
}

struct ResolvedTranslationProvider: Sendable {
    var id: String
    var title: String
    var provider: (any TranslationProviding)?
    var errorMessage: String?

    init(
        id: String,
        title: String,
        provider: any TranslationProviding
    ) {
        self.id = id
        self.title = title
        self.provider = provider
        self.errorMessage = nil
    }

    init(
        id: String,
        title: String,
        errorMessage: String
    ) {
        self.id = id
        self.title = title
        self.provider = nil
        self.errorMessage = errorMessage
    }
}

enum TranslatorProviderBuildResult {
    case provider(any TranslationProviding)
    case providers([ResolvedTranslationProvider])
    case missing(message: String)

    var resolvedProviders: [ResolvedTranslationProvider]? {
        switch self {
        case let .provider(provider):
            return [
                ResolvedTranslationProvider(
                    id: "default",
                    title: "OpenAI 翻译",
                    provider: provider
                ),
            ]
        case let .providers(providers):
            return providers
        case .missing:
            return nil
        }
    }

    var waitingProviderResults: [TranslatorProviderResult] {
        switch self {
        case .provider:
            return [
                TranslatorProviderResult(
                    id: "default",
                    providerTitle: "OpenAI 翻译",
                    phase: .waiting,
                    translation: nil,
                    errorMessage: nil
                ),
            ]
        case let .providers(providers):
            return providers.map {
                TranslatorProviderResult(
                    id: $0.id,
                    providerTitle: $0.title,
                    phase: .waiting,
                    translation: nil,
                    errorMessage: $0.errorMessage
                )
            }
        case .missing:
            return []
        }
    }
}
