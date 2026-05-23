import Foundation
import SwiftUI

public struct PluginMetadata: Identifiable {
    public let id: String
    public let title: String
    public let iconName: String
    public let iconTint: Color
    public let order: Int
    public let defaultDescription: String

    public init(
        id: String,
        title: String,
        iconName: String,
        iconTint: Color,
        order: Int,
        defaultDescription: String
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.iconTint = iconTint
        self.order = order
        self.defaultDescription = defaultDescription
    }
}

public enum PluginControlStyle {
    case `switch`
    case disclosure
    case button
}

public enum PluginPanelAction: Equatable {
    public enum SliderPhase: Equatable {
        case changed
        case ended
    }

    case setSwitch(Bool)
    case setDisclosureExpanded(Bool)
    case setSelection(controlID: String, optionID: String)
    case setNavigationSelection(controlID: String, optionID: String)
    case clearNavigationSelection(controlID: String)
    case setDate(controlID: String, value: Date)
    case setSlider(controlID: String, value: Double, phase: SliderPhase)
    case invokeAction(controlID: String)
}

public enum PluginPanelDescriptionTone {
    case secondary
    case error
}

public enum PluginMenuActionBehavior {
    case keepPresented
    case dismissBeforeHandling
}

public enum PluginStatusTone {
    case neutral
    case positive
    case caution
}

public enum PluginPermissionKind {
    case accessibility
    case calendarFullAccess
    case automation
}

public enum SettingsDestination: Hashable {
    case general
    case pluginConfiguration
    case about
}

public enum PluginDeactivationReason: Equatable {
    case disabled
    case uninstalling
    case updating
    case hostShutdown

    /// `true` when the plugin should revert any external side-effects it owns
    /// (user disabled, plugin uninstalled, or app is quitting).
    /// `false` during hot-reload updates — the new version will re-activate.
    public var requiresStateCleanup: Bool {
        switch self {
        case .disabled, .uninstalling, .hostShutdown: true
        case .updating: false
        }
    }
}

public struct PluginConfigurationContext {
    public let pluginID: String

    public init(pluginID: String) {
        self.pluginID = pluginID
    }
}

public struct PluginConfiguration {
    public let description: String?
    public let prefersFullHeight: Bool
    public let makeView: (PluginConfigurationContext) -> AnyView

    public init<Content: View>(
        description: String? = nil,
        prefersFullHeight: Bool,
        @ViewBuilder content: @escaping (PluginConfigurationContext) -> Content
    ) {
        self.description = description
        self.prefersFullHeight = prefersFullHeight
        self.makeView = { context in
            AnyView(content(context))
        }
    }

    public init<Content: View>(
        description: String? = nil,
        @ViewBuilder content: @escaping (PluginConfigurationContext) -> Content
    ) {
        self.init(
            description: description,
            prefersFullHeight: false,
            content: content
        )
    }
}

public struct PluginPrimaryPanelDescriptor {
    public let controlStyle: PluginControlStyle
    public let menuActionBehavior: PluginMenuActionBehavior
    public let buttonTitle: String?

    public init(
        controlStyle: PluginControlStyle,
        menuActionBehavior: PluginMenuActionBehavior,
        buttonTitle: String? = nil
    ) {
        self.controlStyle = controlStyle
        self.menuActionBehavior = menuActionBehavior
        self.buttonTitle = buttonTitle
    }
}

public struct PluginComponentSpan: Equatable, Hashable, Sendable {
    public static let maximumWidth = 4

    public let width: Int
    public let height: Int

    public init?(width: Int, height: Int) {
        guard Self.isValid(width: width, height: height) else {
            return nil
        }

        self.width = width
        self.height = height
    }

    private init(uncheckedWidth width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public static let oneByOne = PluginComponentSpan(uncheckedWidth: 1, height: 1)
    public static let oneByTwo = PluginComponentSpan(uncheckedWidth: 1, height: 2)
    public static let twoByOne = PluginComponentSpan(uncheckedWidth: 2, height: 1)
    public static let twoByTwo = PluginComponentSpan(uncheckedWidth: 2, height: 2)
    public static let fourByTwo = PluginComponentSpan(uncheckedWidth: 4, height: 2)

    public static func isValid(width: Int, height: Int) -> Bool {
        (1...maximumWidth).contains(width) && height >= 1
    }
}

public struct PluginComponentDescriptor {
    public let span: PluginComponentSpan

    public init(span: PluginComponentSpan) {
        self.span = span
    }
}

public struct PluginComponentState {
    public let subtitle: String
    public let isActive: Bool
    public let isEnabled: Bool
    public let isVisible: Bool
    public let errorMessage: String?

    public init(
        subtitle: String,
        isActive: Bool,
        isEnabled: Bool,
        isVisible: Bool,
        errorMessage: String?
    ) {
        self.subtitle = subtitle
        self.isActive = isActive
        self.isEnabled = isEnabled
        self.isVisible = isVisible
        self.errorMessage = errorMessage
    }
}

public struct PluginComponentContext {
    public let pluginID: String
    public let dismiss: () -> Void
    public let isPanelVisible: Bool

    public init(pluginID: String, dismiss: @escaping () -> Void, isPanelVisible: Bool) {
        self.pluginID = pluginID
        self.dismiss = dismiss
        self.isPanelVisible = isPanelVisible
    }
}

public struct PluginComponentViewItem: Identifiable {
    public let id: String
    public let content: AnyView

    public init(id: String, content: AnyView) {
        self.id = id
        self.content = content
    }
}

public struct PluginComponentItem: Identifiable {
    public let id: String
    public let title: String
    public let iconName: String
    public let iconTint: Color
    public let description: String
    public let helpText: String
    public let descriptionTone: PluginPanelDescriptionTone
    public let span: PluginComponentSpan
    public let isActive: Bool
    public let isEnabled: Bool

    public init(
        id: String,
        title: String,
        iconName: String,
        iconTint: Color,
        description: String,
        helpText: String,
        descriptionTone: PluginPanelDescriptionTone,
        span: PluginComponentSpan,
        isActive: Bool,
        isEnabled: Bool
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.iconTint = iconTint
        self.description = description
        self.helpText = helpText
        self.descriptionTone = descriptionTone
        self.span = span
        self.isActive = isActive
        self.isEnabled = isEnabled
    }
}

public struct PluginPanelState {
    public let subtitle: String
    public let isOn: Bool
    public let isExpanded: Bool
    public let isEnabled: Bool
    public let isVisible: Bool
    public let detail: PluginPanelDetail?
    public let errorMessage: String?

    public init(
        subtitle: String,
        isOn: Bool,
        isExpanded: Bool,
        isEnabled: Bool,
        isVisible: Bool,
        detail: PluginPanelDetail?,
        errorMessage: String?
    ) {
        self.subtitle = subtitle
        self.isOn = isOn
        self.isExpanded = isExpanded
        self.isEnabled = isEnabled
        self.isVisible = isVisible
        self.detail = detail
        self.errorMessage = errorMessage
    }
}

public enum PluginPanelControlKind {
    case segmented
    case datePicker
    case selectList
    case navigationList
    case slider
    case actionRow
}

public enum PluginPanelDatePickerStyle {
    case compact
    case dateTimeCard
}

public struct PluginPanelControlOption: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String?

    public init(id: String, title: String, subtitle: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }
}

public struct PluginPanelControl: Identifiable {
    public let id: String
    public let kind: PluginPanelControlKind
    public let options: [PluginPanelControlOption]
    public let selectedOptionID: String?
    public let dateValue: Date?
    public let minimumDate: Date?
    public let displayedComponents: DatePickerComponents?
    public let datePickerStyle: PluginPanelDatePickerStyle?
    public let sectionTitle: String?
    public let sliderValue: Double?
    public let sliderBounds: ClosedRange<Double>?
    public let sliderStep: Double?
    public let valueLabel: String?
    public let actionTitle: String?
    public let actionIconSystemName: String?
    public let actionBehavior: PluginMenuActionBehavior
    public let showsLeadingDivider: Bool
    public let isEnabled: Bool

    public init(
        id: String,
        kind: PluginPanelControlKind,
        options: [PluginPanelControlOption],
        selectedOptionID: String?,
        dateValue: Date?,
        minimumDate: Date?,
        displayedComponents: DatePickerComponents?,
        datePickerStyle: PluginPanelDatePickerStyle?,
        sectionTitle: String?,
        sliderValue: Double? = nil,
        sliderBounds: ClosedRange<Double>? = nil,
        sliderStep: Double? = nil,
        valueLabel: String? = nil,
        actionTitle: String? = nil,
        actionIconSystemName: String? = nil,
        actionBehavior: PluginMenuActionBehavior = .keepPresented,
        showsLeadingDivider: Bool = false,
        isEnabled: Bool
    ) {
        self.id = id
        self.kind = kind
        self.options = options
        self.selectedOptionID = selectedOptionID
        self.dateValue = dateValue
        self.minimumDate = minimumDate
        self.displayedComponents = displayedComponents
        self.datePickerStyle = datePickerStyle
        self.sectionTitle = sectionTitle
        self.sliderValue = sliderValue
        self.sliderBounds = sliderBounds
        self.sliderStep = sliderStep
        self.valueLabel = valueLabel
        self.actionTitle = actionTitle
        self.actionIconSystemName = actionIconSystemName
        self.actionBehavior = actionBehavior
        self.showsLeadingDivider = showsLeadingDivider
        self.isEnabled = isEnabled
    }
}

public struct PluginPanelSecondaryPanel {
    public let title: String
    public let controls: [PluginPanelControl]

    public init(title: String, controls: [PluginPanelControl]) {
        self.title = title
        self.controls = controls
    }
}

public struct PluginPanelNavigationSecondaryPanel {
    public let controlID: String
    public let optionID: String
    public let panel: PluginPanelSecondaryPanel

    public init(controlID: String, optionID: String, panel: PluginPanelSecondaryPanel) {
        self.controlID = controlID
        self.optionID = optionID
        self.panel = panel
    }
}

public struct PluginPanelDetail {
    public let primaryControls: [PluginPanelControl]
    public let secondaryPanel: PluginPanelSecondaryPanel?
    public let navigationSecondaryPanels: [PluginPanelNavigationSecondaryPanel]

    public var controls: [PluginPanelControl] {
        primaryControls
    }

    public init(
        primaryControls: [PluginPanelControl],
        secondaryPanel: PluginPanelSecondaryPanel?,
        navigationSecondaryPanels: [PluginPanelNavigationSecondaryPanel] = []
    ) {
        self.primaryControls = primaryControls
        self.secondaryPanel = secondaryPanel
        self.navigationSecondaryPanels = navigationSecondaryPanels
    }

    public init(controls: [PluginPanelControl]) {
        self.init(primaryControls: controls, secondaryPanel: nil)
    }

    public func secondaryPanel(controlID: String, optionID: String) -> PluginPanelSecondaryPanel? {
        if navigationSecondaryPanels.isEmpty {
            return secondaryPanel
        }

        return navigationSecondaryPanels.first {
            $0.controlID == controlID && $0.optionID == optionID
        }?.panel
    }
}

public struct PluginPermissionRequirement: Identifiable {
    public let id: String
    public let kind: PluginPermissionKind
    public let title: String
    public let description: String

    public init(id: String, kind: PluginPermissionKind, title: String, description: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.description = description
    }
}

public struct PluginPermissionState {
    public let isGranted: Bool
    public let footnote: String?
    public let statusText: String?
    public let statusSystemImage: String?
    public let statusTone: PluginStatusTone?

    public init(
        isGranted: Bool,
        footnote: String?,
        statusText: String? = nil,
        statusSystemImage: String? = nil,
        statusTone: PluginStatusTone? = nil
    ) {
        self.isGranted = isGranted
        self.footnote = footnote
        self.statusText = statusText
        self.statusSystemImage = statusSystemImage
        self.statusTone = statusTone
    }
}

public struct PluginSettingsSection: Identifiable {
    public struct Status {
        public let text: String
        public let systemImage: String
        public let tone: PluginStatusTone

        public init(text: String, systemImage: String, tone: PluginStatusTone) {
            self.text = text
            self.systemImage = systemImage
            self.tone = tone
        }
    }

    public let id: String
    public let title: String
    public let description: String
    public let status: Status
    public let footnote: String?
    public let buttonTitle: String?
    public let actionID: String?

    public init(
        id: String,
        title: String,
        description: String,
        status: Status,
        footnote: String?,
        buttonTitle: String?,
        actionID: String?
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.status = status
        self.footnote = footnote
        self.buttonTitle = buttonTitle
        self.actionID = actionID
    }
}

public struct PluginPanelItem: Identifiable {
    public let id: String
    public let title: String
    public let iconName: String
    public let iconTint: Color
    public let controlStyle: PluginControlStyle
    public let menuActionBehavior: PluginMenuActionBehavior
    public let description: String
    public let helpText: String
    public let descriptionTone: PluginPanelDescriptionTone
    public let isOn: Bool
    public let isExpanded: Bool
    public let isEnabled: Bool
    public let detail: PluginPanelDetail?
    public let buttonActionID: String?
    public let buttonTitle: String?

    public init(
        id: String,
        title: String,
        iconName: String,
        iconTint: Color,
        controlStyle: PluginControlStyle,
        menuActionBehavior: PluginMenuActionBehavior,
        description: String,
        helpText: String,
        descriptionTone: PluginPanelDescriptionTone,
        isOn: Bool,
        isExpanded: Bool,
        isEnabled: Bool,
        detail: PluginPanelDetail?,
        buttonActionID: String?,
        buttonTitle: String?
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.iconTint = iconTint
        self.controlStyle = controlStyle
        self.menuActionBehavior = menuActionBehavior
        self.description = description
        self.helpText = helpText
        self.descriptionTone = descriptionTone
        self.isOn = isOn
        self.isExpanded = isExpanded
        self.isEnabled = isEnabled
        self.detail = detail
        self.buttonActionID = buttonActionID
        self.buttonTitle = buttonTitle
    }
}

public enum PluginFeaturePresentation: Equatable {
    case featurePanel
    case componentPanel
    case featureAndComponentPanel
}

public struct PluginFeatureManagementItem: Identifiable {
    public let id: String
    public let title: String
    public let description: String
    public let iconName: String
    public let iconTint: Color
    public let isVisible: Bool
    public let isActive: Bool
    public let presentation: PluginFeaturePresentation

    public init(
        id: String,
        title: String,
        description: String,
        iconName: String,
        iconTint: Color,
        isVisible: Bool,
        isActive: Bool,
        presentation: PluginFeaturePresentation
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.iconName = iconName
        self.iconTint = iconTint
        self.isVisible = isVisible
        self.isActive = isActive
        self.presentation = presentation
    }
}

public struct PluginConfigurationItem: Identifiable {
    public let id: String
    public let pluginID: String
    public let title: String
    public let description: String
    public let iconName: String
    public let iconTint: Color
    public let settingsCards: [PluginSettingsCard]
    public let permissionCards: [PluginPermissionCard]
    public let shortcutItems: [ShortcutSettingsItem]
    public let hasCustomConfiguration: Bool
    public let prefersFullHeight: Bool

    public init(
        id: String,
        pluginID: String,
        title: String,
        description: String,
        iconName: String,
        iconTint: Color,
        settingsCards: [PluginSettingsCard],
        permissionCards: [PluginPermissionCard],
        shortcutItems: [ShortcutSettingsItem],
        hasCustomConfiguration: Bool,
        prefersFullHeight: Bool = false
    ) {
        self.id = id
        self.pluginID = pluginID
        self.title = title
        self.description = description
        self.iconName = iconName
        self.iconTint = iconTint
        self.settingsCards = settingsCards
        self.permissionCards = permissionCards
        self.shortcutItems = shortcutItems
        self.hasCustomConfiguration = hasCustomConfiguration
        self.prefersFullHeight = prefersFullHeight
    }
}

public struct PluginConfigurationViewItem: Identifiable {
    public let id: String
    public let content: AnyView

    public init(id: String, content: AnyView) {
        self.id = id
        self.content = content
    }
}

public struct PluginPermissionCard: Identifiable {
    public let id: String
    public let pluginID: String
    public let permissionID: String
    public let title: String
    public let description: String
    public let statusText: String
    public let statusSystemImage: String
    public let statusTone: PluginStatusTone
    public let footnote: String?
    public let buttonTitle: String

    public init(
        id: String,
        pluginID: String,
        permissionID: String,
        title: String,
        description: String,
        statusText: String,
        statusSystemImage: String,
        statusTone: PluginStatusTone,
        footnote: String?,
        buttonTitle: String
    ) {
        self.id = id
        self.pluginID = pluginID
        self.permissionID = permissionID
        self.title = title
        self.description = description
        self.statusText = statusText
        self.statusSystemImage = statusSystemImage
        self.statusTone = statusTone
        self.footnote = footnote
        self.buttonTitle = buttonTitle
    }
}

public struct PluginSettingsCard: Identifiable {
    public let id: String
    public let pluginID: String
    public let title: String
    public let description: String
    public let statusText: String
    public let statusSystemImage: String
    public let statusTone: PluginStatusTone
    public let footnote: String?
    public let buttonTitle: String?
    public let actionID: String?

    public init(
        id: String,
        pluginID: String,
        title: String,
        description: String,
        statusText: String,
        statusSystemImage: String,
        statusTone: PluginStatusTone,
        footnote: String?,
        buttonTitle: String?,
        actionID: String?
    ) {
        self.id = id
        self.pluginID = pluginID
        self.title = title
        self.description = description
        self.statusText = statusText
        self.statusSystemImage = statusSystemImage
        self.statusTone = statusTone
        self.footnote = footnote
        self.buttonTitle = buttonTitle
        self.actionID = actionID
    }
}
