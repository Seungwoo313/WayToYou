import SwiftUI

/// 한 번의 탭으로 현재 상태만 보내는 화면.
struct SignalPickerSheet: View {
    let selectedSignal: CoupleSignal?
    let onSelect: (CoupleSignal) -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: Metric.xxl) {
                VStack(alignment: .leading, spacing: Metric.xs) {
                    Text("지금 상태")
                        .font(.rounded(.title2, .bold))
                        .foregroundStyle(Palette.textPrimary)
                    Text("하나를 탭하면 바로 상대에게 전달돼요")
                        .font(.rounded(.subheadline))
                        .foregroundStyle(Palette.textSecondary)
                }

                HStack(alignment: .top, spacing: Metric.xs) {
                    ForEach(CoupleSignal.allCases) { signal in
                        SignalButton(
                            signal: signal,
                            isSelected: signal == selectedSignal
                        ) {
                            onSelect(signal)
                        }
                    }
                }
            }
            .padding(Metric.screenPadding)
            .padding(.top, Metric.m)
        }
        .presentationBackground(Palette.space)
    }
}

private struct SignalButton: View {
    let signal: CoupleSignal
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Metric.s) {
                Text(signal.emoji)
                    .font(.system(size: 25))
                    .frame(width: 52, height: 52)
                    .background(isSelected ? Color.white : Color.white.opacity(0.08), in: Circle())
                    .overlay {
                        Circle().strokeBorder(Palette.hairline, lineWidth: isSelected ? 0 : 0.5)
                    }

                Text(signal.title)
                    .font(.rounded(.caption2, isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressableCard())
        .accessibilityLabel(signal.title)
        .accessibilityValue(isSelected ? "현재 내 Signal" : "")
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
