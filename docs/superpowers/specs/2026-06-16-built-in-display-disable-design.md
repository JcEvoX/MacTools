# Built-in Display Disable Design

## Summary

Add a control for disabling the MacBook built-in display while an external display is available. The goal is to make the built-in panel stop participating in the active desktop topology, so the pointer cannot move into that screen area. This is not a brightness, shade, gamma, or black overlay feature.

The feature uses private macOS display configuration SPI and performs runtime availability checks. It is intentionally scoped to the built-in display and does not support disabling arbitrary external displays.

## Product Scope

The user-facing control is named "关闭内建显示屏". It lives with display controls, but its behavior is display topology management rather than brightness adjustment. The UI must show a clear recovery action named "恢复内建显示屏".

MVP behavior:

- Support MacBook built-in display only.
- Require at least one external display that is active and visible through `NSScreen.screens`.
- Reject mirror mode in the MVP instead of rewriting the user's display arrangement.
- Use session-scoped display configuration.
- Do not support disabling external displays.
- Do not claim support for Intel Macs unless runtime checks and manual validation prove it reliable.

## Non-Goals

- No permanent display configuration writes.
- No shelling out to `displayplacer`.
- No NVRAM, lid sensor, magnet, root, or privileged helper hacks.
- No brightness-0 or blackout fallback presented as display disable.
- No arbitrary monitor power control.

## Architecture

Introduce a display disable coordinator that owns all display-disable state and recovery behavior. The brightness controller should not directly call private display SPI.

Suggested units:

- `DisplayDisableCoordinator`: main state machine and public API for disabling/restoring the built-in display.
- `DisplayDisableService`: low-level display enumeration and enable/disable operations.
- `DisplayDisableStateStore`: short-lived persisted recovery snapshot for crash/relaunch handling.
- C shim for dynamic SPI lookup: resolves `SLSConfigureDisplayEnabled` first, then `CGSConfigureDisplayEnabled`.

The coordinator should expose a snapshot that the plugin can render:

- built-in display status: available, disabled, unavailable, unsupported, failed
- external survivor count
- whether disable action is currently allowed
- last error message

## Private SPI Boundary

The app should not link directly against private symbols. Use a C shim that dynamically resolves the symbol at runtime:

- Try `/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight` and `SLSConfigureDisplayEnabled`.
- Fall back to `CGSConfigureDisplayEnabled` through the default symbol table.
- Return a normal `CGError` failure when no symbol is available.

The Swift side should call this wrapper only inside a display configuration transaction:

1. `CGBeginDisplayConfiguration`
2. private configure display enabled/disabled call
3. `CGCompleteDisplayConfiguration(config, .forSession)`
4. cancel the transaction on any pre-complete failure

## Display Enumeration

Use active and online displays for different purposes:

- `CGGetActiveDisplayList`: active desktop topology and normal brightness list behavior.
- `NSScreen.screens`: displays visible to AppKit and usable by the user.
- `CGGetOnlineDisplayList`: recovery target lookup, because a disabled built-in display may no longer be active.

The built-in display should be identified through `CGDisplayIsBuiltin`. IDs are not durable, so recovery must fall back from stored IDs to online built-in display discovery.

## Safety Rules

The disable action is allowed only when all checks pass:

- A built-in display exists in online displays.
- The target is the built-in display.
- At least one external survivor exists.
- The survivor is active or visible through AppKit.
- The built-in display is not in a mirror set.
- The private SPI is available.
- No disable or restore transaction is already in progress.

After disabling, wait briefly for topology notifications to settle, then verify:

- The built-in display is absent from active displays and `NSScreen.screens`.
- At least one external survivor is still present.

If verification fails, immediately attempt to re-enable the built-in display and report the failure.

## State Machine

Coordinator states:

- `normal`
- `disabling(snapshot)`
- `disabled(snapshot)`
- `restoring(snapshot)`
- `failed(snapshot?, message)`
- `unsupported(reason)`

State transitions:

- `normal -> disabling`: user invokes disable and all safety checks pass.
- `disabling -> disabled`: SPI call completes and verification passes.
- `disabling -> failed`: SPI call or verification fails; coordinator attempts rollback.
- `disabled -> restoring`: user restores, app exits, external survivor disappears, or system sleep/wake reconciliation requires recovery.
- `restoring -> normal`: built-in display is active again or no disabled state remains.
- `restoring -> failed`: restore call fails; UI keeps showing the recovery action and error message.

## Topology Reconciliation

Reuse the existing display topology observer path:

- `CGDisplayRegisterReconfigurationCallback`
- `NSApplication.didChangeScreenParametersNotification`
- existing `DisplayTopologyRefreshing` debounce in `PluginHost`

Add coordinator reconciliation after topology changes. When the coordinator believes the built-in display is disabled:

- If all external survivors disappear, attempt restore immediately.
- If the built-in display reappears in active displays or `NSScreen.screens`, clear the disabled state.
- If display IDs changed, refresh the snapshot using online display discovery and stored metadata.

Also reconcile on:

- app launch
- app termination
- screen sleep
- screen wake
- session active changes when available

## Recovery Snapshot

Persist enough data to recover after crash or relaunch:

- created date
- built-in display ID
- built-in vendor/model/serial when available
- external survivor display IDs
- original main display ID
- whether session-scoped SPI was used

Do not trust the stored display ID blindly. On restore, prefer the stored online built-in display ID if present, otherwise find the current online built-in display.

## UI Behavior

Suggested panel content:

- section title: "内建显示屏"
- status text: "可用", "已关闭", "不可用", or "不支持"
- switch or button: "关闭内建显示屏"
- button: "恢复内建显示屏"
- short risk text when unsupported or failed

Suggested messages:

- no external display: "连接外接显示器后可关闭内建显示屏"
- mirror mode: "镜像显示时暂不支持关闭内建显示屏"
- unsupported SPI: "当前系统不支持关闭内建显示屏"
- risk note: "使用 macOS 非公开显示器接口，系统更新或扩展坞环境可能导致失败"

The restore action should remain visible whenever disabled or failed recovery state exists.

## Runtime Availability

The feature is part of the Display Brightness plugin by default. It does not require a compile-time feature flag. The plugin always renders the control and uses runtime SPI availability checks to decide whether the action is enabled.

If `SLSConfigureDisplayEnabled` / `CGSConfigureDisplayEnabled` cannot be resolved, the snapshot reports unsupported and the action is shown disabled.

## Testing

Unit tests should use fake display services and fake SPI service implementations. Do not rely on real display hardware in CI.

Required tests:

- Reject disable with no built-in display.
- Reject disable with no external survivor.
- Reject disable in mirror mode.
- Reject disable when SPI is unavailable.
- Disable success updates state only after verification passes.
- Verification failure attempts rollback and reports an error.
- External survivor removal while disabled attempts restore.
- Built-in display reappearing clears disabled state.
- Restore uses online display lookup, not active-only lookup.
- Stored display ID mismatch falls back to current online built-in display.
- Plugin action forwards disable/restore commands and renders status text.

Manual validation matrix:

- Apple Silicon MacBook with one USB-C external display.
- Apple Silicon MacBook with external display through dock.
- Close/open menu panel after disable.
- Disconnect external display while disabled.
- Sleep and wake while disabled.
- Quit and relaunch while disabled.
- Mirror mode rejection.

## Open Risks

Private SPI can change or fail on future macOS releases. Some display docks and adapters may change display IDs or delay topology stabilization after hot plug. Restore may fail on some hardware combinations; the UI must surface a clear recovery message instead of looping retries.

The MVP should remain conservative even if broader SPI support appears to work locally.
