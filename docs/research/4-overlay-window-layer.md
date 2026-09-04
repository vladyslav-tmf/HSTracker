# How the overlay window layer works

Research note for issue [#4](https://github.com/vladyslav-tmf/HSTracker/issues/4).

Date: 2026-09-04. Repo state: `master`, working tree clean, head `b9217d6f`.

**Status: read-only investigation.** Nothing was built, nothing was run, Hearthstone was never launched. Every claim below is marked **[Verified]** (established by reading repo code or official Apple documentation), **[Inferred]** (follows from what was read but was not observed), or **[Open question]** (only running the app can settle it). Build-level context is not re-derived here, see `docs/research/2-build-on-xcode-26.md`.

---

## 1. Question

Issue #4 asks how the overlay window layer works and what a second app target would need to host its own. The wider context is issue #1: a new app target in this same repo with a modern SwiftUI overlay, the engine (`Logging`, `HearthWatcher`, `HearthMirror`, `Database`) extracted into a shared framework, and the new overlay window layer **following the existing approach** rather than reinventing it. So the point of this note is to record the mechanism and the traps, in particular the ones upstream took years to get right and that a rewrite would silently drop.

---

## 2. Verdict, in three sentences

HSTracker does not draw on top of the game, it keeps a separate borderless `NSPanel` with `.nonactivatingPanel` style, level `normalWindow + 1`, a transparent background and `ignoresMouseEvents = true`, and **manually sets its frame equal to the Hearthstone window's frame**, which it reads out of the Accessibility API in a polling loop roughly every 2 seconds. Clicks pass through because `ignoresMouseEvents` is a whole-window switch, and the exceptions for the parts that must be clickable are implemented **not** by hit-testing but by two `NSEvent` mouse monitors that flip that flag on and off depending on whether the cursor currently sits inside a rect that a SwiftUI child reported about itself through a `PreferenceKey`. SwiftUI lives inside that window as an `NSHostingView`, and the window itself comes from a xib whose `File's Owner` is `RootOverlayWindow`.

**The five traps most easily lost in a rewrite** (details in §3 and §4):

| # | Trap | Where |
| --- | --- | --- |
| 1 | `ignoresMouseEvents` is a **window** property, not a per-view one. One flag for the entire game-sized surface. All of the interactivity design exists to work around that | `RootOverlayWindow.swift:31-41` |
| 2 | `WindowManager.show()` resets `ignoresMouseEvents` to `Settings.windowsLocked` on every tick, via the inherited `updateFrames()`. The 150 ms fallback timer exists precisely because of this | `WindowManager.swift:432`, `OverWindowController.swift:48-51` |
| 3 | Entering or leaving fullscreen moves Hearthstone to a different macOS Space, and an already-shown window does not follow. An explicit hide+reshow plus `orderFrontRegardless()` is required | `Game.swift:650-670` |
| 4 | `NSPanel` defaults to `hidesOnDeactivate = true`. A panel decoded from a xib does not show this, a panel built in code must turn it off explicitly | `CardImageTooltip.swift:188`, [Apple](https://developer.apple.com/documentation/appkit/nswindow/hidesondeactivate) |
| 5 | When the game is minimised or not running, `reload()` silently keeps the **old** frame, and the overlay hangs where the window used to be | `SizeHelper.swift:42-120` |

---

## 3. How it works

### 3.1 Window creation and configuration

**[Verified]** The creation chain: `WindowManager.rootOverlay` (`WindowManager.swift:172-179`) lazily creates `RootOverlayWindow(windowNibName: "RootOverlayWindow")`. It is stored as `Any?` with a cast, because the whole class carries `@available(macOS 10.15, *)` and a stored property of a 10.15-only type cannot live in a class without that constraint. The same trick is used for `PlayerResourcesWindow` (`WindowManager.swift:154-170`).

The base class `OverWindowController: NSWindowController` (`OverWindowController.swift:12-52`) sets, in `windowDidLoad()`, everything common to all overlays:

- `backgroundColor = NSColor.clear` (`:18`)
- `isOpaque = false` (`:19`)
- `hasShadow = false` (`:20`)
- `acceptsMouseMovedEvents = true` (`:21`), without which `.mouseMoved` would never reach the local monitor
- `isFloatingPanel = true` when the window is an `NSPanel` (`:23-25`)

`RootOverlayWindow.windowDidLoad()` (`RootOverlayWindow.swift:25-42`) adds its own: the `NSHostingView`, the `contentView` assignment, `isOpaque = false` and `backgroundColor = .clear` again, `ignoresMouseEvents = true`, and the mouse monitors.

`styleMask`, `level` and `collectionBehavior` are **not** set here. They are set every single time in `WindowManager.show(controller:show:frame:title:overlay:)` (`WindowManager.swift:410-475`):

| What | Value | Line |
| --- | --- | --- |
| `level` | `CGWindowLevelForKey(.normalWindow) + 1` when `overlay: true`, otherwise plain `.normalWindow` | `:441-450` |
| `collectionBehavior` | `[.canJoinAllSpaces, .fullScreenAuxiliary]` if `Settings.canJoinFullscreen` (default `true`, `Settings.swift:163-164`), otherwise the empty set | `:452-457` |
| `styleMask` | `[.borderless, .nonactivatingPanel]` when windows are locked, otherwise `[.titled, .miniaturizable, .resizable, .borderless, .nonactivatingPanel]` | `:459-466` |
| show | `window.orderFront(nil)`, never `makeKeyAndOrderFront` | `:468` |

**How it avoids stealing focus.** Three independent mechanisms, each of them necessary:

1. `.nonactivatingPanel`. Apple defines it as "The window is a panel or a subclass of NSPanel that does not activate the owning app" ([docs](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel)). A click on such a panel does not activate HSTracker, so Hearthstone never loses focus.
2. `orderFront(nil)` rather than `makeKeyAndOrderFront(_:)`. There is no `override var canBecomeKey` or `canBecomeMain` anywhere under `UIs/` - the overlay windows simply never ask to become key. **[Verified]** by a whole-tree search: `canBecomeKey`/`canBecomeMain` appear in zero Swift files.
3. `ignoresMouseEvents = true`. Apple: "A Boolean value that indicates whether the window is transparent to mouse events" ([docs](https://developer.apple.com/documentation/appkit/nswindow/ignoresmouseevents)). While it is on, a click is not physically addressed to this window at all.

**Window level.** `CGWindowLevelForKey` is a Core Graphics API and Apple says plainly: "This function is not recommended for use in applications. (This function is provided for application frameworks that create and manage windows, like Cocoa.)" ([docs](https://developer.apple.com/documentation/coregraphics/cgwindowlevelforkey(_:))). Upstream deliberately bypasses `NSWindow.Level.floating` for precise control, and the code states the intent: "Place overlays just above Hearthstone (normal level) but below any system UI level so macOS Notification Center, menu bar, and status items can render above them" (`WindowManager.swift:441-443`). Apple documents level ordering as "Each level in the list groups windows within it in front of those in all preceding groups" ([docs](https://developer.apple.com/documentation/appkit/nswindow/level-swift.property)). `normalWindow + 1` is the gap between normal windows and `floating`, and no stock `NSWindow.Level` constant names it. **For a new target this line ports as-is**, but it is worth knowing that it is a deliberate choice, not an accident: `.floating` would sit noticeably higher and would cover system UI.

`FloatingCard` (the card popup) works differently and sits far higher: `CGWindowLevelForKey(.mainMenuWindow) - 1` (`WindowManager.swift:186`, `:206`, `:226`, `:346`). `CardTooltipPanel` uses `NSWindow.Level.floating + 1` (`CardImageTooltip.swift:185`).

**`collectionBehavior`.** Apple: `canJoinAllSpaces` is "The window can appear in all spaces", `fullScreenAuxiliary` is "The window displays on the same space as the full screen window" ([docs](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct)). Exactly those two are the minimum needed for an overlay to be visible over a fullscreen game. It is tied to a setting because the empty `collectionBehavior` in the `else` branch (`WindowManager.swift:456`) returns the window to ordinary single-Space behaviour, for users who do not want the overlay following them into other Spaces.

**The xib.** `RootOverlayWindow.xib` describes exactly one window and nothing else:

- `File's Owner` carries `customClass="RootOverlayWindow" customModule="HSTracker" customModuleProvider="target"` (`RootOverlayWindow.xib:9`), which **hardcodes the module**, see §4
- a single `window` outlet (`:11`)
- the window has `customClass="NSPanel"`, `hasShadow="NO"`, `restorable="NO"`, `releasedWhenClosed="NO"`, `visibleAtLaunch="NO"`, `allowsToolTipsWhenApplicationIsInactive="NO"` (`:16`)
- `contentRect` 480x270 (`:18`), entirely fictional, the real frame is set in code
- a `contentView` with `wantsLayer="YES"` (`:20`), the layer backing `NSHostingView` needs

**`hidesOnDeactivate`.** Apple: "The default value for `NSWindow` is `false`, the default value for `NSPanel` is `true`" ([docs](https://developer.apple.com/documentation/appkit/nswindow/hidesondeactivate)). The attribute is absent from the xib and no overlay class ever sets it. Meanwhile `CardTooltipPanel`, the one panel the code builds programmatically, sets `hidesOnDeactivate = false` explicitly (`CardImageTooltip.swift:188`). **[Inferred]** a panel decoded from a nib gets `NO` (because IB serialises the checkbox state and the box is unchecked), while a panel created by calling `NSPanel(contentRect:styleMask:backing:defer:)` gets the documented `YES` and would vanish the moment HSTracker loses activation, which is the moment the user clicks into the game. This is only established indirectly, by the fact that the programmatic panel had to set the flag explicitly. **For a new target that builds its window in code, this is a mandatory line.**

`NSPanel.isFloatingPanel` (`OverWindowController.swift:24`) is worth one more note. Apple lists the conditions under which a panel should float, and the last one is "It hides when the app is deactivated (the default behavior for panels)" ([docs](https://developer.apple.com/documentation/appkit/nspanel/isfloatingpanel)). HSTracker uses `isFloatingPanel` outside that documented scenario, since the panel deliberately does **not** hide on deactivation. It works, but it is a departure from the API's intent.

---

### 3.2 Click-through, and where the exceptions are

**[Verified]** The mechanism is described verbatim in a code comment (`RootOverlayWindow.swift:31-39`): "RootOverlay spans the whole Hearthstone client area and stays click-through by default - `ignoresMouseEvents` is a window-level switch, not per-view, so it can't be flipped wholesale without blocking clicks over the rest of the game window too."

Instead of hit-testing there are **four event sources, all of which funnel into one function**, `updateMouseThrough()` (`RootOverlayWindow.swift:82-98`):

1. **Global monitor**, `NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved])` (`:59-61`). Apple: "Installs an event monitor that receives copies of events the system posts to other applications... Note that your handler will not be called for events that are sent to your own application" ([docs](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:))). It sees mouse motion while the window is click-through, so it is what detects the cursor **entering** an interactive region.
2. **Local monitor**, `NSEvent.addLocalMonitorForEvents` (`:66-69`). Needed for exactly the reason that once `ignoresMouseEvents` is off, events are addressed to our window and the global monitor stops seeing them. It detects the cursor **leaving** the region.
3. **Combine subscription** on `viewModel.$interactiveRegions` (`:70-72`), re-evaluating when the set of regions changes rather than the cursor.
4. **Fallback timer at 0.15 s** (`:77-79`), commented as "if either failed to register (or events get dropped for some reason) this guarantees convergence within ~150ms instead of the window getting stuck non-click-through".

Note that `.mouseMoved` monitoring does **not** need the Accessibility permission. Apple restricts that requirement to keyboard events: "Key-related events may only be monitored if accessibility is enabled or if your application is trusted for accessibility access" ([docs](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:))). Accessibility is needed here for a different reason, see §3.3.

**How views declare themselves interactive.** Two `PreferenceKey`s:

- `InteractiveRegionPreferenceKey` (`RootOverlayView.swift:17-32`) collects a **list** of rects, not a union. The comment records the history: last-write-wins was enough at first, then a union, and both broke once the guides panel in the top-right corner and the Inspiration panel in the middle were on screen at once, because "Their bounding box covers most of the overlay, and every click inside it would stop falling through to Hearthstone" (`:26-28`). `reduce` does `append(contentsOf:)` (`:29-31`).
- `HoverRegionPreferenceKey` (`RootOverlayView.swift:40-47`) reports hover **without** claiming clicks. This is a port of HDT's `IsOverlayHoverVisible` (`RootOverlayViewModel.swift:50-61`). It backs the 350x120 `BgsTopBarMask` in the top-right corner (`RootOverlayView.swift:91-100`), which slides the minion browser's filter button out on hover while every click in that corner still falls through to the game. `updateFilterRegionHover()` (`RootOverlayWindow.swift:111-119`) is called **before** the `interactiveRegions` guard, so it keeps working while the overlay is fully click-through.

Both keys are read via `.onPreferenceChange` and written into `@Published` properties of the view model (`RootOverlayView.swift:180-185`, `RootOverlayViewModel.swift:48`, `:61`). The coordinate space is a named `rootOverlayCanvas` declared on the outer `GeometryReader` (`RootOverlayView.swift:179`), so region reports land in the same real post-scale pixel space as the `NSHostingView`'s own bounds.

**Trap #2 in detail.** `WindowManager.show()` calls `controller.updateFrames()` (`WindowManager.swift:432`) before every show. `RootOverlayWindow` does **not** override `updateFrames()`, so the inherited `OverWindowController.updateFrames()` (`OverWindowController.swift:48-51`) runs and does `self.window!.ignoresMouseEvents = Settings.windowsLocked`. And `updateRootOverlay()` runs at least every ~2 seconds (§3.3). So **the outer loop continuously overwrites whatever the mouse monitors decided**. The default for `windowsLocked` is `true` (`Settings.swift:227-228`), so the overwrite normally writes `true`, which matches the desired state. But the moment the user picks Window -> Unlock windows (`AppDelegate.swift:632-653`), every tick makes the entire game-sized overlay opaque to clicks and the fallback timer only puts it back 150 ms later. **[Inferred]** this, rather than abstract robustness, is what makes the fallback timer mandatory rather than cosmetic. **[Open question]** whether that 150 ms flicker is perceptible in practice with unlocked windows can only be settled by running the app.

**Card hover** is a separate, third mechanism (`RootOverlayWindow.swift:139-202`). A registry, `CardHoverRegistry.shared` (`CardImageTooltip.swift:96-120`), collects `CardHoverNSView` instances embedded through `NSViewRepresentable` in every card tile. On each mouse move `updateCardHover()` walks the registry and converts each view's bounds into screen coordinates via `nsView.convert(bounds, to: nil)` then `window.convertToScreen(_:)` (`:156-157`), comparing against `NSEvent.mouseLocation`. The comment explains why not a `PreferenceKey`: "preferences inside a ScrollView are not re-evaluated when the scroll position changes, producing systematically stale/wrong Y values" (`CardImageTooltip.swift:23-25`). It takes `last`, not `first`, because Inspiration tiles overlap by 8 pt (`RootOverlayWindow.swift:143-148`).

The cosmetic hover (a 1.05 tile scale) is done a **fourth** way, with an `NSTrackingArea` using `.activeAlways` (`CardImageTooltip.swift:489-511`), because "An NSTrackingArea is more reliable here than SwiftUI's `.onHover` because it fires even while the app is in the background (the overlay window is non-activating)" (`:486-488`).

**Summary of the exceptions:** four different interaction mechanisms inside one window, each existing because the ordinary SwiftUI route (`.onHover`, hit-testing) does not work in a window with `ignoresMouseEvents = true`. A rewrite that starts from `.onHover` will rediscover all four in turn.

---

### 3.3 Tracking the Hearthstone window

**[Verified]** All geometry lives in `SizeHelper.HearthstoneWindow` (`SizeHelper.swift:19-201`), with a single instance `SizeHelper.hearthstoneWindow` (`:203`).

**`reload()`** (`SizeHelper.swift:38-121`) makes two different queries and stitches them together:

1. `CGWindowListCopyWindowInfo(.excludeDesktopElements, kCGNullWindowID)` filtered on `kCGWindowOwnerName == "Hearthstone"` (the constant `CoreManager.applicationName`, `CoreManager.swift:30`), `kCGWindowLayer == 0` and `kCGWindowIsOnscreen == 1`, sorted by area, largest taken (`:39-46`). That yields `kCGWindowNumber` (used for screenshots) and `kCGWindowOwnerPID`. Apple describes the function as "Generates and returns information about the selected windows in the current user session" and warns "Generating the dictionaries for system windows is a relatively expensive operation" ([docs](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:))).
2. From the PID it builds `AXUIElementCreateApplication(pid)` and asks for `kAXFocusedWindowAttribute` (`:53-56`), then reads `AXFullScreen` (`:66-72`), `kAXPositionAttribute` and `kAXSizeAttribute` (`:74-87`).

**AX wins over CG**, and the reason is recorded in a comment: "kCGWindowBounds can return a stale Mission Control thumbnail rect for some time after MC dismisses, AX reflects HS's actual NSWindow.frame" (`:58-59`). The choice is the single line `axRect ?? CGRect(dictionaryRepresentation: bounds)` (`:99`), so CG remains the fallback. When AX is unavailable, `fullscreen` is derived crudely by comparing the frame against each screen's frame (`:111-118`), and the error is logged exactly once via the static `axErrorReported` flag (`:25`, `:89-92`).

**The Accessibility permission** is requested once at startup: `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt: true` (`AppDelegate.swift:98-103`). Without it the AX branch fails silently into the CG branch, and geometry gets worse (Mission Control ghosts, worse fullscreen detection) rather than disappearing.

**Coordinate conversion.** The `CGRect` from CG/AX is top-left origin, AppKit is bottom-left. The conversion is a single line, `frame.origin.y = screen.frame.maxY - rect.maxY` (`:106`), where `screen` is `NSScreen.screens.first`. Directly above it sits a candid comment: "**Warning: this function assumes that the first screen in the list is the active one**" (`:102-103`). So on a multi-monitor setup where the game is not on the first screen in the list, the vertical coordinate is offset. **[Verified]** from the code, **[Open question]** how visible that is in practice, which needs a real multi-monitor configuration.

**Window height and the titlebar.** `height` subtracts `SizeHelper.HearthstoneWindow.titlebarHeight` when the game is **not** fullscreen (`:129-132`). That height is measured once at startup by creating a throwaway `NSWindow` with the same `styleMask` and subtracting `contentRect` from `frame` (`AppDelegate.swift:339-345`), then stored in the static property inside `completeSetup()` (`:349`).

**The overlay's frame** comes from `SizeHelper.overHearthstoneFrame()` (`:242-250`), which returns `hearthstoneWindow.frame` with **no transformation at all**. The comment explains that running it through `relativeFrame()` would double-apply the scale and drift further the further the window sits from (0,0). This is what separates RootOverlay from every legacy AppKit overlay, which position themselves via `relativeFrame()` against a 1440x922 reference resolution (`:16-17`, `:163-184`).

**Cadence.** The polling loop is `Game.internalUpdateCheck()` (`Game.swift:1609-1640`), kicked off once from `Game.init()` (`Game.swift:1594-1598`) on its own serial queue `net.hearthsim.hstracker.guiupdate` (`Game.swift:209`), and rescheduling itself recursively with `_queue.asyncAfter(deadline: .now() + Game.guiUpdateDelay)` where `guiUpdateDelay = 0.5` (`Game.swift:42`). The logic:

- if an update was requested (`guiNeedsUpdate`, set by `updateTrackers()`, `Game.swift:249-254`), refresh everything immediately and reset the counter
- otherwise, **once every four ticks, that is roughly every 2 seconds**, call `SizeHelper.hearthstoneWindow.reload()` and compare the new frame against the old **plus** the fullscreen flag. The comment: "fullscreen-flag flips can leave `_frame` unchanged but still shift the 50px game-menu offset" (`Game.swift:1616`). Only if something changed does it reposition the overlays, `updateRootOverlay()` included

So: **the game window's frame is polled about once every 2 seconds, and between polls the overlay simply does not move.** `updateAllTrackers()` additionally calls `reload()` first thing (`Game.swift:212`), so any event that triggers a full GUI refresh gets fresh geometry at once.

**Events that force a refresh.** `Game.init()` subscribes to a list of events each of which calls `updateAllTrackers()` (`Game.swift:1563-1590`): `Events.space_changed`, `Events.hearthstone_closed`, `Events.hearthstone_running`, `Events.hearthstone_active`, `Events.hearthstone_deactived`, plus the setting changes `window_locked`, `auto_position_trackers`, `can_join_fullscreen`, `card_size`, `theme_token` and others. Those events are published by `CoreManager` from its `NSWorkspace` observers.

**The `NSWorkspace` subscriptions** (`CoreManager.startListeners()`, `CoreManager.swift:390-407`) are exactly five, all registered on `NSWorkspace.shared.notificationCenter` (`:392`), which Apple requires explicitly: "To receive this notification, use `NSWorkspace.notificationCenter` to register for it. If you use a different notification center to register, you won't receive the notification" ([docs](https://developer.apple.com/documentation/appkit/nsworkspace/didactivateapplicationnotification)).

| Notification | Handler | What it does |
| --- | --- | --- |
| `activeSpaceDidChangeNotification` | `spaceChange` (`:409-413`) | posts `Events.space_changed` |
| `didLaunchApplicationNotification` | `appLaunched` (`:415-437`) | reads the game's build number from its Info.plist, starts tracking, `setHearthstoneRunning(true)` |
| `didTerminateApplicationNotification` | `appTerminated` (`:439-454`) | stops tracking, `setHearthstoneRunning(false)` |
| `didActivateApplicationNotification` | `appActivated` (`:456-470`) | `setHearthstoneActived(true)` plus `setSelfActivated(false)` |
| `didDeactivateApplicationNotification` | `appDeactivated` (`:472-482`) | `setHearthstoneActived(false)` |

Inside those handlers the game is identified **by `app.localizedName == "Hearthstone"`** (`:417`, `:441`, `:459`, `:474`), while finding the running process uses the **bundle id** `unity.Blizzard Entertainment.Hearthstone` (`:500-503`). Two different criteria for the same game. The same `"Hearthstone"` string literal is hardcoded again in `CardTooltipPanel` (`CardImageTooltip.swift:214`).

**When the game loses focus.** `setHearthstoneActived(flag:)` (`Game.swift:148-159`) writes `hearthstoneRunState.isActive`. `updateRootOverlay()` reads it (`Game.swift:646`), and if `Settings.hideAllWhenGameInBackground` is on it hides the overlay via `windowManager.show(controller: win, show: false)`. **The default for that setting is `false`** (`Settings.swift:217-218`), so **by default the overlay stays visible even when the game is not active**.

**When the game is minimised or not running.** The filter in `reload()` requires `kCGWindowIsOnscreen == 1` (`:43`). A minimised window fails it, no dictionary matches, and the whole `if let info = ...` block (`:42-120`) simply **does not execute, and there is no `else` branch**. So `_frame`, `windowId`, `fullscreen` and `screenRect` all keep their previous values. **[Verified]** from the code. **[Inferred]** the overlay stays parked at the last known position and size, and `internalUpdateCheck` sees no frame change so it does not even try to reposition. Since `hideAllWhenGameInBackground` is off by default, nothing hides it either. **[Open question]** what the user actually sees when minimising the game can only be settled by running it.

**Fullscreen.** This is the subtlest part, and it is handled separately in `updateRootOverlay()` (`Game.swift:643-675`):

```
let fullscreenChanged = rootOverlayLastFullscreenState != nil && rootOverlayLastFullscreenState != isFullscreen
...
if fullscreenChanged { windowManager.show(controller: win, show: false) }
windowManager.show(controller: win, show: true, frame: frame, overlay: true)
if fullscreenChanged { win.window?.orderFrontRegardless() }
```

The comment (`Game.swift:655-663`) explains: "Entering/leaving fullscreen moves Hearthstone to a different macOS Space. A window that was already shown before the transition doesn't automatically get recomposited into the new Space... An explicit hide+reshow forces the window server to re-evaluate Space membership for the new frame/collectionBehavior." **This is exactly the kind of knowledge a rewrite loses silently**: without the hide+reshow the overlay just disappears on the fullscreen transition, and `collectionBehavior` alone does not save it.

**Display configuration changes.** **[Verified]** There is **no subscription anywhere in the repo** to `NSApplication.didChangeScreenParametersNotification` and no `CGDisplayRegisterReconfigurationCallback` (a whole-tree search returns zero matches). Apple describes that notification as "Posted when the configuration of the displays attached to the computer is changed", covering a display being added, a display being removed, resolution changes and arrangement changes ([docs](https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification)). So **plugging in or unplugging a monitor, or changing resolution, is handled purely by the ~2 second poll**, and only to the extent that it changes the game window's frame.

Worse, two cached values are **never** refreshed at all:

- `WindowManager.screenFrame` is a `static let` computed as `NSScreen.main!.frame` on first access and kept for the life of the process (`WindowManager.swift:25-27`), along with the derived `WindowManager.top` (`:28-30`). It is the fallback tracker position when auto-positioning is off (`Game.swift:310-315`). The force-unwrap of `NSScreen.main!` is here too, and again in `OverWindowController.setWindowSizes()` (`OverWindowController.swift:42`).
- `SizeHelper.HearthstoneWindow.titlebarHeight` is a `static var` set exactly once from `completeSetup()` (`AppDelegate.swift:349`).

**[Inferred]** after a display configuration change both values are wrong until the app restarts. For RootOverlay this does not matter much (it takes `overHearthstoneFrame()` directly), for the legacy trackers it does.

---

### 3.4 How SwiftUI gets inside that window

**[Verified]** `NSHostingView<RootOverlayView>` is created in `windowDidLoad()` and installed as the xib window's `contentView` (`RootOverlayWindow.swift:27-28`). Apple: "An AppKit view that hosts a SwiftUI view hierarchy... You use `NSHostingView` objects to integrate SwiftUI views into your AppKit view hierarchies" ([docs](https://developer.apple.com/documentation/swiftui/nshostingview)), available from macOS 10.15, which is where the `@available(macOS 10.15, *)` on the whole class comes from.

So **the xib exists for exactly one purpose: to hand over a pre-configured `NSPanel`**. It contains no layout, and the `contentView` it carries is replaced immediately. The other pattern in this repo, `CountersOverlay` (`CountersOverlay.swift:55-60`), does the same thing but keeps no reference to the hosting view and retrieves it by casting `window?.contentView as? NSHostingView<...>` (`:64`) in order to replace `rootView` wholesale. RootOverlay went further: `rootView` is never rebuilt, an `ObservableObject` is mutated instead.

**Scaling.** `RootOverlayView` (`RootOverlayView.swift:55-187`) measures its own bounds with a `GeometryReader` and derives the scale as `geometry.size.height / 1080` (`:65`) and the canvas width as `geometry.size.width / scale` (`:66`). All game-relative content lives in an inner `ZStack` of fixed size `canvasWidth x 1080` with `.scaleEffect(scale, anchor: .center)` and an explicit `.position(...)` centering it (`:146-148`). The comment explains why the explicit `.position()` rather than relying on the hosting view: "rather than relying on NSHostingView's implicit placement of a fixed-size (canvas, pre-scale) root view within its actual (post-scale) bounds, which doesn't reliably line up" (`:60-63`). Fixed-size UI chrome (`ConstructedMulliganPreLobbyWidgetView`, `MulliganGuideTrialsExhaustedView`, the anomaly guide triggers) is deliberately placed **outside** that transform (`:150-171`).

That single scaled canvas is the entire reason RootOverlay exists. `RootOverlayViewModel.swift:12-19` states the goal: "Single scaled canvas new SwiftUI overlay features attach to as children, instead of each feature owning its own window + hand-rolled height/1080 scaling math (what every AppKit overlay, including the V1 mulligan guide, currently does individually)."

**How game state reaches the view model.** `RootOverlayViewModel` (`RootOverlayViewModel.swift:21-62`) is a container of thirteen child view models created as `let` properties (`:22-34`), plus the two `@Published` interaction-geometry properties. It **pulls nothing**. It is filled from outside.

The push path, always one-directional, engine to UI:

```
log parser / watcher
  -> Game.updateXxx()
    -> DispatchQueue.main.async
      -> windowManager.rootOverlay?.viewModel.<sub-model>.update(...)
```

The shortest and most representative example is `Game.updateTurnCounterOverlay()` (`Game.swift:797-804`): a `DispatchQueue.main.async` wrapper, an `if #available(macOS 10.15, *)` inside, and one call to `viewModel.battlegroundsTurnCounter.update(turn:isShown:)`. Dozens of `Game` methods follow the same shape. `@Published`/`ObservableObject` does the rest: `RootOverlayView` holds `@ObservedObject var viewModel` (`RootOverlayView.swift:56`), and each child view holds its own sub-model.

**Threading.** Parsers and watchers run on their own queues (`Watcher` creates one serial queue per watcher, `Watcher.swift:34-37`, and spins `Thread.sleep(forTimeInterval: delay)` inside `watch()`, `:89-117`). Every `update*` method on `Game` wraps its own body in `DispatchQueue.main.async` **itself**, so the threading discipline rests on convention, not on types. `@MainActor` exists but only in spots: `WindowManager.show` (`WindowManager.swift:410`) and `CountersOverlay.updateVisibleCounters` (`CountersOverlay.swift:70`). `WindowManager.show` still carries a manual `if !Thread.isMainThread { DispatchQueue.main.async { ... } }` bounce (`:415-420`), so even the annotation is not fully trusted.

The one **pull** path is `Game.pollMulliganLiveState()` (`Game.swift:121-132`): it reads `MirrorHelper.getMulliganLiveState()` from a background queue every **16 ms** and pushes the result into `viewModel.mulliganGuideV2.updateLiveMulliganState(...)` via `DispatchQueue.main.async`. The comment (`Game.swift:105-107`) calls this a port of HDT's `MulliganStateWatcher` cadence.

**The window's own visibility** is only ever updated from `updateRootOverlay()` (`Game.swift:643-675`), which is called from four places: `updateAllTrackers()` (`:231`), `internalUpdateCheck()` on a frame change (`:1626`), the `hearthstoneRunState.didSet` observer (`:69`, `:80`), and indirectly from `stopTracking()` through the sub-model resets (`CoreManager.swift:358-370`).

---

## 4. The seam: what moves, what needs a parameter, what must be reimplemented

This is the part that matters. The split is by what physically blocks a second app target linking a shared framework.

### 4.1 Reusable as-is

| What | Why it moves |
| --- | --- |
| `SizeHelper.HearthstoneWindow` (`SizeHelper.swift:19-201`) | Pure CG plus AX. Knows nothing about `AppDelegate`, `Settings` or windows. Its only external ties are `CoreManager.applicationName` (`:43`) and the `titlebarHeight` static someone has to set |
| `OverWindowController` (`OverWindowController.swift:12-52`) | One touch of `Settings` (`cardSize`, `windowsLocked`), the rest is plain AppKit |
| The `ignoresMouseEvents` plus two monitors plus fallback-timer machinery (`RootOverlayWindow.swift:54-125`) | Depends on nothing outside its own window and its own view model |
| Both `PreferenceKey`s and the canvas scheme (`RootOverlayView.swift:17-52`, `:64-148`) | Pure SwiftUI |
| `RootOverlayViewModel` (`RootOverlayViewModel.swift:21-62`) | A container of sub-models, zero external dependencies |
| `Watcher` base class (`Watcher.swift:20-118`) | Self-contained, `ManagedAtomic` plus `NSLock` |
| xib lookup through `NSWindowController` | **Not a trap, contrary to expectation.** Apple documents `loadWindow()`: "It uses the `Bundle` class's `init(for:)` method to get the bundle, using the class of the nib file owner as argument. It then locates the nib file within the bundle and, if successful, loads it, if unsuccessful, it tries to find the nib file in the main bundle" ([docs](https://developer.apple.com/documentation/appkit/nswindowcontroller/loadwindow())). A class in a framework with its xib in the same framework resolves correctly, with main-bundle fallback |

### 4.2 Needs a parameter or a small change

| What | What to do |
| --- | --- |
| `WindowManager` (`WindowManager.swift:12`) | It is a **plain class, not a singleton** - `Game` creates it as `let windowManager = WindowManager()` (`Game.swift:40`), and `CoreManager` creates `Game` (`CoreManager.swift:55-56`). Ownership is already parameterised. The real problem is different: `WindowManager` constructs **all 30+ windows eagerly** in its property initialisers. A new target does not want that `WindowManager`, it wants a split between "the RootOverlay part" and "the legacy AppKit trackers part", or a protocol |
| `Toaster` (`Toaster.swift:11-17`) | **The one example of proper DI in the codebase**, `init(windowManager: WindowManager)`. The model to follow |
| `WindowMove` (`WindowMove.swift:33-41`) | Second example, `weak var windowManager` plus `convenience init(windowNibName:windowManager:)`. Debug only (`#if DEBUG`, `AppDelegate.swift:655-663`) |
| `SizeHelper.HearthstoneWindow.titlebarHeight` (`SizeHelper.swift:127`) | A static set once by `AppDelegate.completeSetup()` (`AppDelegate.swift:349`). Inside a framework it has to become an init parameter or be computed lazily by `HearthstoneWindow` itself |
| `CoreManager.applicationName = "Hearthstone"` (`CoreManager.swift:30`) | The same literal is hardcoded again in `CardImageTooltip.swift:214` and used by `localizedName` in four `NSWorkspace` handlers (`:417`, `:441`, `:459`, `:474`), while `hearthstoneApp` matches on the bundle id (`:500-503`). Collapse to one constant |
| `Settings` (`Settings.swift:29-49`) | A `@propertyWrapper UserDefault` over `UserDefaults.standard`, ~168 static properties, every setter posting a `NotificationCenter` notification named after the key (`:44-47`). It moves into a framework mechanically, but **`UserDefaults.standard` is the bundle-id domain**, so two app targets get **two independent sets of settings** unless a shared suite is configured |
| Preference migration from the old bundle id (`AppDelegate.swift:104-110`) | Keyed on `Bundle.main.bundleIdentifier`. In a second target it is either unnecessary or has to read from the first |
| The Accessibility permission (`AppDelegate.swift:98-103`) | `AXIsProcessTrustedWithOptions` with the prompt. TCC grants are **per bundle**, so a second target means a second entry in System Settings and a second dialog. The same holds for `com.apple.security.cs.debugger` and `task_for_pid`, see `docs/research/2-build-on-xcode-26.md` §3.9 |
| `hidesOnDeactivate` | If the new window is built in code rather than loaded from a xib, set it to `false` explicitly, the way `CardTooltipPanel` does (`CardImageTooltip.swift:188`) |

### 4.3 Must be reimplemented

| What | Why |
| --- | --- |
| **`AppDelegate.instance()`** (`AppDelegate.swift:23-29`) | A singleton that `fatalError`s on nil. **237 calls across 112 files**, of which **68 are inside `UIs/Battlegrounds`, `UIs/Overlay` and `UIs/Constructed`**, that is, inside exactly the SwiftUI code that would move into the framework. Each one is `AppDelegate.instance().coreManager.game`. A framework cannot reference the app target's `AppDelegate`. This is **the single largest blocker**, and it cannot be papered over with a parameter, it needs `Game` threaded down explicitly |
| **`Watchers`** (`Watchers.swift:11-27`) | 16 static `let` instances, and `initialize()` (`:29+`) wires their callbacks straight to `AppDelegate.instance().coreManager.game` (`:33`, `:41`, `:44`, `:55`) and to `CoreManager` statics (`:49`, `:52`, `:59`). One global watcher set per process, so **two app targets in one process are impossible**, and in separate processes each would read the game's memory independently |
| **`CardHoverRegistry.shared`** (`CardImageTooltip.swift:96-120`) and **`CardTooltipPanel.shared`** (`:145-146`) | Global singletons wired into one specific window's `updateCardHover()` loop (`RootOverlayWindow.swift:149`, `:177`, `:188`, `:199`). The registry does filter on `nsView.window === overlayWindow` (`:151`), so it is **almost** multi-window ready, but `CardTooltipPanel.shared` is one panel per process with one `currentCardId`. Two overlays would fight over it |
| `RelatedCardsTooltipPanel.shared`, `RelatedCardsBrowserPanel.shared` | Same pattern, reached from `WindowManager` (`:249`) and `hideGameTrackers()` (`:297-298`) |
| **`Bundle.main` in UI code** | `Image("taunt")`, `Image("border")` and friends (`BattlegroundsMinionArtView.swift:133`, `:149`, `:254`). SwiftUI documents the parameter as "The bundle to search for the image resource and localization content. If `nil`, SwiftUI uses the main `Bundle`. Defaults to `nil`" ([docs](https://developer.apple.com/documentation/swiftui/image/init(_:bundle:))). Inside a framework **every one of those silently renders an empty image**. Plus `Bundle.main.resourcePath` for the tier badges (`BattlegroundsMinionArtView.swift:249-251`) and for localisation (`String.swift:81-95`, `Bundle.main.path(forResource: "Base", ofType: "lproj")`). Across `UIs/`, `Core/` and `Utility/` there are **17 files using `Bundle.main`** |
| **`customModuleProvider="target"` in the xib** (`RootOverlayWindow.xib:9`) | `customModule="HSTracker"` plus `customModuleProvider="target"` means "the class comes from the current target's module". Once the class lives in a framework this has to become `customModule="<FrameworkName>"` without `customModuleProvider`, otherwise the nib will not find the class at runtime. The same applies to the project's other 70 xibs |
| **`NSApp.addWindowsItem` / `removeWindowsItem`** (`WindowManager.swift:425-427`, `:471`) | Overlays register themselves in the app's Window menu. RootOverlay does not hit this path (no `title` is passed, `Game.swift:667`) but the rest do. It assumes exactly one `NSApplication` with exactly one Window menu |
| **Infrastructure singletons encountered along the way** | `AppHealth.instance` (`CoreManager.swift:122`), `MirrorHelper` (entirely static), `SizeHelper.hearthstoneWindow` (`SizeHelper.swift:203`), and `logger` as a global (`AppDelegate.swift:11`). All of them are "exactly one instance per process" |
| **Dead code in `WindowManager`** | `var hearthstoneActive` (`:14`) and the private `setHearthstoneActive()`/`setHearthstoneBackground()` (`:278-279`) are called from nowhere. Do not carry them across |

### 4.4 One structural conclusion

**[Inferred]** The overlay window layer is itself almost entirely portable - the mechanism in §3.1 through §3.4 has few ties to the application lifecycle. What is welded to the app is not the *window*, it is **the route by which game state reaches it**: `AppDelegate.instance().coreManager.game` as the way to reach the engine from anywhere in the UI. While that call appears in 68 places inside the overlay's own SwiftUI code, the framework boundary cannot fall where it should. The minimum action that unblocks issue #1 is **not** rewriting the window, it is replacing that global access with explicit injection of `Game` (or a protocol over it) into the view models, following the `Toaster` pattern (`Toaster.swift:11-17`).

### 4.5 The same conclusion in seam vocabulary

**[Inferred]** Restating §4.4 in the deep-module vocabulary, because issue #5 will have to argue about where the framework boundary falls and this is the language for it.

**`AppDelegate.instance()` is not a seam, it is a hole where one should be.** A seam is a place where behaviour can be altered without editing in that place. Here the opposite holds: changing how the UI reaches the engine means editing all 68 call sites inside the overlay's own SwiftUI code. Nothing can be substituted at that point, because there is no interface there to substitute at.

**It is a shallow module in the textbook sense.** The implementation is three lines and a `fatalError` (`AppDelegate.swift:23-29`). The interface is enormous, because every caller must know the whole `AppDelegate -> coreManager -> game` chain and must know that the singleton is populated by the time it runs. Interface more complex than implementation is the exact shape the vocabulary says to remove.

**The deletion test comes out backwards here.** Normally "complexity reappears across N callers" means the module was earning its keep. Delete this one and no complexity reappears, because none was ever absorbed. The accessor hides nothing, it only provides a global route to something that was always spread out.

**Two adapters, so the seam is real rather than hypothetical.** The rule is that one implementation means a speculative seam and two mean a genuine one. Issue #1 has already settled that there will be two app targets over one shared framework, so the engine-to-UI seam has two adapters by construction. This is what licenses cutting it at all, as opposed to leaving the global accessor alone.

**The window layer, by contrast, is already deep.** `SizeHelper.HearthstoneWindow` presents a small interface, roughly "give me the game's frame and whether it is fullscreen", and hides CG plus AX, Mission Control ghost rects, the top-left to bottom-left coordinate conversion, and fullscreen detection behind it (`SizeHelper.swift:19-201`). That is why §4.1 is long: there is little to untangle, the behaviour is already behind a narrow interface.

So the finding is not that the window is entangled. It is that **the seam issue #1 has chosen, engine in a framework and UI in the app targets, is currently crossed by a back channel in 68 places**, and while that channel exists the compiler cannot hold the boundary the map is relying on it to hold.

---

## 5. Open questions, settleable only by running the app

- Whether the panel decoded from `RootOverlayWindow.xib` really has `hidesOnDeactivate == false`. The code does not show it, the attribute is absent from the xib and never set in Swift. One `po window.hidesOnDeactivate` in the debugger answers it (§3.1).
- How perceptible the 150 ms window is during which the game-sized overlay stops being click-through after every `updateRootOverlay()` with windows unlocked (§3.2, trap #2).
- What the user actually sees when Hearthstone is minimised: the overlay parked at its last known frame, or something else hiding it (§3.3).
- How large the `NSScreen.screens.first` error is on a multi-monitor setup where the game is not on the first screen in the list (`SizeHelper.swift:102-107`).
- What `CGWindowListCopyWindowInfo` every 2 seconds actually costs in a real profile. Apple warns the operation is "relatively expensive" ([docs](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:))), but the order of magnitude is not visible from the code.
- Whether HSTracker needs the Screen Recording permission. `SizeHelper.HearthstoneWindow.screenshot()` (`SizeHelper.swift:186-200`) uses `CGWindowListCreateImage`, which requires it on macOS 10.15+, but it is only called from the debug `WindowMove` panel (`WindowMove.swift:199`). Neither `CGPreflightScreenCaptureAccess` nor `CGRequestScreenCaptureAccess` appears anywhere (**[Verified]**, zero matches tree-wide). Whether the absence of that permission affects the *bounds* returned by `CGWindowListCopyWindowInfo` is not stated on the `CGWindowListCopyWindowInfo` page, and the "Optional Window List Keys" page did not resolve at the expected documentation URLs. **Not established.**
- Behaviour on macOS 26 once the deployment target is raised. Today's target is 10.14, which is why all of RootOverlay sits behind `@available(macOS 10.15, *)`. A new macOS 26 target can drop those checks, but `CGWindowLevelForKey` remains "not recommended for use in applications", and whether `.nonactivatingPanel` behaviour over a fullscreen Metal game changed in macOS 26 is not visible from the documentation.

---

## 6. Sources

### Apple

| URL | Used for |
| --- | --- |
| https://developer.apple.com/documentation/appkit/nswindow/ignoresmouseevents | Definition of mouse transparency (§3.1, §3.2) |
| https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel | `.nonactivatingPanel` does not activate the owning app (§3.1) |
| https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct | `canJoinAllSpaces`, `fullScreenAuxiliary` (§3.1) |
| https://developer.apple.com/documentation/appkit/nswindow/level-swift.property | Window level ordering semantics (§3.1) |
| https://developer.apple.com/documentation/appkit/nswindow/hidesondeactivate | Default `true` for `NSPanel`, `false` for `NSWindow` (§3.1) |
| https://developer.apple.com/documentation/appkit/nspanel/isfloatingpanel | Conditions for a floating panel, including hiding on deactivation (§3.1) |
| https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:) | Global monitor does not see own-app events, Accessibility required only for key events (§3.2) |
| https://developer.apple.com/documentation/swiftui/nshostingview | Hosting SwiftUI inside AppKit, available from macOS 10.15 (§3.4) |
| https://developer.apple.com/documentation/swiftui/image/init(_:bundle:) | `Image(_:)` defaults to the main bundle (§4.3) |
| https://developer.apple.com/documentation/appkit/nswindowcontroller/loadwindow() | Nib is looked up in the owner class's bundle, with main-bundle fallback (§4.1) |
| https://developer.apple.com/documentation/appkit/nswindowcontroller/windownibname | Semantics of `windowNibName` (§3.1) |
| https://developer.apple.com/documentation/appkit/nsworkspace/didactivateapplicationnotification | Must register on `NSWorkspace.notificationCenter`, `applicationUserInfoKey` (§3.3) |
| https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification | What triggers the display-configuration notification (§3.3) |
| https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:) | Purpose and cost of the call (§3.3, §5) |
| https://developer.apple.com/documentation/coregraphics/cgwindowlevelforkey(_:) | "not recommended for use in applications" (§3.1) |

### This repository

`HSTracker/UIs/Overlay/Root/RootOverlayWindow.swift:14-16,25-42,44-52,54-80,82-98,111-119,121-125,139-202` · `HSTracker/UIs/Overlay/Root/RootOverlayView.swift:17-32,40-47,50-52,55-56,64-66,91-100,146-148,150-171,179-185` · `HSTracker/UIs/Overlay/Root/RootOverlayViewModel.swift:12-19,21-34,48,50-61` · `HSTracker/UIs/Overlay/Root/RootOverlayWindow.xib:9,11,16,18,20` · `HSTracker/UIs/Trackers/WindowManager.swift:12,14,25-30,154-179,186,194-195,206,226,256-270,278-279,281-301,346,410-475` · `HSTracker/UIs/Trackers/OverWindowController.swift:12-52` · `HSTracker/Core/SizeHelper.swift:16-17,19-201,25,38-121,42-46,53-56,58-59,66-72,74-87,89-94,99,102-107,111-118,127-132,163-184,186-200,203,242-250` · `HSTracker/Logging/Game.swift:40,42,58-85,105-107,108-132,144-159,207-209,211-234,237-247,249-254,310-315,574-602,643-675,797-804,1524-1599,1609-1640,5172-5183` · `HSTracker/Logging/CoreManager.swift:20-27,30,55-56,64-67,120-124,267-321,344-385,390-407,409-482,491-507` · `HSTracker/AppDelegate.swift:11,20-29,61-67,69-70,98-110,113-121,238-247,256-261,339-345,348-352,384-398,632-663` · `HSTracker/Core/Settings.swift:28-49,163-164,217-218,227-228` · `HSTracker/Hearthstone/Watchers.swift:11-27,29-60` · `HSTracker/HearthWatcher/Watcher.swift:20-118` · `HSTracker/UIs/Battlegrounds/Guides/CardImageTooltip.swift:11-25,45-94,96-120,145-146,176-217,434-481,486-511` · `HSTracker/UIs/Battlegrounds/Guides/BattlegroundsMinionArtView.swift:133,149,249-254` · `HSTracker/UIs/CountersOverlay.swift:12-17,55-68,95` · `HSTracker/Logging/Handlers/Toaster.swift:11-17,26-46` · `HSTracker/Debug/WindowMove.swift:33-41,199` · `HSTracker/Core/Extensions/String.swift:81-95`

### Previous notes

`docs/research/2-build-on-xcode-26.md` - build state, ad-hoc signing, `com.apple.security.cs.debugger` and `task_for_pid` (its §3.1 and §3.9).
