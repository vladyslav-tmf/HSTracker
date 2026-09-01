//
//  ArenaCardImageGridView.swift
//  HSTracker
//
//  Copyright © 2026 Benjamin Michotte. All rights reserved.
//

import SwiftUI

/// A wrapped grid of full card images, scaled so the whole set fits the space it
/// is given. Port of HDT's `CardImageGrid`.
@available(macOS 10.15, *)
struct ArenaCardImageGridView: View {
    let cards: [Card]
    let columns: Int
    let maxWidth: CGFloat
    var maxCardHeight: CGFloat = 295

    // HDT's card art is 256x388 with a negative margin that overlaps neighbours,
    // trimming the transparent border the rendered images carry.
    private static let cardWidth: CGFloat = 256
    private static let cardHeight: CGFloat = 388
    private static let marginX: CGFloat = -2
    private static let marginY: CGFloat = -14

    private var spacedWidth: CGFloat { Self.cardWidth + Self.marginX * 2 }
    private var spacedHeight: CGFloat { Self.cardHeight + Self.marginY * 2 }

    /// Port of `CardImageGrid.Update`. HDT scales the whole wrap panel with a
    /// LayoutTransform rather than resizing each image, so the scale is solved
    /// once for the set.
    private var scale: CGFloat {
        let count = cards.count
        guard count > 0 else { return 1 }

        // 10pt of container margin, as HDT subtracts.
        let gridWidth = max(1, maxWidth - 10)
        let maxScale = min(1, maxCardHeight / Self.cardHeight)

        if count <= 3 {
            // HDT lays out up to three cards on one row regardless of `columns`.
            return min(maxScale, gridWidth / (spacedWidth * 3))
        }

        let cols = CGFloat(min(columns, count))
        guard cols > 0 else { return maxScale }
        return min(maxScale, gridWidth / (spacedWidth * cols))
    }

    /// How many fit per row once scaled - the wrap the grid actually performs.
    private var perRow: Int {
        max(1, min(columns, cards.count))
    }

    private var rows: [[Card]] {
        stride(from: 0, to: cards.count, by: perRow).map {
            Array(cards[$0..<min($0 + perRow, cards.count)])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, card in
                        ArenaCardImageView(cardId: card.id)
                            .frame(width: Self.cardWidth, height: Self.cardHeight)
                            .padding(.horizontal, Self.marginX)
                            .padding(.vertical, Self.marginY)
                    }
                }
            }
        }
        // Scale the laid-out grid rather than each image, matching HDT's
        // LayoutTransform on the wrap panel.
        .scaleEffect(scale)
        .frame(width: CGFloat(perRow) * spacedWidth * scale,
               height: CGFloat(rows.count) * spacedHeight * scale)
    }
}

/// One full card image, loaded through the same cache the rest of the overlay uses.
@available(macOS 10.15, *)
struct ArenaCardImageView: View {
    let cardId: String

    @SwiftUI.State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .shadow(color: .black.opacity(0.6), radius: 7, x: 4, y: 4)
            } else {
                // Placeholder keeps the slot's size while the art loads, so the
                // grid doesn't reflow when images arrive one at a time.
                Color.clear
            }
        }
        // Keyed on the card id: .onAppear fires once per view identity, and these
        // views are recycled across hovers, so without this a second card would
        // keep the first one's art.
        .id(cardId)
        .onAppear(perform: load)
    }

    // The rendered card, not the square art crop: HDT binds the card's `Asset`,
    // which is the full frame with name, cost and text. `ImageUtils.art` is the
    // bare 256x256 artwork and reads as the wrong image entirely at this size.
    private func load() {
        if let cached = ImageUtils.cachedCardArt(cardId: cardId) {
            image = cached
            return
        }
        ImageUtils.cardArt(for: cardId) { img in
            DispatchQueue.main.async {
                self.image = img
            }
        }
    }
}
