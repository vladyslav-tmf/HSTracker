# Whether Liquid Glass survives live gameplay

Prototype note for issue [#6](https://github.com/vladyslav-tmf/HSTracker/issues/6).

Date: 2026-09-05. Repo state: `master`, head `02c0a353`.

**Status: prototype run against live Hearthstone.** Unlike `docs/research/4-overlay-window-layer.md`, this note is mostly observation rather than reading. Claims are marked **[Verified]** (observed on this machine, with the measurement stated), **[Judged]** (a human looked at the screen and decided, which is the only way three of these questions can be answered), **[Inferred]** (follows from what was observed but was not itself observed), or **[Open question]**.

Machine: M4, macOS 26.5.2 (25F84), Xcode 26.6, macOS 26.5 SDK. Hearthstone on an external SSD, unmodified.

---

## 1. Verdict, in three sentences

Liquid Glass survives contact with live gameplay: it samples the game's own pixels through a click-through, never-key, always-on-top `NSPanel`, it stays legible over bright saturated board art, and it survives the windowed-to-fullscreen transition. Its GPU cost is roughly **0.5 ms per blurred surface** while the game is windowed, and **not measurable at all** while the game is fullscreen, because the real cost there belongs to something else entirely. That something else is the finding that matters: **any overlay window above a fullscreen Hearthstone knocks the game out of direct-to-display scanout into compositing, costing about 10 FPS out of 122, and a flat opaque panel costs exactly the same as a glass one.**

So the map's direction is not invalidated. One line in its Notes does need amending, but for a reason that has nothing to do with the material failing.

---

## 2. What was built

**[Verified]** A single 270-line Swift file, built as a standalone executable by `swiftc` with no Xcode project and no dependency on HSTracker. It was deleted after the run, which is what a prototype is for; this section records what it was in enough detail to rebuild it, and nothing else in the repository depends on it. Three reasons for that shape, each of which came out of the previous notes:

- The deployment target is still 10.14 (`docs/research/2-build-on-xcode-26.md`). Raising it belongs to issue #5. `swiftc` defaults to the host OS, so macOS 26 glass APIs needed no `@available` gating and no project change.
- Trap #2 of note #4: `WindowManager.show()` rewrites `ignoresMouseEvents` on every ~2 s tick through the inherited `OverWindowController.updateFrames()`. A prototype panel hosted inside `WindowManager` would fight that loop. Outside it, the trap cannot arise.
- Throwaway means throwaway. Nothing in the app target was touched.

The panel is configured exactly as note #4 §3.1 describes the real one, so that what was measured is the real window state and not a friendlier one: `[.borderless, .nonactivatingPanel]`, level `CGWindowLevelForKey(.normalWindow) + 1`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, `ignoresMouseEvents = true`, `hidesOnDeactivate = false`, `isOpaque = false`, `backgroundColor = .clear`, shown with `orderFrontRegardless()` and never `makeKeyAndOrderFront`. The scaled-canvas scheme from `RootOverlayView.swift:64-66` is reused so the stub occupies the same fraction of the board the real tracker would.

Geometry uses `CGWindowListCopyWindowInfo` only, without the Accessibility API. A bare executable run from Terminal has no TCC identity of its own, and window bounds need no permission. Note #4 §3.3 prefers AX because `kCGWindowBounds` can return a stale Mission Control rect; that does not matter for a panel that is looked at rather than measured, and no stale-rect behaviour was seen.

Five backgrounds were compared side by side over one live board, because the board moves and sequential toggling would not be a fair comparison:

| Variant | What it is |
| --- | --- |
| `glass .regular` | `.glassEffect(.regular, in: .rect(cornerRadius: 16))` |
| `glass .clear` | `.glassEffect(.clear, ...)` |
| `glass .tint` | `.glassEffect(.regular.tint(.black.opacity(0.45)), ...)` |
| `NSVisualEffect` | `NSVisualEffectView`, `.behindWindow`, `.hudWindow` - the pre-26 way |
| `flat 55% black` | roughly what HSTracker draws today |

The panel's `appearance` is pinned to `.darkAqua` rather than inherited. An overlay over a game is a dark surface by intent, and leaving it on the system setting would have made the readability judgement depend on a system preference. The first run, before pinning, showed exactly that confound: in light appearance the flat-black variant rendered near-black text on a near-black ground.

---

## 3. Readability

**[Verified]** `.glassEffect` samples the content **behind the window**, not merely the app's own view hierarchy. This was the largest technical unknown going in: had it behaved like `NSVisualEffectView`'s `.withinWindow` blending, it would have rendered essentially nothing over a transparent overlay and the direction would have failed on the first screenshot. It does not. All three glass variants pick up and refract the game's pixels.

**[Judged]** Over a bright, saturated, warm board (the Innkeeper tavern), all five variants stayed legible, dimmed "already drawn" rows included. The three glass variants take on the board's colour noticeably, turning warm over warm art, and hold less contrast than the flat panel; `NSVisualEffect` sits between the two. The judgement was that all of them are acceptable, and that the flat panel is the most comfortable of the five.

**[Judged]** The consequence for the map is not that glass fails. It is that **the panel material should be a user setting in the finished tracker, with the flat option among the choices**, rather than a single fixed system-native look. This is a preference expressed after seeing all five over live play, not a workaround for a failure.

---

## 4. Cost

Measured with Apple's Metal Performance HUD, enabled by `defaults write -g MetalForceHudEnabled -bool YES` and removed again afterwards. CPU sampled with `top -l 4 -s 1`, whose later samples are instantaneous rather than the lifetime average `ps` reports.

**[Verified] Windowed** (game reporting 5120x2616, `Composited`, Game Mode `Off`):

| State | FPS | GPU | Frame interval |
| --- | --- | --- | --- |
| No panel | 122.55 | 9.83 ms | 8.16 ms |
| Flat black panel | 122.55 | 9.87 ms | 8.16 ms |
| One `glass .regular` panel | 121.69 | 10.35 ms | 8.22 ms |
| Five panels (3 glass, 1 `NSVisualEffect`, 1 flat) | 110.77 | 11.35 ms | 9.03 ms |

So while the game is already being composited, a flat overlay is free, one blurred surface costs about **0.5 ms of GPU time and one frame per second out of 122**, and the cost scales with the number of separate blurred surfaces: four blurred surfaces cost about 1.5 ms. **[Inferred]** that scaling is the argument for one glass surface rather than a scatter of them, or for `GlassEffectContainer`, which merges sibling glass shapes into a single pass. `GlassEffectContainer` was not itself measured.

**[Verified] Fullscreen** (5120x2880, Game Mode `On`):

| State | Mode | FPS | GPU | Frame interval |
| --- | --- | --- | --- | --- |
| No panel | **`Direct`** | 122.55 | 10.41 ms | 8.16 ms |
| Flat black panel | `Composited` | 112.94 | 11.39 ms | 8.85 ms |
| One `glass .regular` panel | `Composited` | 111.48 | 11.23 ms | 8.97 ms |

**This is the finding the ticket was worth running for.** With no overlay, fullscreen Hearthstone reports `Direct`, meaning it scans out to the display without going through the compositor. The moment any overlay window is placed above it, the HUD flips to `Composited` and the game loses about 10 FPS.

Every reading above was taken with Hearthstone activated, because the game also reports `Composited` while it is merely in the background. Confusing the two would attribute an ordinary application switch to the overlay.

The control settles the attribution. The flat panel and the glass panel produce the same result within noise: 112.94 against 111.48 FPS, and 11.39 against 11.23 ms of GPU time, with the glass one measuring marginally *cheaper* on GPU, which is only possible if the difference is noise. **The cost is the existence of the overlay window, not the blur.**

**[Verified]** WindowServer CPU was 39-46% without the panel and 39-45% with it: no measurable difference, the compositing work is on the GPU. Hearthstone's own CPU was 88-113% and 82-110% respectively, also indistinguishable.

**[Inferred]** HSTracker's existing overlay already pays the `Direct` to `Composited` cost today, because it is an ordinary window above the game and nothing about what it draws is involved. This was **not** measured: doing so needs the app built and attached to a live game, which this prototype deliberately avoided. It is the one claim here worth confirming before it is quoted as settled.

---

## 5. Behaviour

**[Verified]** Everything above was observed in the state the real overlay always lives in. The panel never became key: it was created with `.nonactivatingPanel`, shown with `orderFrontRegardless()`, and Hearthstone was the active application in every screenshot. Note #4 §3.1 establishes that the real overlay never becomes key by three independent mechanisms, so this is the normal state and not a corner case. The material renders correctly throughout it; there is no degradation when the window is not key.

**[Verified]** The panel survived the windowed-to-fullscreen transition. Trap #3 of note #4 says the transition moves Hearthstone to a different Space and a window already shown does not follow, requiring an explicit hide, reshow and `orderFrontRegardless()`. The prototype implements exactly that, and the panel reappeared correctly positioned over the fullscreen game. `collectionBehavior` alone was not tested in isolation, so this run confirms the documented remedy works on macOS 26 rather than proving the remedy is still necessary.

**[Verified]** The open question left by note #4 §5 - whether `.nonactivatingPanel` over a fullscreen Metal game behaves the same on macOS 26 - is answered: it does. The panel is visible, correctly positioned, click-through and non-activating over fullscreen Hearthstone.

**[Verified]** With `canJoinAllSpaces` the panel also appears over whatever other Space is active, tracking the game window's coordinates there. That is the documented behaviour of the flag and of the existing overlay, not a defect, but it is worth knowing that the panel is visible over other applications while the game is in another Space.

**[Verified]** `NSGlassEffectView` and `NSGlassEffectContainerView` exist in the macOS 26.5 SDK (`AppKit/NSGlassEffectView.h`, both `API_AVAILABLE(macos(26.0))`), with `contentView`, `cornerRadius`, `tintColor` and a `Regular`/`Clear` style enum. The AppKit route is available if a SwiftUI-only route ever proves awkward. It was not exercised.

---

## 6. What this changes for the map

1. **The direction holds.** Liquid Glass over live gameplay works, is legible, and is effectively free. Nothing here argues for a bespoke Hearthstone-flavoured skin.
2. **The Notes line "Visual intent is system-native: Liquid Glass as it comes" needs amending**, not because glass failed but because the material should be selectable. System-native stays the default; the flat option joins it as a setting. That belongs to the settings work in issue #8, and the tokens in issue #5 have to describe more than one background treatment.
3. **A design constraint for #5:** one glass surface, not many. Four blurred surfaces cost three times what one does.
4. **The overlay's real performance cost is the compositing switch**, which is fixed, pre-existing, and unaffected by any visual decision. No amount of design work makes it smaller, and no design decision makes it larger.

---

## 7. Open questions

- Whether HSTracker's existing overlay forces the same `Direct` to `Composited` flip. **[Inferred]** yes, not measured (§4).
- Whether Game Mode being `On` changes the flip. Every fullscreen measurement here had Game Mode `On` and every windowed one had it `Off`, so the two variables were not separated.
- Whether `GlassEffectContainer` actually collapses several glass surfaces into one pass in this setting, which is what would let the tracker use more than one glass shape without paying per shape.
- Whether a signed, bundled, sandboxed app renders glass identically to the bare `swiftc` executable used here. **[Inferred]** yes, nothing observed suggests the binary's packaging is involved.
- Readability over a genuinely dark board, at rest and mid-animation, was judged during live play rather than against a fixed set of captured boards. The bright board was the harder case and it passed, so this is a completeness gap rather than a risk.
- Multi-monitor was not tested, and note #4 §3.3 records that `SizeHelper` assumes the first screen in the list is the active one.

---

## 8. Sources

### Apple

| URL | Used for |
| --- | --- |
| https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:) | `glassEffect(_:in:)` signature and defaults (§2) |
| https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views | `.tint()`, custom shapes (§2) |
| https://developer.apple.com/documentation/swiftui/glasseffectcontainer | Merging glass shapes into one pass (§4, §7) |
| `AppKit/NSGlassEffectView.h`, macOS 26.5 SDK | `NSGlassEffectView`, `NSGlassEffectContainerView`, `Regular`/`Clear` (§5) |

### This repository

`HSTracker/UIs/Overlay/Root/RootOverlayView.swift:64-66` - the scaled-canvas scheme the stub reused. The prototype itself was thrown away, see §2.

### Previous notes

`docs/research/4-overlay-window-layer.md` - window configuration (§3.1), the traps this prototype had to respect (§2), and the open questions §4 and §5 that this run closes.
`docs/research/2-build-on-xcode-26.md` - deployment target and signing state.
