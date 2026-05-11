# GitHub Actions 自动构建

本仓库提供三条流水线：

- `Build`：在 `main` push、Pull Request 和手动触发时运行。执行 XcodeGen、Debug 测试，并在非 PR 场景额外编译 unsigned Release app 做配置校验；不上传不可分发的未签名产物。
- `Release`：在推送 `v*.*.*` 或 `v*.*.*-*` tag，或手动输入 tag 时运行。构建 Release 版本，使用 Developer ID 签名、公证、打包 DMG，创建或更新 GitHub Release，并提交最新 `docs/appcast.xml`。
- `Deploy Pages`：仅在 `Release` 工作流成功完成后，或手动触发时运行。它把 `main` 分支上的 `docs/` 发布到 GitHub Pages；普通 push / PR 不会触发这条流水线。

## 需要配置的 Secrets

进入 GitHub 仓库：`Settings` → `Secrets and variables` → `Actions` → `Repository secrets`，添加以下条目。

| Secret | 用途 |
| --- | --- |
| `APPLE_DEVELOPMENT_TEAM` | Apple Developer Team ID，用于生成 `LocalConfig.xcconfig`。 |
| `BUNDLE_IDENTIFIER_PREFIX` | Bundle ID 前缀，例如 `com.example`，最终 app id 为 `<prefix>.mactools`。 |
| `DEVELOPER_ID_CERT_P12` | Developer ID Application 证书 `.p12` 文件的 Base64 内容。 |
| `DEVELOPER_ID_CERT_PASSWORD` | 导出 `.p12` 时设置的密码。 |
| `ASC_API_KEY_P8_BASE64` | App Store Connect API Key `.p8` 文件的 Base64 内容，用于 notarization。 |
| `ASC_API_KEY_ID` | App Store Connect API Key ID。 |
| `ASC_API_ISSUER_ID` | App Store Connect Issuer ID。 |
| `SPARKLE_PRIVATE_KEY` | Sparkle EdDSA 私钥，必须与 `project.yml` 中的 `SPARKLE_PUBLIC_ED_KEY` 配对。 |
| `HOMEBREW_GITHUB_API_TOKEN` | 可选。GitHub Personal Access Token，用于稳定版发布后自动向 `ggbond268/homebrew-mactools` 提交 cask 更新 PR；未配置时跳过 Homebrew 同步。 |

不要把 `LocalConfig.xcconfig`、`.p12`、`.p8`、Sparkle 私钥、证书密码或 Apple ID 写入仓库。

## 准备证书 Secret

1. 在 Keychain Access 中导出 `Developer ID Application` 证书和私钥为 `.p12`。
2. 给 `.p12` 设置一个强密码，并保存到 `DEVELOPER_ID_CERT_PASSWORD`。
3. 将 `.p12` 转为单行 Base64：

```bash
base64 -i DeveloperIDApplication.p12 | tr -d '\n' | pbcopy
```

4. 将剪贴板内容保存到 `DEVELOPER_ID_CERT_P12`。

## 准备公证 Secret

1. 在 App Store Connect 创建 API Key，并下载 `.p8` 文件。
2. 记录 Key ID 和 Issuer ID。
3. 将 `.p8` 转为单行 Base64：

```bash
base64 -i AuthKey_XXXXXXXXXX.p8 | tr -d '\n' | pbcopy
```

4. 将剪贴板内容保存到 `ASC_API_KEY_P8_BASE64`。
5. 将 Key ID 保存到 `ASC_API_KEY_ID`，Issuer ID 保存到 `ASC_API_ISSUER_ID`。

## 准备 Sparkle Secret

将当前发布使用的 Sparkle EdDSA 私钥保存到 `SPARKLE_PRIVATE_KEY`。它必须与 `project.yml` 中的 `SPARKLE_PUBLIC_ED_KEY` 配对，否则旧版本应用无法验证新的更新包。

如果你只在本机钥匙串中保存了 Sparkle 私钥，请先确认能用本机 `sign_update` 签名当前 DMG；不要为了 CI 随意生成新密钥，除非你计划同时处理已发布版本的更新兼容。

## 发布方式

`project.yml` 是发布版本源。发布前先更新：

```yaml
CURRENT_PROJECT_VERSION: 15
MARKETING_VERSION: 0.9.3
```

提交并推送版本号变更：

```bash
git add project.yml
git commit -m "Bump version to 0.9.3"
git push origin main
```

然后在同一个提交上打 tag 并推送：

```bash
git tag v0.9.3
git push origin v0.9.3
```

Release 工作流会校验 `v0.9.3` 与 `project.yml` 的 `MARKETING_VERSION: 0.9.3` 一致，并使用 `CURRENT_PROJECT_VERSION` 作为 Sparkle appcast 和 App 包里的 build 号。版本不一致时会直接失败，避免产物、tag 和 appcast 不一致。

也可以在 GitHub Actions 页面手动运行 `Release`，输入已存在的 tag，例如 `v0.9.3`；该 tag 指向的提交里仍必须已经更新 `project.yml`。

稳定版发布成功创建 GitHub Release 后，Release 工作流会在配置了 `HOMEBREW_GITHUB_API_TOKEN` 时用刚生成的 DMG URL 和 SHA-256 更新 `ggbond268/homebrew-mactools` 中的 `Casks/mactools.rb`，并打开更新 PR。预发布版本会跳过 Homebrew 同步；未配置该 secret 时也会跳过，不影响发布。

仓库设置中需要允许 workflow 写入：`Settings` → `Actions` → `General` → `Workflow permissions` 选择 `Read and write permissions`。

## GitHub Pages 发布源

为了避免普通 `main` push 触发 GitHub 内置的 `pages-build-deployment`，需要在仓库设置里把 Pages 发布源改为 Actions：

1. 进入 `Settings` → `Pages`。
2. 在 `Build and deployment` → `Source` 选择 `GitHub Actions`。
3. 保存后由本仓库的 `Deploy Pages` workflow 负责发布 `docs/`。

如果 Pages 仍配置为 `Deploy from a branch`，GitHub 会继续在所选分支有提交时自动运行内置的 `pages-build-deployment`。这个内置流水线不是由仓库里的 workflow YAML 控制的，不能只靠修改 `.github/workflows/` 禁止。

## 安全策略

- PR 构建不读取发布 Secrets，只执行未签名构建和测试。
- Release 工作流只使用 `contents: write` 创建或更新 GitHub Release，并把 `docs/appcast.xml` 提交回 `main`；普通 Build 工作流只有 `contents: read`。
- Deploy Pages 工作流只在 Release 成功后发布 `docs/`，使用 `contents: read`、`pages: write` 和 `id-token: write`。
- 签名证书导入临时 keychain，任务结束后清理。
- App Store Connect `.p8` 和 Sparkle 私钥只写入 runner 临时目录，使用后删除。
- 日志不主动输出 Team ID、Bundle 前缀、证书名称、私钥或证书内容。
