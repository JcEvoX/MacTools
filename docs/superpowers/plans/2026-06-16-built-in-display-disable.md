# Built-in Display Disable Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a guarded experimental control that disables the MacBook built-in display while an external display remains available.

**Architecture:** Keep brightness control separate from display topology control. Add a testable display-disable coordinator and service inside `Plugins/DisplayBrightness`, with real system/SPI calls behind protocols and fake services in tests. Render the feature as action rows in the existing display brightness detail panel, so no host UI model changes are needed.

**Tech Stack:** Swift 6, XCTest, CoreGraphics, AppKit, a small C shim for private display SPI, XcodeGen plugin project fragments.

---

## Files

- Create `Plugins/DisplayBrightness/Sources/DisplayDisableModels.swift`: status enums, snapshots, errors, persisted recovery snapshot.
- Create `Plugins/DisplayBrightness/Sources/DisplayDisableCoordinator.swift`: state machine, safety checks, disable/restore flow, topology reconciliation.
- Create `Plugins/DisplayBrightness/Sources/DisplayDisableService.swift`: protocol plus CoreGraphics-backed real service for active/online displays and session-scoped enable/disable transactions.
- Create `Plugins/DisplayBrightness/Sources/DisplayEnableSPI.h`: C wrapper declaration.
- Create `Plugins/DisplayBrightness/Sources/DisplayEnableSPI.c`: runtime lookup for `SLSConfigureDisplayEnabled` and `CGSConfigureDisplayEnabled`.
- Modify `Plugins/DisplayBrightness/project.yml`: add C header search path if XcodeGen does not pick it up automatically.
- Modify `Plugins/DisplayBrightness/Sources/DisplayBrightnessPlugin.swift`: inject coordinator, refresh/reconcile topology, render action rows, handle disable/restore actions.
- Modify `Plugins/DisplayBrightness/Sources/DisplayBrightnessModels.swift`: extend `DisplayBrightnessControlling` only if plugin tests need an explicit display-disable dependency injection point.
- Modify `Plugins/DisplayBrightness/Tests/DisplayBrightnessTestSupport.swift`: fake display-disable service/coordinator helpers.
- Create `Plugins/DisplayBrightness/Tests/DisplayDisableCoordinatorTests.swift`: coordinator unit tests.
- Modify `Plugins/DisplayBrightness/Tests/DisplayBrightnessPluginInteractionTests.swift`: plugin UI/action tests.
- Modify `docs/superpowers/specs/2026-06-16-built-in-display-disable-design.md` only if implementation discoveries require narrowing the spec.

## Task 1: Coordinator Safety Checks

**Files:**
- Create: `Plugins/DisplayBrightness/Sources/DisplayDisableModels.swift`
- Create: `Plugins/DisplayBrightness/Sources/DisplayDisableCoordinator.swift`
- Create: `Plugins/DisplayBrightness/Sources/DisplayDisableService.swift`
- Create: `Plugins/DisplayBrightness/Tests/DisplayDisableCoordinatorTests.swift`
- Modify: `Plugins/DisplayBrightness/Tests/DisplayBrightnessTestSupport.swift`

- [ ] **Step 1: Write failing tests for basic safety rejection**

Add tests that construct `DisplayDisableCoordinator` with a fake service and verify:

```swift
func testDisableRejectsWhenBuiltInDisplayIsMissing() async {
    let service = FakeDisplayDisableService(
        onlineDisplays: [
            DisplayDisableDisplay(id: 2, name: "Studio Display", isBuiltin: false, isActive: true, isInMirrorSet: false, isVisibleToAppKit: true)
        ]
    )
    let coordinator = DisplayDisableCoordinator(service: service, store: InMemoryDisplayDisableStateStore())

    await coordinator.disableBuiltInDisplay()

    XCTAssertEqual(coordinator.snapshot.status, .unavailable)
    XCTAssertEqual(coordinator.snapshot.message, "未检测到内建显示屏")
    XCTAssertTrue(service.setEnabledCalls.isEmpty)
}

func testDisableRejectsWhenNoExternalSurvivorExists() async {
    let service = FakeDisplayDisableService(
        onlineDisplays: [
            DisplayDisableDisplay(id: 1, name: "内建显示屏", isBuiltin: true, isActive: true, isInMirrorSet: false, isVisibleToAppKit: true)
        ]
    )
    let coordinator = DisplayDisableCoordinator(service: service, store: InMemoryDisplayDisableStateStore())

    await coordinator.disableBuiltInDisplay()

    XCTAssertEqual(coordinator.snapshot.status, .available)
    XCTAssertEqual(coordinator.snapshot.message, "连接外接显示器后可关闭内建显示屏")
    XCTAssertTrue(service.setEnabledCalls.isEmpty)
}

func testDisableRejectsMirrorMode() async {
    let service = FakeDisplayDisableService(
        onlineDisplays: [
            DisplayDisableDisplay(id: 1, name: "内建显示屏", isBuiltin: true, isActive: true, isInMirrorSet: true, isVisibleToAppKit: true),
            DisplayDisableDisplay(id: 2, name: "Studio Display", isBuiltin: false, isActive: true, isInMirrorSet: true, isVisibleToAppKit: true)
        ]
    )
    let coordinator = DisplayDisableCoordinator(service: service, store: InMemoryDisplayDisableStateStore())

    await coordinator.disableBuiltInDisplay()

    XCTAssertEqual(coordinator.snapshot.status, .available)
    XCTAssertEqual(coordinator.snapshot.message, "镜像显示时暂不支持关闭内建显示屏")
    XCTAssertTrue(service.setEnabledCalls.isEmpty)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -project MacTools.xcodeproj -scheme MacTools -configuration Debug -derivedDataPath build/DerivedData test -quiet -only-testing:MacToolsTests/DisplayDisableCoordinatorTests
```

Expected: fail because the new coordinator and models do not exist.

- [ ] **Step 3: Implement minimal models and safety checks**

Create the model and protocol types:

```swift
struct DisplayDisableDisplay: Equatable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltin: Bool
    let isActive: Bool
    let isInMirrorSet: Bool
    let isVisibleToAppKit: Bool
    let vendorNumber: UInt32?
    let modelNumber: UInt32?
    let serialNumber: UInt32?
}

enum DisplayDisableStatus: Equatable {
    case available
    case disabled
    case unavailable
    case unsupported
    case busy
    case failed
}

struct DisplayDisableSnapshot: Equatable {
    let status: DisplayDisableStatus
    let isDisableAllowed: Bool
    let isRestoreAllowed: Bool
    let externalDisplayCount: Int
    let message: String?
}

protocol DisplayDisableServicing {
    var isSupported: Bool { get }
    func listDisplays() -> [DisplayDisableDisplay]
    func setDisplay(_ displayID: CGDirectDisplayID, enabled: Bool) throws
}
```

Create `DisplayDisableCoordinator` with `disableBuiltInDisplay()` that performs only the safety checks and updates `snapshot`. Add fake service/store helpers in test support.

- [ ] **Step 4: Run tests to verify they pass**

Run the same `xcodebuild ... -only-testing:MacToolsTests/DisplayDisableCoordinatorTests` command.

Expected: pass.

## Task 2: Disable Success, Verification, Rollback

**Files:**
- Modify: `Plugins/DisplayBrightness/Sources/DisplayDisableCoordinator.swift`
- Modify: `Plugins/DisplayBrightness/Sources/DisplayDisableModels.swift`
- Modify: `Plugins/DisplayBrightness/Tests/DisplayDisableCoordinatorTests.swift`

- [ ] **Step 1: Write failing tests for disable success and verification rollback**

Add tests:

```swift
func testDisableSuccessStoresStateAfterVerificationPasses() async {
    let builtIn = DisplayDisableDisplay(id: 1, name: "内建显示屏", isBuiltin: true, isActive: true, isInMirrorSet: false, isVisibleToAppKit: true)
    let external = DisplayDisableDisplay(id: 2, name: "Studio Display", isBuiltin: false, isActive: true, isInMirrorSet: false, isVisibleToAppKit: true)
    let service = FakeDisplayDisableService(onlineDisplays: [builtIn, external])
    service.displaysAfterDisable = [
        builtIn.withActive(false).withVisibleToAppKit(false),
        external
    ]
    let store = InMemoryDisplayDisableStateStore()
    let coordinator = DisplayDisableCoordinator(service: service, store: store)

    await coordinator.disableBuiltInDisplay()

    XCTAssertEqual(service.setEnabledCalls, [.init(displayID: 1, enabled: false)])
    XCTAssertEqual(coordinator.snapshot.status, .disabled)
    XCTAssertTrue(coordinator.snapshot.isRestoreAllowed)
    XCTAssertEqual(store.snapshot?.builtInDisplayID, 1)
}

func testDisableVerificationFailureRollsBackBuiltInDisplay() async {
    let builtIn = DisplayDisableDisplay(id: 1, name: "内建显示屏", isBuiltin: true, isActive: true, isInMirrorSet: false, isVisibleToAppKit: true)
    let external = DisplayDisableDisplay(id: 2, name: "Studio Display", isBuiltin: false, isActive: true, isInMirrorSet: false, isVisibleToAppKit: true)
    let service = FakeDisplayDisableService(onlineDisplays: [builtIn, external])
    service.displaysAfterDisable = [builtIn, external]
    let coordinator = DisplayDisableCoordinator(service: service, store: InMemoryDisplayDisableStateStore())

    await coordinator.disableBuiltInDisplay()

    XCTAssertEqual(service.setEnabledCalls, [
        .init(displayID: 1, enabled: false),
        .init(displayID: 1, enabled: true)
    ])
    XCTAssertEqual(coordinator.snapshot.status, .failed)
    XCTAssertEqual(coordinator.snapshot.message, "关闭内建显示屏失败，已尝试恢复")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run the coordinator test command.

Expected: fail because disable still stops after safety checks.

- [ ] **Step 3: Implement disable transaction and verification**

After safety checks:

- save a recovery snapshot before calling `setDisplay(..., enabled: false)`
- call service disable
- refresh displays from service
- verify built-in is not active and not visible to AppKit
- verify at least one original external survivor remains active or visible
- on verification failure, call service restore and set failed snapshot
- on success, mark disabled and expose restore allowed

- [ ] **Step 4: Run tests to verify they pass**

Run coordinator tests.

Expected: pass.

## Task 3: Restore and Topology Reconciliation

**Files:**
- Modify: `Plugins/DisplayBrightness/Sources/DisplayDisableCoordinator.swift`
- Modify: `Plugins/DisplayBrightness/Sources/DisplayDisableModels.swift`
- Modify: `Plugins/DisplayBrightness/Tests/DisplayDisableCoordinatorTests.swift`

- [ ] **Step 1: Write failing restore/reconcile tests**

Add tests:

```swift
func testRestoreUsesOnlineBuiltInDisplayWhenStoredIDChanged() async {
    let oldSnapshot = DisplayDisableRecoverySnapshot(
        createdAt: Date(timeIntervalSince1970: 1),
        builtInDisplayID: 1,
        vendorNumber: nil,
        modelNumber: nil,
        serialNumber: nil,
        survivorDisplayIDs: [2],
        originalMainDisplayID: 2
    )
    let currentBuiltIn = DisplayDisableDisplay(id: 9, name: "内建显示屏", isBuiltin: true, isActive: false, isInMirrorSet: false, isVisibleToAppKit: false)
    let external = DisplayDisableDisplay(id: 2, name: "Studio Display", isBuiltin: false, isActive: true, isInMirrorSet: false, isVisibleToAppKit: true)
    let service = FakeDisplayDisableService(onlineDisplays: [currentBuiltIn, external])
    let store = InMemoryDisplayDisableStateStore(snapshot: oldSnapshot)
    let coordinator = DisplayDisableCoordinator(service: service, store: store)

    await coordinator.restoreBuiltInDisplay()

    XCTAssertEqual(service.setEnabledCalls, [.init(displayID: 9, enabled: true)])
    XCTAssertNil(store.snapshot)
}

func testReconcileRestoresWhenExternalSurvivorDisappears() async {
    let disabledSnapshot = DisplayDisableRecoverySnapshot(
        createdAt: Date(timeIntervalSince1970: 1),
        builtInDisplayID: 1,
        vendorNumber: nil,
        modelNumber: nil,
        serialNumber: nil,
        survivorDisplayIDs: [2],
        originalMainDisplayID: 2
    )
    let builtIn = DisplayDisableDisplay(id: 1, name: "内建显示屏", isBuiltin: true, isActive: false, isInMirrorSet: false, isVisibleToAppKit: false)
    let service = FakeDisplayDisableService(onlineDisplays: [builtIn])
    let store = InMemoryDisplayDisableStateStore(snapshot: disabledSnapshot)
    let coordinator = DisplayDisableCoordinator(service: service, store: store)

    await coordinator.reconcileTopology()

    XCTAssertEqual(service.setEnabledCalls, [.init(displayID: 1, enabled: true)])
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run coordinator tests.

Expected: fail because restore/reconcile are not implemented.

- [ ] **Step 3: Implement restore and reconcile**

Implement:

- `restoreBuiltInDisplay()`
- `reconcileTopology()`
- recovery snapshot lookup by stored ID first, then current online built-in display
- clear store when built-in is already active/visible again
- restore when no survivor remains active/visible

- [ ] **Step 4: Run tests to verify they pass**

Run coordinator tests.

Expected: pass.

## Task 4: Real CoreGraphics Service and SPI Shim

**Files:**
- Create: `Plugins/DisplayBrightness/Sources/DisplayEnableSPI.h`
- Create: `Plugins/DisplayBrightness/Sources/DisplayEnableSPI.c`
- Modify: `Plugins/DisplayBrightness/Sources/DisplayDisableService.swift`
- Modify: `Plugins/DisplayBrightness/project.yml` if C sources or include paths are not generated correctly.

- [ ] **Step 1: Write service tests that avoid real SPI**

No unit test should invoke private SPI. Add a small test for mapping `DisplayInfo` plus fake active/visible sets if the service is decomposed enough. Otherwise keep real service untested by hardware-dependent tests and rely on coordinator fakes.

- [ ] **Step 2: Add C shim**

Implement:

```c
CGError MTConfigureDisplayEnabled(CGDisplayConfigRef config, CGDirectDisplayID display, bool enabled);
bool MTDisplayEnableSPIAvailable(void);
```

The implementation uses `dlopen`/`dlsym`, tries `SLSConfigureDisplayEnabled`, then `CGSConfigureDisplayEnabled`, and returns `kCGErrorFailure` if neither exists.

- [ ] **Step 3: Implement real service**

`SystemDisplayDisableService` should:

- list displays from `CGGetOnlineDisplayList`
- mark active displays using `CGGetActiveDisplayList`
- mark AppKit-visible displays from `NSScreen.screens`
- mark mirror state with `CGDisplayIsInMirrorSet`
- identify built-in with `CGDisplayIsBuiltin`
- call `CGBeginDisplayConfiguration`, `MTConfigureDisplayEnabled`, `CGCompleteDisplayConfiguration(config, .forSession)`
- cancel on failure before completion

- [ ] **Step 4: Run build or focused tests**

Run:

```bash
make generate
xcodebuild -project MacTools.xcodeproj -scheme MacTools -configuration Debug -derivedDataPath build/DerivedData test -quiet -only-testing:MacToolsTests/DisplayDisableCoordinatorTests
```

Expected: generated project includes C sources and coordinator tests pass.

## Task 5: Plugin UI Integration

**Files:**
- Modify: `Plugins/DisplayBrightness/Sources/DisplayBrightnessPlugin.swift`
- Modify: `Plugins/DisplayBrightness/Tests/DisplayBrightnessPluginInteractionTests.swift`
- Modify: `Plugins/DisplayBrightness/Tests/DisplayBrightnessTestSupport.swift`

- [ ] **Step 1: Write failing plugin tests**

Add tests:

```swift
func testExpandedDetailShowsBuiltInDisplayDisableActionWhenAllowed() {
    let brightness = MockDisplayBrightnessController()
    brightness.snapshotValue = DisplayBrightnessSnapshot(
        displays: [makeBrightnessDisplay(id: 2, name: "Studio Display", brightness: 0.7)],
        errorMessage: nil
    )
    let displayDisable = MockDisplayDisableCoordinator()
    displayDisable.snapshotValue = DisplayDisableSnapshot(
        status: .available,
        isDisableAllowed: true,
        isRestoreAllowed: false,
        externalDisplayCount: 1,
        message: nil
    )
    let plugin = DisplayBrightnessPlugin(controller: brightness, displayDisableCoordinator: displayDisable)

    plugin.handleAction(.setDisclosureExpanded(true))

    let controls = plugin.primaryPanelState.detail?.primaryControls ?? []
    let action = controls.first { $0.id == "built-in-display-disable" }
    XCTAssertEqual(action?.kind, .actionRow)
    XCTAssertEqual(action?.actionTitle, "关闭内建显示屏")
    XCTAssertTrue(action?.isEnabled == true)
}

func testDisableActionForwardsToCoordinator() async {
    let plugin = DisplayBrightnessPlugin(
        controller: MockDisplayBrightnessController(),
        displayDisableCoordinator: MockDisplayDisableCoordinator()
    )

    plugin.handleAction(.invokeAction(controlID: "built-in-display-disable"))

    let coordinator = plugin.testDisplayDisableCoordinator
    await waitUntil { coordinator.disableCallCount == 1 }
}
```

Use whatever test-only accessor or direct mock reference is simplest.

- [ ] **Step 2: Run plugin tests to verify they fail**

Run:

```bash
xcodebuild -project MacTools.xcodeproj -scheme MacTools -configuration Debug -derivedDataPath build/DerivedData test -quiet -only-testing:MacToolsTests/DisplayBrightnessPluginInteractionTests
```

Expected: fail because plugin has no disable coordinator and no action rows.

- [ ] **Step 3: Integrate coordinator into plugin**

Update `DisplayBrightnessPlugin`:

- add constants `built-in-display-disable` and `built-in-display-restore`
- inject coordinator with default `DisplayDisableCoordinator(service: SystemDisplayDisableService(), store: UserDefaultsDisplayDisableStateStore())`
- call coordinator `refreshSnapshot()` during `refresh()`
- call coordinator `reconcileTopology()` during `refreshDisplayTopology()`
- append an action row after brightness sliders when snapshot is supported/available/disabled/failed
- handle `.invokeAction` by launching a main-actor task for disable/restore and calling `onStateChange`

- [ ] **Step 4: Run plugin tests to verify they pass**

Run plugin interaction tests.

Expected: pass.

## Task 6: Lifecycle Recovery Hooks

**Files:**
- Modify: `Plugins/DisplayBrightness/Sources/DisplayBrightnessPlugin.swift`
- Modify: `Plugins/DisplayBrightness/Sources/DisplayDisableCoordinator.swift`
- Modify: `Plugins/DisplayBrightness/Tests/DisplayBrightnessPluginInteractionTests.swift`

- [ ] **Step 1: Write failing lifecycle tests**

Add tests that verify:

- `refreshDisplayTopology()` calls coordinator reconciliation.
- `deactivate(reason:)` asks coordinator to restore if disabled.
- `refresh()` refreshes coordinator snapshot without blocking brightness snapshot reads.

- [ ] **Step 2: Run tests to verify they fail**

Run plugin interaction tests.

Expected: fail for missing lifecycle calls.

- [ ] **Step 3: Implement lifecycle calls**

Implementation:

- `refreshDisplayTopology()` calls brightness refresh and starts coordinator reconciliation.
- `deactivate(reason:)` starts restore.
- If async task is needed, store and cancel it on deinit/deactivate.

- [ ] **Step 4: Run tests to verify they pass**

Run plugin interaction tests.

Expected: pass.

## Task 7: Runtime Availability and Project Generation

**Files:**
- Modify: `Plugins/DisplayBrightness/Sources/DisplayBrightnessPlugin.swift`
- Modify: `docs/superpowers/specs/2026-06-16-built-in-display-disable-design.md` if the runtime behavior differs from the design.

- [ ] **Step 1: Add runtime availability handling**

The feature is enabled by default. The plugin renders "关闭内建显示屏" and uses the service snapshot to disable the action when private SPI cannot be resolved at runtime.

- [ ] **Step 2: Regenerate project**

Run:

```bash
make generate
```

Expected: `MacTools.xcodeproj` updates and `Configs/GeneratedPlugins.yml` is created locally.

- [ ] **Step 3: Run focused tests**

Run coordinator and plugin interaction tests.

Expected: pass.

## Task 8: Final Verification

**Files:**
- No new files unless verification exposes a bug.

- [ ] **Step 1: Run focused DisplayBrightness tests**

Run:

```bash
xcodebuild -project MacTools.xcodeproj -scheme MacTools -configuration Debug -derivedDataPath build/DerivedData test -quiet -only-testing:MacToolsTests/DisplayDisableCoordinatorTests -only-testing:MacToolsTests/DisplayBrightnessPluginInteractionTests -only-testing:MacToolsTests/DisplayBrightnessControllerTests
```

Expected: pass.

- [ ] **Step 2: Run build**

Run:

```bash
make build
```

Expected: build exits 0.

- [ ] **Step 3: Inspect git diff**

Run:

```bash
git status --short
git diff --stat
```

Expected: changes are limited to the display brightness plugin, tests, generated project config if required, and the new docs.
