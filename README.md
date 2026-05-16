<div align="center">
  <img src="docs/assets/logo-mactools-rounded.png" width="96" height="96" alt="MacTools logo">
  <h1>MacTools</h1>
  <p><strong>免费、开源的原生 macOS 菜单栏工具集合。</strong></p>
  <p>聚合高频系统能力，保持轻量、快速、低打扰。使用 SwiftUI + AppKit 构建，支持 macOS 14.0 及以上版本。</p>
</div>

## 截图

|                                   菜单栏功能面板                                    |                                              组件仪表盘                                              |                                        设置与功能                                         |                                       关于与更新                                        |
| :---------------------------------------------------------------------------------: | :--------------------------------------------------------------------------------------------------: | :---------------------------------------------------------------------------------------: | :-------------------------------------------------------------------------------------: |
| <img src="docs/assets/screenshots/menu-panel.png" width="220" alt="菜单栏功能面板"> | <img src="docs/assets/screenshots/component-dashboard.png" width="220" alt="日历与系统状态组件面板"> | <img src="docs/assets/screenshots/settings-general.png" width="220" alt="设置与功能页面"> | <img src="docs/assets/screenshots/settings-about.png" width="220" alt="关于与更新页面"> |

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
| 磁盘清理         | 扫描缓存、开发者缓存与浏览器缓存，执行前进行路径安全和敏感数据保护校验。                                        |
| 推出磁盘         | 一键推出所有可移动磁盘，自动过滤系统卷并在无可推出磁盘时给出状态提示。                                          |
| 清空剪贴板       | 一键清空当前剪贴板内容，保护隐私，防止误粘贴。                                                                  |
| 启动项管理       | 可视化查看 LaunchAgent/LaunchDaemon，支持搜索筛选、字段解释和用户级启动项启停管理。                             |
| 日历组件         | 在组件面板中查看月历、农历、节假日与当天日程。                                                                  |
| 系统状态         | 展示 CPU、内存、磁盘、电量、网络速率与高占用进程。                                                              |
| 功能与设置       | 管理功能显示顺序，并在各功能面板中维护权限、快捷键和插件专属设置。                                              |
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

```bash
make setup      # 生成 LocalConfig.xcconfig，请填写 DEVELOPMENT_TEAM 与 BUNDLE_IDENTIFIER_PREFIX
make generate   # 使用 XcodeGen 生成 MacTools.xcodeproj
make build      # 编译校验
make run        # 本地运行
```

运行完整测试：

```bash
xcodebuild -project MacTools.xcodeproj -scheme MacTools -configuration Debug -derivedDataPath build/DerivedData test -quiet
```

贡献、测试和发布流程请参考 [CONTRIBUTING.md](CONTRIBUTING.md)。
GitHub Actions 自动构建与发布配置请参考 [docs/github-actions.md](docs/github-actions.md)。

## 许可证

MacTools 基于 [Apache License 2.0](LICENSE) 开源。

## 致谢

- 第三方素材、依赖与实现参考见 [Sources/Resources/ThirdPartyNotices](Sources/Resources/ThirdPartyNotices)。
- 贡献者

  <a href="https://github.com/ggbond268/MacTools/graphs/contributors">
    <img src="https://contrib.rocks/image?repo=ggbond268/MacTools&max=120&columns=12" width="480" alt="contributors">
  </a>
