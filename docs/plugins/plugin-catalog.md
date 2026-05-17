# MacTools Plugin Catalog

MacTools dynamic plugins use one catalog-driven flow for both production distribution and local development.

- Production reads `catalog.json` from GitHub Pages and downloads plugin packages from GitHub Releases.
- Local development reads a Debug-only `file://` catalog, usually configured with `MACTOOLS_PLUGIN_CATALOG_URL`.
- Both flows resolve a catalog entry into a local staged package, verify checksum and manifest compatibility, then install through the same package store.

## Catalog v1

```json
{
  "schemaVersion": 1,
  "catalogID": "com.ggbond.mactools.plugins",
  "generatedAt": "2026-05-16T12:00:00Z",
  "minimumHostVersion": "0.15.2",
  "pluginKitVersion": 1,
  "plugins": [
    {
      "id": "com.ggbond.mactools.demo",
      "displayName": "Demo",
      "summary": "示例插件",
      "version": "1.0.0",
      "minimumHostVersion": "0.15.2",
      "pluginKitVersion": 1,
      "capabilities": {
        "primaryPanel": true,
        "componentPanel": false,
        "configuration": true
      },
      "permissions": [],
      "package": {
        "url": "https://github.com/ggbond268/MacTools/releases/download/plugins-2026.05.17/Demo.mactoolsplugin.zip",
        "sha256": "...",
        "size": 1234567
      },
      "releaseNotesURL": "https://github.com/ggbond268/MacTools/releases/tag/plugins-2026.05.17"
    }
  ],
  "revoked": [],
  "signature": {
    "algorithm": "ed25519",
    "value": "..."
  }
}
```

Release catalogs must include an Ed25519 signature. Debug local catalogs may omit `signature`, but they still go through package checksum, manifest, staging, and same-team code signature validation.

## Local Development

The default local workflow is convention based:

```text
MacTools/
  Plugins/
    Demo/
      plugin.json
      Demo.bundle or an Xcode project that builds Demo.bundle
```

External plugin repositories can use the same structure:

```text
MacToolsPlugins/
  Demo/
    plugin.json
    Demo.bundle or an Xcode project that builds Demo.bundle
```

From the MacTools repository, build all local plugins and generate the Debug catalog:

```bash
make build-plugin
```

Or build one plugin by directory name or plugin ID:

```bash
make build-plugin PLUGIN=Demo
make build-plugin PLUGIN=com.example.mactools.demo
```

Generated output lives under:

```text
build/LocalPlugins/
  Packages/*.mactoolsplugin
  catalog.dev.json
```

Then run MacTools:

```bash
make run
```

`make run` starts the app executable directly so the catalog environment variable reaches the app process. If `MACTOOLS_PLUGIN_CATALOG_URL` is not already set and `build/LocalPlugins/catalog.dev.json` exists, Make uses that file automatically.

You can override the fixed directories:

```bash
make build-plugin LOCAL_PLUGIN_SOURCE_DIR=/path/to/plugins LOCAL_PLUGIN_BUILD_DIR=/path/to/build
make run MACTOOLS_PLUGIN_CATALOG_URL=file:///path/to/catalog.dev.json
```

For Debug runs, the catalog URL scheme selects the verification mode. A `file://` URL uses the local development catalog policy, where signatures are optional. An `https://` URL uses the production catalog policy, where the catalog signature is required:

```bash
make run MACTOOLS_PLUGIN_CATALOG_URL=https://ggbond268.github.io/MacTools/plugins/catalog.json
```

The app copies the package into its own staging and installed directories. Uninstall deletes only the installed copy under MacTools application support; it never deletes the plugin source directory or the local build directory.

## Release Flow

Recommended production flow is a batch plugin release:

1. Bump `plugin.json.version` only for plugins whose code or resources changed.
2. Push a batch tag such as `plugins-2026.05.17`.
3. The `Plugin Release` GitHub Action builds all plugin bundles in Release configuration.
4. The workflow signs every plugin bundle with the same Developer ID Team ID as MacTools.
5. The workflow zips each package as `*.mactoolsplugin.zip`.
6. The workflow uploads all plugin zips to the same GitHub Release.
7. The workflow generates and signs `docs/plugins/catalog.json`.
8. `Deploy Pages` publishes the signed catalog to GitHub Pages.

The release record looks like:

```text
GitHub Release: plugins-2026.05.17
  appearance.mactoolsplugin.zip
  calendar.mactoolsplugin.zip
  disk-clean.mactoolsplugin.zip
  ...
```

Each zip keeps the package root:

```text
appearance.mactoolsplugin/
  plugin.json
  Appearance.bundle/
    Contents/
      Info.plist
      MacOS/Appearance
      Resources/
      _CodeSignature/
```

Local dry-run packaging uses the same release asset script:

```bash
make package-plugins-release \
  PLUGIN_CODE_SIGN_IDENTITY="Developer ID Application: Example (TEAMID)" \
  PLUGIN_CATALOG_PRIVATE_KEY_BASE64="$PLUGIN_CATALOG_PRIVATE_KEY_BASE64" \
  PLUGIN_RELEASE_TAG=plugins-2026.05.17
```

Generated local output:

```text
build/PluginRelease/
  Assets/*.mactoolsplugin.zip
  catalog.json
docs/plugins/catalog.json
```

The lower-level scripts are still useful for external plugin repositories:

```bash
scripts/plugins/build-plugin-release-assets.sh \
  --base-url https://github.com/ggbond268/MacTools/releases/download/plugins-2026.05.17 \
  --catalog-output build/PluginRelease/catalog.json \
  --signed-catalog-output docs/plugins/catalog.json \
  --sign-identity "Developer ID Application: Example (TEAMID)"

scripts/plugins/generate-plugin-catalog.sh \
  --mode release \
  --base-url https://github.com/ggbond268/MacTools/releases/download/plugins-2026.05.17 \
  --output dist/catalog.json \
  --package dist/Demo.mactoolsplugin.zip \
  --release-notes-url https://github.com/ggbond268/MacTools/releases/tag/plugins-2026.05.17

scripts/plugins/sign-plugin-catalog.sh \
  --input dist/catalog.json \
  --output dist/catalog.signed.json \
  --private-key-base64 "$PLUGIN_CATALOG_PRIVATE_KEY_BASE64"
```

The catalog private key, Developer ID identity, and GitHub token must come from local environment variables or CI secrets. Do not commit them. The catalog public key is safe to embed in the app as `PLUGIN_CATALOG_PUBLIC_KEY`.

## Runtime Lifecycle

Install, update, enable, disable, and uninstall are immediate at the UI contribution level:

- Installed and enabled plugins contribute panels, components, settings, permissions, and shortcuts.
- Disabled plugins are removed from UI and function lists immediately.
- Uninstalled plugins are removed from UI immediately and package files are deleted.
- Already-loaded native code is not force-unloaded in-process. The executable code is fully released after the app restarts.

This keeps the native bundle lifecycle aligned with macOS loadable bundle constraints while preserving a predictable management UI.
