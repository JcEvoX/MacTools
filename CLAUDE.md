# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

## Claude Code Adapter
- Canonical shared rules — build/test commands, plugin conventions, the settings-UI spec, Swift style, feature safety boundaries, test requirements, agent workflow — live in `AGENTS.md` (imported above). Read it; update it rather than duplicating rules here.
- `GEMINI.md` is a parallel thin adapter to the same `AGENTS.md`. Put personal/machine-local Claude notes in `CLAUDE.local.md` (do not commit).

## 运行时架构总览（大局 —— 需读多文件才能拼出，AGENTS.md 没有的串联视角）

MacTools 是「菜单栏宿主 + 插件」结构。三块拼起来才看得懂：宿主（`Sources/App` + `Sources/Core/Plugins`）、插件协议层（`Sources/MacToolsPluginKit`）、功能插件（`Plugins/<Name>`）。

**两类插件 / 两条加载路线（核心二元性）**
- *静态插件*：`Plugins/<Name>/` 在树内，由 XcodeGen 编进 App。`scripts/plugins/generate-plugin-project-config.rb` 扫描各 `plugin.json` → 本地 `Configs/GeneratedPlugins.yml`（不提交）→ 经 `project.yml` 进 `MacTools.xcodeproj`。普通新增插件不用改 `project.yml`。
- *动态插件*：`.mactoolsplugin` 包在运行时由 `Sources/Core/Plugins/Dynamic` 三件套处理 —— `PluginPackageStore`（安装/记录/给每个插件 `runtimeContext`：support/cache/temp 目录 + pluginID 作用域存储）、`PluginTrustValidator`（信任校验，fail-closed）、`DynamicPluginManager`/`DynamicPluginLoader`（加载、`pausePlugin`/`resumePlugin`、热更新标记重启）。`plugin.json.id` 必须 == 运行时 `PluginMetadata.id`。

**宿主是中枢（`PluginHost`），插件从不直接碰菜单栏 UI**。Host 把每个插件的 `primaryPanelState` / `componentPanelState` / `settingsSections` / `permissionRequirements` / `shortcutDefinitions` 派生成宿主可渲染项，统管排序、可见性、快捷键、权限卡，并缓存组件视图、合并/debounce 状态重建。四个用户可见面：菜单栏「功能面板」(`PluginPrimaryPanel`)、「组件仪表盘」(`PluginComponentPanel`)、通用设置、插件管理页。

**UI 是描述式的，不是裸 SwiftUI**：用 `PluginPanelState`/`PluginPanelDetail`/`PluginPanelControl`、`PluginConfiguration` 表达界面，宿主统一渲染；只有 `PluginComponentPanel.makeView` 与 `PluginConfiguration.makeView` 才写真 SwiftUI（复杂列表/拖放/图表时）。

**数据流**：用户操作 → `handleAction(PluginPanelAction)` → 插件改自身状态 → 调 `onStateChange?()` → 宿主重建派生状态重渲染。**外部系统事件**（显示器热插拔、权限变化、文件系统、日历授权）不能依赖「用户展开面板才刷新」——要接明确观察器（如显示器拓扑：Core 层 `DisplayConfigurationObserving` 通知 → 实现 `DisplayTopologyRefreshing` 的插件刷新快照）并 debounce。

**生命周期**：`activate(context:)` / `deactivate(reason:)`。`reason.requiresStateCleanup` 区分真正清理（disable/uninstall/shutdown，需还原系统副作用）与 `.updating` 热更新（不清理、进程内不重激活、靠重启彻底卸载）。改副作用相关代码时：清理路径失败别静默吞、强制放电/亮度覆盖/壁纸/event tap 等必须有还原与可退出路径。

## 构建踩坑（AGENTS.md 命令之外、容易踩的）
- `MacTools.xcodeproj`、`Configs/GeneratedPlugins.yml`、`Configs/LocalConfig.xcconfig` 都是**生成且 gitignore** 的。**切换 git 分支后必须重跑 `make generate`** —— .xcodeproj 引用具体文件，换分支文件集变了，不重新生成会编译失败或漏文件（新增/删除源文件后同理）。
- 平台是 **macOS**（不是 iOS 模拟器）：单插件快速编译用 `-scheme <Name>Plugin -destination 'platform=macOS'`；单测试类在 AGENTS.md 的完整 test 命令后加 `-only-testing:MacToolsTests/<TestClassName>`。
- 插件测试放在 `Plugins/<Name>/Tests/`，但都跑在 `MacToolsTests` 这个 bundle 下，写法是 `@testable import MacTools` + `@testable import <Name>Plugin`。
