# Container Top Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give each group a full-width tab bar inside its container, and make any move of the bar or of a member window move the whole group.

**Architecture:** `TabGroup.bounds` becomes the container rectangle (bar plus content). Pure geometry rules in `GroupGeometry` decide the content rectangle, how a member's new rectangle turns into a container, and whether a reported rectangle is our own echo. `GroupCoordinator` keeps a live Accessibility handle per member, listens for member moves, and adopts them instead of reverting them. The bar is an AppKit panel that reports drags in screen coordinates.

**Tech Stack:** Swift 5, AppKit, SwiftUI, macOS Accessibility API, XCTest. macOS 14+.

**Spec:** `docs/plans/2026-11-25-container-topbar-design.md`

## Global Constraints

- Bar height 36pt, echo tolerance 3pt, settle delay 0.12s, Accessibility messaging timeout 0.25s. Each lives once, in `GroupGeometry` or as a named constant beside its use.
- `WindowBounds` uses Accessibility coordinates: origin top-left of the main display, y grows downward.
- Font weight at most `.medium`. No `strokeBorder`, `.bordered`, `.borderedProminent` or `.roundedBorder` on controls. No scale on press. Emphasis by colour.
- No in-place mutation of shared models where a copy works: build an updated `TabGroup` and upsert it.
- Files stay under 400 lines.
- The project file lists sources by hand (`objectVersion = 56`, ids `A1…` for build files and `A2…` for file references). Every new or deleted Swift file needs its `PBXBuildFile`, `PBXFileReference`, group and Sources entries updated, following the existing id pattern.
- The folder is not a git repository. Skip commit steps; do not run `git init`.
- Test command: `xcodebuild -project TabGroups.xcodeproj -scheme TabGroups -destination 'platform=macOS' test 2>&1 | tail -30`. Passing output ends with `** TEST SUCCEEDED **`.

## Review Focus

1. An app that refuses the requested size (Terminal's cell grid, fixed-size windows): the group must not loop or jitter. Pinned by `testConstrainedWindowReportIsAnEcho` (Task 1).
2. A window snapped to the very top of the screen: the bar must stay on screen. Pinned by `testAdoptionClampsBarToVisibleTop` (Task 1).
3. A saved file from before this change: windows must not shrink on first launch. Pinned by `testVersionOneGroupsGrowUpwardByBarHeight` (Task 2).
4. A group on a second display placed above or left of the main one (negative coordinates): bar placement must be right. Pinned by `testAppKitRectHandlesNegativeCoordinates` (Task 1).
5. A window shorter than the bar or a zero-height container: content height must not go negative. Pinned by `testContentHeightNeverNegative` (Task 1).

---

### Task 1: Geometry rules

**Files:**
- Create: `TabGroups/Geometry/GroupGeometry.swift`
- Create: `TabGroupsTests/GroupGeometryTests.swift`
- Modify: `TabGroups.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces:

```swift
enum GroupGeometry {
    static let barHeight: Double = 36
    static let tolerance: Double = 3
    static func contentBounds(of container: WindowBounds) -> WindowBounds
    static func barBounds(of container: WindowBounds) -> WindowBounds
    /// Container for a member that now sits at `member`. `visibleTop` is the top of the usable
    /// area of the member's screen, in Accessibility coordinates.
    static func container(adopting member: WindowBounds, visibleTop: Double) -> WindowBounds
    static func clamped(_ container: WindowBounds, visibleTop: Double) -> WindowBounds
    static func isEcho(_ reported: WindowBounds, of lastApplied: WindowBounds?) -> Bool
    static func appKitRect(for bounds: WindowBounds, mainDisplayHeight: Double) -> CGRect
}
extension WindowBounds {
    func translated(dx: Double, dy: Double) -> WindowBounds
    func distance(to other: WindowBounds) -> Double   // sum of absolute differences of x, y, width, height
}
```

- [ ] **Step 1: Write the failing tests** in `GroupGeometryTests.swift`

```swift
let c = WindowBounds(x: 100, y: 200, width: 800, height: 600)

func testContentSitsUnderBar() {
    XCTAssertEqual(GroupGeometry.contentBounds(of: c), WindowBounds(x: 100, y: 236, width: 800, height: 564))
    XCTAssertEqual(GroupGeometry.barBounds(of: c), WindowBounds(x: 100, y: 200, width: 800, height: 36))
}
func testContentHeightNeverNegative() {
    let tiny = WindowBounds(x: 0, y: 0, width: 300, height: 20)
    XCTAssertEqual(GroupGeometry.contentBounds(of: tiny).height, 0)
}
func testAdoptionGrowsUpwardSoMemberKeepsItsRectangle() {
    let member = WindowBounds(x: 300, y: 400, width: 700, height: 500)
    let adopted = GroupGeometry.container(adopting: member, visibleTop: 25)
    XCTAssertEqual(adopted, WindowBounds(x: 300, y: 364, width: 700, height: 536))
    XCTAssertEqual(GroupGeometry.contentBounds(of: adopted), member)
}
func testAdoptionClampsBarToVisibleTop() {
    let snapped = WindowBounds(x: 0, y: 25, width: 756, height: 957)
    let adopted = GroupGeometry.container(adopting: snapped, visibleTop: 25)
    XCTAssertEqual(adopted, snapped)   // bar inside the snapped area
    XCTAssertEqual(GroupGeometry.contentBounds(of: adopted), WindowBounds(x: 0, y: 61, width: 756, height: 921))
}
func testClampKeepsBottomEdge() {
    let above = WindowBounds(x: 0, y: 5, width: 400, height: 300)
    XCTAssertEqual(GroupGeometry.clamped(above, visibleTop: 25), WindowBounds(x: 0, y: 25, width: 400, height: 280))
}
func testEchoWithinTolerance() {
    let applied = WindowBounds(x: 10, y: 10, width: 500, height: 400)
    XCTAssertTrue(GroupGeometry.isEcho(WindowBounds(x: 11, y: 10, width: 500, height: 401), of: applied))
    XCTAssertFalse(GroupGeometry.isEcho(WindowBounds(x: 14, y: 10, width: 500, height: 400), of: applied))
    XCTAssertFalse(GroupGeometry.isEcho(applied, of: nil))
}
func testConstrainedWindowReportIsAnEcho() {
    // We asked for 800x564, the app took 797x555; its later report must not count as an outside move.
    let took = WindowBounds(x: 100, y: 236, width: 797, height: 555)
    XCTAssertTrue(GroupGeometry.isEcho(took, of: took))
}
func testAppKitRectHandlesNegativeCoordinates() {
    let b = WindowBounds(x: -1200, y: -300, width: 800, height: 36)
    XCTAssertEqual(GroupGeometry.appKitRect(for: b, mainDisplayHeight: 1117),
                   CGRect(x: -1200, y: 1117 + 300 - 36, width: 800, height: 36))
}
func testTranslated() {
    XCTAssertEqual(c.translated(dx: 5, dy: -7), WindowBounds(x: 105, y: 193, width: 800, height: 600))
}
```

- [ ] **Step 2: Add both files to the project file and run the tests.** Expected: build fails, `GroupGeometry` not found.
- [ ] **Step 3: Implement `GroupGeometry` and the `WindowBounds` extension.** `container(adopting:)` is `clamped` applied to the member grown upward by `barHeight`; `clamped` raises `y` to `visibleTop` while keeping the bottom edge. `isEcho` is `distance <= tolerance`.
- [ ] **Step 4: Run the tests.** Expected: `** TEST SUCCEEDED **`.

### Task 2: Saved-file migration

**Files:**
- Modify: `TabGroups/Persistence/GroupStore.swift`
- Modify: `TabGroupsTests/GroupStoreTests.swift`

**Interfaces:**
- Consumes: `GroupGeometry.barHeight`.
- Produces: `GroupDocument.currentSchemaVersion == 2`. From here on `TabGroup.bounds` means the container rectangle.

- [ ] **Step 1: Write the failing test**

```swift
func testVersionOneGroupsGrowUpwardByBarHeight() throws {
    let old = makeGroup("Old")   // bounds x10 y20 w800 h600
    // write {"schemaVersion":1,"groups":[old]} to fileURL with JSONEncoder
    let store = GroupStore(fileURL: fileURL)
    XCTAssertNil(store.loadError)
    XCTAssertEqual(store.groups.first?.bounds, WindowBounds(x: 10, y: -16, width: 800, height: 636))
}
```

- [ ] **Step 2: Run it.** Expected: FAIL, bounds unchanged.
- [ ] **Step 3: In `load()`, accept version 1 and map each group to a copy whose bounds have `y - barHeight` and `height + barHeight`; accept version 2 as is; anything else still throws `unsupportedSchema`.** Writing always uses version 2. Screen clamping is not done here; Task 4 clamps on restore.
- [ ] **Step 4: Run all tests.** Expected: `** TEST SUCCEEDED **`, including `testUnknownSchemaIsReportedAndPreserved`.

### Task 3: Full-width tab bar

**Files:**
- Modify: `TabGroups/TabStrip/TabStripView.swift` (rewrite)
- Modify: `TabGroups/TabStrip/TabStripPanel.swift` (rewrite; delete `GroupFramePanel`, `GroupFrameView`, `WindowScreenGeometry`)
- Modify: `TabGroups/TabStrip/TabStripCoordinator.swift`
- Create: `TabGroups/TabStrip/ScreenGeometry.swift`

**Interfaces:**
- Consumes: `GroupGeometry.barBounds(of:)`, `GroupGeometry.appKitRect(for:mainDisplayHeight:)`.
- Produces:

```swift
enum ScreenGeometry {
    static var mainDisplayHeight: Double            // frame.maxY of the main display
    static func visibleTop(for bounds: WindowBounds) -> Double   // Accessibility y of the usable top of the screen
                                                                  // holding the rect's centre; main screen if none
}
struct TabItem: Identifiable, Equatable { let id: UUID; let appName: String; let title: String; let icon: NSImage? }

final class TabStripPanel: NSPanel {
    var onDragChanged: ((CGSize) -> Void)?   // total offset since mouse down, Accessibility axes (dy positive = down)
    var onDragEnded: (() -> Void)?
    func update(tabs: [TabItem], selectedID: UUID?, onSelect: @escaping (UUID) -> Void, onRemove: @escaping (UUID) -> Void)
    func place(at container: WindowBounds)   // frame = bar rectangle of the container
    func orderAbove(windowNumber: Int)
}
final class TabStripCoordinator {
    func show(_ group: TabGroup, tabs: [TabItem], select:, remove:, dragChanged: @escaping (CGSize) -> Void,
              dragEnded: @escaping () -> Void, memberWindowNumbers: [CGWindowID])
    func place(groupID: UUID, at container: WindowBounds)
    func reorder(groupID: UUID, memberWindowNumbers: [CGWindowID])
    func hide(groupID: UUID)
}
```

- [ ] **Step 1: `ScreenGeometry`.** `visibleTop` converts the screen's `visibleFrame.maxY` to Accessibility y as `mainDisplayHeight - visibleFrame.maxY`.
- [ ] **Step 2: `TabStripView`.** Takes `tabs`, `selectedID`, `onSelect`, `onRemove`. A bar filling its panel (`maxWidth: .infinity`, height 36) on `.regularMaterial` with only the top corners rounded at 10. Tabs share the width equally, capped at 220pt each, left-aligned. Each tab: 16pt app icon, app name at 12pt regular (primary ink when selected, secondary otherwise), window title at 11pt secondary, truncated. Selected tab gets a `Color.primary.opacity(0.08)` fill with radius 7. A close glyph (`xmark`, 9pt medium) appears on hover only. No strokes, no bold, no drag gesture, no scale effect. Tab tap calls `onSelect`.
- [ ] **Step 3: `TabStripPanel`.** Borderless, non-activating, `.normal` level, clear background, no shadow, `[.fullScreenAuxiliary, .ignoresCycle]`. Keep one `NSHostingView` and update its root view in `update` rather than replacing the content view. Drag handling in `sendEvent(_:)`:
  - `leftMouseDown`: remember `NSEvent.mouseLocation`, forward to `super`.
  - `leftMouseDragged`: once the pointer is more than 3pt from the start, mark dragging; while dragging call `onDragChanged(CGSize(width: now.x - start.x, height: start.y - now.y))` and do not forward.
  - `leftMouseUp`: if dragging, call `onDragEnded`, clear state, do not forward (so a drag never selects a tab); otherwise forward.
  - Everything else forwards to `super`.
- [ ] **Step 4: `TabStripCoordinator`.** One `TabStripPanel` per group, no frame panel. `show` updates tabs, wires the drag callbacks, places the panel and orders it above the frontmost member window, reusing the existing `frontmostMemberWindowNumber` logic.
- [ ] **Step 5: Update the project file** (add `ScreenGeometry.swift`). The app target will not build until Task 4 updates the call sites; that is expected.

### Task 4: Coordinator: live handles, bar drag, adopting member moves

**Files:**
- Create: `TabGroups/Interaction/LiveWindowRegistry.swift`
- Create: `TabGroups/Interaction/GeometryObserverCenter.swift` (the `AXObserver` code moved out of the coordinator)
- Create: `TabGroups/Interaction/GroupCoordinator+Movement.swift`
- Modify: `TabGroups/Interaction/GroupCoordinator.swift`
- Modify: `TabGroups/WindowControl/AXWindow.swift`
- Modify: `TabGroups.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: everything from Tasks 1 and 3.
- Produces:

```swift
extension AXWindow {
    func setMessagingTimeout(_ seconds: Float)
    func isSameWindow(as other: AXUIElement) -> Bool   // CFEqual
}
final class LiveWindowRegistry {
    /// Live handle for a member: the remembered one if it still answers `bounds()`, otherwise a fresh
    /// match from `candidates` (remembered, with a 0.25s messaging timeout set). Nil when unmatched.
    func window(for member: WindowReference, among candidates: [DiscoveredWindow]) -> DiscoveredWindow?
    func forget(memberID: UUID)
    var lastApplied: [UUID: WindowBounds] { get }
    func recordApplied(_ bounds: WindowBounds, memberID: UUID)
}
final class GeometryObserverCenter {
    var onChange: ((_ groupID: UUID, _ memberID: UUID) -> Void)?
    func observe(group: TabGroup, resolve: (WindowReference) -> DiscoveredWindow?)
    func stop(groupID: UUID)
}
```

- [ ] **Step 1: `AXWindow` additions and `LiveWindowRegistry`.** Every place in the coordinator that today calls `WindowReferenceMatcher.match(member, among: availableWindows)` to act on a window goes through `registry.window(for:among:)` instead. `unmatchedMembers` keeps using the matcher so ambiguity is still reported.
- [ ] **Step 2: Move the observer code into `GeometryObserverCenter`** unchanged in behaviour, except that the callback calls `onChange` directly with no debounce.
- [ ] **Step 3: One placement helper in the coordinator.**

```swift
/// Places a member at the group's content rectangle and records what the window actually took.
@discardableResult
private func place(_ member: WindowReference, in group: TabGroup) -> WindowBounds?
```

  `createGroup`, `select`, `restore` and `reassign` use it. `createGroup` sets `group.bounds = GroupGeometry.container(adopting: first.bounds, visibleTop:)` so the first window keeps its place unless it touches the top edge. `restore` first replaces `group.bounds` with `GroupGeometry.clamped(...)`. `select` no longer overwrites `group.bounds` with what one app accepted.
- [ ] **Step 4: Bar drag** in `GroupCoordinator+Movement.swift`.
  - `dragChanged(groupID:offset:)`: on the first call remember the group's container as the drag origin. New container = origin translated by the offset. Move the bar panel there, and move only the selected member, position only (`AXWindow.move(to:)`), recording the applied bounds. Keep the working group in `activeGroupMoves`.
  - `dragEnded(groupID:)`: place every member at the content rectangle, upsert the group, forget the drag origin.
- [ ] **Step 5: Adopting a member move.** Replace `scheduleWindowBoundsSync` and `synchronizeGroupBounds` with:
  - `memberGeometryChanged(groupID:memberID:)`: ignore if a bar drag is active for the group. Read the member's bounds. Ignore if `GroupGeometry.isEcho(reported, of: registry.lastApplied[memberID])`. Otherwise compute `GroupGeometry.container(adopting: reported, visibleTop: ScreenGeometry.visibleTop(for: reported))`, store it as the pending container for the group, move the bar panel there at once, and (re)schedule a settle after 0.12s.
  - `settle(groupID:)`: if `NSEvent.pressedMouseButtons != 0`, reschedule and return. Otherwise set the group's bounds to the pending container, update `displayIdentifier`, place every member at the content rectangle (the source too, which is what nudges a top-snapped window down), upsert, and reorder the bar above the members.
- [ ] **Step 6: Follow app switches.** Observe `NSWorkspace.didActivateApplicationNotification`. For each group with a member owned by the activated process, find the member whose handle `isSameWindow(as:)` the app's `kAXFocusedWindowAttribute`; if it differs from `selectedMemberID`, upsert a copy with the new selection and refresh the bar. In every case reorder that group's bar above its members.
- [ ] **Step 7: Split to size.** `GroupCoordinator.swift` keeps lifecycle, scanning, create, select, remove, delete, reassign, restore and `show`. Movement lives in the extension file. Both under 400 lines. `show` builds `[TabItem]` with `NSRunningApplication.icon`.
- [ ] **Step 8: Build and run all tests.** Expected: `** TEST SUCCEEDED **`.

### Task 5: Groups window styling and README

**Files:**
- Modify: `TabGroups/StatusMenuView.swift`
- Modify: `TabGroups/Settings/UnmatchedWindowView.swift`, `TabGroups/Settings/PermissionHelpView.swift` (only where they break the styling rules)
- Modify: `README.md`

- [ ] **Step 1: Styling.** Replace `.semibold`/`.headline` with weight at most `.medium`. Replace `.bordered` and `.borderedProminent` with one shared borderless `ButtonStyle` (filled background, colour change on press, no scale). Replace `.roundedBorder` on the search field with `.plain` on a filled rounded background.
- [ ] **Step 2: README.** Rewrite the Use steps: the bar sits on top of the group, dragging it or any member window moves the group, and window managers such as Rectangle Pro can reposition it.
- [ ] **Step 3: Build and run all tests.** Expected: `** TEST SUCCEEDED **`.

### Task 6: Check by hand

- [ ] Build and launch the Debug app, create a group of two windows.
- [ ] Drag the bar: bar and visible window move together; the other window is underneath after release.
- [ ] Drag a member by its own title bar: the bar follows live; the other member follows on release; the dragged window does not jump.
- [ ] Use a Rectangle Pro shortcut on a member (left half, then bottom half): the group lands there; on the top edge the window sits 36pt lower with the bar above it.
- [ ] Click a tab, close a tab, click a member's Dock icon: selection and bar stay right.
- [ ] Group a Terminal window (it limits its size): no jitter or loop.
