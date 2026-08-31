//
//  ArenaPlaqueView.swift
//  HSTracker
//
//  Copyright © 2026 Benjamin Michotte. All rights reserved.
//

import SwiftUI

/// Port of HDT's `ArenaPlaque.xaml`.
///
/// The plate is drawn as concentric rounded rectangles, exactly as the XAML layers
/// them: gradient ground, an outer highlight ring at level 5, an inner highlight
/// ring from level 3, a dark inner overlay, then the bolts and the score.
@available(macOS 10.15, *)
struct ArenaPlaqueView: View {
    @ObservedObject var viewModel: ArenaPlaqueViewModel

    private var size: CGSize { ArenaPlaqueViewModel.size }

    var body: some View {
        ZStack {
            // Recessed backing plate, visible around the badge itself.
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.black.opacity(0.25))

            plate
                .rotationEffect(.degrees(viewModel.angle), anchor: anchor)
        }
        .frame(width: size.width, height: size.height)
    }

    /// The level-1 plate hangs from its single bolt, so rotation is anchored there
    /// rather than at the centre.
    private var anchor: UnitPoint {
        UnitPoint(x: viewModel.rotateOrigin.x / size.width,
                  y: viewModel.rotateOrigin.y / size.height)
    }

    private var plate: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(viewModel.backgroundGradient)

            if viewModel.isLevel5 {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(viewModel.outerHighlightColor, lineWidth: 1)
            }

            if viewModel.isLevel3OrHigher {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(viewModel.innerHighlightColor, lineWidth: 1)
                    .padding(viewModel.isLevel5 ? 2 : 1)
            }

            RoundedRectangle(cornerRadius: 3)
                .fill(Color.black.opacity(0.66))
                .padding(viewModel.innerInset)

            if viewModel.isLevel4OrHigher {
                flames
            }

            RoundedRectangle(cornerRadius: viewModel.isLevel5 ? 3 : 4)
                .strokeBorder(Color.black.opacity(0.25), lineWidth: 1)
                .padding(viewModel.innerInset)

            bolts

            if viewModel.isLevel5, #available(macOS 12.0, *) {
                ArenaPlaqueParticlesView(gradients: viewModel.particleGradients)
                    .padding(-10)
                    .allowsHitTesting(false)
            }

            score
        }
        .shadow(color: .black.opacity(0.4), radius: 7, x: 1.5, y: 1.5)
    }

    private var score: some View {
        // Text(verbatim:) so a numeric score never picks up locale grouping, and
        // fixedSize so it is never truncated inside the plate.
        Text(verbatim: viewModel.score)
            .font(.system(size: 32, weight: .bold))
            .foregroundColor(.white)
            .fixedSize()
            .shadow(color: viewModel.isLevel5 ? viewModel.glowColor.opacity(0.8) : .clear, radius: 7)
    }

    private var flames: some View {
        // Soft licks of the plate's accent colour rising from the bottom edge, in
        // place of HDT's flame bitmaps. The gradient has to reach zero well inside
        // the ellipse: at full width three overlapping glows saturate the whole
        // plate and the clip below then reads as a hard-edged rectangle instead of
        // as flames.
        ZStack(alignment: .bottom) {
            Color.clear
            ForEach(Array(viewModel.innerFlames.enumerated()), id: \.offset) { index, flame in
                Ellipse()
                    .fill(
                        RadialGradient(gradient: Gradient(stops: [
                            .init(color: viewModel.glowColor.opacity(0.5), location: 0),
                            .init(color: viewModel.glowColor.opacity(0.18), location: 0.45),
                            .init(color: viewModel.glowColor.opacity(0), location: 1)
                        ]), center: .center, startRadius: 0, endRadius: 17)
                    )
                    .frame(width: 34, height: 30)
                    .scaleEffect(x: CGFloat(flame.scaleX), y: CGFloat(flame.scaleY))
                    .rotationEffect(.degrees(flame.angle))
                    .offset(x: CGFloat(index - 1) * 24, y: 9)
            }
        }
        .compositingGroup()
        .opacity(0.75)
        // XAML clips the flame canvas to Rect 2,2,86,54 with a 3pt radius.
        .clipShape(RoundedRectangle(cornerRadius: 3).inset(by: 2))
        .allowsHitTesting(false)
    }

    private var bolts: some View {
        ZStack {
            bolt(present: viewModel.hasTopLeftBolt, alignment: .topLeading)
            bolt(present: viewModel.hasTopRightBolt, alignment: .topTrailing)
            bolt(present: viewModel.hasBottomLeftBolt, alignment: .bottomLeading)
            bolt(present: viewModel.hasBottomRightBolt, alignment: .bottomTrailing)
        }
        .padding(viewModel.boltInset)
    }

    /// The hole is always drawn - an unfitted bolt leaves an empty socket, which is
    /// what makes the level-1 plate read as barely held on.
    private func bolt(present: Bool, alignment: Alignment) -> some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.07))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.13), lineWidth: 1))
                .padding(1)
            if present {
                Circle().fill(viewModel.boltGradient)
                Circle().strokeBorder(Color.white.opacity(0.53), lineWidth: 1)
            }
        }
        .frame(width: 8, height: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

/// Level-5 sparkle. Port of HDT's `ParticleEmitter.xaml.cs`, which spawns motes on
/// a timer and drifts them upward.
///
/// Canvas and TimelineView are macOS 12, so on 10.15/11 the plate simply renders
/// without its sparkle rather than the whole badge being unavailable.
@available(macOS 12.0, *)
struct ArenaPlaqueParticlesView: View {
    let gradients: [Gradient]

    private struct Particle {
        let seed: Double
        let gradient: Int
        let size: CGFloat
        let xOffset: CGFloat
        let duration: Double
        let delay: Double
    }

    // Fixed set rather than a live spawner: the plate is small and short-lived on
    // screen, and a deterministic set avoids per-frame allocation in the overlay.
    private let particles: [Particle] = {
        var rng = SeededGenerator(seed: 0x5A17)
        return (0..<14).map { index in
            Particle(seed: rng.nextDouble(),
                     gradient: index % 3,
                     size: 3 + CGFloat(rng.nextDouble()) * 4,
                     xOffset: CGFloat(rng.nextDouble()),
                     duration: 1.6 + rng.nextDouble() * 1.8,
                     delay: rng.nextDouble() * 2.4)
        }
    }()

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let now = timeline.date.timeIntervalSinceReferenceDate
                    for particle in particles {
                        let phase = ((now + particle.delay) / particle.duration)
                            .truncatingRemainder(dividingBy: 1)
                        let y = size.height * (1 - phase)
                        let x = size.width * particle.xOffset
                        // Fade in at the bottom, out at the top.
                        let alpha = sin(phase * .pi)
                        let rect = CGRect(x: x - particle.size / 2,
                                          y: y - particle.size / 2,
                                          width: particle.size,
                                          height: particle.size)
                        let gradient = gradients[particle.gradient % gradients.count]
                        context.opacity = alpha
                        context.fill(Path(ellipseIn: rect),
                                     with: .radialGradient(gradient,
                                                           center: CGPoint(x: rect.midX, y: rect.midY),
                                                           startRadius: 0,
                                                           endRadius: particle.size))
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }
}
