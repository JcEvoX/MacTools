<div align="center">
  <img src="docs/assets/logo-mactools-rounded.png" width="96" height="96" alt="MacTools logo">
  <h1>MacTools</h1>
  <p><strong>免费、开源的原生 macOS 菜单栏工具集合。</strong></p>
  <p>聚合高频系统能力，保持轻量、快速、低打扰。使用 SwiftUI + AppKit 构建，支持 macOS 14.0 及以上版本。</p>
</div>

## 截图

|                                   菜单栏功能面板                                    |                                              组件仪表盘                                              |                                        通用设置                                         |                                       插件页面                                        |
| :---------------------------------------------------------------------------------: | :--------------------------------------------------------------------------------------------------: | :---------------------------------------------------------------------------------------: | :-------------------------------------------------------------------------------------: |
| <img src="docs/assets/screenshots/menu-panel.png" width="220" alt="菜单栏功能面板"> | <img src="docs/assets/screenshots/component-dashboard.png" width="220" alt="日历与系统状态组件面板"> | <img src="docs/assets/screenshots/settings-general.png" width="220" alt="通用设置页面"> | <img src="docs/assets/screenshots/settings-plugins.png" width="220" alt="插件页面"> |

## 功能

| 功能             | 说明                                                                                                            |
| ---------------- | --------------------------------------------------------------------------------------------------------------- |
| 显示器分辨率     | 查看已连接显示器，并按显示器切换可用分辨率。                                                                    |
| 显示器亮度       | 快速调节内建屏、DDC/CI 外接屏亮度，并提供 Gamma/Shade 回退。                                                    |
| 原彩显示         | 自动调节显示器颜色以适应环境光，支持 MacBook 和兼容显示器。                                                     |
| 深色模式         | 一键切换系统亮色与深色外观，并实时跟随系统主题变化同步状态。                                                    |
| 夜览             | 一键开关 Night Shift，降低屏幕蓝光，使颜色偏暖，保护夜间视力。                                                  |
| 阻止休眠         | 保持系统空闲时唤醒，支持 30 分钟、1 小时、2 小时、5 小时后自动停止。                                            |
| 清洁模式         | 全屏黑色覆盖并临时禁用输入，适合清洁屏幕、键盘或触控板。                                                        |
| 模拟鼠标中键     | 三指轻点触控板触发鼠标中键，通过 CGEvent tap 原地转换系统事件，不影响其他手势与左键操作。                       |
| 隐藏刘海         | 自动遮挡内建刘海屏顶部区域，不修改用户原始壁纸。                                                                |
| 隐藏 Dock        | 一键切换 Dock 自动隐藏状态。                                                                                    |
| 麦克风静音       | 一键静音或恢复默认麦克风输入，通过 CoreAudio 直接控制输入设备，无需录音权限。                                   |
| 磁盘清理         | 扫描缓存、开发者缓存与浏览器缓存，执行前进行路径安全和敏感数据保护校验。                                        |
| 推出磁盘         | 一键推出所有可移动磁盘，自动过滤系统卷并在无可推出磁盘时给出状态提示。                                          |
| 清空废纸篓       | 显示废纸篓项目数，一键通过 Finder 清空，废纸篓为空时自动禁用按钮。                                              |
| 清空剪贴板       | 一键清空当前剪贴板内容，保护隐私，防止误粘贴。                                                                  |
| 锁定屏幕         | 一键立即锁定屏幕，进入密码解锁界面，等同于 Cmd+Ctrl+Q 快捷键。                                                  |
| 启动项管理       | 可视化查看 LaunchAgent/LaunchDaemon，支持搜索筛选、字段解释和用户级启动项启停管理。                             |
| 日历组件         | 在组件面板中查看月历、农历、节假日与当天日程。                                                                  |
| 系统状态         | 展示 CPU、内存、磁盘、电量、网络速率与高占用进程。                                                              |
| 活动统计         | 统计键盘、鼠标、滚动、前台应用使用时长，并可通过手动 Hook 记录 Claude Code、Cursor、Codex 活动。                |
| 风扇控制         | 通过预设管理风扇转速，支持自动、全速与自定义固定转速，实时显示当前转速。                                        |
| 修复损坏应用     | 移除应用隔离属性，解决「已损坏，无法打开」提示，通过文件面板选择 .app 并以管理员权限执行修复。                  |
| 插件与设置       | 在插件市场中安装、更新和批量更新插件，并在各插件设置页维护权限、快捷键和专属设置。                              |
| 状态栏图标自定义 | 上传本地图片或轻量 GIF/MP4 动画作为菜单栏图标，也可选择内置动态图标，并支持自动扣背景、播放速度调整和恢复默认。 |

## 特性

- 菜单栏常驻，默认不进入 Dock，适合后台长期运行。
- 插件化架构，菜单功能与组件面板可按需启用、隐藏和排序。
- 原生 macOS 视觉与交互，主面板、详情面板、设置页体验一致。
- 对权限、显示器、文件路径和系统 API 调用保留失败分支与降级路径。

## 安装

```bash
brew tap ggbond268/mactools
brew install --cask mactools
```

## 升级

Homebrew 升级前需要先刷新 tap，确保本地拿到最新的 cask 配方：

```bash
brew update
brew upgrade --cask --greedy ggbond268/mactools/mactools
```

如果仍提示已经是最新版本，可以先查看本地识别到的 cask 版本：

```bash
brew info --cask ggbond268/mactools/mactools
```

## 开发

核心 app 代码在 `Sources/`，插件源码在 `Plugins/<PluginName>/`。每个插件目录包含 `plugin.json`、`Sources/`、`Bundle/`，有测试时放在同目录的 `Tests/`。普通插件不需要手动修改根 `project.yml`；`make generate`、`make build`、`make run` 和 `make build-plugin` 会自动扫描插件并生成 XcodeGen 配置。需要额外 framework、include path 或 bundle 资源的插件，可在自己的 `Plugins/<PluginName>/project.yml` 中只声明差异项。

```bash
make setup      # 生成 LocalConfig.xcconfig，请填写 DEVELOPMENT_TEAM 与 BUNDLE_IDENTIFIER_PREFIX
make generate   # 使用 XcodeGen 生成 MacTools.xcodeproj
make build      # 编译校验
make run        # 本地运行
```

开发或调试本地插件：

```bash
make build-plugin                 # 构建 Plugins/ 下的所有本地插件并生成 Debug catalog
make build-plugin PLUGIN=calendar # 只构建指定插件目录名或插件 ID
make run                          # 自动使用 build/LocalPlugins/catalog.dev.json
```

插件发布通过 `plugins-*` 批次 tag 触发 GitHub Actions。只需要给实际变更的插件递增 `plugin.json.version`；工作流会默认只构建和上传变更插件，合并签名后的 catalog，并保留未变化插件的既有下载链接。

新增和更新插件的简短流程见 [docs/plugins/local-native-plugins.md](docs/plugins/local-native-plugins.md#development-steps)。

运行完整测试：

```bash
xcodebuild -project MacTools.xcodeproj -scheme MacTools -configuration Debug -derivedDataPath build/DerivedData test -quiet
```

贡献、测试和发布流程请参考 [CONTRIBUTING.md](CONTRIBUTING.md)。
GitHub Actions 自动构建与发布配置请参考 [docs/github-actions.md](docs/github-actions.md)。
插件 catalog、包结构和批次发布流程请参考 [docs/plugins/plugin-catalog.md](docs/plugins/plugin-catalog.md)。

## 许可证

MacTools 基于 [Apache License 2.0](LICENSE) 开源。

## 致谢

- 第三方素材、依赖与实现参考见 [Sources/Resources/ThirdPartyNotices](Sources/Resources/ThirdPartyNotices)。
- 贡献者

  <a href="https://github.com/ggbond268/MacTools/graphs/contributors">
    <img src="https://contrib.rocks/image?repo=ggbond268/MacTools&max=120&columns=12" width="480" alt="contributors">
  </a>
