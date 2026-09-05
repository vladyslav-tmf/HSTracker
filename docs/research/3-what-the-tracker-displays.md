# What the Constructed tracker displays today

Research note for issue [#3](https://github.com/vladyslav-tmf/HSTracker/issues/3).

Date: 2026-09-05. Repo state: `master`, head `b2049697`, working tree clean.

**Status: read only.** Nothing was built, nothing was run, Hearthstone was never launched. Every claim below is sourced from the working tree and carries a `path:line` citation. Where a call had to be made rather than read, it is marked **[Judged]**; where the source did not settle a question, **[Unresolved]**.

This note is the inventory the map's **Not yet specified** section was waiting on. It is a contract, so it is complete rather than short.

---

## 1. Verdict, in five sentences

The Constructed tracker is **one `NSPanel` loaded from `Tracker.xib`**, containing eleven fixed-frame subviews whose geometry is recomputed by hand in a single 279-line function on every refresh. There is no table view, no scroll view, no stack view and no autolayout in it: `Tracker.updateFrames()` walks a cursor down the panel and assigns every child frame arithmetically. Its card rows are `CardBar` instances that paint themselves with immediate-mode `NSImage.draw(in:)` calls against PNG assets picked by a four-value theme string. It is refreshed by a **0.5 s polling loop that sets a dirty flag**, after which `Game` assigns roughly ten stored properties onto the window controller and triggers a full relayout - not by KVO, not by Combine, and not by the `@Published` push path that `docs/research/4-overlay-window-layer.md` §3.4 documents for the SwiftUI overlay. And the theme system, though it looks like prior art for a design system, controls **only pixels**: every rect, font, alpha and draw-order decision is a `let` constant on `CardBar` that no theme can reach.

---

## 2. The scope line

The ticket requires this note to draw the boundary the map's **Out of scope** left fuzzy ("Counters beyond what the tracker itself needs"). The source supplies a criterion that is structural rather than aesthetic, so that is the one used.

> **The Constructed tracker is the single `NSPanel` created from `Tracker.xib`, plus everything laid out inside it by `Tracker.updateFrames()`. A display with its own `NSWindowController` and its own `SizeHelper` frame is a separate overlay, not part of the tracker.**

That criterion is checkable, it matches how `WindowManager` already partitions the app (`HSTracker/UIs/Trackers/WindowManager.swift:32-62`, `:126-128`, `:243-245`), and it puts each of the ticket's grey-zone satellites on a definite side.

### In scope - subviews of the one panel

| Display | Outlet | xib | Frame assigned at |
| --- | --- | --- | --- |
| Hero / deck-name header (`playerClass`, holds one `CardBar`) | `Tracker.swift:21` | `Tracker.xib:35-38` | `Tracker.swift:201-204`, `:229-232` |
| Main deck list (`cardsView: AnimatedCardList`) | - | `Tracker.xib:47-50` | `Tracker.swift:317-323` |
| "On Top" dredge lens (`playerTop: DeckLens`) | `Tracker.swift:24` | `Tracker.xib:39-42` | `Tracker.swift:305-315` |
| "On Bottom" dredge lens (`playerBottom: DeckLens`) | `Tracker.swift:25` | `Tracker.xib:51-54` | `Tracker.swift:325-335` |
| "Related Cards" lens (`opponentRelatedCards: DeckLens`) | `Tracker.swift:27` | `Tracker.xib:43-46` | `Tracker.swift:365-375` |
| Sideboards (`playerSideboards: DeckSideboards`) | `Tracker.swift:26` | `Tracker.xib:75-78` | `Tracker.swift:336-346` |
| Card counter (`cardCounter: CardCounter`) | `Tracker.swift:18` | `Tracker.xib:55-58` | `Tracker.swift:347-350` |
| Opponent draw chance (`OpponentDrawChance`) | `Tracker.swift:20` | `Tracker.xib:63-66` | `Tracker.swift:351-357` |
| Player draw chance (`PlayerDrawChance`) | `Tracker.swift:19` | `Tracker.xib:59-62` | `Tracker.swift:358-364` |
| Graveyard counter (`GraveyardCounter`) | `Tracker.swift:23` | `Tracker.xib:71-74` | `Tracker.swift:376-389` |
| Win/loss record (`recordTracker: StringTracker`) | `Tracker.swift:22` | `Tracker.xib:67-70` | `Tracker.swift:390-396` |

### Out of scope - separate windows

| Display | Own window created at |
| --- | --- |
| `BoardDamage` (two instances, one per side) | `WindowManager.swift:50-58` |
| `TimerHud` | `WindowManager.swift:60-62` |
| `FlavorText` (driven by `BoardOverlay`, not by the tracker) | `WindowManager.swift:126-128`, shown `BoardOverlay.swift:142-143` |
| `CardHudContainer` and its ten `CardHud` children | `WindowManager.swift:243-245`, children `CardHudContainer.swift:23-28` |
| `CardList` used as the secret helper | `WindowManager.swift:46-48`, `:257` |
| `FloatingCard`, `LinkOpponentDeckPanel` | `WindowManager.swift:42-44` and the floating-card registration |
| `CountersOverlay`, `ActiveEffectsOverlay`, `PlayerResourcesWindow` | separate `OverWindowController`s, shown from `Game.swift:541-542`, `:508-509`, `:612` |

### Two rulings that the criterion alone does not make

**[Judged] `GraveyardCounter` is in scope, its hover popup is an attached surface.** The counter row itself is a subview (`Tracker.xib:71-74`). It lazily owns a *separate* `CardList` window for the detail popup (`GraveyardCounter.swift:29`, shown `:72`). The row is part of the tracker's layout; the popup is a hover surface the tracker owns but does not lay out. The redesign has to render the row and has to keep the popup working, but the popup's own visual design is not part of the panel contract.

**[Judged] The same treatment applies to every hover surface the tracker triggers**: `FloatingCard` (card image preview), the related-cards tooltip, and `LinkOpponentDeckPanel`. Behaviour is in the contract, layout is not.

**`JadeCounter` is neither - it is dead code.** `rg -c 'JadeCounter'` matches only `HSTracker/UIs/Trackers/JadeCounter.swift` itself. No xib references it, nothing instantiates it. It is listed in the ticket's satellite list but has no runtime existence.

---

## 3. Panel anatomy

### 3.1 Stacking order

`Tracker.updateFrames()` (`Tracker.swift:127-405`) starts a cursor `y` at the top of the content view and decrements it per element. Top to bottom:

1. Hero / deck-name header - `smallFrameHeight`
2. "On Top" lens - `count*cardHeight + smallFrameHeight + 5`
3. **Main card list** - `count * cardHeight`
4. "On Bottom" lens - same shape as 2
5. Sideboards - `count*cardHeight + smallFrameHeight*sideboardCount`
6. Card counter - `smallFrameHeight`
7. Opponent draw chance - `bigFrameHeight`
8. Player draw chance - `smallFrameHeight`
9. "Related Cards" lens - same shape as 2
10. Graveyard counter - `smallFrameHeight`
11. Win/loss record - `smallFrameHeight`

The final cursor value becomes `bottomY` (`Tracker.swift:398`), used as the top edge of the opponent hover tracking area (`:49-55`, `:399-404`) and as the anchor for `LinkOpponentDeckPanel` (`LinkOpponentDeckPanel.swift:123`).

Derived heights, both recomputed from the card-size ratio on every pass (`Tracker.swift:191-192`):

```
bigFrameHeight   = round(71 / ratio)     // OpponentDrawChance only
smallFrameHeight = round(40 / ratio)     // every other counter row
```

### 3.2 What each element renders

| Element | Content |
| --- | --- |
| Header | Exactly one `CardBar` with `playerType = .hero`, created lazily by `CardBar.factory()` (`Tracker.swift:207-212`, `:234-240`). It is a card row, not a bespoke header. `hero.playerName` overrides the card name (`CardBar.swift:736-737`) so it prints the deck name or the opponent battletag. **No wins/losses and no card count live here.** |
| Header hero card | `Cards.hero(byId: playerClassId)`, `count = 1` (`Tracker.swift:215-217`, `:242-244`). Opponent forces `cost = -1`, which makes `addCost` and `addGem` bail out (`CardBar.swift:625`, `:655-657`), so **the opponent header has no mana gem and the player header does**. |
| `AnimatedCardList` | A bare `NSView` holding `CardBar` subviews (`AnimatedCardList.swift:11-12`). No `NSTableView`, no cell reuse. |
| `DeckLens` (x3) | `NSStackView` of an `NSBox` (fill `#23272A`), a 17x17 magnifier `NSImageView`, an `NSTextField` label and a nested `AnimatedCardList` (`DeckLens.swift:12-52`, `:58-69`). Labels "On Top" / "On Bottom" (`Tracker.swift:74-75`) and "Related_Cards" (`:78`). |
| `DeckSideboards` | Two labelled boxes, each with a nested `AnimatedCardList`: ETC Band Manager and King of the Underbelly (`DeckSideboards.swift:22-68`, `:74-98`). |
| `CardCounter` | `card-counter-frame.png` plus hand count and deck count (`CardCounter.swift:13-26`). |
| `PlayerDrawChance` | `player-chance-frame.png` plus two percentages (`PlayerDrawChance.swift:13-26`). |
| `OpponentDrawChance` | `opponent-chance-frame.png` plus four percentages, 71 pt tall (`OpponentDrawChance.swift:13-32`). |
| `GraveyardCounter` | `graveyard-frame.png` plus minion count and murloc count, with its own hover tracking area (`GraveyardCounter.swift:32-89`). |
| `StringTracker` | `text-frame.png` plus one centred string (`StringTracker.swift:12-22`). |

### 3.3 There is no panel background art

The window is transparent (`OverWindowController.swift:18-21`). The only panel-level fill is a black `backgroundColor` at `Settings.trackerOpacity / 100.0`, **default `0.0`** (`Tracker.swift:110-116`, `Settings.swift:169`). Every visible frame is per-row PNG: counter rows from `Resources/Themes/Overlay/<theme>/` with a `default/` fallback (`TrackerFrame.swift:56-68`), card rows from `Resources/Themes/Bars/<themeDir>/` (`CardBar.swift:810-816`).

This matters for the redesign: **the tracker today has no surface of its own to make out of glass.** It is a stack of individually framed rows over nothing.

### 3.4 Presence conditions

| Element | Condition | Line |
| --- | --- | --- |
| `cardCounter` | `showOpponentCardCount` / `showPlayerCardCount` | `Tracker.swift:144`, `:150` |
| `opponentDrawChance` | opponent: `showOpponentDrawChance`; player: always hidden | `:145`, `:151` |
| `playerDrawChance` | opponent: always hidden; player: `showPlayerDrawChance` | `:146`, `:152` |
| header | `showOpponentClassInTracker` / `showDeckNameInTracker` | `:147`, `:153` |
| `recordTracker` | opponent: always hidden; player: `showWinLossRatio` | `:148`, `:154` |
| `graveyardCounter` | `showGraveyard`, itself from `showOpponentGraveyard` / `showPlayerGraveyard` | `:157`; `Game.swift:288`, `:369` |
| `playerTop` | `count > 0 && showPlayerCardsTop` | `:277`, `:305` |
| `playerBottom` | `count > 0 && showPlayerCardsBottom` | `:273`, `:325` |
| `playerSideboards` | `count > 0 && !hidePlayerSideboards` | `:281`, `:336` |
| `opponentRelatedCards` | `count > 0 && showOpponentRelatedCards` | `:285`, `:365` |
| `cardsView` | unconditional | `:317-323` |

**Nothing in this panel is conditioned on game format.** `Tracker.currentFormat`, `.currentGameMode` and `.matchInfo` are assigned every refresh (`Game.swift:298-300`, `:390-392`) and never read (`Tracker.swift:43-45`). Format gates the panel only indirectly, through `Game`'s not-Battlegrounds / not-Mercenaries checks (`Game.swift:264`, `:339`).

### 3.5 Sizing

**Width is fixed by card size, not by content or by drag.** `OverWindowController.setWindowSizes()` pins `contentMinSize.width == contentMaxSize.width` per size and clamps height to `[400, screen.height]` (`OverWindowController.swift:28-43`).

**Height and position** are either anchored to the Hearthstone window via `SizeHelper.playerTrackerFrame()` / `opponentTrackerFrame()` (`SizeHelper.swift:264-274`, `:328-338`) when `autoPositionTrackers` is on, or restored from `Settings.playerTrackerFrame` / `opponentTrackerFrame` (`Game.swift:308`, `:401`).

**Overflow squeezes, it does not scroll.** Row height is shrunk so the whole list fits (`Tracker.swift:298-300`):

```
if totalCards > 0 { cardHeight = min(cardHeight, (windowHeight - offsetFrames) / totalCards) }
```

**Internal scaling** is a divisor, not a transform. `TrackerFrame.ratioWidth` / `ratioHeight` is `kRowHeight / <sizeRowHeight>` (`TrackerFrame.swift:42-54`); every subclass authors its rects in the 217x34 "big" coordinate system and divides through when drawing (`:35-40`, `:56-89`). Font size follows: `NSFont(name: "ChunkFive", size: round(18 / ratioHeight))` (`:81`). `CardBar` carries its own copy of the same logic (`CardBar.swift:818-859`).

---

## 4. The card row

### 4.1 Anatomy, in draw order

All drawing is sequential immediate-mode painting inside `CardBar.draw(_:)` (`CardBar.swift:295-371`). "Z-order" is literally call order.

| # | Layer | `ThemeElement` | Asset | Rect |
| --- | --- | --- | --- | --- |
| 1 | background image | none | never assigned, see §4.5 | `imageRect` / `imageRectBG` |
| 2 | card portrait tile | none | downloaded tile, §4.4 | `imageRect` `(83,0,134,34)` |
| 3 | fade overlay | `.fadeOverlay` | `fade.png` | `frameRect`, per-theme override |
| 4 | count box | `.defaultCountBox` + 4 rarity variants | `countbox*.png` | `boxRect` `(183,0,34,34)` |
| 5 | count text | none | - | `countTextRect` `(196,9,14,34)` |
| 6 | "created by" icon | `.createdIcon` | `icon_created.png` | `boxRect`, shifted by `createdIconOffset` |
| 7 | legendary star | `.legendaryIcon` | `icon_legendary.png` | `boxRect` |
| 8 | battlecry / deathrattle tags | none (SF Symbols) | `b.circle.fill`, `d.circle.fill` | Battlegrounds only |
| 9 | coin cost | none | asset-catalog `coin-cost` | Battlegrounds only |
| 10 | **frame** | `.defaultFrame` + 4 rarity variants | `frame*.png` | `frameRect` `(0,0,217,34)` |
| 11 | mana gem | `.defaultGem` + 4 rarity variants | `gem*.png` | `gemRect` `(0,0,34,34)` |
| 12 | mana cost text | none | - | `costTextRect` `(0,9,34,34)` |
| 13 | synergy highlight tint | `.highlightTeal` / `.highlightOrange` / `.highlightGreen` | `highlight_*.png` | `frameRect` |
| 14 | card name text | none | - | computed, `CardBar.swift:678-695` |
| 15 | "bad as multiple" arena icon | `.badAsMultipleIcon` | `icon_bad_multiple.png` | `arenaHelperRect` `(17,0,34,34)` |
| 16 | darken overlay | `.darkOverlay` | `dark.png` | `frameRect` |
| 17 | mulligan keep-rate box | `.defaultKeepRateBox` / `...ActiveBox` | `keeprate*.png` | `mulliganWinrateBoxRect` `(136,4,54,26)` |
| 18 | mulligan keep-rate text | none | - | box shifted `+8` y, `-6` h |
| 19 | flash overlay | `.flashFrame` | `frame_mask.png` | separate `CALayer`, `CardBar.swift:243-272` |

Rect declarations: `CardBar.swift:128-140`. Filename mapping: `:160-204`.

### 4.2 Every visual state a row can be in

| State | Trigger | Visual effect, concrete |
| --- | --- | --- |
| Count badge | `abs(count) > 1 && playerType != .editDeck`, or legendary (`:314`) | countbox image plus the number in `countTextColor`; text drawn only when `count > 1` (`:473-474`) |
| Legendary marker | `(abs(count) <= 1 \|\| editDeck) && rarity == .legendary && !isBattlegrounds` (`:321-325`) | `icon_legendary.png` at `boxRect` |
| Elite coercion | `rarity == .invalid && mechanics.contains("ELITE")` -> treated as legendary. Repeated verbatim **seven times** (`:312`, `:378`, `:430`, `:449`, `:537`, `:600`, `:629`) | selects the legendary frame/gem/countbox/icon |
| Created / stolen | `card.isCreated` (`:318`) | `icon_created.png`, shifted left by `createdIconOffset`; also shrinks the name width by `abs(createdIconOffset)` (`:687-689`) |
| **Drawn / played out (dimmed)** | `(count <= 0 \|\| jousted) && playerType != .cardList && != .editDeck` (`:362-364`) | **`dark.png` composited over `frameRect` (`:756-760`) - not an alpha value, a PNG.** Text also turns grey `rgb(0.501, 0.501, 0.501)` (`Card.swift:332-333`) |
| Deck-editor "at max copies" | `editDeck && !isArena && (count >= 2 \|\| (count == 1 && legendary))` (`:358-361`) | same `dark.png` |
| Last drawn | `highlightDraw && Settings.highlightLastDrawn` (`Card.swift:328-329`) | text `rgb(1, 0.647, 0)` |
| In hand | `highlightInHand && Settings.highlightCardsInHand` (`Card.swift:330-331`) | text = `Settings.playerInHandColor`, default `rgb(0.678, 1, 0.184)` (`Settings.swift:443`) |
| Discarded | `wasDiscarded && Settings.highlightDiscarded` (`Card.swift:334-335`) | text `rgb(0.803, 0.36, 0.36)` |
| Synergy highlight | `card.highlightColor` is teal / orange / green (`:348-350`) | full-width `highlight_<colour>.png` over `frameRect` |
| **Flash on count change** | `update(highlight: true)` and `Settings.flashOnDraw` (`:243-244`), raised by `AnimatedCardList` when the count changed (`AnimatedCardList.swift:96-106`) | `flashColor` layer masked by `frame_mask.png`, opacity **0.7 -> 0.0 over 0.5 s** (`:263-265`) |
| **Fade in (insert)** | new row, `highlight = !reset` (`AnimatedCardList.swift:157`) | `alphaValue` **0.3 -> 1.0 over 0.5 s** (`:275-283`) |
| **Fade out (remove)** | removed row with `count > 0` (`AnimatedCardList.swift:166`) | `alphaValue` **-> 0.3 over 0.5 s**, view actually removed **600 ms** later (`:285-292`, `AnimatedCardList.swift:167-174`) |
| Arena "bad as multiple" | `card.isBadAsMultiple` (`:352`) | `icon_bad_multiple.png` |
| Mulligan keep rate | `card.cardWinRates != nil` (`:367`), active box when `isMulliganOption` (`:507`) | box plus `"%.1f%%"` in an HSL-derived colour at intensity 75 (`:516-521`, `Helper.swift:89-129`) |
| Hero row | `playerType == .hero` | name replaced by `playerName` (`:736-737`); the "nothing changed" early-return guard is skipped (`:300`); gem suppressed for non-playable heroes (`:624`) |
| Deck-list / editor row | `playerType == .cardList` / `.editDeck` | name **and** cost forced to pure white regardless of state (`:660-662`, `:746-748`) |

**Two states the ticket asked about do not exist.**

- **No "wild" or format-illegal marker.** No format or legality flag is read anywhere in `CardBar.swift`. `CardLegalityChecker.isCardLegal(gameType:format:)` exists (`HSTracker/Hearthstone/CardLegalityChecker.swift:70-74`) but `rg -c` finds the type in only two files - itself and `Game.swift`, where it is used solely for `loadCardsByFormat` (`Game.swift:1967`, `:2065`). The `rarity == .invalid` checks in `CardBar` are about rarity, not legality.
- **No "animating" flag.** Animation is fire-and-forget through `NSAnimationContext` and `CABasicAnimation`; nothing tracks whether a row is mid-animation.

### 4.3 List diffing

`AnimatedCardList.update(cards:reset:)` (`AnimatedCardList.swift:81-162`), the whole body inside `lock.around { }` on an `UnfairLock` (`:18`, `:82`):

1. `reset` clears the array (`:83-85`).
2. Row identity is `areEqualForList`: same `id`, `jousted`, `isCreated`, `deckListIndex`, Incindius extra-info, plus `wasDiscarded` only when `Settings.highlightDiscarded` is on (`:180-184`).
3. Match found: mutate the live `CardBar`'s count / `highlightInHand` / `extraInfo`, then `update(highlight:)` where `highlight` is true **only when the count changed** (`:96-106`).
4. Gone from the new list: if a new card shares the `id`, a replacement bar is inserted at the old index with `highlight: true`; otherwise the old row fades out (`:112-141`).
5. Genuinely new: fresh `CardBar` at the model index, then `fadeIn(highlight: !reset)` (`:143-158`).

**There is no move or reorder animation.** Reordering is expressed as remove-then-insert, and the final layout is a hard `frame` assignment: `AnimatedCardList.updateFrames()` removes *all* subviews and re-adds every bar with an explicit frame on every pass (`:186-201`).

### 4.4 Card art

Three-stage lookup in `addCardImage`: in-instance `cardTile` cache, then `ImageUtils.cachedTile(cardId:)`, then an async `ImageUtils.tile(for:completion:)` that sets `needsDisplay = true` on arrival (`CardBar.swift:388-416`). `ImageUtils` caches to `Paths.tiles/<cardId>.jpg` and downloads from `https://art.hearthstonejson.com/v1/tiles/<cardId>.png` (`ImageUtils.swift:20-22`, `:144`, `:176-177`).

`MinimalBar` does not use `ImageUtils` at all: it loads a bundled full-card render from `Resources/Small/<cardId>.png` and runs `CIGaussianBlur` at radius 1.5 across the whole `frameRect` (`MinimalBar.swift:22`, `:31-49`). **[Unresolved]** `Resources/Small/` does not exist in the repo. If it is not populated at build time, MinimalBar rows draw no portrait.

### 4.5 Dead code in the row pipeline

- `cardLayer` is created and added as a sublayer (`CardBar.swift:230-234`) and cleared on every draw (`:302`), but nothing is ever added to it.
- `backgroundImage` (`:69`) is read at `:304` and never assigned anywhere, so draw layer 1 never paints.
- `playerRace` (`:68`) is never read or written. `playerRank` (`:66`) is never assigned by a caller, so the "hero row shows rank instead of cost" branch at `:666-668` is unreachable.
- `textFontSize` (`:122`, set to 18 by `ClassicBar.swift:41`) is never read; name sizing uses a literal `15.0` (`:751`).
- Flash sublayers are added with `isRemovedOnCompletion = false` and never removed (`:261-268`).

---

## 5. The theme system as prior art

This is the part the ticket did not name and the handoff correctly flagged as the most important. HSTracker already has a themeable card row. Inventoried properly, it turns out to specify far less than its existence suggests.

**There is no `Theme` type and no `ThemeManager`.** A theme is exactly two things: a directory-name string returned by `themeDir`, and a hardcoded `CardBar` subclass. `ThemeElementInfo` is a two-field struct, `filename` plus `rect` (`ThemeElementInfo.swift:12-13`). That is the entire token schema.

### 5.1 What a theme controls

**Lever 1 - the asset directory** `Resources/Themes/Bars/<themeDir>/`. A theme may replace the pixels of 26 named files. Fourteen are required and the row is skipped entirely if any is missing (`CardBar.swift:72-81`, `:298`); twelve are optional in three all-or-nothing sets - rarity frames, rarity gems, rarity count boxes - gated by `hasAllOptionalFrames` / `hasAllOptionalGems` / `hasAllOptionalCountBoxes` (`:83-114`) **and** `Settings.showRarityColors` (`:448`, `:604`, `:628`).

On disk: `classic` ships 25 files and is the **only** theme with the rarity count-box set; `dark`, `frost` and `minimal` ship 21 each. So `showRarityColors` affects only frames and gems for three of the four themes.

**Lever 2 - a Swift subclass**, which may override `themeDir`, `flashColor`, `countTextColor`, `numbersFont`, `textFont`, the four filename maps, `initVars()` and any `addX()` drawing method (`CardBar.swift:50-204`, `:373-756`).

### 5.2 What a theme cannot control

| Thing | Value | Why it cannot be reached |
| --- | --- | --- |
| Canonical row geometry | 217 x 34 | `CardSize.swift:11`, `:13` |
| All 13 rects | §4.1 | **`let`, not `var`** (`CardBar.swift:128-140`) - not overridable at all |
| Numbers font | `ChunkFive` | no subclass overrides `numbersFont` (`:145-147`) |
| Font sizes | count 17, mulligan 15, cost 20, name max 15.0 | `:120-123`, `:751` |
| Text stroke | width `-2.0` / `-1.0`, colour always `NSColor.black` | `:764`, `:772`, `:780` |
| Name and cost colour | `Card.textColor()`, or forced white for `cardList`/`editDeck` | `Card.swift:326-338`; `CardBar.swift:660-662`, `:746-748` |
| Dimming mechanism | `dark.png`, not an alpha | `:756-760` |
| Fade / flash timings | 0.3, 1.0, 0.7, 0.0, all at 0.5 s | `:263-265`, `:277-290` |
| Name-rect layout maths | x 38 (14 BG), y 10, h 30 | `:679-694` |
| Scaling maths | `ratio`, `ratioWidth`, `ratioHeight` are **`private`** | `:818-859` |
| Draw order and state triggers | fixed | `:295-371` |
| Corner radius | **none anywhere** in the eight card files | absence |
| The theme list itself | `["classic","frost","dark","minimal"]` hardcoded twice | `TrackersPreferences.swift:43`; `CardBar.swift:37-48` |

**Consequence: a user cannot add a theme.** Dropping a fifth directory into `Resources/Themes/Bars/` does nothing, because `CardBar.factory()` maps four literal strings and falls through to `ClassicBar`, and the preferences combo box is a static xib list (`TrackersPreferences.xib:234-239`).

### 5.3 How the four variants actually differ

| Override | ClassicBar | DarkBar | FrostBar | MinimalBar |
| --- | --- | --- | --- | --- |
| `themeDir` | `"classic"` | `"dark"` | `"frost"` | `"minimal"` |
| `textFont` | **Belwe Bd BT** / Benguiat Rus | inherits | inherits | inherits |
| `flashColor` | `rgb(1, .647, 0)` | `rgb(.192, .526, .871)` | `rgb(.41, .65, .88)` | `= countTextColor` |
| `countTextColor` | inherits | inherits | inherits | **rarity-driven** (`:56-69`) |
| offsets | `-19` for image/fade/created | keeps `-23` | keeps `-23` | `createdIconOffset = -15` |
| `addCardImage` | `_imageRect (108,4,108,27)` | offset by count box | `dx: -1` | **bundled render + `CIGaussianBlur(1.5)`** |
| `addCountBox` | inherits | inherits | inherits | **overridden to a no-op** |
| nudges | cost `dx: +1` | count `dx: +2` | count `dx: +1`, legendary `dx: -1` | - |

`ClassicBar` is the only variant that changes the font family. `MinimalBar` is not a re-skin - it swaps the art pipeline and deletes the count box. No variant overrides the filename maps, so all four share the same asset vocabulary and identical rects.

### 5.4 The bearing on #9

**[Judged]** The theme system is prior art for *asset swapping*, not for a design system. Everything a token system would want to own - spacing, typography scale, corner radius, state opacity, motion timing - is a `let` or a `private` on `CardBar` and was never designed to vary. #9 therefore inherits a vocabulary of **element names** (frame, gem, count box, fade, dark, highlight, flash mask) and a **row aspect ratio**, and nothing else. The four shipped themes are useful as four reference looks to compare against, not as a specification to satisfy.

---

## 6. Where every value comes from

### 6.1 The refresh mechanism - a correction to note #4 §3.4

`docs/research/4-overlay-window-layer.md` §3.4 documents the SwiftUI RootOverlay path: engine calls `Game.updateXxx()`, hops to main, pushes into a view model, `@Published` drives a re-render. **The AppKit trackers do not work that way.** No KVO, no Combine, no `@Published`, no view model anywhere in the chain.

They are timer-driven:

| What | Where |
| --- | --- |
| Private serial queue `net.hearthsim.hstracker.guiupdate` | `Game.swift:209` |
| Interval `guiUpdateDelay = 0.5` s | `Game.swift:42` |
| Loop started once from `Game.init()` | `Game.swift:1593-1598` |
| Loop body `internalUpdateCheck()`, self-rescheduling | `Game.swift:1608-1639` |

`Game.updateTrackers(reset:)` is the only writer of the dirty flag and does nothing else (`Game.swift:249-254`). Log-parsing events do **not** update the tracker - they raise a flag that the 0.5 s loop picks up. The loop has three branches: dirty flag set means `updateAllTrackers()` now; otherwise every fourth tick (~2 s) it reloads the Hearthstone window rect and repaints only if the rect or the fullscreen flag changed; otherwise it increments a counter (`Game.swift:1609-1634`).

Six call sites bypass the flag and call `updatePlayerTracker()` / `updateOpponentTracker()` directly: `handlePlayerDredge` (`:2845`), `handleChameleosReveal` (`:2868`), `handleCardCopy` (`:2882`), `handleIncidiusEndOfTurn` (`:2739`, `:2741`), `windowDidResize` (`:5178`, `:5181`).

Three further channels exist: `NotificationCenter` observers on ~30 settings keys and lifecycle events, on `OperationQueue.main` (`Game.swift:1545-1590`); one independent 1 s `Timer` on `RunLoop.main` for the turn clock (`TurnTimer.swift:34-38`); and a **re-entrant view-to-engine callback** where `DeckLens.update` and `DeckSideboards.update` call back into `updatePlayerTracker(reset: false)` whenever a row fades out (`DeckLens.swift:85`, `DeckSideboards.swift:128`, `:137`).

The per-refresh sequence, all on main after the hop at `Game.swift:257` / `:332`:

```
_queue (0.5 s tick)
  Game.internalUpdateCheck()                                    Game.swift:1608
  Game.updateAllTrackers()                                      Game.swift:211
  Game.updatePlayerTracker(reset:)   -> DispatchQueue.main      Game.swift:331-332
    tracker.update(cards:top:bottom:sideboards:relatedCards:)   Tracker.swift:119-125
    tracker.updateCardCounter(deckCount:handCount:...)          Tracker.swift:407-459
    tracker.showGraveyard / playerName / playerClassId / ...    Game.swift:369-392
    tracker.setWindowSizes()                                    OverWindowController.swift:28-43
    windowManager.show(...)                    [@MainActor]     WindowManager.swift:410-475
      controller.updateFrames()                                 WindowManager.swift:432
        Tracker.updateFrames()  - re-reads Settings, relayouts  Tracker.swift:127-405
```

**So it is a hybrid.** `Game` **pushes** ten stored properties onto the window controller; `Tracker` then **pulls** every `Settings` value it needs inside `updateFrames()` on every single tick (`Tracker.swift:135-155`, `:264-297`, `:382-386`) and rebuilds the entire layout by hand. The tracker never reads the game model. It observes exactly one notification of its own, `tracker_opacity` (`Tracker.swift:60-62`).

### 6.2 Value-by-value provenance

| Displayed value | View | Engine source | Travel |
| --- | --- | --- | --- |
| Card name and art | `CardBar.addCardName` `:732-754`, `addCardImage` `:373-417` | `Card.id` / `.name` via `Cards.by(cardId:)` inside `Player.playerCardList` (`Player.swift:396-415`) / `opponentCardList` (`:471-532`) | push of `[Card]` -> `Tracker.update` -> `AnimatedCardList.update` |
| Mana cost | `addGem` `:622-645`, `addCost` `:647-676` | `Card.cost` (`Card.swift:26`); Zilliax 3000 override via `Helper.resolveZilliax3000` (`Player.swift:419`, `:623-627`) | pull from the pushed `Card` |
| Rarity treatment | `addFrame` `:597-620`, `addGem`, `addCountBox` `:444-465`, `addLegendaryIcon` `:547-556` | `Card.rarity` (`Card.swift:41`), with the ELITE promotion (§4.2) | pull, gated by `showRarityColors` |
| **Count remaining** | `addCountText` `:467-478`; darken and grey text at `count <= 0` | `Card.count` from `Player.getDeckState().toRemaingCard` (`Player.swift:599-609`), `toRemovedCard` (`:611-621`) - see §6.3 | push then pull |
| "Created" gift icon | `addCreatedIcon` `:528-545` | `Card.isCreated` from `DynamicEntity.created = info.created \|\| info.stolen` (`Player.swift:319`, `:326`, `:500-501`, `:544`) | push then pull |
| Jousted / hidden | grey text plus darken | `Card.jousted` (`Player.swift:287`, `:302-304`, `:327`, `:509`) | push then pull |
| Discarded highlight | `Card.textColor()` | `Card.wasDiscarded` from `info.discarded && Settings.highlightDiscarded` (`Player.swift:281`, `:502`) | push then pull |
| In-hand highlight | `Card.textColor()` | `Card.highlightInHand` (`Player.swift:374`, `:554`, `:602-604`, `:657`) | push then pull |
| Synergy highlight | `addHighlightColor` `:491-504` | `RelatedCardsManager.getCardWithHighlight(...)` reached through the **singleton** in `Tracker.highlightPlayerDeckCards` (`Tracker.swift:539-548`) | pull on hover, via a closure stored on `AnimatedCardList.shouldHighlightCard` (`:33-57`) |
| Mulligan keep-rate badge | `addMulliganWinRate` `:506-526` | `Card.cardWinRates` from `Player.annotateCards` / `mulliganCardStats` (`Player.swift:417-439`) | push; the setter itself triggers a refresh through the singleton (`Player.swift:1164-1172`) |
| **Wild / format-illegal flag** | **none** | `CardLegalityChecker` exists but is never reached by any UI | **does not exist** |
| Deck name | hero `CardBar`, `playerName` path `:736-737` | `Game.currentDeck?.name`, falling back to `player.name` (`Game.swift:377`, `:384`) | push to `Tracker.playerName` |
| Opponent name | same | `Game.opponent.name`, split on `#` to drop the discriminator (`Game.swift:290-293`) | push |
| Class / hero portrait | the `playerClass` subview's single `CardBar` | `currentDeck?.heroId`, else `playerClass.defaultHeroCardId`, else `Game.playerHeroId` (`Game.swift:378-386`); opponent `Game.opponent.playerClassId` (`:296`) | push of the id; the view **pulls** the card via `Cards.hero(byId:)` (`Tracker.swift:215`, `:242`) |
| Deck count remaining | `CardCounter.draw` `:25` | `Player.deckCount` = `deck.filter { isControlled(by: id) }.count` (`Player.swift:153-156`), forced to 30 pre-game (`Game.swift:364`); opponent uses `30 - handCount` until mulligan is done (`:283`) | push via `updateCardCounter` |
| Hand count | `CardCounter.draw` `:24` | `Player.handCount` (`Player.swift:149-151`) | same push |
| Opponent revealed cards | the same `AnimatedCardList` with `playerType = .opponent` | `Player.opponentCardList` (`:471-532`), two modes depending on whether a linked deck is known (`getOpponentDeckState`, `:672-749`) | push (`Game.swift:279`) |
| Opponent "related cards" | `opponentRelatedCards: DeckLens` | `RelatedCardsManager.getCardsOpponentMayHave(...)`, every card forced to `count = 1` (`Game.swift:275-278`) | push |
| Dredge top / bottom | `playerTop` / `playerBottom` | `Game.player.deck.filter { info.deckIndex != 0 }`, split by sign, sorted descending, `count = 1` (`Game.swift:346-358`) | push |
| Sideboards | `playerSideboards` | `Player.playerSideboardsDict` -> `getPlayerSideboards(Settings.removeCardsFromDeck)` (`Player.swift:441-469`, `:644-667`) | push |
| **Player draw chance** | `PlayerDrawChance.draw` `:20-26` | **computed in the view controller**: `draw1 = 100/deckCount`, `draw2 = 200/deckCount` (`Tracker.swift:449-457`) | only `deckCount` is pushed |
| **Opponent draw + in-hand chances** | `OpponentDrawChance.draw` `:24-32` | **also computed in `Tracker.updateCardCounter`** (`:413-447`), hand chances by a hypergeometric approximation over `maxDeckSize = max(30, deckCount)` (`:428-441`) | only `deckCount` and `gameStarted` are pushed |
| **Graveyard counts** | `GraveyardCounter.draw` `:40-42` | `Player.graveyard` = `playerEntities.filter { isInGraveyard }` (`Player.swift:192`), pushed as raw `[Entity]` (`Game.swift:295`, `:388`). **The entity-to-card aggregation happens in the view**, rebuilt every tick (`Tracker.swift:166-189`) | push of `[Entity]`, aggregation in the view |
| Win/loss record | `StringTracker.draw` `:17-22` | `StatsHelper.getDeckManagerRecordLabel(deck:mode:.all)` over the Realm deck (`Game.swift:371-376`) | push of a formatted string |

Three of those rows are the ones worth carrying into #5: **the draw-chance probability model and the graveyard aggregation live in a view controller, not the engine**, and the synergy highlight is reached through the app-delegate singleton rather than through pushed data.

### 6.3 How "2 remaining of Fireball" is computed

`Player.getDeckState()` (`Player.swift:538-670`):

1. Flatten the active deck into a bag of ids, one entry per copy (`:566-571`).
2. Collect revealed entities no longer in the deck zone - not created, playable, `!isInDeck || info.stolen`, `originalController == id`, `!info.hidden` (`:573-579`).
3. Remove one bag entry per such entity and record it as removed (`:585-597`), plus the Zilliax Deluxe 3000 cosmetic-module special case (`:590-592`).
4. Group what is left and set the count - `toRemaingCard`, `card.count = g.value.count` (`:599-609`).
5. Fully-drawn cards get `count = 0` via `toRemovedCard` (`:611-621`), which is what makes the row grey and darkened.
6. Created or stolen cards physically in the deck zone are counted separately (`:539-560`).

Without an active deck the player side falls back to `knownCardsInDeck`, which groups actual deck entities and forces `jousted = true` (`Player.swift:315-334`). The opponent side without a linked deck groups `revealedEntities` (`:508`); with one it runs `getOpponentDeckState()` (`:672-749`).

`playerCardList` then chooses which bucket to show, driven by `Settings.removeCardsFromDeck` and `Settings.highlightCardsInHand` (`Player.swift:402-414`). **Sorting is code, not preference**: `CardListSorting.cost` after the mulligan, `.mulliganWr` during it (`:401`).

### 6.4 The `AppDelegate.instance()` reach-through in this chain

Note #4 established that `AppDelegate.instance().coreManager.game` blocks the framework boundary and counted 68 sites inside the SwiftUI overlay. For completeness, the Constructed AppKit chain adds its own:

| File | Count | Lines |
| --- | --- | --- |
| `Tracker.swift` | 7 | `:94`, `:100`, `:499`, `:545`, `:597`, `:601`, `:624` |
| `GraveyardCounter.swift` | 2 | `:72`, `:79` |
| `DeckSideboards.swift` | 2 | `:128`, `:137` |
| `DeckLens.swift` | 1 | `:85` |
| `Player.swift` | 1 | `:1170` |

**13 sites across 5 files** in the tracker chain proper (19 across 6 if `BoardOverlay.swift` is counted, which shares the `FlavorText` window). Three of them are not reads of state but **writes back into the engine's refresh loop from inside a view** (`DeckLens.swift:85`, `DeckSideboards.swift:128`, `:137`). A fourth, `Player.swift:1170`, is the engine's own model reaching the UI through the app delegate even though `Player` already holds `private let game: Game` (`Player.swift:130`).

Recorded only. Replacing these belongs to #5.

---

## 7. Preferences that constrain any replacement layout

All preferences live in `Settings` (`HSTracker/Core/Settings.swift:130`), a `final class` of `static` properties behind `@UserDefault` wrappers. **Every setter posts an `NSNotification` named after the raw key** (`Settings.swift:44-46`). That is the only reactive channel the AppKit trackers have, and a replacement view can subscribe to it unchanged.

Roughly 45 preferences shape the tracker. They fall into four groups.

**Visibility** - the 20 keys enumerated in §3.4 plus the window-level gates `showPlayerTracker` / `showOpponentTracker` (`Game.swift:337`, `:263`), `hideAllTrackersWhenNotInGame`, `hideAllWhenGameInBackground`, `dontTrackWhileSpectating`, `clearTrackersOnGameEnd`.

**Geometry** - and here is the constraint that matters most:

| Key | Default | Note |
| --- | --- | --- |
| `cardSize` | `.big` (34 px) | **The single scale knob.** Read in nine places. Cases: tiny 17, small 23, medium 29, big 34, huge 52 (`CardSize.swift:13-25`) |
| `trackerOpacity` | `0.0` | Window background alpha, `value/100` (`Tracker.swift:111`) |
| `autoPositionTrackers` | `true` | Anchor to the Hearthstone window rather than a saved frame |
| `windowsLocked` | `true` | `ignoresMouseEvents` and the titled-vs-borderless styleMask |
| `playerTrackerFrame` / `opponentTrackerFrame` | `nil` | Persisted on drag and resize |
| `preventOpponentNameCovering` | `false` | 12.5 % top inset on the opponent panel (`SizeHelper.swift:333`) |

**There is no window-scale preference, no max-card-count preference, no scrolling, no font preference and no dark/light appearance mode.** The `"dark"` value of `theme` is a card-bar art set, not an appearance mode. Overflow squeezes rows (`Tracker.swift:298-300`).

**Appearance** - `theme` (default `"dark"`), `showRarityColors`, `playerInHandColor`, `flashOnDraw`.

**Content** - `removeCardsFromDeck`, `highlightCardsInHand`, `highlightLastDrawn`, `highlightDiscarded`, `showPlayerHighlightSynergies`, `showPlayerGet`, `showOpponentCreated`, `enableLinkOpponentDeckInNonFriendly`.

### 7.1 Preferences UI, and why it can stay out of scope

Every tracker preference with UI lives in exactly three AppKit panes: `TrackersPreferences`, `PlayerTrackersPreferences`, `OpponentTrackersPreferences`, all `NSViewController` plus xib. They talk to `Settings` through plain `@IBAction` setters and never touch a view. **A replacement tracker that subscribes to the same per-key notifications leaves the existing panes working unchanged**, which is what makes the map's "Preferences out of scope" tenable.

### 7.2 Dead preferences

With a live checkbox and no reader: `showPlayerDeathrattle` (`Settings.swift:364`), `showOpponentDeathrattle` (`:382`), `preferGoldenCards` (`:229`). Without UI and without a reader: `fatigueIndicator` (`:472`), `floatingCardStyle` (`:223`). The two deathrattle checkboxes are the only place a pane promises something the tracker does not deliver.

---

## 8. SwiftUI versus AppKit

**`HSTracker/UIs/Trackers/` and `HSTracker/UIs/Cards/` are 100 % AppKit, zero SwiftUI.** `UIs/Cards/` has zero xibs and is pure programmatic `draw(_:)` and `CALayer` work.

`HSTracker/UIs/Constructed/` is split:

| Already SwiftUI | Still AppKit with a xib |
| --- | --- |
| `Mulligan/V2/` - 7 files, `ObservableObject` + `@Published` | `Mulligan/` V1 - guide, pre-lobby, overlay message, single-card header, single-card stats, single-deck status |
| `PlayerResourcesWidget/PlayerResourcesView` + view model | `ActiveEffects/` - both files |
| `Mulligan/ConstructedMulliganPreLobbyWidgetView`, `MulliganGuideTrialsExhaustedView` | `PlayerResourcesWindow` is the AppKit host that carries the SwiftUI widget |

**Hosting is always `NSHostingView` assigned to `window.contentView` inside an `OverWindowController.windowDidLoad()` override. There is no `NSHostingController` anywhere in the app.** Sites: `RootOverlayWindow.swift:27-28`, `PlayerResourcesWindow.swift:18-19`, `CountersOverlay.swift:58`, `:64`, `:67`. The four `NSHostingView` matches inside `RootOverlayView.swift` are comments only.

`RootOverlayWindow` is the modern host and is worth reusing: one full-screen scaled overlay, click-through by default, flipping `ignoresMouseEvents` only when the cursor enters a region a SwiftUI child published through `InteractiveRegionPreferenceKey` (`RootOverlayWindow.swift:40-41`, `:82-98`; `RootOverlayView.swift:17-32`, `:180-182`). **[Judged]** a SwiftUI Constructed tracker could plug into it as another child of `RootOverlayView` rather than creating its own host - a question #5 has to settle, not this note.

### 8.1 Shared conventions, and the absence of a token file

V2 Mulligan and PlayerResources share two things: `ObservableObject` with `@Published`, and `Color(hex:)` from `Core/Extensions/Color.swift:70-77`. That is a deliberate break from the V1 Mulligan code, which still uses the hand-rolled `ViewModel` base at `Utility/ViewModel.swift:11`.

**There is no shared SwiftUI styling or design-token file in this repo.** `UIs/Overlay/OutlinedText.swift` and `RoundedCorners.swift` exist but are used only by Battlegrounds and Overlay, never by `Constructed/`. Every SwiftUI view under `Constructed/` hard-codes its own colours, radii and spacing inline. #9 therefore has nothing to conflict with, and nothing to inherit.

### 8.2 Xib count - closing a carried-forward footnote

Note #4 §4.3 cites 71 xibs project-wide; the handoff observed 74 from `fd`. Measured here:

| Scope | Count |
| --- | --- |
| `HSTracker/` on disk | **74** |
| Referenced by `HSTracker.xcodeproj/project.pbxproj` | **72** |
| `UIs/Trackers/` | 15 |
| `UIs/Constructed/` | 9 |
| `UIs/Cards/` | 0 |

The two unreferenced files are `UIs/Trackers/BgHeroesViewController.xib` and `LanguageChooser.xib`. **[Unresolved]** the figure 71 is still not reproduced - it is off by one from the referenced count, and by three from disk. Not worth chasing further. The number that matters for a port is that **exactly one xib is the Constructed tracker: `Tracker.xib`.**

---

## 9. Design tokens literally present in the source

Extraction only, nothing proposed. This is the raw material #9 starts from.

**Fonts.** Numbers always `ChunkFive` (`CardBar.swift:146`); counter rows also `ChunkFive` at `18/ratioHeight` (`TrackerFrame.swift:81`). Card names by Hearthstone language, not app language (`Settings.swift:575-592`): `AR LisuGB Medium` simplified Chinese, `NanumGothic` other Asian, `BenguiatBold` Cyrillic, `ChunkFive` Latin (`CardBar.swift:148-158`); `ClassicBar` substitutes `Belwe Bd BT` and `Benguiat Rus` (`ClassicBar.swift:17-27`). **No weight is ever requested** - only `NSFont(name:size:)`.

**Font sizes.** count 17, mulligan 15, cost 20 (`CardBar.swift:120-123`); card name fitted between 15.0 and 1.0 (`:751`); generic fitter bounds max 15, min 5, accuracy 1 (`:700-702`).

**Colours.** Default count text `rgb(0.9221, 0.7215, 0.2226)` (`:143`). Flash: white base, `rgb(1, .647, 0)` Classic, `rgb(.1922, .5255, .8706)` Dark, `rgb(.41, .65, .88)` Frost (`ClassicBar.swift:30`, `DarkBar.swift:20`, `FrostBar.swift:18`). Text stroke always black (`:780`). State colours: drawn grey `rgb(.501, .501, .501)`, last-drawn orange `rgb(1, .647, 0)`, discarded `rgb(.803, .36, .36)` (`Card.swift:329-335`), in-hand default `rgb(.678, 1, .184)` (`Settings.swift:443`). `DeckLens` box fill `#23272A` (`DeckLens.swift:12-52`).

**Alphas and motion.** Flash 0.7 -> 0.0 over 0.5 s. Fade in 0.3 -> 1.0 over 0.5 s. Fade out -> 0.3 over 0.5 s, removal deferred 600 ms. Hover tooltip delay 0.400 s (`Tracker.swift:555`), link-panel hide delay 0.2 s (`:99-101`). **There is no alpha token for the dimmed state** - dimming is a PNG.

**Geometry.** Canonical row 217 x 34. All 13 rects at `CardBar.swift:128-140`. Counter rows 40 px tall, opponent draw chance 71 px, both divided by the size ratio. **No corner radius appears anywhere in the eight card files.**

---

## 10. Domain vocabulary

The vocabulary this inventory needed now lives in [`CONTEXT.md`](../../CONTEXT.md) at the repo root, written by `/domain-modeling` off the back of this note. That file is the single source; this section records only which collisions forced a ruling, since the reasoning is inventory-specific and does not belong in a glossary.

| Collision | Ruling |
| --- | --- |
| `CardList` the class is a table-based popup window (secret helper, graveyard detail); `AnimatedCardList` is the stack of rows inside the panel | **card list** means the run of rows; the class named `CardList` is a **card popup** |
| "count" means `Card.count` (copies unaccounted for), `deckCount` (cards in the deck zone) and `handCount` | **count remaining** and **deck count** are separate terms; the card counter row shows the latter |
| `theme` is a PNG directory plus a `CardBar` subclass, controlling pixels only (§5) | **theme** stays reserved for the four legacy looks; the replacement is a **design system** whose values are **tokens** |
| `OpponentDrawChance` draws four numbers, two of which are not draw chances | **draw chance** and **in-hand chance** are separate terms |
| `isCreated` is `info.created \|\| info.stolen`, and the two are indistinguishable on screen | **created card** is defined to include stolen |
| `jousted` marks inferred rather than confirmed presence, and renders identically to a spent card | **predicted card**, and the word `jousted` is retired from prose |
| An earlier draft of this note coined "satellite" for the separate-window displays | dropped - **overlay window** says the same thing and already matches the code |

---

## 11. What this changes for the map

1. **The scope line is drawn** (§2). The tracker is the one panel. `BoardDamage`, `TimerHud`, `FlavorText` and `CardHudContainer` are separate windows and stay out of scope; `CardCounter`, both draw chances and `GraveyardCounter` are subviews and are in. `JadeCounter` is dead code and can be deleted from every list it appears on.
2. **The component inventory patch in "Not yet specified" is now sharp enough to be a ticket.** §3 and §4 name the components: tracker panel, hero row, card row with 19 draw layers and 18 states, card list with three animations, lens, sideboard box, four counter-row variants. That should become its own ticket and leave the map.
3. **The data set is confirmed unchanged and now fully traced** (§6). Two pieces of it are computed in a view controller rather than the engine - the draw-chance model (`Tracker.swift:413-457`) and the graveyard aggregation (`:166-189`). Any framework boundary has to decide where those go, which is #5's problem, not the redesign's.
4. **The theme system is weaker prior art than it looked** (§5.4). #9 inherits element names and a row aspect ratio, not a token system.
5. **The redesign has no existing surface to convert.** The panel is transparent by default and every visual boundary is per-row PNG (§3.3). The single-glass-surface constraint from #6 is therefore an addition to the design, not a substitution for something already there.
6. **`ImageUtils` question, partly answered.** The map's "Whether the new tracker reuses `ImageUtils`" is narrower than it looked: three of four themes use it for tiles, and only `MinimalBar` bypasses it for a bundled render whose asset directory does not exist in the repo (§4.4). Still #5's or #9's call, but the ground is now known.

---

## 12. Open questions

- **[Unresolved]** Whether switching `Settings.theme` repaints live. The setter posts a notification (`Settings.swift:44-46`) and `Game` observes `theme_token` for `updateAllTrackers()` (`Game.swift:1585-1590`), but no `CardBar` observer exists, and existing bars are not re-created by `AnimatedCardList.update` unless card identity changes. Needs a run.
- **[Unresolved]** `Resources/Small/` - `MinimalBar`'s portrait source - does not exist in the repo (`MinimalBar.swift:32`). If it is not populated at build time, MinimalBar rows draw no portrait at all.
- **[Unresolved]** Whether `playerSideboards.isHidden` is ever reset to `false`. `Tracker.updateFrames()` only ever sets it true (`Tracker.swift:345`) while `DeckSideboards.update` manages it independently (`DeckSideboards.swift:123`, `:144`). Ordering across a refresh could not be settled from source.
- **[Unresolved]** The polarity of `OverWindowController.swift:50` (`ignoresMouseEvents = windowsLocked`) against the comment above it. Needs a run.
- **[Unresolved]** The 71-vs-72-vs-74 xib count (§8.2). Narrowed, not closed.
- **[Unresolved]** Writers of `Card.isBadAsMultiple`, `Player.tracker` and consumers of `Player.displayRevealedCards` were not located in the files read. All three look dead from the tracker's side.

---

## 13. Defects observed, not fixed

Recorded because a rewrite should not reproduce them, and because two of them affect the `.huge` card size that any layout work will exercise.

| Observation | Line |
| --- | --- |
| `.huge` row height uses `kHighRowFrameWidth` (331.88, a **width**) where every other branch uses `kHighRowHeight` (52.0) | `AnimatedCardList.swift:67-68`, `CardBar.swift:851` vs `CardList.swift:116`, `:147`, `Tracker.swift:139`, `:295` |
| `playerClass.frame` is built with `width: windowHeight` in both branches | `Tracker.swift:203`, `:231` |
| `updateFrames()` runs **before** `window.setFrame`, so every layout pass uses the previous window size | `WindowManager.swift:432-439` |
| `WindowManager.cardWidth` is a `static let`, so it goes stale after a card-size change until relaunch; `SizeHelper.trackerWidth` is the live equivalent | `WindowManager.swift:16-24` vs `SizeHelper.swift:252-262` |
| `WindowManager.show` reads `controller.window` before its own off-main bounce | `WindowManager.swift:413` vs `:415-420` |
| `Settings.shouldShowGUIElement` ORs `hideAllWhenGameInBackground` with itself | `Game.swift:242` |
| Persisted key for "player cards bottom" is misspelled `player_cards_botto` | `Settings.swift:691` |
| `updateCardCounter`'s `hasCoin` parameter is accepted and never used | `Tracker.swift:407` |
| `opponentBoardDamage` is shown with `SizeHelper.opponentBoardDamageFrame()` directly, ignoring the rect just computed from `Settings.opponentBoardDamageFrame` | `Game.swift:946-957` vs the player branch `:916-926` |
| `keeprate_*.png` is 51x26 against a 54-wide rect; `frame_mask.png` is 218x35 against a 217x34 frame, on all four themes | `CardBar.swift:128`, `:131` vs measured assets |
| The ELITE-as-legendary coercion is duplicated verbatim seven times | `CardBar.swift:312`, `:378`, `:430`, `:449`, `:537`, `:600`, `:629` |

---

## 14. Sources

### This repository

Read in full: `HSTracker/UIs/Trackers/Tracker.swift`, `Tracker.xib`, `CardList.swift`, `CardList.xib`, `AnimatedCardList.swift`, `TrackerFrame.swift`, `StringTracker.swift`, `OverWindowController.swift`, `WindowManager.swift`, `CardCounter.swift`, `PlayerDrawChance.swift`, `OpponentDrawChance.swift`, `GraveyardCounter.swift`, `JadeCounter.swift`, `BoardDamage.swift`, `TimerHud.swift`, `FlavorText.swift`, `CardHud.swift`, `CardHudContainer.swift`, `DeckLens.swift`, `DeckSideboards.swift`, `BoardOverlay.swift`; `HSTracker/UIs/Cards/` all eight files; `HSTracker/Logging/Player.swift`, `TurnTimer.swift`; `HSTracker/Core/Settings.swift`, `SizeHelper.swift`; `HSTracker/Database/Models/Card.swift`; `HSTracker/UIs/ImageUtils.swift`; `HSTracker/Hearthstone/CardLegalityChecker.swift`; `HSTracker/UIs/Overlay/Root/RootOverlayWindow.swift`, `RootOverlayView.swift`; `HSTracker/UIs/Constructed/` all files; the three tracker Preferences panes and their xibs.

Read in part: `HSTracker/Logging/Game.swift`. The range `3150-4699` was not read, which is why two of that file's eight `AppDelegate.instance()` sites are unlocated.

Asset directories inspected: `HSTracker/Resources/Themes/Bars/{classic,dark,frost,minimal}/`, `HSTracker/Resources/Fonts/`.

### Previous notes

`docs/research/4-overlay-window-layer.md` - §3.4 is the push path this note corrects for AppKit (§6.1); §4.3's xib count is narrowed in §8.2; its `AppDelegate.instance()` finding is extended in §6.4.
`docs/research/2-build-on-xcode-26.md` - build state, not re-derived here.
`docs/research/6-liquid-glass-over-gameplay.md` - the single-glass-surface constraint referenced in §11.5.
