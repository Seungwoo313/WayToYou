import SwiftUI

/// 앱 전체가 공유하는 색. 두 사람에게 각자의 색을 주는 게 이 팔레트의 핵심이다.
/// 나는 차가운 쪽, 상대는 따뜻한 쪽. 비콘·소포·시그널·궤적이 전부 이 두 색으로 갈린다.
enum Palette {
    static let space = Color(red: 0.024, green: 0.028, blue: 0.055)
    static let spaceDeep = Color(red: 0.006, green: 0.008, blue: 0.020)

    static let me = Color(red: 0.51, green: 0.78, blue: 1.00)
    static let you = Color(red: 1.00, green: 0.55, blue: 0.46)

    /// 입력 필드나 목록 행처럼 별이 비치면 안 되는 표면.
    /// white.opacity(0.05)로 두면 뒤의 별밤이 그대로 뚫고 올라온다.
    static let surface = Color(red: 0.085, green: 0.094, blue: 0.125)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.66)
    static let textTertiary = Color.white.opacity(0.40)
    static let hairline = Color.white.opacity(0.14)

    static func tint(for direction: ParcelDirection) -> Color {
        direction == .outgoing ? me : you
    }
}

/// 여백 스케일. 화면마다 다른 숫자를 쓰던 걸 여기로 모았다.
enum Metric {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 28

    static let screenPadding: CGFloat = 20
    static let panelRadius: CGFloat = 28
    static let cardRadius: CGFloat = 20
}

extension Font {
    /// Dynamic Type를 따라가는 rounded 서체. `.system(size:)` 하드코딩을 대체한다.
    static func rounded(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded).weight(weight)
    }
}

// MARK: - Glass

extension View {
    /// 유리 패널. iOS 26 Liquid Glass 위에 아주 얇은 테두리만 얹는다.
    func glassPanel(radius: CGFloat = Metric.panelRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return glassEffect(.regular, in: shape)
            .overlay { shape.strokeBorder(Palette.hairline, lineWidth: 0.5) }
    }

    /// 값이 바뀔 때만 살짝 튀는 스프링. 앱 전체의 기본 모션.
    func softSpring<V: Equatable>(_ value: V) -> some View {
        animation(.spring(response: 0.42, dampingFraction: 0.82), value: value)
    }
}

/// 화면 전체를 덮는 우주 배경. 별 + 아주 옅은 성운.
/// 입력이 없으므로 Equatable로 못 박아서 1초 타이머에 딸려 다시 그려지지 않게 한다.
struct SpaceBackground: View, Equatable {
    static func == (lhs: SpaceBackground, rhs: SpaceBackground) -> Bool { true }

    private struct Star {
        let x: Double
        let y: Double
        let radius: Double
        let opacity: Double
    }

    /// 서로소인 소수 모듈러로 흩뿌린다.
    /// 황금비 수열을 쓰면 x와 y가 상관돼서 별이 전부 대각선 위에 줄을 서버린다.
    private static let stars: [Star] = (0..<96).map { index in
        let x = Double((index * 47 + 19) % 101) / 100
        let y = Double((index * 73 + 11) % 103) / 102
        let size = Double((index * 13) % 3 + 1)
        let opacity = 0.16 + Double((index * 17) % 45) / 100
        return Star(x: x, y: y, radius: size / 2, opacity: opacity)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Palette.spaceDeep, Palette.space, Palette.spaceDeep],
                startPoint: .top,
                endPoint: .bottom
            )

            // 상대 쪽 색이 화면 아래에서 아주 옅게 올라온다.
            RadialGradient(
                colors: [Palette.you.opacity(0.10), .clear],
                center: UnitPoint(x: 0.85, y: 1.05),
                startRadius: 0,
                endRadius: 420
            )
            RadialGradient(
                colors: [Palette.me.opacity(0.08), .clear],
                center: UnitPoint(x: 0.1, y: -0.05),
                startRadius: 0,
                endRadius: 380
            )

            Canvas { context, size in
                for star in Self.stars {
                    let rect = CGRect(
                        x: size.width * star.x,
                        y: size.height * star.y,
                        width: star.radius * 2,
                        height: star.radius * 2
                    )
                    context.opacity = star.opacity
                    context.fill(Path(ellipseIn: rect), with: .color(.white))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
