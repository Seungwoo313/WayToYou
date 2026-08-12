import SwiftUI

struct UsView: View {
    @Bindable var store: WayToYouStore
    let presentedAsSheet: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReset = false
    @State private var isProcessingAvatar = false
    @State private var avatarSelectionMessage: String?
    @State private var avatarToastID: UUID?
    @State private var isPickingDefaultAirport = false

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
                            profileSection(title: "나", profile: me)
                        }
                        if let partner = store.partnerProfile {
                            profileSection(title: "상대", profile: partner)
                        }

                        if let me = store.myProfile {
                            section("기본 배송 공항") {
                                airportRow(
                                    title: "나",
                                    airport: me.defaultAirport
                                )

                                if let partner = store.partnerProfile {
                                    Divider().overlay(Palette.hairline)
                                    airportRow(
                                        title: partner.displayName,
                                        airport: partner.defaultAirport
                                    )
                                }

                                Button {
                                    isPickingDefaultAirport = true
                                } label: {
                                    Label("내 기본 공항 변경", systemImage: "slider.horizontal.3")
                                        .font(.rounded(.subheadline, .semibold))
                                        .foregroundStyle(Palette.textPrimary)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 48)
                                }
                                .buttonStyle(.glass)
                                .disabled(store.connectionIsWorking)

                                if let message = store.connectionMessage {
                                    Label(message, systemImage: "exclamationmark.circle.fill")
                                        .font(.rounded(.caption, .medium))
                                        .foregroundStyle(Palette.you)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
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

                if let avatarToastID {
                    ProfileAvatarSuccessToast(message: "프로필 사진이 변경되었어요!")
                        .id(avatarToastID)
                        .padding(.horizontal, Metric.screenPadding)
                        .padding(.top, Metric.s)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .transition(
                            .move(edge: .top)
                                .combined(with: .opacity)
                                .combined(with: .scale(scale: 0.96, anchor: .top))
                        )
                        .zIndex(10)
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
            .sheet(isPresented: $isPickingDefaultAirport) {
                if let profile = store.myProfile {
                    RouteAirportPicker(city: profile.city) { airport in
                        Task {
                            await store.saveProfileToBackend(
                                displayName: profile.displayName,
                                city: profile.city,
                                defaultAirport: airport
                            )
                        }
                    }
                    .presentationDetents([.large])
                    .presentationBackground(Palette.space)
                }
            }
            .task(id: avatarToastID) {
                guard let toastID = avatarToastID else { return }

                do {
                    try await Task.sleep(for: .seconds(2.1))
                } catch {
                    return
                }

                guard avatarToastID == toastID else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    avatarToastID = nil
                }
            }
        }
        .presentationBackground(Palette.space)
    }

    private var routeSection: some View {
        VStack(spacing: Metric.l) {
            Text("OUR CITIES")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .tracking(2.4)
                .foregroundStyle(Palette.textTertiary)

            Text("\(store.homeCity.name) ↔ \(store.partnerCity.name)")
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)

            Text("\(store.homeCity.name)에서 \(store.partnerCity.name)까지")
                .font(.rounded(.subheadline))
                .foregroundStyle(Palette.textSecondary)

            if let me = store.myProfile,
               let partner = store.partnerProfile {
                Text(
                    "기본 배송  \(airportLabel(me.defaultAirport)) ↔ "
                        + airportLabel(partner.defaultAirport)
                )
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(Palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Metric.xxl)
        .padding(.horizontal, Metric.l)
        .glassPanel(radius: Metric.panelRadius)
        .accessibilityElement(children: .combine)
    }

    private func profileSection(title: String, profile: UserProfile) -> some View {
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
                                    showAvatarSuccessToast()
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
            showAvatarSuccessToast()
        }
    }

    private func showAvatarSuccessToast() {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
            avatarToastID = UUID()
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

    private func airportRow(title: String, airport: RouteAirport) -> some View {
        HStack(spacing: Metric.m) {
            Image(systemName: "airplane.departure")
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.rounded(.caption, .medium))
                    .foregroundStyle(Palette.textTertiary)
                Text(airport.name)
                    .font(.rounded(.subheadline, .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: Metric.s)
            if let code = airport.displayCode {
                Text(code)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private func airportLabel(_ airport: RouteAirport) -> String {
        airport.displayCode ?? airport.name
    }
}
