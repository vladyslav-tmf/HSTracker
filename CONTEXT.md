# HSTracker overlay

A macOS deck tracker for Hearthstone. It reads the game's logs and memory, then draws what it learns on top of the running game. This glossary covers the in-game overlay surfaces and the card data behind them, which is where the language collides most.

Several terms here exist because the codebase uses one word for two things. Where that happens the entry says which meaning wins.

## Surfaces

**Tracker panel**:
The single window showing one player's deck, with its header, card lists and counter rows. There are two instances of it, the player tracker and the opponent tracker.
_Avoid_: tracker (bare), deck tracker, overlay

**Overlay window**:
Any in-game display that owns its own window and positions itself independently of the tracker panel. Board damage, the turn timer, the flavour text panel and the opponent hand markers are overlay windows, not parts of the tracker panel.
_Avoid_: satellite, HUD, widget

**Hover surface**:
A panel the tracker panel opens on hover and closes on exit, such as the graveyard detail popup or the enlarged card preview. It belongs to the tracker panel's behaviour but not to its layout.
_Avoid_: popup, tooltip, flyout

**Card popup**:
A standalone window listing cards in a table, used for the secret helper and the graveyard detail. Distinct from a card list despite the class being named `CardList`.
_Avoid_: card list, secret list

## Inside the tracker panel

**Card row**:
One card as drawn in the tracker: its art, mana cost, name, remaining count and current state, in a single fixed-height strip.
_Avoid_: card bar, card cell, row, card (when the drawn thing is meant rather than the card itself)

**Card list**:
An ordered run of card rows that animates as cards enter, leave and change count. The tracker panel contains several of them, not one.
_Avoid_: card stack, deck view, `CardList` (which is a card popup)

**Deck list**:
The main card list in the tracker panel: what remains of the tracked deck. The other card lists in the panel are lenses and sideboard boxes.
_Avoid_: the card list, main list

**Lens**:
A labelled box wrapping its own small card list, used to call out a subset of the deck such as cards known to be on top, on the bottom, or cards the opponent may hold.
_Avoid_: section, group, drawer

**Sideboard box**:
A labelled box holding the cards attached to a sideboard card rather than shuffled into the deck.
_Avoid_: sideboard list

**Counter row**:
A row inside the tracker panel that shows numbers rather than cards: the card counter, the draw chances, the graveyard counter, the win/loss record.
_Avoid_: counter (bare, which reads as the separate counters overlay), frame, stat row

**Deck header**:
The strip at the top of the tracker panel carrying the hero portrait and either the deck name or the opponent's name.
_Avoid_: title bar, hero bar

## Card state

**Count remaining**:
How many copies of a card are still unaccounted for in the deck. Zero means every copy has been seen, which is what makes a row read as spent.
_Avoid_: count, quantity, copies left

**Deck count**:
How many cards are left in the deck zone, regardless of which cards they are. This is the number the card counter row shows, and it is not a sum of counts remaining.
_Avoid_: cards left, deck size

**Deck state**:
The resolved picture of a tracked deck at a moment: what remains, what has been removed, and what sits in sideboards. It is derived by subtracting what has been seen from the deck as submitted.
_Avoid_: deck contents, deck snapshot

**Created card**:
A card obtained outside the starting deck, including one stolen from the opponent. The two cases are not distinguished on screen.
_Avoid_: generated card, gift, token

**Predicted card**:
A card shown because its presence is inferred rather than confirmed. It reads dimmed, the same way a spent card does.
_Avoid_: jousted, hidden, guessed

**Draw chance**:
The probability that the next draw is a named card. Shown for one copy and for two.
_Avoid_: odds, topdeck chance

**In-hand chance**:
The probability that the opponent is already holding a named card. Shown alongside the draw chances on the opponent side, and not itself a draw chance.
_Avoid_: draw chance, hand odds

## Appearance

**Theme**:
The legacy look of a card row: a set of images plus a hardcoded variant class. A theme controls pixels only, and cannot reach spacing, type, timing or layout. Reserved for the four shipped looks.
_Avoid_: using this word for the new design system

**Design system**:
The replacement's shared visual language, shipped as code. Its values are tokens. It is not a theme, and the two do not coexist on the same surface.
_Avoid_: theme, skin, style

**Panel material**:
The background treatment of the tracker panel, chosen by the user, ranging from system glass to flat and opaque.
_Avoid_: background, blur, glass (when the setting is meant rather than the material)

**Card size**:
The single knob scaling the tracker panel. It picks a card row height, and every other measurement in the panel is derived from it.
_Avoid_: zoom, scale, row height, window size
