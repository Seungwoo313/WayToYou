import SwiftUI

struct HeartParticle: Identifiable, Equatable {
    let id = UUID()
    let originX: CGFloat
    let horizontalOffset: CGFloat
    let drift: CGFloat
    let rise: CGFloat
    let size: CGFloat
    let rotation: Double

    static func make(sequence: Int, incoming: Bool) -> HeartParticle {
        let offsets: [CGFloat] = [-28, 18, -8, 34, 4, -36, 24]
        let drifts: [CGFloat] = [18, -14, 9, -20, 14, -8, 22]
        let sizes: [CGFloat] = [20, 25, 18, 23, 28, 21, 24]
        let index = sequence % offsets.count

        return HeartParticle(
            originX: incoming ? 0.58 : 0.42,
            horizontalOffset: offsets[index],
            drift: drifts[index],
            rise: 210 + CGFloat((sequence * 17) % 90),
            size: sizes[index],
            rotation: Double((sequence * 19) % 30) - 15
        )
    }
}

struct HeartBurstOverlay: View {
    let particles: [HeartParticle]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particles) { particle in
                    FloatingHeart(particle: particle)
                        .position(
                            x: geometry.size.width * particle.originX + particle.horizontalOffset,
                            y: geometry.size.height - 86
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct FloatingHeart: View {
    let particle: HeartParticle

    @State private var isFlying = false

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: particle.size, weight: .semibold))
            .foregroundStyle(Color.pink)
            .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
            .scaleEffect(isFlying ? 1.18 : 0.72)
            .rotationEffect(.degrees(isFlying ? particle.rotation : 0))
            .offset(
                x: isFlying ? particle.drift : 0,
                y: isFlying ? -particle.rise : 0
            )
            .opacity(isFlying ? 0 : 0.96)
            .onAppear {
                withAnimation(.easeOut(duration: 1.45)) {
                    isFlying = true
                }
            }
    }
}
