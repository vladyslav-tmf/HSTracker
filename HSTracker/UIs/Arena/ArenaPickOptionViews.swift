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
    /// HDT's `BadgeBorderColor` - teal normally, red in Underground, and white on
    /// the caution badge while improvements are highlighted.
    let border: Color
    let isUnderground: Bool
    let dimmed: Bool
    @ViewBuilder let content: () -> Content

    private var shape: UnevenRoundedCornersShape {
        UnevenRoundedCornersShape(bottomLeading: 3, bottomTrailing: 3)
    }

    var body: some View {
        content()
            .foregroundColor(foreground)
            .frame(height: 26)
            .frame(minWidth: 28)
            .padding(.horizontal, 4)
            .background(background)
            .opacity(dimmed ? 0.2 : 1)
            .shadow(color: .black.opacity(0.2), radius: 2.5, x: 1, y: 1)
    }

    /// Five layers, as the XAML stacks them: a black base, the arena_cell_bg
    /// texture masked to it, a translucent black inner edge, the coloured border
    /// over a barely-there dark wash, and a shade falling from the top edge.
    /// The borders are open on top - XAML's `BorderThickness="2,0,2,2"` - so they
    /// read as the badge hanging off the plate above it.
    private var background: some View {
        ZStack {
            // Only this subtree is clipped: the strokes below sit on the boundary
            // and would lose their outer half to a clip applied over everything.
            shape.fill(Color.black)
                .overlay(texture)
                .clipShape(shape)
            ArenaBadgeSideBorder()
                .stroke(Color.black.opacity(0.267), lineWidth: 3)
                .padding(1.5)
            shape.fill(Color.black.opacity(0.063))
            ArenaBadgeSideBorder()
                .stroke(border, lineWidth: 2)
                .padding(1)
            shape.fill(LinearGradient(gradient: Gradient(stops: [
                .init(color: Color.black.opacity(0.533), location: 0),
                .init(color: Color.black.opacity(0), location: 0.3)
            ]), startPoint: .top, endPoint: .bottom))
        }
    }

    /// Drawn at its native 156x52 and centred, overflowing a narrow badge exactly
    /// as HDT's IgnoreSizeDecorator does, then masked by the caller's clip.
    @ViewBuilder
    private var texture: some View {
        if let image = NSImage(named: isUnderground ? "arena-cell-bg-underground" : "arena-cell-bg") {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 156, height: 52)
        }
    }
}

/// The left, bottom and right edges only, with the bottom corners rounded - an
/// open path, so stroking it leaves the top edge bare like `BorderThickness`
/// with a zero top.
@available(macOS 10.15, *)
struct ArenaBadgeSideBorder: Shape {
    var radius: CGFloat = 3

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.maxY),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - radius),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
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
                                 border: viewModel.badgeBorderColor,
                                 isUnderground: viewModel.isUnderground,
                                 dimmed: !viewModel.hasRelatedCards) {
                    ArenaCardGlyph()
                        .fill(viewModel.badgeForegroundColor)
                        .frame(width: ArenaCardGlyph.width, height: ArenaCardGlyph.height)
                        .shadow(color: .black.opacity(0.4), radius: 4)
                }
            }
            if viewModel.showSynergy {
                ArenaOptionBadge(foreground: viewModel.badgeForegroundColor,
                                 border: viewModel.badgeBorderColor,
                                 isUnderground: viewModel.isUnderground,
                                 dimmed: false) {
                    ArenaBoostGlyph()
                        .fill(viewModel.badgeForegroundColor)
                        .frame(width: ArenaBoostGlyph.width, height: ArenaBoostGlyph.height)
                        .shadow(color: .black.opacity(0.4), radius: 4)
                }
            }
            if let caution = viewModel.cautionImageName, let image = NSImage(named: caution) {
                // HDT switches this one's border to white while improvements
                // are highlighted.
                ArenaOptionBadge(foreground: .white,
                                 border: viewModel.highlightImprovements ? .white : viewModel.badgeBorderColor,
                                 isUnderground: viewModel.isUnderground,
                                 dimmed: false) {
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
                .padding(.top, viewModel.plaqueTop)

            if viewModel.hasStats {
                rates.padding(.top, viewModel.statsTop)
            }
        }
        .padding(.leading, viewModel.leadingInset)
        .padding(.trailing, viewModel.trailingInset)
    }

    private var rates: some View {
        HStack(spacing: 4) {
            ArenaOptionBadge(foreground: viewModel.badgeForegroundColor,
                             border: viewModel.badgeBorderColor,
                             isUnderground: viewModel.isUnderground,
                             dimmed: false) {
                rateLabel(String.localizedString("ArenaPick_SingleHero_WinRate", comment: ""),
                          value: viewModel.winrate)
            }
            ArenaOptionBadge(foreground: viewModel.badgeForegroundColor,
                             border: viewModel.badgeBorderColor,
                             isUnderground: viewModel.isUnderground,
                             dimmed: false) {
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
