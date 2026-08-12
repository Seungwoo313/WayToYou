import SwiftUI
import UIKit

/// 연결 전의 단일 진입점. 프로필 작성과 초대 대기를 끝내야 기존 홈이 열린다.
struct ConnectionOnboardingView: View {
    @Bindable var store: WayToYouStore

    @State private var draftName: String
    @State private var draftCityID: String
    @State private var isPickingCity = false
    @State private var isEditingProfile = false
    @State private var isEnteringCode = false

    init(store: WayToYouStore, suggestedName: String? = nil) {
        self.store = store
        _draftName = State(initialValue: store.myProfile?.displayName ?? suggestedName ?? "")
        _draftCityID = State(initialValue: store.myProfile?.cityID ?? store.homeCityID)
    }

    private var draftCity: CoupleCity { CoupleCity.city(id: draftCityID) }
    private var canSaveProfile: Bool {
        !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.spaceDeep.ignoresSafeArea()

                ScrollView {
                    Group {
                        if store.myProfile == nil || isEditingProfile {
                            profileSetup
                        } else {
                            connectionStep
                        }
                    }
                    .frame(maxWidth: 560)
                    .padding(.horizontal, Metric.screenPadding)
                    .padding(.top, 36)
                    .padding(.bottom, Metric.xxl)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $isPickingCity) {
                CityPickerList(
                    title: "나의 도시",
                    selection: $draftCityID,
                    excluding: ""
                )
                .presentationDetents([.large])
                .presentationBackground(Palette.space)
            }
            .sheet(isPresented: $isEnteringCode) {
                InviteCodeEntrySheet(store: store)
                    .presentationDetents([.height(450)])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Palette.space)
            }
            .task { await pollForConnection() }
        }
    }

    private var profileSetup: some View {
        VStack(alignment: .leading, spacing: Metric.xxl) {
            header(
                step: "1 / 2",
                title: "먼저, 나를 알려주세요",
                detail: "상대에게 보일 이름과 도시를 설정해요. 정확한 위치는 공유하지 않아요."
            )

            VStack(alignment: .leading, spacing: Metric.l) {
                VStack(alignment: .leading, spacing: Metric.s) {
                    Text("이름")
                        .font(.rounded(.caption, .semibold))
                        .foregroundStyle(Palette.textTertiary)

                    TextField("상대에게 보일 이름", text: $draftName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .font(.rounded(.body, .medium))
                        .padding(.horizontal, Metric.l)
                        .frame(height: 54)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                VStack(alignment: .leading, spacing: Metric.s) {
                    Text("도시")
                        .font(.rounded(.caption, .semibold))
                        .foregroundStyle(Palette.textTertiary)

                    Button { isPickingCity = true } label: {
                        HStack(spacing: Metric.m) {
                            Circle()
                                .fill(Palette.me)
                                .frame(width: 8, height: 8)
                                .shadow(color: Palette.me.opacity(0.8), radius: 5)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(draftCity.name)
                                    .font(.rounded(.body, .semibold))
                                    .foregroundStyle(Palette.textPrimary)
                                Text(draftCity.country)
                                    .font(.rounded(.caption))
                                    .foregroundStyle(Palette.textTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.textTertiary)
                        }
                        .padding(.horizontal, Metric.l)
                        .frame(height: 64)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PressableCard())
                }
            }
            .padding(Metric.l)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 0.5)
            }

            Button {
                Task {
                    let saved = await store.saveProfileToBackend(
                        displayName: draftName,
                        cityID: draftCityID
                    )
                    if saved {
                        isEditingProfile = false
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    }
                }
            } label: {
                actionLabel("계속하기", systemImage: "arrow.right")
            }
            .buttonStyle(.glassProminent)
            .tint(.white)
            .disabled(!canSaveProfile || store.connectionIsWorking)

            connectionError
        }
    }

    @ViewBuilder
    private var connectionStep: some View {
        switch store.connectionStatus {
        case .notConnected:
            connectionChoice
        case .inviting(let invitation):
            invitationWaiting(invitation)
        case .connected:
            ProgressView()
                .tint(Palette.me)
        }
    }

    private var connectionChoice: some View {
        VStack(alignment: .leading, spacing: Metric.xxl) {
            header(
                step: "2 / 2",
                title: "상대와 연결하기",
                detail: "초대 코드를 보내거나, 상대에게 받은 코드를 입력하세요."
            )

            if let profile = store.myProfile {
                profileCard(profile)
            }

            VStack(spacing: Metric.m) {
                Button {
                    Task {
                        await store.createInvitation()
                        if case .inviting = store.connectionStatus {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                    }
                } label: {
                    actionLabel("초대 코드 만들기", systemImage: "link.badge.plus")
                }
                .buttonStyle(.glassProminent)
                .tint(.white)
                .disabled(store.connectionIsWorking)

                Button { isEnteringCode = true } label: {
                    Label("받은 코드 입력하기", systemImage: "number")
                        .font(.rounded(.body, .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }
                .buttonStyle(.glass)
                .disabled(store.connectionIsWorking)
            }

            connectionError

            Button {
                draftName = store.myProfile?.displayName ?? ""
                draftCityID = store.myProfile?.cityID ?? store.homeCityID
                isEditingProfile = true
            } label: {
                Text("내 정보 수정")
                    .font(.rounded(.footnote, .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }

    private func invitationWaiting(_ invitation: ConnectionInvite) -> some View {
        VStack(alignment: .leading, spacing: Metric.xxl) {
            header(
                step: "초대 대기",
                title: "이 코드를 상대에게 보내세요",
                detail: "상대가 코드를 입력하면 두 도시가 연결돼요."
            )

            VStack(spacing: Metric.l) {
                Text("초대 코드")
                    .font(.rounded(.caption, .semibold))
                    .foregroundStyle(Palette.textTertiary)

                Text(invitation.code.chunkedInviteCode)
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .monospaced()
                    .tracking(5)
                    .foregroundStyle(Palette.textPrimary)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                    .accessibilityLabel("초대 코드 \(invitation.code)")

                Label("24시간 동안 유효해요", systemImage: "clock")
                    .font(.rounded(.caption))
                    .foregroundStyle(Palette.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Metric.xxl)
            .padding(.horizontal, Metric.l)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 0.5)
            }

            ShareLink(
                item: "Way to You에서 초대 코드 \(invitation.code)를 입력해 나와 연결해 주세요.",
                subject: Text("Way to You 초대")
            ) {
                Label("초대 코드 공유하기", systemImage: "square.and.arrow.up")
                    .font(.rounded(.body, .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }
            .buttonStyle(.glassProminent)
            .tint(.white)

            connectionError

            Button("초대 취소") {
                Task { await store.cancelInvitation() }
            }
                .font(.rounded(.footnote, .medium))
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity)
                .disabled(store.connectionIsWorking)
        }
    }

    @ViewBuilder
    private func actionLabel(_ title: String, systemImage: String) -> some View {
        if store.connectionIsWorking {
            ProgressView()
                .tint(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
        } else {
            Label(title, systemImage: systemImage)
                .font(.rounded(.body, .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
        }
    }

    @ViewBuilder
    private var connectionError: some View {
        if let message = store.connectionMessage {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.rounded(.caption, .medium))
                .foregroundStyle(Palette.you)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pollForConnection() async {
        while !Task.isCancelled, !store.isConnected {
            if case .inviting = store.connectionStatus {
                await store.refreshConnection()
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func header(step: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: Metric.m) {
            Text(step)
                .font(.rounded(.caption, .semibold))
                .foregroundStyle(Palette.textTertiary)

            Text(title)
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(detail)
                .font(.rounded(.body))
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func profileCard(_ profile: UserProfile) -> some View {
        HStack(spacing: Metric.l) {
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.displayName)
                    .font(.rounded(.headline, .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text("\(profile.city.name), \(profile.city.country)")
                    .font(.rounded(.subheadline))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Palette.me)
        }
        .padding(Metric.l)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.5)
        }
    }
}

private struct InviteCodeEntrySheet: View {
    @Bindable var store: WayToYouStore

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.spaceDeep.ignoresSafeArea()

                VStack(spacing: Metric.xl) {
                    Image(systemName: "number")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Palette.me)

                    VStack(spacing: Metric.s) {
                        Text("받은 초대 코드")
                            .font(.rounded(.title2, .bold))
                            .foregroundStyle(Palette.textPrimary)
                        Text("상대가 보낸 8자리 코드를 입력하세요.")
                            .font(.rounded(.subheadline))
                            .foregroundStyle(Palette.textSecondary)
                    }

                    TextField("ABCD1234", text: $code)
                        .keyboardType(.asciiCapable)
                        .textContentType(.oneTimeCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.center)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospaced()
                        .tracking(6)
                        .padding(.horizontal, Metric.l)
                        .frame(height: 62)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .onChange(of: code) { _, newValue in
                            let allowed = newValue.uppercased().filter { $0.isASCII && $0.isLetter || $0.isNumber }
                            code = String(allowed.prefix(8))
                        }

                    Button {
                        Task {
                            if await store.acceptInvitation(code: code) {
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                dismiss()
                            } else {
                                UINotificationFeedbackGenerator().notificationOccurred(.error)
                            }
                        }
                    } label: {
                        Group {
                            if store.connectionIsWorking {
                                ProgressView().tint(.black)
                            } else {
                                Text("연결하기")
                                    .font(.rounded(.body, .semibold))
                                    .foregroundStyle(.black)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.white)
                    .disabled(code.count != 8 || store.connectionIsWorking)

                    if let message = store.connectionMessage {
                        Label(message, systemImage: "exclamationmark.circle.fill")
                            .font(.rounded(.caption, .medium))
                            .foregroundStyle(Palette.you)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(Metric.screenPadding)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

private extension String {
    var chunkedInviteCode: String {
        guard count == 8 else { return self }
        return "\(prefix(4)) \(suffix(4))"
    }
}

private enum OnboardingPreviewStage {
    case profile
    case connection
    case invitation
}

private struct OnboardingPreviewConnectionService: ConnectionServicing {
    func makeInvite(for profile: UserProfile, at date: Date) -> ConnectionInvite {
        ConnectionInvite(
            code: "428617",
            createdByID: profile.id,
            createdAt: date,
            expiresAt: date.addingTimeInterval(24 * 60 * 60)
        )
    }
}

@MainActor
private func onboardingPreviewStore(_ stage: OnboardingPreviewStage) -> WayToYouStore {
    let defaults = UserDefaults(suiteName: "wty.onboarding.preview.\(UUID().uuidString)")!
    let store = WayToYouStore(
        defaults: defaults,
        connectionService: OnboardingPreviewConnectionService()
    )

    guard stage != .profile else { return store }
    store.saveProfile(displayName: "승우", cityID: "seoul")

    if stage == .invitation {
        store.createPreviewInvitation()
    }
    return store
}

#Preview("1 · 내 정보") {
    ConnectionOnboardingView(store: onboardingPreviewStore(.profile))
        .preferredColorScheme(.dark)
}

#Preview("2 · 연결 방법") {
    ConnectionOnboardingView(store: onboardingPreviewStore(.connection))
        .preferredColorScheme(.dark)
}

#Preview("3 · 초대 대기") {
    ConnectionOnboardingView(store: onboardingPreviewStore(.invitation))
        .preferredColorScheme(.dark)
}
