import SwiftUI
import UIKit

/// 소포를 여는 순간. 앱에서 유일하게 시간을 들여도 되는 화면이라
/// 리본을 푸는 동작을 남기고 편지지로 넘어가는 전환을 크게 잡았다.
struct ParcelLetterSheet: View {
    let parcel: Parcel
    let onOpen: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isOpen: Bool
    @State private var ribbonPull: CGFloat = 0

    init(parcel: Parcel, onOpen: @escaping () -> Void) {
        self.parcel = parcel
        self.onOpen = onOpen
        _isOpen = State(initialValue: parcel.openedAt != nil)
    }

    private var tint: Color { parcel.wrap.color }

    var body: some View {
        NavigationStack {
            ZStack {
                SpaceBackground().equatable()

                RadialGradient(
                    colors: [tint.opacity(isOpen ? 0.22 : 0.34), .clear],
                    center: .center,
                    startRadius: 20,
                    endRadius: 420
                )
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.8), value: isOpen)

                if isOpen {
                    letter
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.88).combined(with: .opacity),
                            removal: .opacity
                        ))
                } else {
                    wrapped
                        .transition(.scale(scale: 1.15).combined(with: .opacity))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .presentationBackground(Palette.space)
    }

    // MARK: - Closed

    private var wrapped: some View {
        VStack(spacing: Metric.xxl) {
            VStack(spacing: Metric.xs) {
                Text("\(parcel.fromCity.name)에서 온 소포")
                    .font(.rounded(.subheadline, .semibold))
                    .foregroundStyle(Palette.textSecondary)
                Text(travelCaption)
                    .font(.rounded(.title, .bold))
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
            }

            box
                .rotationEffect(.degrees(ribbonPull * -1.5))
                .offset(y: ribbonPull * 2)

            Button(action: open) {
                Label("리본을 풀어 열기", systemImage: "gift.fill")
                    .font(.rounded(.headline, .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .buttonStyle(.glassProminent)
            .tint(tint)
            .padding(.horizontal, Metric.xxl)
        }
        .padding(Metric.screenPadding)
    }

    private var box: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(tint.gradient)
                .frame(width: 262, height: 232)

            Rectangle().fill(.white.opacity(0.34)).frame(width: 38, height: 232)
            Rectangle().fill(.white.opacity(0.34)).frame(width: 262, height: 38)

            Image(systemName: "heart.fill")
                .font(.system(size: 30))
                .foregroundStyle(tint)
                .frame(width: 62, height: 62)
                .background(.white, in: Circle())
        }
        .shadow(color: tint.opacity(0.5), radius: 40, y: 22)
        .accessibilityLabel("포장된 소포")
    }

    /// 얼마나 걸려서 왔는지 알려주면 기다린 시간이 값이 된다.
    private var travelCaption: String {
        let travel = parcel.arrivesAt.timeIntervalSince(parcel.sentAt)
        return "\(travel.shortKoreanDuration)을 날아왔어요"
    }

    private func open() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.55)) { ribbonPull = 1 }
        withAnimation(.spring(response: 0.8, dampingFraction: 0.78).delay(0.18)) { isOpen = true }
        onOpen()
    }

    // MARK: - Open

    private var letter: some View {
        ScrollView {
            VStack(spacing: Metric.xl) {
                VStack(spacing: Metric.m) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(tint)

                    Text(parcel.title)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .multilineTextAlignment(.center)

                    Rectangle()
                        .fill(tint.opacity(0.45))
                        .frame(width: 40, height: 2)
                }

                Text(parcel.message)
                    .font(.system(.body, design: .serif))
                    .lineSpacing(9)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: Metric.xs) {
                    Text("— \(parcel.fromCity.name)에서")
                        .font(.rounded(.subheadline, .semibold))
                        .foregroundStyle(.black.opacity(0.55))
                    Text(sentStamp)
                        .font(.rounded(.caption2))
                        .foregroundStyle(.black.opacity(0.35))
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                if parcel.isSimulated {
                    demoNote
                }
            }
            .foregroundStyle(.black)
            .padding(Metric.xxl)
            .background(
                Color(red: 0.98, green: 0.96, blue: 0.91),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
            .shadow(color: .black.opacity(0.35), radius: 26, y: 14)
            .padding(Metric.screenPadding)
        }
    }

    private var sentStamp: String {
        parcel.sentAt.dayStamp(in: parcel.fromCity.timeZone)
    }

    /// 서버가 붙기 전까지 상대 쪽은 앱이 만들어낸 글이다. 그 사실을 숨기지 않는다.
    private var demoNote: some View {
        HStack(spacing: Metric.s) {
            Image(systemName: "sparkles")
                .font(.caption2.weight(.bold))
            Text("데모 모드가 만든 답장이에요")
                .font(.rounded(.caption2, .medium))
        }
        .foregroundStyle(.black.opacity(0.42))
        .padding(.horizontal, Metric.m)
        .padding(.vertical, 7)
        .background(.black.opacity(0.05), in: Capsule())
        .frame(maxWidth: .infinity)
    }
}
