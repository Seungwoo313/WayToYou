import SwiftUI

/// 도시·데모 설정. 예전에는 애플 기본 Form이라 메인 화면과 완전히 다른 앱처럼 보였다.
struct UsView: View {
    @Bindable var store: WayToYouStore
    let presentedAsSheet: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var draftHome: String
    @State private var draftPartner: String
    @State private var picking: Slot?
    @State private var confirmingReset = false

    enum Slot: String, Identifiable {
        case home, partner
        var id: String { rawValue }
    }

    init(store: WayToYouStore, presentedAsSheet: Bool = true) {
        self.store = store
        self.presentedAsSheet = presentedAsSheet
        _draftHome = State(initialValue: store.homeCityID)
        _draftPartner = State(initialValue: store.partnerCityID)
    }

    private var home: CoupleCity { CoupleCity.city(id: draftHome) }
    private var partner: CoupleCity { CoupleCity.city(id: draftPartner) }
    private var isValid: Bool { draftHome != draftPartner }

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.spaceDeep.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Metric.xl) {
                        section("우리의 위치") {
                            citySlot(role: "나", city: home, tint: Palette.me) { picking = .home }
                            citySlot(role: "상대", city: partner, tint: Palette.you) { picking = .partner }

                            if !isValid {
                                Label("서로 다른 도시를 골라주세요", systemImage: "exclamationmark.circle.fill")
                                    .font(.rounded(.caption, .medium))
                                    .foregroundStyle(Palette.you)
                            }
                        }

                        section("두 사람 사이") {
                            infoRow(
                                "거리",
                                "\(Int(CoupleDistance.distanceInKilometers(from: home, to: partner).rounded()).grouped)km"
                            )
                            infoRow("시차", store.timeDifferenceCaption(at: .now))
                            infoRow(
                                "실제 배송 시간",
                                CoupleDistance.deliveryDuration(from: home, to: partner).shortKoreanDuration
                            )
                        }

                        section("데모 모드") {
                            Toggle(isOn: $store.demoMode) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("시간을 압축하고 상대를 흉내 내기")
                                        .font(.rounded(.subheadline, .semibold))
                                        .foregroundStyle(Palette.textPrimary)
                                    Text("배송이 100초로 줄고, 상대가 소포를 열고 답장을 보내는 반응이 자동으로 생겨요.")
                                        .font(.rounded(.caption))
                                        .foregroundStyle(Palette.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .tint(Palette.me)

                            Text("아직 서버가 없어서 상대 쪽은 앱이 만들어냅니다. 데모 모드를 꺼도 반응은 오지만, 실제 거리만큼 느려집니다.")
                                .font(.rounded(.caption2))
                                .foregroundStyle(Palette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        section("기록") {
                            Button(role: .destructive) {
                                confirmingReset = true
                            } label: {
                                Label("주고받은 기록 모두 지우기", systemImage: "trash")
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
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소") { dismiss() }
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(presentedAsSheet ? "완료" : "저장") {
                        store.updateCities(home: draftHome, partner: draftPartner)
                        if presentedAsSheet {
                            dismiss()
                        }
                    }
                    .font(.rounded(.body, .semibold))
                    .disabled(!isValid)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(item: $picking) { slot in
                CityPickerList(
                    title: slot == .home ? "나의 도시" : "상대의 도시",
                    selection: slot == .home ? $draftHome : $draftPartner,
                    excluding: slot == .home ? draftPartner : draftHome
                )
                .presentationDetents([.large])
                .presentationBackground(Palette.space)
            }
            .confirmationDialog("기록을 모두 지울까요?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("모두 지우기", role: .destructive) { store.clearHistory() }
                Button("취소", role: .cancel) {}
            } message: {
                Text("주고받은 소포와 시그널이 전부 사라져요. 되돌릴 수 없어요.")
            }
        }
        .presentationBackground(Palette.space)
    }

    // MARK: - Pieces

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

    private func citySlot(role: String, city: CoupleCity, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Metric.m) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                    .shadow(color: tint.opacity(0.8), radius: 5)

                VStack(alignment: .leading, spacing: 1) {
                    Text(role)
                        .font(.rounded(.caption2, .bold))
                        .foregroundStyle(tint)
                    Text("\(city.name), \(city.country)")
                        .font(.rounded(.subheadline, .semibold))
                        .foregroundStyle(Palette.textPrimary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCard())
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

/// 도시가 16곳이라 스톡 Picker로는 스크롤이 길어진다. 검색을 붙였다.
struct CityPickerList: View {
    let title: String
    @Binding var selection: String
    let excluding: String

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var results: [CoupleCity] {
        let pool = CoupleCity.presets.filter { $0.id != excluding }
        guard !query.isEmpty else { return pool }
        return pool.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.country.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.spaceDeep.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: Metric.s) {
                        ForEach(results) { city in
                            Button {
                                selection = city.id
                                dismiss()
                            } label: {
                                HStack(spacing: Metric.m) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(city.name)
                                            .font(.rounded(.body, .semibold))
                                            .foregroundStyle(Palette.textPrimary)
                                        Text(city.country)
                                            .font(.rounded(.caption))
                                            .foregroundStyle(Palette.textTertiary)
                                    }
                                    Spacer(minLength: 0)
                                    Text(localTime(in: city))
                                        .font(.rounded(.subheadline, .medium))
                                        .monospacedDigit()
                                        .foregroundStyle(Palette.textSecondary)
                                    if selection == city.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(Palette.me)
                                    }
                                }
                                .padding(Metric.m)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    selection == city.id
                                        ? AnyShapeStyle(Palette.me.opacity(0.16))
                                        : AnyShapeStyle(Palette.surface),
                                    in: RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
                                )
                            }
                            .buttonStyle(PressableCard())
                        }
                    }
                    .padding(Metric.screenPadding)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "도시 또는 나라")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private func localTime(in city: CoupleCity) -> String {
        Date.now.hourMinute(in: city.timeZone)
    }
}
