//
//  ArenaPickHelperViewModel.swift
//  HSTracker
//
//  Copyright © 2026 Benjamin Michotte. All rights reserved.
//

import Foundation
import SwiftUI

/// Which direction a synergy runs between an offered card and one already drafted.
struct ArenaSynergy: OptionSet {
    let rawValue: Int
    static let receives = ArenaSynergy(rawValue: 1)
    static let provides = ArenaSynergy(rawValue: 2)
    static let both: ArenaSynergy = [.receives, .provides]
}

/// How the panel should come and go as the client moves between arena screens.
enum ArenaScreenBehavior {
    case none
    case slideIn
    case slideOut
    case fadeIn
    case fadeOut
}

/// One row of the drafted-deck rail down the right of the screen.
@available(macOS 10.15, *)
final class ArenaDeckListTileViewModel: ObservableObject, Identifiable {
    let cardId: String
    let count: Int
    let card: Card?

    @Published var synergy: ArenaSynergy = []
    @Published var hoveredChoiceCardId: String?
    /// Arenasmith's score for this card, shown while editing a redraft deck.
    @Published var arenasmithScore: Double?
    @Published var suggestRemove = false

    var id: String { cardId }

    init(cardId: String, count: Int) {
        self.cardId = cardId
        self.count = count
        self.card = Cards.by(cardId: cardId)
    }

    var cardName: String? { card?.name }
    var showSynergy: Bool { !synergy.isEmpty }
    var hoveredChoiceCardName: String? { Cards.by(cardId: hoveredChoiceCardId ?? "")?.name }
}

/// The Arenasmith draft overlay's state machine.
///
/// Port of HDT's `ArenaPickHelperViewModel`. It subscribes to `ArenaStateWatcher`,
/// decides which of the four pick kinds is on screen (hero, hero power, dual-class
/// hero, or card), gates on availability/premium/trials, calls the matching
/// endpoint, and exposes the results plus the synergy highlighting for the deck
/// rail.
@available(macOS 10.15, *)
final class ArenaPickHelperViewModel: ObservableObject {

    // MARK: published state

    @Published private(set) var cardStats: [ArenaPickSingleCardOptionViewModel]?
    @Published private(set) var heroStats: [ArenaPickSingleHeroOptionViewModel]?
    @Published private(set) var heroPowerStats: [ArenaPickSingleHeroOptionViewModel]?
    @Published private(set) var dualClassHeroStats: [ArenaPickSingleHeroOptionViewModel]?

    @Published private(set) var tileViewModels = [ArenaDeckListTileViewModel]()
    @Published private(set) var redraftTileViewModels = [ArenaDeckListTileViewModel]()

    @Published private(set) var messages: [String]?
    @Published private(set) var bottomPanelCards = [Card]()
    @Published private(set) var bottomPanelTitle = ""
    @Published private(set) var isRelatedCardsSorted = false

    @Published private(set) var showErrorMessage = false
    @Published private(set) var stateChange = ArenaScreenBehavior.none
    @Published private(set) var isDrafting = false
    @Published private(set) var isUnderground = false
    @Published private(set) var arenaSeasonId = 0
    @Published private(set) var clientState = ArenaClientStateType.none
    @Published private(set) var sessionState = ArenaSessionState.invalid
    @Published private(set) var isAnimating = false
    @Published private(set) var isHeroZoomed = false
    @Published private(set) var isPackageSelectOpen = false
    @Published private(set) var hoveredChoice: ArenaDraftChoice?
    /// Cursor is over the bottom panel. Set by RootOverlayWindow, which tracks
    /// the pointer even while the overlay is click-through.
    @Published var hoveringPanel = false {
        didSet {
            guard hoveringPanel != oldValue else { return }
            updateTileViewModels()
        }
    }
    @Published private(set) var scrollOffset: CGFloat = 0
    @Published private(set) var redraftScrollOffset: CGFloat = 0

    /// Read by `Watchers` when recording a pick, so the saved draft says whether
    /// the player actually had the overlay in front of them.
    private(set) var isArenasmithAvailable = false
    private(set) var isOverlayVisible = false
    private(set) var isTrialsActivated = false
    private(set) var arenasmithScores = [String: Float]()

    // MARK: internal state

    private var chosenHero = ""
    private var chosenHeroPower = ""
    private var isDualClass = false
    private var choices: [ArenaDraftChoice]?
    private var lastHoveredChoice: ArenaDraftChoice?
    private var pickedDeck: [String]?
    private var pickedRedraftDeck: [String]?
    private var scrollValue = 0.0
    private var arenaCardStatsCache = [String: ArenaCardStats?]()

    // MARK: visibility, straight off the settings

    var arenasmithScoreVisible: Bool { Settings.showArenasmithScore }
    var heroPickVisible: Bool { Settings.showArenaHeroPicking }
    var relatedCardsVisible: Bool { Settings.showArenaRelatedCards }
    var synergiesVisible: Bool { Settings.showArenaDeckSynergies }
    var redraftDiscardVisible: Bool { Settings.showArenaRedraftDiscard }

    /// The client sometimes reports `undergroundDraft` while redrafting, so the
    /// session state - not the client state - is what decides this.
    var isRedraft: Bool { sessionState == .redrafting || sessionState == .midrun_redraft_pending }
    var isEditingDeck: Bool { sessionState == .editing_deck }

    var showStats: Bool {
        !isAnimating && !isHeroZoomed && !isPackageSelectOpen
            && (cardStats != nil || heroStats != nil || heroPowerStats != nil || dualClassHeroStats != nil)
    }

    var showMessages: Bool { !(messages?.isEmpty ?? true) }

    var hasBottomPanelCards: Bool { !bottomPanelCards.isEmpty }

    /// The messages column eats 280pt, so the card grid gets fewer columns when
    /// one is present.
    var bottomPanelColumnCount: Int { showMessages ? 4 : 6 }

    var showBottom: Bool {
        if isPackageSelectOpen || isAnimating || isHeroZoomed { return false }
        // The in-game hover is what opens the panel. Once it ends the panel stays
        // only while the cursor is actually on it, so moving over to scroll the
        // card list doesn't dismiss it.
        if hoveredChoice == nil && (lastHoveredChoice == nil || !hoveringPanel) { return false }
        return Settings.showArenaRelatedCards && (hasBottomPanelCards || showMessages)
    }

    // MARK: wiring

    init(watcher: ArenaStateWatcher = Watchers.arenaStateWatcher) {
        watcher.onClientStateChanged.subscribe { [weak self] in self?.updateClientState($0) }
        watcher.onIsAnimatingChanged.subscribe { [weak self] in self?.isAnimating = $0 }
        watcher.onIsPackageSelectOpen.subscribe { [weak self] in self?.isPackageSelectOpen = $0 }
        watcher.onIsUndergroundChanged.subscribe { [weak self] in self?.isUnderground = $0 }
        watcher.onArenaSeasonIdChanged.subscribe { [weak self] in self?.arenaSeasonId = $0 }
        watcher.onHeroZoomed.subscribe { [weak self] in self?.isHeroZoomed = $0 != nil }
        watcher.onHeroPicked.subscribe { [weak self] in self?.chosenHero = $0 }
        watcher.onHeroPowerPicked.subscribe { [weak self] in self?.chosenHeroPower = $0 }
        watcher.onScrollChange.subscribe { [weak self] in self?.updateScroll($0) }
        watcher.onDeckListChange.subscribe { [weak self] in self?.updateDeckList($0) }
        watcher.onRedraftDeckListChange.subscribe { [weak self] in self?.updateRedraftDeckList($0) }
        watcher.onChoicesChanged.subscribe { [weak self] in self?.updateChoices($0) }
        watcher.onCardHover.subscribe { [weak self] in self?.updateHoveredChoice($0) }
    }

    // MARK: state transitions

    private func updateClientState(_ state: ArenaClientState) {
        if clientState.isLanding && (state.clientState == .normalDraft || state.clientState == .undergroundDraft) {
            stateChange = .slideIn
        } else if clientState.isDrafting && state.clientState.isLanding {
            stateChange = .slideOut
        } else if state.clientState.isDrafting || state.clientState.isDeckEdit {
            stateChange = .fadeIn
        } else if state.clientState == .undergroundReady && state.sessionState == .editing_deck {
            stateChange = .fadeIn
        } else {
            stateChange = .fadeOut
        }

        clientState = state.clientState
        sessionState = state.sessionState
        isDrafting = state.clientState.isDrafting
    }

    private func updateScroll(_ value: Double) {
        scrollValue = value

        // The rail scrolls in lockstep with the game's own deck tray, whose scroll
        // value the mirror reads directly. These constants are the tray's metrics
        // in the 1080-tall reference space.
        let scrollBottomPadding = 0.8275
        let visibleScrollItems = 21.5
        let scrollItemHeight = 40.75
        let redraftPanelHeightPx = 251.0
        let redraftPanelHeaderHeightPx = 38.0

        var totalHeightInItems = Double(tileViewModels.count) + scrollBottomPadding
        if isRedraft {
            totalHeightInItems += redraftPanelHeightPx / scrollItemHeight
        }

        let overflow = scrollItemHeight * max(0, totalHeightInItems - visibleScrollItems)
        let offset = overflow * -scrollValue

        scrollOffset = CGFloat(isRedraft ? offset + redraftPanelHeightPx : offset)
        redraftScrollOffset = CGFloat(offset + redraftPanelHeaderHeightPx)
    }

    private func updateDeckList(_ cards: [MirrorCard]) {
        // This lands before the next choices arrive. Clearing the hover here stops
        // the synergy highlighting flickering against a stale card.
        hoveredChoice = nil
        lastHoveredChoice = nil

        pickedDeck = cards.flatMap { Array(repeating: $0.cardId, count: $0.count.intValue) }
        tileViewModels = cards.map { ArenaDeckListTileViewModel(cardId: $0.cardId, count: $0.count.intValue) }
        updateTileViewModels()
        updateScroll(scrollValue)

        if sessionState == .editing_deck {
            Task { await onDeckEditing() }
        }
    }

    private func updateRedraftDeckList(_ cards: [MirrorCard]) {
        hoveredChoice = nil
        lastHoveredChoice = nil

        pickedRedraftDeck = cards.flatMap { Array(repeating: $0.cardId, count: $0.count.intValue) }
        redraftTileViewModels = cards.map { ArenaDeckListTileViewModel(cardId: $0.cardId, count: $0.count.intValue) }
        updateTileViewModels()
        updateScroll(scrollValue)
    }

    /// Recomputes which drafted cards light up for the currently hovered choice.
    private func updateTileViewModels() {
        // Falling back to the last hovered choice keeps the deck highlighting up
        // while the cursor is on the panel; without that guard the highlights
        // would persist after the player stops hovering anything.
        let choice = hoveredChoice ?? (hoveringPanel ? lastHoveredChoice : nil)
        let activeCard = choice.flatMap { cardStats?[safeIndex: $0.index] }?.cardStats

        let enhancedBy = activeCard?.related_cards?.enhanced_by_card_ids?.all ?? []
        let enabled = activeCard?.related_cards?.card_ids_enabled?.all ?? []

        for tile in tileViewModels + redraftTileViewModels {
            tile.hoveredChoiceCardId = choice?.cardId
            var synergy: ArenaSynergy = []
            if enhancedBy.contains(tile.cardId) { synergy.insert(.provides) }
            if enabled.contains(tile.cardId) { synergy.insert(.receives) }
            tile.synergy = synergy
        }
    }

    // MARK: choices

    private func updateChoices(_ newChoices: [ArenaDraftChoice]) {
        if sessionState == .editing_deck {
            logger.warning("Received choices while editing deck. Second arena run in progress?")
            return
        }

        cardStats = nil
        messages = nil
        heroStats = nil
        heroPowerStats = nil
        dualClassHeroStats = nil
        lastHoveredChoice = nil
        hoveredChoice = nil
        bottomPanelCards = []
        choices = newChoices
        updateTileViewModels()

        Task { await loadChoices(newChoices) }
    }

    private func loadChoices(_ newChoices: [ArenaDraftChoice]) async {
        let availabilities = await ArenasmithStatusManager.instance.ensureAvailabilities()
        guard availabilities.isAvailable(isUnderground: isUnderground) else {
            logger.info("Arenasmith is not available for \(isUnderground ? "Underground Arena" : "Arena"), aborting")
            await MainActor.run {
                isArenasmithAvailable = false
                isTrialsActivated = false
                isOverlayVisible = false
                arenasmithScores.removeAll()
            }
            return
        }

        await MainActor.run { isArenasmithAvailable = true }

        guard !newChoices.isEmpty else { return }

        let offered = newChoices.map { $0.cardId }
        guard let accountId = MirrorHelper.getAccountId(),
              let arenaInfo = MirrorHelper.getArenaInfo() else {
            return
        }
        let deckId = arenaInfo.deck.id.int64Value
        let accountHi = accountId.hi.int64Value
        let accountLo = accountId.lo.int64Value

        if chosenHero.isEmpty && chosenHeroPower.isEmpty {
            await loadHeroPick(offered: offered, deckId: deckId, hi: accountHi, lo: accountLo, choices: newChoices)
            return
        }

        await MainActor.run { isOverlayVisible = false }

        guard Settings.enableArenasmithOverlay else {
            await MainActor.run { arenasmithScores.removeAll() }
            return
        }

        // Non-premium players only get results for a deck the server has accepted
        // for a trial.
        if !userOwnsPremium {
            await ArenaTrial.instance.ensureLoaded(hi: accountHi, lo: accountLo)
            guard ArenaTrial.instance.isDeckResumable(deckId) else {
                logger.info("Current deck is not registered for trials, aborting")
                await MainActor.run {
                    isTrialsActivated = false
                    arenasmithScores.removeAll()
                }
                return
            }
        }

        // Dual-class: hero power is picked first, so a still-empty hero means the
        // second screen is the hero choice.
        if !chosenHeroPower.isEmpty && chosenHero.isEmpty {
            await loadDualClassHeroPick(offered: offered, deckId: deckId, hi: accountHi, lo: accountLo, choices: newChoices)
            return
        }

        await loadCardPick(offered: offered, deckId: deckId, lo: accountLo, hi: accountHi,
                           losses: arenaInfo.losses.intValue)
    }

    private var userOwnsPremium: Bool {
        HSReplayAPI.isFullyAuthenticated && (HSReplayAPI.accountData?.is_premium ?? false)
    }

    // MARK: hero pick

    private func loadHeroPick(offered: [String], deckId: Int64, hi: Int64, lo: Int64, choices: [ArenaDraftChoice]) async {
        await ArenaTrial.instance.ensureLoaded(hi: hi, lo: lo)
        let trials = ArenaTrial.instance.remainingTrials ?? (0, 0)

        await MainActor.run {
            isTrialsActivated = false
            arenasmithScores.removeAll()
        }

        if !userOwnsPremium {
            guard trials.starter + trials.recurring > 0 else {
                logger.info("No trials left for hero pick, aborting")
                return
            }
            await MainActor.run { isTrialsActivated = true }
        }

        await MainActor.run { isOverlayVisible = false }
        guard Settings.enableArenasmithOverlay else { return }

        if pickedDeck == nil {
            await MainActor.run { reset() }
        }

        guard let firstCard = Cards.by(cardId: choices[0].cardId),
              firstCard.type == .hero || firstCard.type == .hero_power else {
            return
        }
        let dualClass = firstCard.type == .hero_power
        let variant: ArenaPickSingleHeroOptionViewModel.Variant = dualClass ? .heroPower : .hero

        // Loading plates while the request is in flight.
        await MainActor.run {
            isDualClass = dualClass
            let loading = offered.enumerated().map { index, _ in
                ArenaPickSingleHeroOptionViewModel(isUnderground: isUnderground, variant: variant, index: index)
            }
            if dualClass { heroPowerStats = loading } else { heroStats = loading }
        }

        let response = await requestHeroPick(offeredHeroes: offered, deckId: deckId, hi: hi, lo: lo)
        ArenaTrial.instance.clear()

        guard let response else {
            await MainActor.run { showErrorMessage = true }
            return
        }

        let ordered = orderHeroData(response, choices: choices)
        await MainActor.run {
            showErrorMessage = false
            let models = ordered.enumerated().map { index, data in
                ArenaPickSingleHeroOptionViewModel(data: data, isUnderground: isUnderground, variant: variant, index: index)
            }
            if dualClass { heroPowerStats = models } else { heroStats = models }
            isOverlayVisible = heroPickVisible
        }
    }

    private func loadDualClassHeroPick(offered: [String], deckId: Int64, hi: Int64, lo: Int64, choices: [ArenaDraftChoice]) async {
        guard let firstCard = Cards.by(cardId: choices[0].cardId),
              firstCard.type == .hero || firstCard.type == .hero_power else {
            return
        }

        await MainActor.run {
            dualClassHeroStats = offered.enumerated().map { index, _ in
                ArenaPickSingleHeroOptionViewModel(isUnderground: isUnderground, variant: .dualClassHero, index: index)
            }
        }

        let response = await requestHeroPick(offeredHeroes: offered, deckId: deckId, hi: hi, lo: lo,
                                             pickedHeroCardIds: [chosenHeroPower])
        ArenaTrial.instance.clear()

        guard let response else {
            await MainActor.run { showErrorMessage = true }
            return
        }

        let ordered = orderHeroData(response, choices: choices)
        await MainActor.run {
            showErrorMessage = false
            dualClassHeroStats = ordered.enumerated().map { index, data in
                ArenaPickSingleHeroOptionViewModel(data: data, isUnderground: isUnderground,
                                                   variant: .dualClassHero, index: index)
            }
            isOverlayVisible = heroPickVisible
        }
    }

    /// The API returns classes in ascending class-id order, but they have to be
    /// drawn in the order the game offered them.
    private func orderHeroData(_ response: ArenaHeroPickApiResponse,
                               choices: [ArenaDraftChoice]) -> [ArenaHeroPickApiResponse.ResponseData?] {
        var byClass = [CardClass: ArenaHeroPickApiResponse.ResponseData]()
        for entry in response.data {
            // deck_class is HearthDb's numeric CardClass, whose order HSTracker's
            // CardClass enum matches case for case.
            if entry.deck_class >= 0 && entry.deck_class < CardClass.allCases.count {
                byClass[CardClass.allCases[entry.deck_class]] = entry
            }
        }
        return choices.map { choice in
            guard let cardClass = Cards.by(cardId: choice.cardId)?.playerClass else { return nil }
            return byClass[cardClass]
        }
    }

    // MARK: card pick

    private func loadCardPick(offered: [String], deckId: Int64, lo: Int64, hi: Int64, losses: Int) async {
        await MainActor.run {
            cardStats = offered.map { ArenaPickSingleCardOptionViewModel(cardId: $0, isUnderground: isUnderground) }
            isOverlayVisible = arenasmithScoreVisible
        }

        var pickData: [String: ArenaCardPickApiResponse.CardStatsEntry]?

        if !isRedraft {
            let picked = tileViewModels.flatMap { Array(repeating: $0.cardId, count: $0.count) }
            // The game occasionally fires a choices change after the final pick.
            guard picked.count != 30 else { return }

            let response = await requestCardPick(offered: offered, picked: picked, deckCardIds: nil,
                                                 redraftNumber: nil, deckId: deckId, hi: hi, lo: lo)
            pickData = response?.data
        } else {
            let deckCards = tileViewModels.flatMap { Array(repeating: $0.cardId, count: $0.count) }
            guard !deckCards.isEmpty else { return }

            let response = await requestCardPick(offered: offered,
                                                 picked: pickedRedraftDeck ?? [],
                                                 deckCardIds: deckCards,
                                                 redraftNumber: max(1, losses),
                                                 deckId: deckId, hi: hi, lo: lo)
            pickData = response?.data
        }

        await MainActor.run {
            showErrorMessage = pickData == nil
            cardStats = offered.map { cardId in
                ArenaPickSingleCardOptionViewModel(cardId: cardId,
                                                   data: pickData?[cardId] ?? ArenaCardPickApiResponse.CardStatsEntry(),
                                                   pickedDeck: pickedDeck,
                                                   isUnderground: isUnderground,
                                                   apiError: pickData == nil)
            }

            arenasmithScores.removeAll()
            for cardId in offered {
                arenasmithScores[cardId] = Self.score(of: pickData?[cardId])
            }
            updateTileViewModels()
        }
    }

    private static func score(of stats: ArenaCardPickApiResponse.CardStatsEntry?) -> Float {
        if let dyn = stats?.arenasmith_dyn?.score, let value = Float(dyn) { return value }
        if let base = stats?.arenasmith?.score, let value = Float(base) { return value }
        return -1
    }

    // MARK: deck editing (redraft discard hints)

    private func onDeckEditing() async {
        guard Settings.enableArenasmithOverlay else { return }

        let availabilities = await ArenasmithStatusManager.instance.ensureAvailabilities()
        guard availabilities.undergroundArena else { return }

        await MainActor.run {
            cardStats = nil
            messages = nil
        }

        guard let arenaInfo = MirrorHelper.getArenaInfo(), let accountId = MirrorHelper.getAccountId() else {
            return
        }
        let deckId = arenaInfo.deck.id.int64Value
        let redraftNumber = max(1, arenaInfo.losses.intValue)
        let cacheKey = "\(deckId)_\(redraftNumber)"

        var stats = arenaCardStatsCache[cacheKey] ?? nil
        if arenaCardStatsCache[cacheKey] == nil {
            if !userOwnsPremium {
                await ArenaTrial.instance.ensureLoaded(hi: accountId.hi.int64Value, lo: accountId.lo.int64Value)
                guard ArenaTrial.instance.isDeckResumable(deckId) else {
                    logger.info("Current deck is not registered for trials, aborting")
                    return
                }
            }

            // Depending on read timing the game either already holds all 35 cards in
            // the original deck, or still has them split across the two lists.
            let original = pickedDeck ?? []
            let deck = original.count == 35 ? original : original + (pickedRedraftDeck ?? [])

            stats = await requestScoreDeck(deck: deck, redraftNumber: redraftNumber, deckId: deckId,
                                           hi: accountId.hi.int64Value, lo: accountId.lo.int64Value)
            arenaCardStatsCache[cacheKey] = stats
        }

        await MainActor.run {
            for tile in tileViewModels {
                if let entry = stats?.data[tile.cardId], let score = entry.score {
                    tile.arenasmithScore = (score).rounded()
                }
            }

            // Everything at or below the score of the nth-worst card is a discard
            // candidate, where n is how many cards have to go to get back to 30.
            let floorIndex = max(0, tileViewModels.reduce(0) { $0 + $1.count } - 30) - 1
            let sortedScores = tileViewModels
                .filter { $0.arenasmithScore != nil }
                .flatMap { tile in Array(repeating: tile.arenasmithScore!, count: tile.count) }
                .sorted()
            let scoreFloor = floorIndex >= 0 && floorIndex < sortedScores.count ? sortedScores[floorIndex] : nil

            for tile in tileViewModels {
                if let score = tile.arenasmithScore, let floor = scoreFloor, score <= floor {
                    tile.suggestRemove = true
                }
            }
            updateScroll(scrollValue)
        }
    }

    // MARK: hover

    private func updateHoveredChoice(_ choice: ArenaDraftChoice?) {
        hoveredChoice = choice
        updateTileViewModels()

        guard let choice, let card = Cards.by(cardId: choice.cardId) else {
            return
        }

        if card.type == .hero || card.type == .hero_power {
            let stats = (card.type == .hero
                         ? (heroStats?[safeIndex: choice.index] ?? dualClassHeroStats?[safeIndex: choice.index])
                         : heroPowerStats?[safeIndex: choice.index])
            let className = stats.flatMap { model -> String? in
                guard let deckClass = model.data?.deck_class,
                      deckClass >= 0, deckClass < CardClass.allCases.count else { return nil }
                return CardClass.allCases[deckClass].rawValue.capitalized
            } ?? ""
            bottomPanelCards = (stats?.classDeckSignatureCardIds ?? []).compactMap { Cards.by(cardId: $0) }
            bottomPanelTitle = "\(className) – \(String.localizedString("ArenaPick_ClassTopCards", comment: ""))"
            isRelatedCardsSorted = false
            lastHoveredChoice = choice
            messages = nil
            return
        }

        guard let stats = cardStats?[safeIndex: choice.index] else { return }

        let related = stats.cardStats?.related_cards?.generated_card_ids
        let cards = (related?.generated ?? []).compactMap { Cards.by(cardId: $0) }
        bottomPanelCards = cards
        isRelatedCardsSorted = related?.is_sorted ?? false

        if cards.isEmpty {
            bottomPanelTitle = card.name
        } else {
            let total = related?.total_cards ?? 0
            let label = String.localizedString("ArenaPick_RelatedCards", comment: "")
            bottomPanelTitle = cards.count < total
                ? "\(card.name) – \(label) \(cards.count)/\(total)"
                : "\(card.name) – \(label) \(cards.count)"
        }

        messages = stats.cardStats?.messages?.compactMap(Self.describe)
        lastHoveredChoice = choice
        updateTileViewModels()
    }

    private static func describe(_ message: ArenaPickMessage) -> String? {
        func cardName(_ id: String?) -> String { Cards.by(cardId: id ?? "")?.name ?? "" }

        switch (message.type, message.content) {
        case (.lowSynergy, .lowSynergy(let content)):
            return String(format: String.localizedString("ArenaPick_Message_LowSynergy", comment: ""),
                          content.remaining_picks ?? 0)
        case (.highlander, .highlander(let content)):
            return String(format: String.localizedString("ArenaPick_Message_Highlander", comment: ""),
                          cardName(content.highlander_card_id))
        case (.softHighlander, .highlander(let content)):
            return String(format: String.localizedString("ArenaPick_Message_SoftHighlander", comment: ""),
                          cardName(content.highlander_card_id))
        case (.highlanderChances, _):
            return String.localizedString("ArenaPick_Message_HighlanderChance", comment: "")
        case (.veryRare, .veryRare(let content)):
            // The catalog entry uses %@, so the percentage goes in as a string -
            // a Double through %@ would be a mismatched specifier.
            let percent = content.percent_drafts ?? 0
            let formatted = percent == percent.rounded()
                ? String(Int(percent))
                : String(format: "%.1f", percent)
            return String(format: String.localizedString("ArenaPick_Message_VeryRare", comment: ""), formatted)
        case (.questHelps, .questHelps(let content)):
            return String(format: String.localizedString("ArenaPick_Message_HelpsQuest", comment: ""),
                          cardName(content.quest_card_id))
        default:
            return nil
        }
    }

    // MARK: reset

    /// The visibility properties above read `Settings` directly rather than
    /// mirroring it into @Published state, so nothing tells SwiftUI to re-read
    /// them when a preference changes. The preferences pane calls this.
    func settingsChanged() {
        objectWillChange.send()
    }

    func reset(keepGameState: Bool = false) {
        heroStats = nil
        heroPowerStats = nil
        dualClassHeroStats = nil
        cardStats = nil
        messages = nil
        tileViewModels = []
        redraftTileViewModels = []
        lastHoveredChoice = nil
        ArenasmithStatusManager.instance.clear()
        if !keepGameState {
            chosenHero = ""
            chosenHeroPower = ""
            isDualClass = false
        }
    }

    // MARK: requests

    private func requestHeroPick(offeredHeroes: [String], deckId: Int64, hi: Int64, lo: Int64,
                                 pickedHeroCardIds: [String] = []) async -> ArenaHeroPickApiResponse? {
        let parameters = ArenaHeroPickParams(
            picked_hero_card_ids: pickedHeroCardIds,
            offered_hero_card_ids: offeredHeroes,
            player_region: Helper.getRegion(hi: hi).rawValue,
            account_lo: lo,
            arena_season: arenaSeasonId,
            deck_id: deckId,
            game_type: gameType
        )
        return await HSReplayAPI.getArenaHeroPickStats(parameters: parameters)
    }

    //swiftlint:disable:next function_parameter_count
    private func requestCardPick(offered: [String], picked: [String], deckCardIds: [String]?,
                                 redraftNumber: Int?, deckId: Int64, hi: Int64, lo: Int64) async -> ArenaCardPickApiResponse? {
        let parameters = ArenaCardPickParams(
            picked_hero_card_id: chosenHero,
            picked_card_ids: picked,
            offered_card_ids: offered,
            player_region: Helper.getRegion(hi: hi).rawValue,
            account_lo: lo,
            arena_season: arenaSeasonId,
            deck_id: deckId,
            game_type: gameType,
            redraft_number: redraftNumber,
            deck_card_ids: deckCardIds,
            picked_hero_power_card_id: chosenHeroPower.isEmpty ? nil : chosenHeroPower
        )
        return await HSReplayAPI.getArenaCardPickStats(parameters: parameters)
    }

    private func requestScoreDeck(deck: [String], redraftNumber: Int, deckId: Int64,
                                  hi: Int64, lo: Int64) async -> ArenaCardStats? {
        let parameters = ArenaScoreDeckParams(
            picked_hero_card_id: chosenHero,
            deck_card_ids: deck,
            player_region: Helper.getRegion(hi: hi).rawValue,
            account_lo: lo,
            arena_season: arenaSeasonId,
            deck_id: deckId,
            game_type: gameType,
            redraft_number: redraftNumber,
            picked_hero_power_card_id: chosenHeroPower.isEmpty ? nil : chosenHeroPower
        )
        return await HSReplayAPI.scoreArenaDeck(parameters: parameters)
    }

    private var gameType: Int {
        (isUnderground ? BnetGameType.bgt_underground_arena : BnetGameType.bgt_arena).rawValue
    }
}

extension Array {
    /// Bounds-checked lookup - the hovered choice index comes from game memory and
    /// can outrun a stats array that is still being replaced.
    subscript(safeIndex index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
