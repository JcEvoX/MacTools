import SwiftUI
import MacToolsPluginKit

// MARK: - FanControlPresetManagerView

struct FanControlPresetManagerView: View {
    @ObservedObject var presetStore: FanControlPresetStore
    /// Live snapshot for showing actual hardware max RPM in sliders.
    var fanSnapshot: FanSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            builtInSection
            customSection
        }
    }

    // MARK: - Built-in Section

    private var builtInSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "内置预设", icon: "lock")

            VStack(spacing: 0) {
                ForEach(FanControlPresetStore.builtInPresets) { preset in
                    BuiltInPresetRow(preset: preset, fanSnapshot: fanSnapshot)
                    if preset.id != FanControlPresetStore.builtInPresets.last?.id {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Custom Section

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader(title: "自定义预设", icon: "slider.horizontal.3")
                Spacer()
                Button(action: addPreset) {
                    Label("添加", systemImage: "plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if presetStore.customPresets.isEmpty {
                emptyCustomPresetsView
            } else {
                VStack(spacing: 0) {
                    ForEach(presetStore.customPresets) { preset in
                        CustomPresetRow(
                            preset: preset,
                            fanSnapshot: fanSnapshot,
                            onRename: { presetStore.renameCustomPreset(id: preset.id, newName: $0) },
                            onRPMChange: { presetStore.updateCustomPresetRPM(id: preset.id, rpm: $0) },
                            onDelete: { presetStore.deleteCustomPreset(id: preset.id) }
                        )
                        if preset.id != presetStore.customPresets.last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
            }
        }
    }

    private var emptyCustomPresetsView: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("点击「添加」创建自定义转速预设")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 24)
            Spacer()
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    // MARK: - Helpers

    private func sectionHeader(title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func addPreset() {
        _ = presetStore.addCustomPreset()
    }
}

// MARK: - BuiltInPresetRow

private struct BuiltInPresetRow: View {
    let preset: FanPreset
    let fanSnapshot: FanSnapshot

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("内置")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(Color(nsColor: .quaternaryLabelColor).opacity(0.4))
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var subtitle: String {
        switch preset.strategy {
        case .auto:
            return "由 macOS 自动管理"
        case .fullSpeed:
            let max = fanSnapshot.globalMaxSpeed
            return max > 0 ? "最高 \(max) RPM" : "最高转速"
        case .fixed(let rpm):
            return "\(rpm) RPM"
        }
    }
}

// MARK: - CustomPresetRow

private struct CustomPresetRow: View {
    let preset: FanPreset
    let fanSnapshot: FanSnapshot
    let onRename: (String) -> Void
    let onRPMChange: (Int) -> Void
    let onDelete: () -> Void

    @State private var nameText: String
    @State private var sliderValue: Double
    @FocusState private var isNameFocused: Bool
    @State private var isNameHovered = false

    init(
        preset: FanPreset,
        fanSnapshot: FanSnapshot,
        onRename: @escaping (String) -> Void,
        onRPMChange: @escaping (Int) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.preset = preset
        self.fanSnapshot = fanSnapshot
        self.onRename = onRename
        self.onRPMChange = onRPMChange
        self.onDelete = onDelete
        let rpm = { if case .fixed(let r) = preset.strategy { return r }; return FanRPMLimits.defaultCustomRPM }()
        _nameText = State(initialValue: preset.name)
        _sliderValue = State(initialValue: Double(rpm))
    }

    private var currentRPM: Int {
        if case .fixed(let r) = preset.strategy { return r }
        return FanRPMLimits.defaultCustomRPM
    }

    private func resignFocus() {
        isNameFocused = false
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private var sliderMax: Double {
        let max = fanSnapshot.globalMaxSpeed
        return Double(max > 0 ? max : FanRPMLimits.fallbackMax)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Name row
            HStack(spacing: 6) {
                TextField("预设名称", text: $nameText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isNameFocused
                                  ? Color(nsColor: .textBackgroundColor)
                                  : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                isNameFocused
                                    ? Color(nsColor: .controlAccentColor)
                                    : isNameHovered
                                        ? Color(nsColor: .separatorColor)
                                        : Color.clear,
                                lineWidth: 1
                            )
                    )
                    .frame(maxWidth: 100)
                    .onHover { isNameHovered = $0 }
                    .focused($isNameFocused)
                    .onSubmit { onRename(nameText) }
                    .onChange(of: nameText) { _, new in
                        onRename(new)
                    }

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("删除此预设")
            }

            // RPM slider row
            HStack(spacing: 10) {
                Slider(
                    value: $sliderValue,
                    in: Double(FanRPMLimits.absoluteMin)...sliderMax,
                    step: 100
                ) {
                    EmptyView()
                } onEditingChanged: { editing in
                    if editing { resignFocus() }
                    if !editing { onRPMChange(Int(sliderValue)) }
                }

                Text("\(Int(sliderValue)) RPM")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { resignFocus() }
        // Sync external changes (e.g. from panel slider) back to local state
        .onChange(of: preset.strategy) { _, newStrategy in
            if case .fixed(let r) = newStrategy {
                sliderValue = Double(r)
            }
        }
        .onChange(of: preset.name) { _, newName in
            if nameText != newName { nameText = newName }
        }
    }
}
