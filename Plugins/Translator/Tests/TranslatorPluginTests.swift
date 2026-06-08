import AppKit
import Carbon
import Foundation
import MacToolsPluginKit
import XCTest
@testable import TranslatorPlugin

@MainActor
final class TranslatorPluginTests: XCTestCase {
    func testMetadataMatchesManifestContract() {
        let plugin = makePlugin()

        XCTAssertEqual(plugin.metadata.id, "translator")
        XCTAssertEqual(plugin.metadata.title, "翻译")
        XCTAssertEqual(plugin.metadata.defaultDescription, "划词与截图快捷键翻译")
        XCTAssertNotNil(plugin.primaryPanel)
        XCTAssertNotNil(plugin.configuration)
    }

    func testShortcutDefinitionsIncludeSelectAndScreenshotTranslation() throws {
        let plugin = makePlugin()
        let definitions = plugin.shortcutDefinitions
        let select = try XCTUnwrap(definitions.first { $0.id == "translator.select-translation" })
        let screenshot = try XCTUnwrap(definitions.first { $0.id == "translator.screenshot-translation" })

        XCTAssertEqual(definitions.count, 2)
        XCTAssertEqual(select.title, "划词翻译")
        XCTAssertEqual(select.description, "翻译当前选中的文本。")
        XCTAssertEqual(select.actionID, "select-translation")
        XCTAssertEqual(select.scope, .global)
        XCTAssertEqual(select.defaultBinding?.keyCode, UInt16(kVK_ANSI_D))
        XCTAssertEqual(select.defaultBinding?.modifiers, [.option])
        XCTAssertFalse(select.isRequired)

        XCTAssertEqual(screenshot.title, "截图翻译")
        XCTAssertEqual(screenshot.description, "框选截图区域并翻译识别出的文字。")
        XCTAssertEqual(screenshot.actionID, "screenshot-translation")
        XCTAssertEqual(screenshot.scope, .global)
        XCTAssertEqual(screenshot.defaultBinding?.keyCode, UInt16(kVK_ANSI_S))
        XCTAssertEqual(screenshot.defaultBinding?.modifiers, [.option])
        XCTAssertFalse(screenshot.isRequired)
    }

    func testDeclaresAccessibilityAutomationAndScreenRecordingPermissions() {
        let plugin = makePlugin()
        let requirements = plugin.permissionRequirements

        XCTAssertEqual(requirements.map(\.id), ["accessibility", "automation", "screen-recording"])
        XCTAssertEqual(requirements.map(\.kind), [.accessibility, .automation, .screenRecording])
        XCTAssertEqual(requirements.map(\.title), ["辅助功能授权", "自动化授权", "屏幕录制授权"])
        XCTAssertEqual(
            requirements.map(\.description),
            [
                "划词翻译需要读取当前选中文本。",
                "浏览器划词可能需要允许 MacTools 控制当前浏览器。",
                "截图翻译需要读取框选区域的屏幕内容。",
            ]
        )
    }

    func testAutomationPermissionStateUsesOnDemandGuidance() {
        let plugin = makePlugin()
        let state = plugin.permissionState(for: "automation")

        XCTAssertTrue(state.isGranted)
        XCTAssertEqual(state.footnote, "macOS 会在首次控制浏览器时请求自动化授权。")
        XCTAssertEqual(state.statusText, "按需确认")
        XCTAssertEqual(state.statusSystemImage, "sparkles")
        XCTAssertEqual(state.statusTone, .neutral)
    }

    func testAccessibilityPermissionStateUsesDeniedGuidance() {
        let plugin = makePlugin(accessibilityTrustProvider: { false })
        let state = plugin.permissionState(for: "accessibility")

        XCTAssertFalse(state.isGranted)
        XCTAssertEqual(state.footnote, "前往系统设置 → 隐私与安全性 → 辅助功能，授权 MacTools。")
    }

    func testAccessibilityPermissionActionRequestsTrustAndNotifies() {
        var requestedPrompt: Bool?
        let plugin = makePlugin(accessibilityTrustRequester: { prompt in
            requestedPrompt = prompt
            return true
        })
        var didNotify = false
        plugin.onStateChange = { didNotify = true }

        plugin.handlePermissionAction(id: "accessibility")

        XCTAssertEqual(requestedPrompt, true)
        XCTAssertTrue(didNotify)
    }

    func testPrimaryPanelShowsSetupSubtitleAfterOpenAIKeyIsKnownMissing() {
        let storage = TranslatorInMemoryPluginStorage()
        let secretStore = CountingTranslatorSecretStore(apiKey: nil)
        let plugin = makePlugin(
            storage: storage,
            accessibilityTrustProvider: { true },
            secretStore: secretStore
        )
        let configuration = OpenAICompatibleConfiguration(
            baseURL: "https://gateway.example.com",
            model: "gpt-test",
            promptTemplate: "{{text}}"
        )

        let message = plugin.saveConfiguration(
            configuration,
            apiKey: "",
            languagePair: TranslatorLanguagePair(first: .english, second: .simplifiedChinese)
        )
        let state = plugin.primaryPanelState

        XCTAssertEqual(message, "API Key 不能为空。")
        XCTAssertTrue(state.isVisible)
        XCTAssertTrue(state.isEnabled)
        XCTAssertTrue(state.isOn)
        XCTAssertEqual(state.subtitle, "需要配置翻译服务")
    }

    func testPrimaryPanelDoesNotClaimOpenAIIsMissingBeforeAPIKeyStateIsKnown() {
        let secretStore = CountingTranslatorSecretStore(apiKey: "sk-cached")
        let plugin = makePlugin(accessibilityTrustProvider: { true }, secretStore: secretStore)
        let state = plugin.primaryPanelState

        XCTAssertEqual(secretStore.loadCount, 0)
        XCTAssertEqual(secretStore.containsCount, 0)
        XCTAssertEqual(state.subtitle, "按 ⌥D 划词，⌥S 截图")
    }

    func testPrimaryPanelShowsAccessibilitySubtitleBeforeOpenAISetupWhenPermissionIsMissing() {
        let storage = TranslatorInMemoryPluginStorage()
        let plugin = makePlugin(storage: storage, accessibilityTrustProvider: { false })

        XCTAssertEqual(plugin.primaryPanelState.subtitle, "启用前需要辅助功能授权")
    }

    func testWhitespaceOnlyAPIKeyShowsSetupSubtitleAfterProviderBuild() async {
        let secretStore = CountingTranslatorSecretStore(apiKey: "   \n\t  ")
        let capture = DeferredSelectedTextCapture(
            result: SelectedTextCaptureResult(
                text: "hello",
                strategyID: .accessibility,
                isEditable: false,
                sourceApplicationBundleID: "com.example.app",
                failureReason: nil
            )
        )
        let plugin = makePlugin(
            secretStore: secretStore,
            selectedTextCapturePipeline: SelectedTextCapturePipeline(strategies: [capture])
        )

        plugin.handleShortcutAction(id: "select-translation")
        await capture.waitUntilStarted()
        capture.resume()
        await capture.waitUntilCompleted()

        XCTAssertEqual(plugin.primaryPanelState.subtitle, "需要配置翻译服务")
    }

    func testShortcutNotifiesHostWhenLazyAPIKeyLoadFindsMissingKey() async {
        let secretStore = CountingTranslatorSecretStore(apiKey: nil)
        let capture = DeferredSelectedTextCapture(
            result: SelectedTextCaptureResult(
                text: "hello",
                strategyID: .accessibility,
                isEditable: false,
                sourceApplicationBundleID: "com.example.app",
                failureReason: nil
            )
        )
        let plugin = makePlugin(
            secretStore: secretStore,
            selectedTextCapturePipeline: SelectedTextCapturePipeline(strategies: [capture])
        )
        var notificationCount = 0
        plugin.onStateChange = {
            notificationCount += 1
        }

        plugin.handleShortcutAction(id: "select-translation")
        await capture.waitUntilStarted()
        capture.resume()
        await capture.waitUntilCompleted()

        XCTAssertEqual(notificationCount, 1)
        XCTAssertEqual(plugin.primaryPanelState.subtitle, "需要配置翻译服务")
    }

    func testPanelControllerClampsRestoredFrameIntoVisibleScreen() throws {
        _ = NSApplication.shared
        closeTranslatorPanels()
        defer { closeTranslatorPanels() }

        let controller = TranslatorPanelController()
        controller.show(snapshot: .idle)
        let panel = try XCTUnwrap(translatorPanel())
        let allVisibleFrames = NSScreen.screens.map(\.visibleFrame)
        let visibleFrameUnion = allVisibleFrames.reduce(NSRect.null) { partialResult, frame in
            partialResult.union(frame)
        }
        let offscreenFrame = NSRect(
            x: visibleFrameUnion.maxX + 1_000,
            y: visibleFrameUnion.maxY + 1_000,
            width: panel.frame.width,
            height: panel.frame.height
        )

        panel.setFrame(offscreenFrame, display: false)
        controller.close()
        controller.show(snapshot: .idle)

        let restoredVisibleFrame = try XCTUnwrap((panel.screen ?? NSScreen.main)?.visibleFrame)
        XCTAssertGreaterThanOrEqual(panel.frame.minX, restoredVisibleFrame.minX)
        XCTAssertLessThanOrEqual(panel.frame.maxX, restoredVisibleFrame.maxX)
        XCTAssertGreaterThanOrEqual(panel.frame.minY, restoredVisibleFrame.minY)
        XCTAssertLessThanOrEqual(panel.frame.maxY, restoredVisibleFrame.maxY)
    }

    func testConfigurationViewDoesNotLoadAPIKeyFromKeychain() throws {
        let secretStore = CountingTranslatorSecretStore(apiKey: "sk-cached")
        let plugin = makePlugin(secretStore: secretStore)

        XCTAssertEqual(secretStore.loadCount, 0)

        let configuration = try XCTUnwrap(plugin.configuration)

        _ = configuration.makeView(PluginConfigurationContext(pluginID: "translator"))
        _ = configuration.makeView(PluginConfigurationContext(pluginID: "translator"))

        XCTAssertEqual(secretStore.loadCount, 0)
    }

    func testShortcutLoadsAPIKeyOnlyWhenBuildingProvider() async {
        let secretStore = CountingTranslatorSecretStore(apiKey: "sk-cached")
        let capture = DeferredSelectedTextCapture(
            result: SelectedTextCaptureResult(
                text: "hello",
                strategyID: .accessibility,
                isEditable: false,
                sourceApplicationBundleID: "com.example.app",
                failureReason: nil
            )
        )
        let panelController = RecordingTranslatorPanelController()
        let plugin = makePlugin(
            secretStore: secretStore,
            panelController: panelController,
            selectedTextCapturePipeline: SelectedTextCapturePipeline(strategies: [capture])
        )

        XCTAssertEqual(secretStore.loadCount, 0)

        plugin.handleShortcutAction(id: "select-translation")
        await capture.waitUntilStarted()
        capture.resume()
        await capture.waitUntilCompleted()

        // 默认 profile 未命中 profile 密钥时回退读取 legacy 单密钥，故加载两次存储项。
        XCTAssertEqual(secretStore.loadCount, 2)
    }

    func testSavingBlankAPIKeyWithoutExistingKeyReturnsConfigurationError() {
        let secretStore = CountingTranslatorSecretStore(apiKey: nil)
        let plugin = makePlugin(secretStore: secretStore)
        let configuration = OpenAICompatibleConfiguration(
            baseURL: "https://gateway.example.com",
            model: "gpt-test",
            promptTemplate: "{{text}}"
        )

        let message = plugin.saveConfiguration(
            configuration,
            apiKey: "  ",
            languagePair: TranslatorLanguagePair(first: .english, second: .simplifiedChinese)
        )

        XCTAssertEqual(message, "API Key 不能为空。")
        XCTAssertEqual(secretStore.saveCount, 0)
    }

    func testSavingBlankAPIKeyPreservesExistingKeyWithoutLoadingSecretValue() {
        let secretStore = CountingTranslatorSecretStore(apiKey: "sk-cached")
        let plugin = makePlugin(secretStore: secretStore)
        let configuration = OpenAICompatibleConfiguration(
            baseURL: "https://gateway.example.com",
            model: "gpt-test",
            promptTemplate: "{{text}}"
        )

        let message = plugin.saveConfiguration(
            configuration,
            apiKey: "  ",
            languagePair: TranslatorLanguagePair(first: .english, second: .simplifiedChinese)
        )

        XCTAssertNil(message)
        XCTAssertEqual(secretStore.loadCount, 0)
        // 先检查 profile 密钥是否存在，未命中再回退检查 legacy 单密钥，故存在性检查两次。
        XCTAssertEqual(secretStore.containsCount, 2)
        XCTAssertEqual(secretStore.saveCount, 0)
        XCTAssertEqual(plugin.primaryPanelState.subtitle, "按 ⌥D 划词，⌥S 截图")
    }

    func testSavingProfilesDeletesKeychainEntriesForRemovedProfiles() {
        let secretStore = CountingTranslatorSecretStore(apiKey: nil)
        let plugin = makePlugin(secretStore: secretStore)
        let first = TranslatorProviderProfile(id: "openai", name: "OpenAI")
        let second = TranslatorProviderProfile(id: "second", name: "Second")
        let languagePair = TranslatorLanguagePair(first: .english, second: .simplifiedChinese)

        XCTAssertNil(plugin.saveConfiguration(
            profiles: [first, second],
            apiKeys: [first.id: "sk-1", second.id: "sk-2"],
            languagePair: languagePair
        ))

        // 第二次保存移除了 second，应清理它残留的 Keychain 凭据。
        XCTAssertNil(plugin.saveConfiguration(
            profiles: [first],
            apiKeys: [first.id: "sk-1"],
            languagePair: languagePair
        ))

        XCTAssertEqual(secretStore.deletedProfileIDs, ["second"])
    }

    func testAPIKeyStatePresentWhenOneEnabledProfileHealthyAndAnotherMissesKey() async {
        let storage = TranslatorInMemoryPluginStorage()
        let healthy = TranslatorProviderProfile(id: "openai", name: "OpenAI")
        let missing = TranslatorProviderProfile(id: "second", name: "Second")
        try? TranslatorProviderProfileStore(storage: storage).saveProfiles([healthy, missing])

        let secretStore = CountingTranslatorSecretStore(apiKey: nil)
        // 仅 healthy profile 有可用密钥，missing profile 缺密钥。
        try? secretStore.saveAPIKey("sk-1", forProfileID: healthy.id)

        let capture = DeferredSelectedTextCapture(
            result: SelectedTextCaptureResult(
                text: "hello",
                strategyID: .accessibility,
                isEditable: false,
                sourceApplicationBundleID: "com.example.app",
                failureReason: nil
            )
        )
        let plugin = makePlugin(
            storage: storage,
            secretStore: secretStore,
            selectedTextCapturePipeline: SelectedTextCapturePipeline(strategies: [capture])
        )

        plugin.handleShortcutAction(id: "select-translation")
        await capture.waitUntilStarted()
        capture.resume()
        await capture.waitUntilCompleted()

        // 存在一个可用 provider，整体状态应保持可用，而非被缺密钥的 profile 拉成 missing。
        XCTAssertEqual(plugin.primaryPanelState.subtitle, "按 ⌥D 划词，⌥S 截图")
    }

    func testPrimaryPanelTogglePersistsDisabledStateAndNotifies() {
        let storage = TranslatorInMemoryPluginStorage()
        let plugin = makePlugin(storage: storage)
        var didNotify = false
        plugin.onStateChange = { didNotify = true }

        plugin.handleAction(.setSwitch(false))

        XCTAssertTrue(didNotify)
        XCTAssertFalse(plugin.primaryPanelState.isOn)
        XCTAssertEqual(plugin.primaryPanelState.subtitle, "快捷键已暂停")
        XCTAssertEqual(storage.bool(forKey: "translator.shortcut.enabled"), false)

        let reloadedPlugin = makePlugin(storage: storage)
        XCTAssertFalse(reloadedPlugin.primaryPanelState.isOn)
        XCTAssertEqual(reloadedPlugin.primaryPanelState.subtitle, "快捷键已暂停")
    }

    func testShortcutActionStartsSelectTranslationWhenEnabled() {
        let storage = TranslatorInMemoryPluginStorage()
        let plugin = makePlugin(storage: storage, selectTranslationStarter: {
            storage.set(true, forKey: "handler.invoked")
        })

        plugin.handleShortcutAction(id: "select-translation")

        XCTAssertTrue(storage.bool(forKey: "handler.invoked"))
    }

    func testShortcutActionStartsScreenshotTranslationWhenEnabled() {
        let storage = TranslatorInMemoryPluginStorage()
        let plugin = makePlugin(storage: storage, screenshotTranslationStarter: {
            storage.set(true, forKey: "screenshot.invoked")
        })

        plugin.handleShortcutAction(id: "screenshot-translation")

        XCTAssertTrue(storage.bool(forKey: "screenshot.invoked"))
    }

    func testScreenshotShortcutUsesPluginScreenRecordingPermissionProvider() async {
        let storage = TranslatorInMemoryPluginStorage()
        let screenshotCapturer = RecordingPluginScreenshotRegionCapturer(
            permissionProvider: { true },
            result: .failure(.cancelled)
        )
        let plugin = makePlugin(
            storage: storage,
            screenRecordingPermissionProvider: { false },
            screenshotRegionCapturerFactory: { permissionProvider in
                screenshotCapturer.permissionProvider = permissionProvider
                return screenshotCapturer
            },
            translationProviderFactoryOverride: {
                .provider(RecordingTranslationProvider(resultText: "unused"))
            }
        )

        plugin.handleShortcutAction(id: "screenshot-translation")
        await screenshotCapturer.waitUntilCaptureCount(1)

        XCTAssertEqual(screenshotCapturer.permissionChecks, [false])
    }

    func testShortcutActionDoesNotStartSelectTranslationWhenDisabled() {
        let storage = TranslatorInMemoryPluginStorage()
        storage.set(false, forKey: "translator.shortcut.enabled")
        let plugin = makePlugin(storage: storage, selectTranslationStarter: {
            storage.set(true, forKey: "handler.invoked")
        })

        plugin.handleShortcutAction(id: "select-translation")

        XCTAssertFalse(storage.bool(forKey: "handler.invoked"))
    }

    func testShortcutActionDoesNotStartSelectTranslationForWrongActionID() {
        let storage = TranslatorInMemoryPluginStorage()
        let plugin = makePlugin(storage: storage, selectTranslationStarter: {
            storage.set(true, forKey: "handler.invoked")
        })

        plugin.handleShortcutAction(id: "unexpected")

        XCTAssertFalse(storage.bool(forKey: "handler.invoked"))
    }

    func testShortcutActionStillStartsCapturePipelineWhenAccessibilityIsDenied() {
        let storage = TranslatorInMemoryPluginStorage()
        let plugin = makePlugin(
            storage: storage,
            accessibilityTrustProvider: { false },
            selectTranslationStarter: {
                storage.set(true, forKey: "handler.invoked")
            }
        )

        plugin.handleShortcutAction(id: "select-translation")

        XCTAssertTrue(storage.bool(forKey: "handler.invoked"))
    }

    func testAutomationPermissionActionRequestsGuidanceAndNotifies() {
        let plugin = makePlugin()
        var requestedPermissionID: String?
        plugin.requestPermissionGuidance = { requestedPermissionID = $0 }
        var didNotify = false
        plugin.onStateChange = { didNotify = true }

        plugin.handlePermissionAction(id: "automation")

        XCTAssertEqual(requestedPermissionID, "automation")
        XCTAssertTrue(didNotify)
    }

    func testSavingConfigurationClosesExistingPanelBeforeDroppingCoordinator() {
        let panelController = RecordingTranslatorPanelController()
        let plugin = makePlugin(panelController: panelController)
        let configuration = OpenAICompatibleConfiguration(
            baseURL: "https://gateway.example.com",
            model: "gpt-test",
            promptTemplate: "{{text}}"
        )

        let message = plugin.saveConfiguration(
            configuration,
            apiKey: "sk-test",
            languagePair: TranslatorLanguagePair(first: .english, second: .simplifiedChinese)
        )

        XCTAssertNil(message)
        XCTAssertTrue(panelController.didClose)
    }

    func testSavingConfigurationDuringPendingCapturePreventsProviderInvocation() async {
        let capture = DeferredSelectedTextCapture(
            result: SelectedTextCaptureResult(
                text: "hello",
                strategyID: .accessibility,
                isEditable: false,
                sourceApplicationBundleID: "com.example.app",
                failureReason: nil
            )
        )
        let provider = RecordingTranslationProvider(resultText: "你好")
        let panelController = RecordingTranslatorPanelController()
        let plugin = makePlugin(
            panelController: panelController,
            selectedTextCapturePipeline: SelectedTextCapturePipeline(strategies: [capture]),
            translationProviderFactoryOverride: { .provider(provider) }
        )
        let configuration = OpenAICompatibleConfiguration(
            baseURL: "https://gateway.example.com",
            model: "gpt-test",
            promptTemplate: "{{text}}"
        )

        plugin.handleShortcutAction(id: "select-translation")
        await capture.waitUntilStarted()

        let message = plugin.saveConfiguration(
            configuration,
            apiKey: "sk-test",
            languagePair: TranslatorLanguagePair(first: .english, second: .simplifiedChinese)
        )
        capture.resume()
        await capture.waitUntilCompleted()

        XCTAssertNil(message)
        XCTAssertTrue(panelController.didClose)
        XCTAssertTrue(provider.requests.isEmpty)
    }

    func testPanelCloseActionClosesPanelEvenWithoutCoordinator() {
        let panelController = RecordingTranslatorPanelController()
        let plugin = makePlugin(panelController: panelController)

        panelController.onAction?(.close)

        XCTAssertTrue(panelController.didClose)
        withExtendedLifetime(plugin) {}
    }

    func testPanelOpenSettingsRequestsConfigurationPresentation() {
        let panelController = RecordingTranslatorPanelController()
        let plugin = makePlugin(panelController: panelController)
        var didRequestPresentation = false
        plugin.requestConfigurationPresentation = { didRequestPresentation = true }

        panelController.onAction?(.openSettings)

        XCTAssertTrue(didRequestPresentation)
    }

    func testPanelCloseActionDuringPendingCapturePreventsProviderInvocation() async {
        let capture = DeferredSelectedTextCapture(
            result: SelectedTextCaptureResult(
                text: "hello",
                strategyID: .accessibility,
                isEditable: false,
                sourceApplicationBundleID: "com.example.app",
                failureReason: nil
            )
        )
        let provider = RecordingTranslationProvider(resultText: "你好")
        let panelController = RecordingTranslatorPanelController()
        let plugin = makePlugin(
            panelController: panelController,
            selectedTextCapturePipeline: SelectedTextCapturePipeline(strategies: [capture]),
            translationProviderFactoryOverride: { .provider(provider) }
        )

        plugin.handleShortcutAction(id: "select-translation")
        await capture.waitUntilStarted()

        panelController.onAction?(.close)
        capture.resume()
        await capture.waitUntilCompleted()

        XCTAssertTrue(panelController.didClose)
        XCTAssertTrue(provider.requests.isEmpty)
    }

    func testDeactivateClosesPanelAndCancelsPendingTranslation() async {
        let capture = DeferredSelectedTextCapture(
            result: SelectedTextCaptureResult(
                text: "hello",
                strategyID: .accessibility,
                isEditable: false,
                sourceApplicationBundleID: "com.example.app",
                failureReason: nil
            )
        )
        let provider = RecordingTranslationProvider(resultText: "你好")
        let panelController = RecordingTranslatorPanelController()
        let plugin = makePlugin(
            panelController: panelController,
            selectedTextCapturePipeline: SelectedTextCapturePipeline(strategies: [capture]),
            translationProviderFactoryOverride: { .provider(provider) }
        )

        plugin.handleShortcutAction(id: "select-translation")
        await capture.waitUntilStarted()

        plugin.deactivate(reason: .disabled)
        capture.resume()
        await capture.waitUntilCompleted()

        XCTAssertTrue(panelController.didClose)
        XCTAssertTrue(provider.requests.isEmpty)
    }

    func testSavingIdenticalLanguagePairDoesNotPersistProviderOrLanguageData() {
        let storage = TranslatorInMemoryPluginStorage()
        let plugin = makePlugin(storage: storage)
        let configuration = OpenAICompatibleConfiguration(
            baseURL: "https://gateway.example.com",
            model: "gpt-test",
            promptTemplate: "{{text}}"
        )

        let message = plugin.saveConfiguration(
            configuration,
            apiKey: "sk-test",
            languagePair: TranslatorLanguagePair(first: .english, second: .english)
        )

        XCTAssertEqual(message, "两种偏好语言不能相同。")
        XCTAssertNil(storage.string(forKey: "translator.openai.base-url"))
        XCTAssertNil(storage.string(forKey: "translator.openai.model"))
        XCTAssertNil(storage.string(forKey: "translator.openai.prompt-template"))
        XCTAssertNil(storage.string(forKey: "translator.language.first"))
        XCTAssertNil(storage.string(forKey: "translator.language.second"))
    }

    private func makePlugin(
        storage: TranslatorInMemoryPluginStorage? = nil,
        accessibilityTrustProvider: @escaping () -> Bool = { true },
        accessibilityTrustRequester: @escaping (Bool) -> Bool = { _ in true },
        screenRecordingPermissionProvider: @escaping () -> Bool = { true },
        selectTranslationStarter: (() -> Void)? = nil,
        screenshotTranslationStarter: (() -> Void)? = nil,
        secretStore: (any TranslatorSecretStoring)? = nil,
        panelController: (any TranslatorPanelControlling)? = nil,
        selectedTextCapturePipeline: SelectedTextCapturePipeline? = nil,
        screenshotRegionCapturerFactory: ScreenshotRegionCapturerFactory? = nil,
        translationProviderFactoryOverride: TranslatorProviderFactory? = nil
    ) -> TranslatorPlugin {
        let storage = storage ?? TranslatorInMemoryPluginStorage()

        return TranslatorPlugin(
            context: PluginRuntimeContext(pluginID: "translator", storage: storage),
            accessibilityTrustProvider: accessibilityTrustProvider,
            accessibilityTrustRequester: accessibilityTrustRequester,
            screenRecordingPermissionProvider: screenRecordingPermissionProvider,
            selectTranslationStarter: selectTranslationStarter,
            screenshotTranslationStarter: screenshotTranslationStarter,
            secretStore: secretStore ?? OpenAICompatibleSecretStore(service: uniqueTestKeychainService()),
            panelController: panelController ?? TranslatorPanelController(),
            selectedTextCapturePipeline: selectedTextCapturePipeline ?? .live(),
            screenshotRegionCapturerFactory: screenshotRegionCapturerFactory,
            translationProviderFactoryOverride: translationProviderFactoryOverride
        )
    }

    private func uniqueTestKeychainService() -> String {
        "cc.ggbond.mactools.translator.tests.plugin.\(UUID().uuidString)"
    }

    private func translatorPanel() -> TranslatorPanelWindow? {
        NSApp.windows.compactMap { $0 as? TranslatorPanelWindow }.last
    }

    private func closeTranslatorPanels() {
        for panel in NSApp.windows.compactMap({ $0 as? TranslatorPanelWindow }) {
            panel.performProgrammaticClose {
                panel.close()
            }
        }
    }
}

private final class CountingTranslatorSecretStore: TranslatorSecretStoring, @unchecked Sendable {
    private var apiKey: String?
    private var profileAPIKeys: [String: String] = [:]
    private(set) var loadCount = 0
    private(set) var containsCount = 0
    private(set) var saveCount = 0
    private(set) var deletedProfileIDs: [String] = []

    init(apiKey: String?) {
        self.apiKey = apiKey
    }

    func containsAPIKey() throws -> Bool {
        containsCount += 1
        return apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    func containsAPIKey(forProfileID profileID: String) throws -> Bool {
        containsCount += 1
        return profileAPIKeys[profileID]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    func loadAPIKey() throws -> String? {
        loadCount += 1
        return apiKey
    }

    func loadAPIKey(forProfileID profileID: String) throws -> String? {
        loadCount += 1
        return profileAPIKeys[profileID]
    }

    func saveAPIKey(_ apiKey: String) throws {
        saveCount += 1
        self.apiKey = apiKey
    }

    func saveAPIKey(_ apiKey: String, forProfileID profileID: String) throws {
        saveCount += 1
        profileAPIKeys[profileID] = apiKey
    }

    func deleteAPIKey() throws {
        apiKey = nil
    }

    func deleteAPIKey(forProfileID profileID: String) throws {
        deletedProfileIDs.append(profileID)
        profileAPIKeys.removeValue(forKey: profileID)
    }
}

@MainActor
private final class RecordingPluginScreenshotRegionCapturer: ScreenshotRegionCapturing {
    var permissionProvider: () -> Bool
    var result: ScreenshotCaptureResult
    private(set) var permissionChecks: [Bool] = []
    private(set) var captureCount = 0
    private var captureCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(
        permissionProvider: @escaping () -> Bool,
        result: ScreenshotCaptureResult
    ) {
        self.permissionProvider = permissionProvider
        self.result = result
    }

    func captureRegion() async -> ScreenshotCaptureResult {
        captureCount += 1
        permissionChecks.append(permissionProvider())
        resumeCaptureCountWaiters()
        return result
    }

    func waitUntilCaptureCount(_ expectedCount: Int) async {
        if captureCount >= expectedCount { return }

        await withCheckedContinuation { continuation in
            captureCountWaiters.append((expectedCount, continuation))
        }
    }

    private func resumeCaptureCountWaiters() {
        let matching = captureCountWaiters.filter { captureCount >= $0.0 }
        captureCountWaiters.removeAll { captureCount >= $0.0 }
        matching.forEach { $0.1.resume() }
    }
}

@MainActor
private final class RecordingTranslatorPanelController: TranslatorPanelControlling {
    var onAction: ((TranslatorPanelAction) -> Void)?
    private(set) var shownSnapshots: [TranslatorPanelSnapshot] = []
    private(set) var updatedSnapshots: [TranslatorPanelSnapshot] = []
    private(set) var didClose = false

    func show(snapshot: TranslatorPanelSnapshot) {
        shownSnapshots.append(snapshot)
    }

    func update(snapshot: TranslatorPanelSnapshot) {
        updatedSnapshots.append(snapshot)
    }

    func close() {
        didClose = true
    }
}

@MainActor
private final class DeferredSelectedTextCapture: SelectedTextCapturing {
    let strategyID: SelectedTextCaptureStrategyID
    let result: SelectedTextCaptureResult
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var completedContinuation: CheckedContinuation<Void, Never>?
    private var resultContinuation: CheckedContinuation<SelectedTextCaptureResult, Never>?
    private var didStart = false
    private var didComplete = false

    init(
        strategyID: SelectedTextCaptureStrategyID = .accessibility,
        result: SelectedTextCaptureResult
    ) {
        self.strategyID = strategyID
        self.result = result
    }

    func capture(context: SelectedTextCaptureContext) async -> SelectedTextCaptureResult {
        didStart = true
        startedContinuation?.resume()
        startedContinuation = nil

        let result = await withCheckedContinuation { continuation in
            resultContinuation = continuation
        }
        didComplete = true
        completedContinuation?.resume()
        completedContinuation = nil
        return result
    }

    func waitUntilStarted() async {
        if didStart { return }

        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func resume() {
        resultContinuation?.resume(returning: result)
        resultContinuation = nil
    }

    func waitUntilCompleted() async {
        if didComplete { return }

        await withCheckedContinuation { continuation in
            completedContinuation = continuation
        }
    }
}

private final class RecordingTranslationProvider: TranslationProviding, @unchecked Sendable {
    var resultText: String
    private(set) var requests: [String] = []

    init(resultText: String) {
        self.resultText = resultText
    }

    func translate(
        text: String,
        languageSelection: TranslatorLanguageSelection
    ) async throws -> TranslationResult {
        requests.append(text)
        return TranslationResult(
            providerTitle: "测试翻译",
            text: resultText,
            sourceText: text,
            languageSelection: languageSelection
        )
    }
}
