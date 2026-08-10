import SwiftUI

/// 한 번의 탭으로 지금의 마음만 보내는 화면. 말을 고르지 않아도 되는 게 요점이라
/// 설명은 최소로 두고 카드를 크게 잡았다.
struct SignalPickerSheet: View {
    let onSelect: (CoupleSignal) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: Metric.m),
        GridItem(.flexible(), spacing: Metric.m)
    ]

    var body: some View {
        ZStack {
            SpaceBackground().equatable()

            VStack(alignment: .leading, spacing: Metric.xl) {
                VStack(alignment: .leading, spacing: Metric.xs) {
                    Text("지금 마음은 어떤가요")
                        .font(.rounded(.title2, .bold))
                        .foregroundStyle(Palette.textPrimary)
                    Text("고르면 바로 상대에게 표시돼요")
                        .font(.rounded(.subheadline))
                        .foregroundStyle(Palette.textSecondary)
                }

                LazyVGrid(columns: columns, spacing: Metric.m) {
                    ForEach(CoupleSignal.allCases) { signal in
                        SignalCard(signal: signal) { onSelect(signal) }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(Metric.screenPadding)
            .padding(.top, Metric.m)
        }
        .presentationBackground(Palette.space)
    }
}

private struct SignalCard: View {
    let signal: CoupleSignal
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Metric.m) {
                Image(systemName: signal.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(signal.color)
                    .frame(width: 36, height: 36)
                    .background(signal.color.opacity(0.16), in: Circle())

                Text(signal.title)
                    .font(.rounded(.subheadline, .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Metric.m)
            .frame(height: 62)
            .frame(maxWidth: .infinity)
            .background(
                signal.color.opacity(0.10),
                in: RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
                    .strokeBorder(signal.color.opacity(0.28), lineWidth: 1)
            }
        }
        .buttonStyle(PressableCard())
    }
}

/// 누를 때 살짝 들어가는 반응. 커스텀 카드에는 시스템 버튼 하이라이트가 없어서 직접 준다.
struct PressableCard: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
