//
//  ArenaPickOptionViews.swift
//  HSTracker
//
//  Copyright © 2026 Benjamin Michotte. All rights reserved.
//

import SwiftUI

/// A badge pinned under one of the three offered cards.
///
/// HDT builds these from a `Border` with `BorderThickness="2,0,2,2"` and a
/// `CornerRadius="0,0,3,3"` - a tab that reads as hanging off the bottom edge of
/// the card - with the icon clipped inside it.
@available(macOS 10.15, *)
private struct ArenaOptionBadge<Content: View>: View {
    let foreground: Color
    let dimmed: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .foregroundColor(foreground)
            .frame(height: 26)
            .frame(minWidth: 28)
            .padding(.horizontal, 4)
            .background(
                UnevenRoundedCornersShape(bottomLeading: 3, bottomTrailing: 3)
                    .fill(Color.black)
            )
            .opacity(dimmed ? 0.2 : 1)
            .shadow(color: .black.opacity(0.2), radius: 2.5, x: 1, y: 1)
    }
}

/// Rounded on the bottom two corners only, as XAML's `CornerRadius="0,0,3,3"`.
@available(macOS 10.15, *)
struct UnevenRoundedCornersShape: Shape {
    var bottomLeading: CGFloat = 0
    var bottomTrailing: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomTrailing))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - bottomTrailing, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + bottomLeading, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - bottomLeading),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - card option

/// One of the three offered cards. The card art itself is Hearthstone's - all this
/// draws is the score plate and the badges that hang under it.
@available(macOS 10.15, *)
struct ArenaPickSingleCardOptionView: View {
    @ObservedObject var viewModel: ArenaPickSingleCardOptionViewModel
    let showScore: Bool
    let showRelatedCards: Bool
    let showSynergy: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear

            if showScore {
                ArenaPlaqueView(viewModel: viewModel.plaqueViewModel)
                    .padding(.top, 595)
            }

            badges
                // The multi-tribe banner on a card overhangs its frame slightly;
                // HDT nudges the badge row down to sit under it.
                .padding(.top, viewModel.isMultiTribe ? 561 : 565)

            if showSynergy && viewModel.showSynergy {
                synergyBubble
                    .padding(.top, 580)
                    .padding(.leading, 180)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var badges: some View {
        HStack(spacing: 4) {
            if showRelatedCards {
                ArenaOptionBadge(foreground: viewModel.badgeForegroundColor,
                                 dimmed: !viewModel.hasRelatedCards) {
                    ArenaCardGlyph()
                        .fill(viewModel.badgeForegroundColor)
                        .frame(width: 15, height: 21)
                }
            }
            if viewModel.showSynergy {
                ArenaOptionBadge(foreground: viewModel.badgeForegroundColor, dimmed: false) {
                    ArenaBoostGlyph()
                        .fill(viewModel.badgeForegroundColor)
                        .frame(width: 19, height: 20)
                }
            }
            if let caution = viewModel.cautionImageName, let image = NSImage(named: caution) {
                ArenaOptionBadge(foreground: .white, dimmed: false) {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 18, height: 18)
                }
            }
        }
    }

    /// The count of drafted cards this pick interacts with.
    private var synergyBubble: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .overlay(Circle().strokeBorder(Color.black, lineWidth: 2))
                .shadow(color: .black.opacity(0.4), radius: 7, x: 1.5, y: 1.5)
            Text(verbatim: "\(viewModel.synergyCount)")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.black)
                .fixedSize()
        }
        .frame(width: 25, height: 25)
    }
}

// MARK: - hero option

/// One offered hero, hero power, or dual-class hero: a tier plate over the card,
/// and win/pick rates under it.
@available(macOS 10.15, *)
struct ArenaPickSingleHeroOptionView: View {
    @ObservedObject var viewModel: ArenaPickSingleHeroOptionViewModel

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear

            ArenaPlaqueView(viewModel: viewModel.plaqueViewModel)
                .padding(.top, 230)

            if viewModel.hasStats {
                rates.padding(.top, 533)
            }
        }
    }

    private var rates: some View {
        HStack(spacing: 4) {
            ArenaOptionBadge(foreground: viewModel.badgeForegroundColor, dimmed: false) {
                rateLabel(String.localizedString("ArenaPick_SingleHero_WinRate", comment: ""),
                          value: viewModel.winrate)
            }
            ArenaOptionBadge(foreground: viewModel.badgeForegroundColor, dimmed: false) {
                rateLabel(String.localizedString("ArenaPick_SingleHero_PickRate", comment: ""),
                          value: viewModel.pickrate)
            }
        }
    }

    private func rateLabel(_ label: String, value: Double) -> some View {
        // verbatim + fixedSize so the percentage is never locale-formatted or
        // truncated inside the badge.
        HStack(spacing: 3) {
            Text(verbatim: label)
                .font(.system(size: 14))
            Text(verbatim: "\(Int(value.rounded()))%")
                .font(.system(size: 14, weight: .bold))
        }
        .fixedSize()
    }
}


// MARK: - glyphs

/// The "has related cards" mark: HDT draws a card outline (its `CardIcon`
/// DrawingImage). Drawn as a path rather than an SF Symbol so it renders on the
/// 10.14 deployment target, where `Image(systemName:)` is unavailable.
@available(macOS 10.15, *)
struct ArenaCardGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: rect.width * 0.16)
    }
}

/// The synergy mark: HDT's `BoostIcon`, a pair of stacked up-arrows.
@available(macOS 10.15, *)
struct ArenaBoostGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Two arrows, the trailing one raised, as in the original 40x42 geometry.
        for (index, offset) in [(0, CGPoint(x: 0, y: rect.height * 0.14)),
                                (1, CGPoint(x: rect.width * 0.45, y: 0))] {
            _ = index
            let w = rect.width * 0.55
            let h = rect.height * 0.86
            let originX = rect.minX + offset.x
            let originY = rect.minY + offset.y
            let headHeight = h * 0.42
            let shaftWidth = w * 0.34

            path.move(to: CGPoint(x: originX + w / 2, y: originY))
            path.addLine(to: CGPoint(x: originX + w, y: originY + headHeight))
            path.addLine(to: CGPoint(x: originX + w / 2 + shaftWidth / 2, y: originY + headHeight))
            path.addLine(to: CGPoint(x: originX + w / 2 + shaftWidth / 2, y: originY + h))
            path.addLine(to: CGPoint(x: originX + w / 2 - shaftWidth / 2, y: originY + h))
            path.addLine(to: CGPoint(x: originX + w / 2 - shaftWidth / 2, y: originY + headHeight))
            path.addLine(to: CGPoint(x: originX, y: originY + headHeight))
            path.closeSubpath()
        }
        return path
    }
}
