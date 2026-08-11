import SwiftUI
import UIKit

struct UsView: View {
    @Bindable var store: WayToYouStore
    let presentedAsSheet: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReset = false
    @State private var isProcessingAvatar = false
    @State private var avatarSelectionMessage: String?

    init(store: WayToYouStore, presentedAsSheet: Bool = true) {
        self.store = store
        self.presentedAsSheet = presentedAsSheet
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.spaceDeep.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Metric.xl) {
                        routeSection

                        if let me = store.myProfile {
                            endpointSection(title: "나", profile: me)
                        }
                        if let partner = store.partnerProfile {
                            endpointSection(title: "상대", profile: partner)
                        }

                        section("두 사람 사이") {
                            infoRow("거리", "\(store.distanceKilometers.grouped)km")
                            infoRow("시차", store.timeDifferenceCaption(at: .now))
                            infoRow(
                                "기본 배송 시간",
                                CoupleDistance.deliveryDuration(
                                    from: store.homeCity,
                                    to: store.partnerCity
                                ).shortKoreanDuration
                            )
                        }

                        section("개발 설정") {
                            Toggle(isOn: $store.demoMode) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("배송 시간 압축")
                                        .font(.rounded(.subheadline, .semibold))
                                        .foregroundStyle(Palette.textPrimary)
                                    Text("실제 통신 기능이 완성될 때까지 배송 흐름을 빠르게 확인해요.")
                                        .font(.rounded(.caption))
                                        .foregroundStyle(Palette.textSecondary)
                                }
                            }
                            .tint(Palette.me)
                        }

                        section("로컬 데이터") {
                            Button(role: .destructive) {
                                confirmingReset = true
                            } label: {
                                Label("이 기기의 기록 지우기", systemImage: "trash")
                                    .font(.rounded(.subheadline, .medium))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Palette.you)
                        }
                    }
                    .padding(Metric.screenPadding)
                }
            }
            .navigationTitle("우리")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if presentedAsSheet {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("완료") { dismiss() }
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .confirmationDialog("이 기기의 기록을 지울까요?", isPresented: $confirmingReset) {
                Button("기록 지우기", role: .destructive) { store.clearHistory() }
                Button("취소", role: .cancel) {}
            } message: {
                Text("현재 기기에 저장된 데모 소포와 시그널이 삭제돼요.")
            }
        }
        .presentationBackground(Palette.space)
    }

    private var routeSection: some View {
        VStack(spacing: Metric.l) {
            Text("YOUR ROUTE")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .tracking(2.4)
                .foregroundStyle(Palette.textTertiary)

            Text(store.coupleRoute?.label ?? "Route를 준비하고 있어요")
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)

            if let route = store.coupleRoute {
                Text("\(route.mine.city.name)에서 \(route.partner.city.name)까지")
                    .font(.rounded(.subheadline))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Metric.xxl)
        .padding(.horizontal, Metric.l)
        .glassPanel(radius: Metric.panelRadius)
        .accessibilityElement(children: .combine)
    }

    private func endpointSection(title: String, profile: UserProfile) -> some View {
        let isMine = profile.id == store.myProfile?.id
        return section(title) {
            HStack(alignment: .top, spacing: Metric.m) {
                if isMine {
                    ProfileAvatarPicker(
                        data: store.avatarData(for: profile),
                        hasAvatar: profile.avatarPath != nil,
                        displayName: profile.displayName,
                        isWorking: isProcessingAvatar || store.avatarIsWorking,
                        size: 58,
                        onImageReady: { data in
                            Task { await uploadAvatar(data) }
                        },
                        onUseDefault: {
                            avatarSelectionMessage = nil
                            Task {
                                if await store.clearProfileAvatar() {
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                }
                            }
                        },
                        onError: { avatarSelectionMessage = $0 }
                    )
                } else {
                    ProfileAvatarImage(
                        data: store.avatarData(for: profile),
                        displayName: profile.displayName,
                        size: 58
                    )
                }

                VStack(alignment: .leading, spacing: Metric.s) {
                    Text(profile.displayName)
                        .font(.rounded(.headline, .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Label(
                        "\(profile.city.name), \(profile.city.country)",
                        systemImage: "building.2"
                    )
                    Label(profile.airport.name, systemImage: "airplane")
                }
                .font(.rounded(.subheadline))
                .foregroundStyle(Palette.textSecondary)

                Spacer(minLength: 0)
            }

            if isMine {
                Text("사진을 누르면 촬영, 앨범 선택, 기본 이미지 변경을 할 수 있어요")
                    .font(.rounded(.caption))
                    .foregroundStyle(Palette.textTertiary)

                if let message = avatarSelectionMessage ?? store.avatarMessage {
                    Label(message, systemImage: "exclamationmark.circle.fill")
                        .font(.rounded(.caption, .medium))
                        .foregroundStyle(Palette.you)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func uploadAvatar(_ data: Data) async {
        isProcessingAvatar = true
        avatarSelectionMessage = nil
        store.clearAvatarMessage()
        defer { isProcessingAvatar = false }

        if await store.uploadProfileAvatar(data) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Metric.m) {
            Text(title)
                .font(.rounded(.footnote, .semibold))
                .foregroundStyle(Palette.textTertiary)
                .padding(.leading, Metric.xs)

            VStack(alignment: .leading, spacing: Metric.m) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Metric.l)
            .glassPanel(radius: Metric.cardRadius)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.rounded(.subheadline))
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            Text(value)
                .font(.rounded(.subheadline, .semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
        }
    }
}
