import SwiftUI
import MacToolsPluginKit

struct HomebrewDetailView: View {
    @ObservedObject var controller: HomebrewController
    private let localization: PluginLocalization
    private let showsHeader: Bool
    private let contentPadding: CGFloat
    private let minimumContentHeight: CGFloat
    
    @State private var activeTab: BrewTabSection = .installed
    @State private var installedFilter: BrewPackageFilter = .all
    @State private var localSearchText = ""
    @State private var onlineSearchText = ""
    @State private var newTapName = ""
    
    @State private var selectedInstalledPkg: BrewPackage?
    @State private var selectedSearchPkg: BrewPackage?
    @State private var onlinePackageDetail: BrewPackage?
    @State private var isFetchingOnlineDetail = false
    @State private var customBrewPath = ""
    
    enum BrewTabSection: String, CaseIterable, Identifiable {
        case installed
        case search
        case taps
        case diagnostics
        
        var id: String { rawValue }
        
        func title(localization: PluginLocalization) -> String {
            switch self {
            case .installed: return localization.string("detail.tabs.installed", defaultValue: "Installed")
            case .search: return localization.string("detail.tabs.search", defaultValue: "Search")
            case .taps: return localization.string("detail.tabs.taps", defaultValue: "Taps")
            case .diagnostics: return localization.string("detail.tabs.diagnostics", defaultValue: "Diagnostics")
            }
        }
        
        var icon: String {
            switch self {
            case .installed: return "shippingbox.fill"
            case .search: return "magnifyingglass"
            case .taps: return "square.stack.3d.up.fill"
            case .diagnostics: return "wrench.and.screwdriver.fill"
            }
        }
    }
    
    enum BrewPackageFilter: String, CaseIterable, Identifiable {
        case all
        case formula
        case cask
        
        var id: String { rawValue }
        
        func title(localization: PluginLocalization) -> String {
            switch self {
            case .all: return localization.string("detail.filter.all", defaultValue: "All")
            case .formula: return localization.string("detail.filter.formula", defaultValue: "Formula")
            case .cask: return localization.string("detail.filter.cask", defaultValue: "Cask")
            }
        }
    }
    
    init(
        controller: HomebrewController,
        localization: PluginLocalization = PluginLocalization(bundle: .main),
        showsHeader: Bool = true,
        contentPadding: CGFloat = 16,
        minimumContentHeight: CGFloat = 450
    ) {
        self.controller = controller
        self.localization = localization
        self.showsHeader = showsHeader
        self.contentPadding = contentPadding
        self.minimumContentHeight = minimumContentHeight
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                header
                    .padding(.horizontal, contentPadding)
                    .padding(.top, contentPadding)
            }
            
            if !controller.isBrewAvailable {
                pathNotFoundView
            } else {
                // Tab Selector
                tabBar
                    .padding(.horizontal, contentPadding)
                    .padding(.vertical, 8)
                
                Divider()
                
                // Main Content Area
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        Group {
                            switch activeTab {
                            case .installed:
                                installedTabContent
                            case .search:
                                searchTabContent
                            case .taps:
                                tapsTabContent
                            case .diagnostics:
                                diagnosticsTabContent
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        // Console Output Drawer
                        if !controller.logs.isEmpty {
                            consoleDrawer
                                .frame(height: 140)
                                .transition(.move(edge: .bottom))
                        }
                    }
                }
            }
        }
        .frame(minHeight: minimumContentHeight)
        .onAppear {
            customBrewPath = controller.brewPath
            if controller.isBrewAvailable && controller.installedPackages.isEmpty && !controller.isBusy {
                controller.scanAll()
            }
        }
        .onChange(of: controller.brewPath) { _, newPath in
            customBrewPath = newPath
        }
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(localization.string("detail.title", defaultValue: "Homebrew Manager"))
                    .font(PluginSettingsTheme.Typography.pageTitle)
                Text(localization.string("detail.subtitle", defaultValue: "Manage Homebrew packages, applications, and repositories visually"))
                    .font(PluginSettingsTheme.Typography.pageDescription)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            
            if controller.isBusy {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(controller.currentOperationName)
                        .font(PluginSettingsTheme.Typography.rowDescription)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .pluginSettingsCardBackground(.recessed)
            }
        }
    }
    
    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(BrewTabSection.allCases) { section in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        activeTab = section
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: section.icon)
                        Text(section.title(localization: localization))
                    }
                    .font(.body.weight(activeTab == section ? .semibold : .regular))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(activeTab == section ? Color.accentColor.opacity(0.15) : Color.clear)
                    )
                    .foregroundStyle(activeTab == section ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
    
    // MARK: - Tab Contents
    
    private var installedTabContent: some View {
        HStack(spacing: 12) {
            // Left List Column
            VStack(spacing: 8) {
                // Search & Filter
                HStack(spacing: 8) {
                    TextField(localization.string("detail.search.placeholder", defaultValue: "Search installed packages..."), text: $localSearchText)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.regular)
                    
                    Picker("", selection: $installedFilter) {
                        ForEach(BrewPackageFilter.allCases) { filter in
                            Text(filter.title(localization: localization)).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
                .padding(.horizontal, 4)
                
                // Package List
                let filtered = controller.installedPackages.filter { pkg in
                    let matchesText = localSearchText.isEmpty || pkg.name.localizedCaseInsensitiveContains(localSearchText) || pkg.desc.localizedCaseInsensitiveContains(localSearchText)
                    let matchesFilter = (installedFilter == .all) ||
                        (installedFilter == .formula && !pkg.isCask) ||
                        (installedFilter == .cask && pkg.isCask)
                    return matchesText && matchesFilter
                }
                
                if filtered.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                        Text(localization.string("detail.search.noMatch", defaultValue: "No matching installed packages"))
                            .font(PluginSettingsTheme.Typography.rowDescription)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .pluginSettingsCardBackground(.recessed)
                } else {
                    List(filtered, selection: $selectedInstalledPkg) { pkg in
                        HStack {
                            Image(systemName: pkg.isCask ? "macwindow" : "terminal")
                                .foregroundStyle(pkg.isCask ? .blue : .green)
                                .font(.system(size: 13))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pkg.name)
                                    .font(PluginSettingsTheme.Typography.emphasizedRowTitle)
                                if !pkg.desc.isEmpty {
                                    Text(pkg.desc)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            
                            if pkg.isOutdated {
                                Text(localization.string("detail.search.hasUpdate", defaultValue: "Update Available"))
                                    .font(PluginSettingsTheme.Typography.statusBadge)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.orange.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.orange)
                            }
                            
                            Text(pkg.version)
                                .font(PluginSettingsTheme.Typography.monospacedValue)
                                .foregroundStyle(.secondary)
                        }
                        .tag(pkg)
                        .padding(.vertical, 2)
                    }
                    .listStyle(.inset)
                    .pluginSettingsCardBackground(.recessed)
                }
            }
            .frame(width: 320)
            
            // Right Detail Column
            VStack {
                if let pkg = selectedInstalledPkg {
                    packageDetailView(for: pkg)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text(localization.string("detail.detail.selectionHint", defaultValue: "Select an installed package to view details"))
                            .font(PluginSettingsTheme.Typography.rowDescription)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .pluginSettingsCardBackground(.host)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, contentPadding)
        .padding(.bottom, contentPadding)
    }
    
    private var searchTabContent: some View {
        HStack(spacing: 12) {
            // Left List Column
            VStack(spacing: 8) {
                // Search bar
                HStack {
                    TextField(localization.string("detail.search.onlinePlaceholder", defaultValue: "Search online formulae or casks..."), text: $onlineSearchText, onCommit: {
                        controller.search(query: onlineSearchText)
                    })
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.regular)
                    
                    Button(localization.string("detail.search.button", defaultValue: "Search")) {
                        controller.search(query: onlineSearchText)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(onlineSearchText.isEmpty || controller.isSearching)
                }
                .padding(.horizontal, 4)
                
                if controller.isSearching {
                    VStack {
                        ProgressView()
                        Text(localization.string("detail.search.searching", defaultValue: "Searching Homebrew..."))
                            .font(PluginSettingsTheme.Typography.rowDescription)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .pluginSettingsCardBackground(.recessed)
                } else if controller.searchResults.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                        Text(localization.string("detail.search.empty", defaultValue: "Enter keywords to search on Homebrew"))
                            .font(PluginSettingsTheme.Typography.rowDescription)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .pluginSettingsCardBackground(.recessed)
                } else {
                    List(controller.searchResults, selection: $selectedSearchPkg) { pkg in
                        HStack {
                            Image(systemName: pkg.isCask ? "macwindow" : "terminal")
                                .foregroundStyle(pkg.isCask ? .blue : .green)
                            Text(pkg.name)
                                .font(PluginSettingsTheme.Typography.rowTitle)
                            Spacer()
                            Text(pkg.isCask ? localization.string("detail.filter.cask", defaultValue: "Cask") : localization.string("detail.filter.formula", defaultValue: "Formula"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(pkg)
                        .padding(.vertical, 2)
                    }
                    .listStyle(.inset)
                    .pluginSettingsCardBackground(.recessed)
                    .onChange(of: selectedSearchPkg) { _, newPkg in
                        if let pkg = newPkg {
                            fetchOnlinePackageDetail(pkg)
                        }
                    }
                }
            }
            .frame(width: 320)
            
            // Right Detail Column
            VStack {
                if isFetchingOnlineDetail {
                    VStack {
                        ProgressView()
                        Text(localization.string("detail.search.fetchingDetail", defaultValue: "Fetching detailed metadata..."))
                            .font(PluginSettingsTheme.Typography.rowDescription)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .pluginSettingsCardBackground(.host)
                } else if let pkg = onlinePackageDetail {
                    onlinePackageDetailView(for: pkg)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text(localization.string("detail.detail.onlineHint", defaultValue: "Select search result to install package"))
                            .font(PluginSettingsTheme.Typography.rowDescription)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .pluginSettingsCardBackground(.host)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, contentPadding)
        .padding(.bottom, contentPadding)
    }
    
    private var tapsTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Add Tap Card
            VStack(alignment: .leading, spacing: 8) {
                Text(localization.string("detail.taps.titleAdd", defaultValue: "Add Tap Repository"))
                    .font(PluginSettingsTheme.Typography.sectionTitle)
                    .foregroundStyle(.secondary)
                
                HStack {
                    TextField(localization.string("detail.taps.placeholderAdd", defaultValue: "Enter tap path (e.g., user/repo or repository URL)"), text: $newTapName)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.regular)
                    
                    Button(localization.string("detail.taps.buttonAdd", defaultValue: "Add")) {
                        controller.tapRepository(name: newTapName)
                        newTapName = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newTapName.isEmpty || controller.isBusy)
                }
            }
            .padding(12)
            .pluginSettingsCardBackground(.host)
            
            // Active Taps List
            VStack(alignment: .leading, spacing: 8) {
                Text(String(format: localization.string("detail.taps.titleList", defaultValue: "Active Taps (%d)"), controller.taps.count))
                    .font(PluginSettingsTheme.Typography.sectionTitle)
                    .foregroundStyle(.secondary)
                
                if controller.taps.isEmpty {
                    Text(localization.string("detail.taps.empty", defaultValue: "No active tap repositories"))
                        .font(PluginSettingsTheme.Typography.rowDescription)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(controller.taps) { tap in
                                HStack {
                                    Image(systemName: "square.stack.3d.up")
                                        .foregroundStyle(.secondary)
                                    Text(tap.name)
                                        .font(PluginSettingsTheme.Typography.rowTitle)
                                    Spacer()
                                    
                                    Button(localization.string("detail.taps.buttonUntap", defaultValue: "Untap")) {
                                        controller.untapRepository(tap: tap)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(controller.isBusy)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.primary.opacity(0.02))
                                .cornerRadius(6)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(12)
            .pluginSettingsCardBackground(.host)
        }
        .padding(.horizontal, contentPadding)
        .padding(.bottom, contentPadding)
    }
    
    private var diagnosticsTabContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Path Config Card
                VStack(alignment: .leading, spacing: 8) {
                    Text(localization.string("detail.diagnostics.pathTitle", defaultValue: "Homebrew Path Configuration"))
                        .font(PluginSettingsTheme.Typography.sectionTitle)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        TextField(localization.string("detail.diagnostics.pathPlaceholder", defaultValue: "Path to brew executable (e.g. /opt/homebrew/bin/brew)"), text: $customBrewPath)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.regular)
                        
                        Button(localization.string("detail.diagnostics.pathApply", defaultValue: "Apply")) {
                            controller.updateCustomPath(customBrewPath)
                        }
                        .buttonStyle(.bordered)
                        .disabled(customBrewPath == controller.brewPath)
                    }
                }
                .padding(12)
                .pluginSettingsCardBackground(.host)

                diagnosticRow(
                    title: localization.string("detail.diagnostics.update.title", defaultValue: "Update Repositories (brew update)"),
                    description: localization.string("detail.diagnostics.update.desc", defaultValue: "Sync the latest list of formulas and casks from remote servers."),
                    icon: "arrow.clockwise.circle.fill",
                    color: .blue,
                    action: { controller.updateBrew() }
                )
                
                diagnosticRow(
                    title: localization.string("detail.diagnostics.upgrade.title", defaultValue: "Upgrade All Outdated Packages (brew upgrade)"),
                    description: localization.string("detail.diagnostics.upgrade.desc", defaultValue: "Upgrade all outdated formulas and casks currently detected on your system."),
                    icon: "arrow.up.circle.fill",
                    color: .orange,
                    action: { controller.upgradeAll() }
                )
                
                diagnosticRow(
                    title: localization.string("detail.diagnostics.doctor.title", defaultValue: "Health Diagnostics (brew doctor)"),
                    description: localization.string("detail.diagnostics.doctor.desc", defaultValue: "Diagnose potential issues with environment variables, permissions, and build paths."),
                    icon: "heart.text.square.fill",
                    color: .green,
                    action: { controller.runDoctor() }
                )
                
                diagnosticRow(
                    title: localization.string("detail.diagnostics.cleanup.title", defaultValue: "Cleanup Trash & Caches (brew cleanup)"),
                    description: localization.string("detail.diagnostics.cleanup.desc", defaultValue: "Remove outdated local downloads and caches to reclaim disk space."),
                    icon: "trash.circle.fill",
                    color: .red,
                    action: { controller.runCleanup() }
                )
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, contentPadding)
        .padding(.bottom, contentPadding)
    }

    private var pathNotFoundView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            
            Text(localization.string("detail.diagnostics.pathNotFoundTitle", defaultValue: "Homebrew Not Detected"))
                .font(PluginSettingsTheme.Typography.pageTitle)
            
            Text(localization.string("detail.diagnostics.pathNotFoundDesc", defaultValue: "Homebrew was not found in standard system directories. Please ensure it is installed or provide the custom path to the 'brew' executable below:"))
                .font(PluginSettingsTheme.Typography.rowDescription)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField(localization.string("detail.diagnostics.pathPlaceholder", defaultValue: "Path to brew executable (e.g. /opt/homebrew/bin/brew)"), text: $customBrewPath)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.regular)
                    
                    Button(localization.string("detail.diagnostics.pathApply", defaultValue: "Apply")) {
                        controller.updateCustomPath(customBrewPath)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(customBrewPath == controller.brewPath)
                }
            }
            .frame(maxWidth: 480)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(localization.string("detail.diagnostics.pathHelpTitle", defaultValue: "Common Installation Locations:"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(localization.string("detail.diagnostics.pathHelpAppleSilicon", defaultValue: "• Apple Silicon Mac: /opt/homebrew/bin/brew"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(localization.string("detail.diagnostics.pathHelpIntel", defaultValue: "• Intel Mac: /usr/local/bin/brew"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 12)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pluginSettingsCardBackground(.host)
    }
    
    private func diagnosticRow(
        title: String,
        description: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(color)
                .frame(width: 36)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(PluginSettingsTheme.Typography.emphasizedRowTitle)
                Text(description)
                    .font(PluginSettingsTheme.Typography.rowDescription)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            
            Button(localization.string("detail.diagnostics.buttonExecute", defaultValue: "Execute")) {
                action()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(controller.isBusy)
        }
        .padding(12)
        .pluginSettingsCardBackground(.host)
    }
    
    // MARK: - Component Views
    
    private func packageDetailView(for pkg: BrewPackage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: pkg.isCask ? "macwindow" : "terminal")
                    .font(.system(size: 20))
                    .foregroundStyle(pkg.isCask ? .blue : .green)
                
                Text(pkg.name)
                    .font(PluginSettingsTheme.Typography.pageTitle)
                Spacer()
                
                if pkg.isPinned {
                    Label(localization.string("detail.detail.pinned", defaultValue: "Pinned"), systemImage: "pin.fill")
                        .font(PluginSettingsTheme.Typography.statusBadge)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.15))
                        .foregroundStyle(.yellow)
                        .cornerRadius(4)
                }
            }
            
            if !pkg.desc.isEmpty {
                Text(pkg.desc)
                    .font(PluginSettingsTheme.Typography.rowTitle)
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 8) {
                infoRow(label: localization.string("detail.detail.type", defaultValue: "Type"), value: pkg.isCask ? localization.string("detail.detail.typeCask", defaultValue: "GUI App (Cask)") : localization.string("detail.detail.typeFormula", defaultValue: "CLI Package (Formula)"))
                infoRow(label: localization.string("detail.detail.installedVer", defaultValue: "Installed"), value: pkg.version)
                infoRow(label: localization.string("detail.detail.latestVer", defaultValue: "Latest"), value: pkg.latestVersion)
                if !pkg.homepage.isEmpty {
                    HStack {
                        Text(localization.string("detail.detail.website", defaultValue: "Homepage")).font(PluginSettingsTheme.Typography.rowDescription).foregroundStyle(.secondary)
                        Spacer()
                        if let url = URL(string: pkg.homepage) {
                            Link(pkg.homepage, destination: url)
                                .font(PluginSettingsTheme.Typography.rowDescription)
                                .lineLimit(1)
                        } else {
                            Text(pkg.homepage)
                                .font(PluginSettingsTheme.Typography.rowDescription)
                                .lineLimit(1)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .padding(10)
            .pluginSettingsCardBackground(.recessed)
            
            if !pkg.dependencies.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(format: localization.string("detail.detail.dependencies", defaultValue: "Dependencies (%d)"), pkg.dependencies.count))
                        .font(PluginSettingsTheme.Typography.sectionTitle)
                        .foregroundStyle(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(pkg.dependencies, id: \.self) { dep in
                                Button {
                                    navigateToPackage(name: dep)
                                } label: {
                                    Text(dep)
                                        .font(PluginSettingsTheme.Typography.monospacedValue)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.primary.opacity(0.05))
                                        .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            let usedBy = pkg.requiredBy(in: controller.installedPackages)
            if !usedBy.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(format: localization.string("detail.detail.usedBy", defaultValue: "Required By (%d)"), usedBy.count))
                        .font(PluginSettingsTheme.Typography.sectionTitle)
                        .foregroundStyle(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(usedBy, id: \.self) { parent in
                                Button {
                                    navigateToPackage(name: parent)
                                } label: {
                                    Text(parent)
                                        .font(PluginSettingsTheme.Typography.monospacedValue)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.primary.opacity(0.05))
                                        .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 10) {
                if pkg.isOutdated {
                    Button {
                        controller.upgrade(package: pkg)
                    } label: {
                        Label(localization.string("detail.detail.actionUpgrade", defaultValue: "Upgrade"), systemImage: "arrow.up.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(controller.isBusy)
                }
                
                if !pkg.isPinned {
                    Button {
                        if pkg.isPinned {
                            controller.unpin(package: pkg)
                        } else {
                            controller.pin(package: pkg)
                        }
                    } label: {
                        Label(pkg.isPinned ? localization.string("detail.detail.actionUnpin", defaultValue: "Unpin") : localization.string("detail.detail.actionPin", defaultValue: "Pin Version"), systemImage: pkg.isPinned ? "pin.slash" : "pin")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(controller.isBusy)
                } else {
                    Button {
                        if pkg.isPinned {
                            controller.unpin(package: pkg)
                        } else {
                            controller.pin(package: pkg)
                        }
                    } label: {
                        Label(pkg.isPinned ? localization.string("detail.detail.actionUnpin", defaultValue: "Unpin") : localization.string("detail.detail.actionPin", defaultValue: "Pin Version"), systemImage: pkg.isPinned ? "pin.slash" : "pin")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(controller.isBusy)
                }
                
                Button(role: .destructive) {
                    controller.uninstall(package: pkg)
                } label: {
                    Label(localization.string("detail.detail.actionUninstall", defaultValue: "Uninstall"), systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(controller.isBusy)
            }
        }
        .padding(14)
        .pluginSettingsCardBackground(.host)
    }
    
    private func onlinePackageDetailView(for pkg: BrewPackage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: pkg.isCask ? "macwindow" : "terminal")
                    .font(.system(size: 20))
                    .foregroundStyle(pkg.isCask ? .blue : .green)
                
                Text(pkg.name)
                    .font(PluginSettingsTheme.Typography.pageTitle)
                Spacer()
            }
            
            if !pkg.desc.isEmpty {
                Text(pkg.desc)
                    .font(PluginSettingsTheme.Typography.rowTitle)
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 8) {
                infoRow(label: localization.string("detail.detail.type", defaultValue: "Type"), value: pkg.isCask ? localization.string("detail.filter.cask", defaultValue: "Cask") : localization.string("detail.filter.formula", defaultValue: "Formula"))
                infoRow(label: localization.string("detail.detail.latestAvailableVer", defaultValue: "Latest Available"), value: pkg.latestVersion)
                if !pkg.homepage.isEmpty {
                    HStack {
                        Text(localization.string("detail.detail.website", defaultValue: "Homepage")).font(PluginSettingsTheme.Typography.rowDescription).foregroundStyle(.secondary)
                        Spacer()
                        if let url = URL(string: pkg.homepage) {
                            Link(pkg.homepage, destination: url)
                                .font(PluginSettingsTheme.Typography.rowDescription)
                                .lineLimit(1)
                        } else {
                            Text(pkg.homepage)
                                .font(PluginSettingsTheme.Typography.rowDescription)
                                .lineLimit(1)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .padding(10)
            .pluginSettingsCardBackground(.recessed)
            
            Spacer()
            
            // Actions
            let alreadyInstalled = controller.installedPackages.contains { $0.name == pkg.name }
            
            Button {
                controller.install(package: pkg)
            } label: {
                Label(alreadyInstalled ? localization.string("detail.search.installAgainAction", defaultValue: "Install Again") : localization.string("detail.search.installAction", defaultValue: "Install"), systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(controller.isBusy)
            
            if alreadyInstalled {
                Text(localization.string("detail.search.installedHint", defaultValue: "This package is already installed on your system."))
                    .font(.caption)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(14)
        .pluginSettingsCardBackground(.host)
    }
    
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(PluginSettingsTheme.Typography.rowDescription)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(PluginSettingsTheme.Typography.rowDescription)
        }
    }
    
    // MARK: - Console Output Drawer
    
    private var consoleDrawer: some View {
        VStack(spacing: 0) {
            Divider()
            
            // Terminal Header
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(controller.isBusy ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                        .opacity(controller.isBusy ? 0.8 : 0.4)
                    
                    Text(localization.string("detail.console.title", defaultValue: "Terminal Console Logs"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                
                Button(localization.string("detail.console.buttonClear", defaultValue: "Clear")) {
                    controller.clearLogs()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(4)
                
                if controller.isBusy {
                    Button(localization.string("detail.console.buttonCancel", defaultValue: "Cancel Operation")) {
                        controller.cancelCurrentOperation()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.02))
            
            // Scrollable Console
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(controller.logs.suffix(150)) { log in
                            Text(log.text)
                                .font(PluginSettingsTheme.Typography.monospacedValue)
                                .foregroundStyle(log.isError ? Color.red : Color.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(log.id)
                        }
                    }
                    .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.95))
                .onChange(of: controller.logs.count) { _, _ in
                    if let last = controller.logs.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func fetchOnlinePackageDetail(_ pkg: BrewPackage) {
        let requestedName = pkg.name
        let requestedIsCask = pkg.isCask
        isFetchingOnlineDetail = true
        onlinePackageDetail = nil
        
        Task {
            defer {
                if selectedSearchPkg?.name == requestedName && selectedSearchPkg?.isCask == requestedIsCask {
                    isFetchingOnlineDetail = false
                }
            }
            do {
                let tempRunner = controller.runner
                var jsonOutput = ""
                
                _ = try await tempRunner.run(
                    executable: controller.brewPath,
                    arguments: ["info", "--json=v2", pkg.name],
                    onOutput: { jsonOutput += $0 },
                    onError: { _ in }
                )
                
                guard selectedSearchPkg?.name == requestedName && selectedSearchPkg?.isCask == requestedIsCask else { return }
                
                guard let data = jsonOutput.data(using: .utf8) else {
                    return
                }
                
                struct BrewInfoResponse: Codable {
                    let formulae: [FormulaInfo]
                    let casks: [CaskInfo]
                }
                struct FormulaInfo: Codable {
                    let name: String
                    let desc: String?
                    let homepage: String?
                    let versions: StableVersion?
                }
                struct StableVersion: Codable {
                    let stable: String?
                }
                struct CaskInfo: Codable {
                    let token: String
                    let name: [String]?
                    let desc: String?
                    let homepage: String?
                    let version: String?
                }
                
                let response = try JSONDecoder().decode(BrewInfoResponse.self, from: data)
                
                guard selectedSearchPkg?.name == requestedName && selectedSearchPkg?.isCask == requestedIsCask else { return }
                
                if pkg.isCask, let cask = response.casks.first {
                    onlinePackageDetail = BrewPackage(
                        name: cask.token,
                        version: "",
                        latestVersion: cask.version ?? "",
                        isCask: true,
                        desc: cask.desc ?? (cask.name?.first ?? ""),
                        homepage: cask.homepage ?? "",
                        isOutdated: false,
                        isPinned: false
                    )
                } else if let formula = response.formulae.first {
                    onlinePackageDetail = BrewPackage(
                        name: formula.name,
                        version: "",
                        latestVersion: formula.versions?.stable ?? "",
                        isCask: false,
                        desc: formula.desc ?? "",
                        homepage: formula.homepage ?? "",
                        isOutdated: false,
                        isPinned: false
                    )
                }
            } catch {}
        }
    }
    
    private func navigateToPackage(name: String) {
        if let found = controller.installedPackages.first(where: { $0.name == name }) {
            activeTab = .installed
            selectedInstalledPkg = found
        } else {
            activeTab = .search
            onlineSearchText = name
            controller.search(query: name)
        }
    }
}
