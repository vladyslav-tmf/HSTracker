//
//  ArenaPickHelperView.swift
//  HSTracker
//
//  Copyright © 2026 Benjamin Michotte. All rights reserved.
//

import SwiftUI

/// The Arenasmith draft overlay. Port of HDT's `ArenaPickHelper.xaml`.
///
/// Authored at HDT's 1440x1080 reference and hosted on `RootOverlayView`'s scaled
/// canvas, which applies the same `height / 1080` factor HDT's
/// `_arenaOverlayBehavior` does.
@available(macOS 10.15, *)
struct ArenaPickHelperView: View {
    @ObservedObject var viewModel: ArenaPickHelperViewModel

    // HDT's outer grid: 3.25* for the pick area, 1* for the deck rail.
    private static let referenceWidth: CGFloat = 1440
    private static let referenceHeight: CGFloat = 1080
    private static let optionsFraction: CGFloat = 3.25 / 4.25

    private var optionsWidth: CGFloat { Self.referenceWidth * Self.optionsFraction }
    private var railWidth: CGFloat { Self.referenceWidth - optionsWidth }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if viewModel.isVisible {
                HStack(spacing: 0) {
                    optionsArea
                        .frame(width: optionsWidth)
                    deckRail
                        .frame(width: railWidth)
                }
                .frame(width: Self.referenceWidth, height: Self.referenceHeight, alignment: .topLeading)
                .transition(transition)
            }
        }
        .frame(width: Self.referenceWidth, height: Self.referenceHeight, alignment: .topLeading)
        .animation(.easeOut(duration: 0.3), value: viewModel.isVisible)
        .allowsHitTesting(false)
    }

    /// HDT drives this with four storyboards keyed off `StateChange`; entering the
    /// draft from the landing screen slides in from the right, leaving slides back
    /// out, and everything else cross-fades.
    private var transition: AnyTransition {
        switch viewModel.stateChange {
        case .slideIn, .slideOut:
            return .move(edge: .trailing).combined(with: .opacity)
        default:
            return .opacity
        }
    }

    // MARK: options

    private var optionsArea: some View {
        // Inside the pick area HDT splits 108 / 782 / 110; the three options live
        // in the middle column with a 10pt gutter either side.
        GeometryReader { geometry in
            let unit = geometry.size.width / 1000
            HStack(spacing: 0) {
                Spacer().frame(width: 108 * unit)
                options
                    .padding(.horizontal, 10)
                    .frame(width: 782 * unit)
                Spacer().frame(width: 110 * unit)
            }
        }
    }

    @ViewBuilder
    private var options: some View {
        if viewModel.showStats {
            if let heroStats = viewModel.heroStats, viewModel.heroPickVisible {
                heroRow(heroStats)
            } else if let heroPowerStats = viewModel.heroPowerStats, viewModel.heroPickVisible {
                heroRow(heroPowerStats)
            } else if let dualClassStats = viewModel.dualClassHeroStats, viewModel.heroPickVisible {
                heroRow(dualClassStats)
            } else if let cardStats = viewModel.cardStats {
                HStack(spacing: 0) {
                    ForEach(Array(cardStats.enumerated()), id: \.offset) { _, option in
                        ArenaPickSingleCardOptionView(viewModel: option,
                                                      showScore: viewModel.arenasmithScoreVisible,
                                                      showRelatedCards: viewModel.relatedCardsVisible,
                                                      showSynergy: viewModel.synergiesVisible)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func heroRow(_ stats: [ArenaPickSingleHeroOptionViewModel]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.offset) { _, option in
                ArenaPickSingleHeroOptionView(viewModel: option)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: deck rail

    /// Overlays the game's own drafted-card list, scrolling in lockstep with it so
    /// each marker stays on its card.
    private var deckRail: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            if viewModel.isRedraft {
                VStack(spacing: 0) {
                    ForEach(viewModel.redraftTileViewModels) { tile in
                        ArenaDeckListTileView(viewModel: tile,
                                              showSynergy: viewModel.synergiesVisible,
                                              showDiscard: viewModel.redraftDiscardVisible)
                    }
                }
                .padding(.top, viewModel.redraftScrollOffset)
            }

            VStack(spacing: 0) {
                ForEach(viewModel.tileViewModels) { tile in
                    ArenaDeckListTileView(viewModel: tile,
                                          showSynergy: viewModel.synergiesVisible,
                                          showDiscard: viewModel.redraftDiscardVisible)
                }
            }
            .padding(.top, viewModel.scrollOffset)
        }
        .clipped()
    }
}

/// One row of the deck rail: a synergy marker, or a discard suggestion while
/// editing a redraft deck.
@available(macOS 10.15, *)
struct ArenaDeckListTileView: View {
    @ObservedObject var viewModel: ArenaDeckListTileViewModel
    let showSynergy: Bool
    let showDiscard: Bool

    /// HDT's deck rows are 30pt tall inside a 40.75pt scroll step.
    private static let rowHeight: CGFloat = 40.75

    var body: some View {
        HStack(spacing: 4) {
            Spacer()

            if showDiscard, viewModel.suggestRemove, let score = viewModel.arenasmithScore {
                discardBadge(score: score)
            }

            if showSynergy, viewModel.showSynergy {
                synergyMarker
            }
        }
        .padding(.trailing, 47)
        .frame(height: Self.rowHeight, alignment: .center)
    }

    private var synergyMarker: some View {
        // HDT ships three boost icons - one pointing left (this card enhances the
        // hovered pick), one right (the pick enhances this card), and a paired one
        // for both. Drawn rather than SF Symbols, which need macOS 11.
        HStack(spacing: -3) {
            if viewModel.synergy.contains(.provides) {
                ArenaChevronGlyph(pointsLeft: true)
                    .fill(Color(hex: "#205080"))
                    .overlay(ArenaChevronGlyph(pointsLeft: true).stroke(Color.white, lineWidth: 2))
                    .frame(width: 16, height: 16)
            }
            if viewModel.synergy.contains(.receives) {
                ArenaChevronGlyph(pointsLeft: false)
                    .fill(Color(hex: "#805020"))
                    .overlay(ArenaChevronGlyph(pointsLeft: false).stroke(Color.white, lineWidth: 2))
                    .frame(width: 16, height: 16)
            }
        }
        .padding(.horizontal, 5)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.75)))
    }

    private func discardBadge(score: Double) -> some View {
        Text(verbatim: "\(Int(score))")
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.75)))
    }
}

@available(macOS 10.15, *)
extension ArenaPickHelperViewModel {
    /// The overlay is only up while the player is on a draft screen with the
    /// feature enabled - HDT's `UpdateArenaPickHelperVisibility` plus the panel's
    /// own `ShowStats`.
    var isVisible: Bool {
        Settings.enableArenasmithOverlay && showStats
    }
}


/// HDT's `BoostGeo` - a chevron-tailed plaque, blue pointing left and orange
/// pointing right.
@available(macOS 10.15, *)
struct ArenaChevronGlyph: Shape {
    let pointsLeft: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let notch = rect.width * 0.32
        if pointsLeft {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + notch, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX + notch, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - notch, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX - notch, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}
