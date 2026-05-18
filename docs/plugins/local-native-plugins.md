# MacTools Local Native Plugins

MacTools supports trusted local native plugins through a host-owned package store and a shared `MacToolsPluginKit.framework`.

This phase intentionally supports only trusted local plugins built by the same developer identity as the host app. The host validates the plugin bundle signature before loading code. Disabling or uninstalling a plugin immediately removes its contributions from the UI and deletes package files when requested, while already-loaded native code is fully released after the app restarts.

For catalog-based installation, GitHub release distribution, and Debug `file://` development catalogs, see [plugin-catalog.md](plugin-catalog.md).

## Package Layout

Use a directory package with the `.mactoolsplugin` extension:

```text
Example.mactoolsplugin/
  plugin.json
  Example.bundle/
    Contents/
      Info.plist
      MacOS/Example
      Resources/
```

`plugin.json` is read before loading executable code:

```json
{
  "id": "com.example.mactools.demo",
  "displayName": "Demo",
  "version": "1.0.0",
  "minHostVersion": "0.15.2",
  "pluginKitVersion": 1,
  "bundleRelativePath": "Example.bundle",
  "factoryClass": "Example.ExamplePluginFactory",
  "capabilities": {
    "primaryPanel": true,
    "componentPanel": false,
    "configuration": true
  },
  "permissions": []
}
```

The plugin bundle must expose a factory that conforms to `MacToolsPluginBundleFactory`. The factory returns a `PluginProvider`, and the provider returns exactly one `MacToolsPlugin` instance for the package.

Source repositories can keep implementation and tests beside each plugin:

```text
Plugins/Example/
  plugin.json
  Sources/              # Plugin implementation and feature code
  Bundle/               # Thin bundle entrypoint that anchors the factory
  Tests/                # Optional XCTest files
  project.yml           # Optional build overrides for non-default plugins
  Resources/            # Optional plugin resources
```

Only `plugin.json` and the built `.bundle` are copied into a `.mactoolsplugin` package. `Tests/` is included only by the host unit-test target during development and is never packaged into the app or plugin distribution.

In this repository, plugin Xcode targets are generated before XcodeGen runs. The generator scans `Plugins/*/plugin.json` and applies a shared target template for `Sources/`, `Bundle/`, `Tests/`, plugin schemes, and the host test target. Most plugins do not need any root project changes. Add `Plugins/<PluginName>/project.yml` only for plugin-local build differences such as `OTHER_LDFLAGS`, `SWIFT_INCLUDE_PATHS`, extra bundle resources, or additional target dependencies.

The manifest ID is the stable identity of the package. It must match the runtime `PluginMetadata.id`, and a package must return exactly one plugin instance. Use lower-case, readable IDs such as `display-brightness` unless there is a strong reason to use a reverse-DNS identifier.

## Development Steps

To add a plugin, create `Plugins/<PluginName>/plugin.json`, `Sources/`, and `Bundle/`. Add `Tests/` when the behavior is testable. Most plugins can then run directly with:

```bash
make run
```

If the plugin needs extra frameworks, private include paths, bundle resources, or target dependencies, add only those differences in `Plugins/<PluginName>/project.yml`.

To test the plugin as a dynamic local package, build its package and Debug catalog first:

```bash
make build-plugin PLUGIN=<plugin directory or id>
make run
```

To update an existing plugin, change its code/resources/tests beside the plugin. If the update should be released through the plugin catalog, bump only that plugin's `plugin.json.version`, then run the focused build or tests before opening a PR.

## Settings UI

Plugin settings are hosted by MacTools. Prefer the descriptive surfaces first:

- Use `settingsSections` for simple status/action cards.
- Use `permissionRequirements` for system permission rows.
- Use `shortcutDefinitions` for global shortcut rows.
- Use `PluginConfiguration` only when the plugin needs a custom manager, list, editor, drag-and-drop surface, chart, or other interaction that cannot be expressed by the descriptive models.

Custom configuration views must provide only the plugin-specific content. The settings window header, plugin icon, plugin description, permission cards, and shortcut cards are derived by the host; do not repeat a full page title inside the custom view.

All custom settings views should use `MacToolsPluginKit.PluginSettingsTheme` for typography, spacing, radii, strokes, colors, and shared card backgrounds. This keeps the dependency direction clean: the host app and plugins both depend on `MacToolsPluginKit`, while plugins never depend on `Sources/App/SettingsStyle.swift`.

Recommended mapping:

- Page-level text: `PluginSettingsTheme.Typography.pageTitle` and `pageDescription`.
- Section labels: `Label` with an SF Symbol, `sectionTitle`, and `.foregroundStyle(.secondary)`.
- Row text: `rowTitle` or `emphasizedRowTitle`; supporting text uses `rowDescription`; status pills use `statusBadge`.
- Fixed-width numeric or path-like values may use `monospacedValue` or a local monospaced font when the content requires it.
- Layout: use `Spacing.section`, `sectionHeaderContent`, `cardContent`, `rowHorizontal`, `rowVertical`, `interactiveRowVertical`, and `rowContentControl`.
- Containers: use `.pluginSettingsCardBackground(.host)` for host-style cards, `.pluginSettingsCardBackground(.plugin)` for native plugin lists, and `.pluginSettingsCardBackground(.recessed)` for inset fields/log panes.

Avoid copying a plugin-local settings style enum. If a token is missing, add it to `PluginSettingsTheme` instead of hard-coding the same value in multiple plugins.

## Install Location

Installed plugins are copied into:

```text
~/Library/Application Support/MacTools/Plugins/
  Installed/
  Staging/
  Data/
  Caches/
  Temporary/
```

Debug builds use a separate application identity and storage root:

```text
~/Library/Application Support/MacTools Dev/Plugins/
```

Install and update are staged before moving into `Installed`. Per-plugin runtime context includes scoped `UserDefaults` storage plus support, cache, temporary, and bundle resource locations.

## Security Model

- Only local package directories ending in `.mactoolsplugin` are accepted.
- The manifest ID and bundle relative path are validated before loading code.
- Host version and plugin kit version are checked before loading code.
- The plugin bundle signature is validated before loading code.
- When the host has a Team ID, the plugin bundle must have the same Team ID.
- Untrusted third-party native plugins should use a future isolated process or XPC model instead of in-process bundle loading.

## Lifecycle

Plugins can implement:

```swift
func activate(context: PluginRuntimeContext)
func deactivate(reason: PluginDeactivationReason)
```

`deactivate` is called before disabling, updating, uninstalling, and host shutdown. Plugins should cancel tasks, timers, observers, event taps, windows, and other retained system resources there.

Native bundle code is treated as loaded for the lifetime of the current app process. If a loaded plugin is disabled, updated, or uninstalled, its contributions are removed from MacTools immediately and `deactivate` is called, but the executable code is considered fully released only after the app restarts. Updating a loaded plugin replaces the package files on disk and activates the new code on the next launch.
