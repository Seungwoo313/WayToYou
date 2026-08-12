import SwiftUI

enum ClockDisplayFormat: String, CaseIterable, Identifiable {
    case twentyFourHour
    case twelveHour

    var id: Self { self }

    var title: String {
        switch self {
        case .twentyFourHour: "24시간제"
        case .twelveHour: "12시간제"
        }
    }

    var example: String {
        switch self {
        case .twentyFourHour: "18:30"
        case .twelveHour: "오후 6:30"
        }
    }

    func text(for date: Date, in timeZone: TimeZone) -> String {
        switch self {
        case .twentyFourHour:
            date.hourMinute(in: timeZone)
        case .twelveHour:
            date.formatted(
                Date.FormatStyle(
                    locale: Locale(identifier: "ko_KR"),
                    timeZone: timeZone
                )
                .hour(.defaultDigits(amPM: .abbreviated))
                .minute(.twoDigits)
            )
        }
    }
}

enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius
    case fahrenheit

    var id: Self { self }

    var title: String {
        switch self {
        case .celsius: "섭씨(°C)"
        case .fahrenheit: "화씨(°F)"
        }
    }

    func displayTemperature(fromCelsius temperature: Double) -> String {
        let converted = switch self {
        case .celsius: temperature
        case .fahrenheit: temperature * 9 / 5 + 32
        }
        return "\(Int(converted.rounded()))°"
    }

    func accessibilityTemperature(fromCelsius temperature: Double) -> String {
        let converted = switch self {
        case .celsius: temperature
        case .fahrenheit: temperature * 9 / 5 + 32
        }
        let unit = self == .celsius ? "섭씨" : "화씨"
        return "\(unit) \(Int(converted.rounded()))도"
    }
}

enum RouteHeartEmoji: String, CaseIterable, Identifiable {
    case red = "❤️"
    case pink = "🩷"
    case orange = "🧡"
    case yellow = "💛"
    case green = "💚"
    case blue = "💙"
    case lightBlue = "🩵"
    case purple = "💜"
    case brown = "🤎"
    case black = "🖤"
    case gray = "🩶"
    case white = "🤍"
    case broken = "💔"
    case exclamation = "❣️"
    case twoHearts = "💕"
    case revolving = "💞"
    case beating = "💓"
    case growing = "💗"
    case sparkling = "💖"
    case arrow = "💘"
    case ribbon = "💝"
    case decoration = "💟"
    case fire = "❤️‍🔥"
    case mending = "❤️‍🩹"
    case suit = "♥️"
    case heartHands = "🫶"
    case fingerHeart = "🫰"
    case loveLetter = "💌"
    case anatomical = "🫀"

    var id: String { rawValue }
}

struct SettingsView: View {
    @Bindable var store: WayToYouStore
    @Binding var clockFormat: ClockDisplayFormat
    @Binding var temperatureUnit: TemperatureUnit
    @Binding var showsRouteHeart: Bool
    @Binding var animatesRouteHeart: Bool
    @Binding var routeHeartEmoji: RouteHeartEmoji

    @State private var presentedSetting: PresentedSetting?

    private enum PresentedSetting: String, Identifiable {
        case time
        case city
        case airport
        case temperature
        case routeHeart
        #if DEBUG
        case debugMineCity
        case debugPartnerCity
        #endif

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.spaceDeep.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Metric.xl) {
                        settingsSection

                        #if DEBUG
                        if store.isDebugSession {
                            debugCitySection
                        }
                        #endif

                        if let message = store.connectionMessage {
                            Label(message, systemImage: "exclamationmark.circle.fill")
                                .font(.rounded(.caption, .medium))
                                .foregroundStyle(Palette.you)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(Metric.screenPadding)
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(item: $presentedSetting) { setting in
                settingSheet(setting)
            }
            #if DEBUG
            .onAppear {
                if UserDefaults.standard.string(forKey: "previewSetting") == "routeHeart" {
                    presentedSetting = .routeHeart
                }
            }
            #endif
        }
        .presentationBackground(Palette.space)
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: Metric.m) {
            Text("나의 설정")
                .font(.rounded(.footnote, .semibold))
                .foregroundStyle(Palette.textTertiary)
                .padding(.leading, Metric.xs)

            VStack(spacing: 0) {
                settingRow(
                    title: "시간 설정",
                    value: clockFormat.title,
                    systemImage: "clock"
                ) {
                    presentedSetting = .time
                }

                Divider().overlay(Palette.hairline)

                settingRow(
                    title: "도시 설정",
                    value: store.myProfile?.city.name ?? store.homeCity.name,
                    systemImage: "building.2"
                ) {
                    presentedSetting = .city
                }

                Divider().overlay(Palette.hairline)

                settingRow(
                    title: "공항 설정",
                    value: airportValue,
                    systemImage: "airplane.departure"
                ) {
                    presentedSetting = .airport
                }

                Divider().overlay(Palette.hairline)

                settingRow(
                    title: "기온 단위",
                    value: temperatureUnit.title,
                    systemImage: "thermometer.medium"
                ) {
                    presentedSetting = .temperature
                }

                Divider().overlay(Palette.hairline)

                toggleSettingRow(
                    title: "경로 위에 하트 표시",
                    systemImage: "heart.fill",
                    isOn: $showsRouteHeart
                )

                if showsRouteHeart {
                    Divider()
                        .overlay(Palette.hairline)
                        .padding(.leading, 38)

                    routeHeartDetailRow

                    Divider()
                        .overlay(Palette.hairline)
                        .padding(.leading, 38)

                    routeHeartAnimationDetailRow
                }
            }
            .animation(.snappy(duration: 0.25), value: showsRouteHeart)
            .padding(.horizontal, Metric.l)
            .glassPanel(radius: Metric.cardRadius)

            Link(destination: URL(string: "https://open-meteo.com/")!) {
                Text("날씨 데이터 · Open-Meteo")
                    .font(.rounded(.caption2))
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.leading, Metric.xs)
        }
    }

    private var airportValue: String {
        guard let airport = store.myProfile?.defaultAirport else { return "선택 필요" }
        return airport.displayCode ?? airport.name
    }

    #if DEBUG
    private var debugCitySection: some View {
        VStack(alignment: .leading, spacing: Metric.m) {
            Label("DEBUG · 도시 테스트", systemImage: "ladybug.fill")
                .font(.rounded(.footnote, .semibold))
                .foregroundStyle(.orange)
                .padding(.leading, Metric.xs)

            VStack(spacing: 0) {
                settingRow(
                    title: "내 테스트 도시",
                    value: store.homeCity.name,
                    systemImage: "person.fill"
                ) {
                    presentedSetting = .debugMineCity
                }

                Divider().overlay(Palette.hairline)

                settingRow(
                    title: "상대 테스트 도시",
                    value: store.partnerCity.name,
                    systemImage: "person.fill"
                ) {
                    presentedSetting = .debugPartnerCity
                }
            }
            .padding(.horizontal, Metric.l)
            .glassPanel(radius: Metric.cardRadius)

            Text("선택 즉시 홈의 지구본, 거리, 시차와 날씨가 갱신돼요. 서버에는 반영되지 않아요.")
                .font(.rounded(.caption2))
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Metric.xs)
        }
    }
    #endif

    private func settingRow(
        title: String,
        value: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Metric.m) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 26)

                Text(title)
                    .font(.rounded(.subheadline, .semibold))
                    .foregroundStyle(Palette.textPrimary)

                Spacer(minLength: Metric.s)

                Text(value)
                    .font(.rounded(.subheadline))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.connectionIsWorking)
    }

    private func toggleSettingRow(
        title: String,
        systemImage: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: Metric.m) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 26)

            Text(title)
                .font(.rounded(.subheadline, .semibold))
                .foregroundStyle(Palette.textPrimary)

            Spacer(minLength: Metric.s)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.pink)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private var routeHeartDetailRow: some View {
        Button {
            presentedSetting = .routeHeart
        } label: {
            HStack(spacing: Metric.s) {
                Text("모양")
                    .font(.rounded(.footnote, .medium))
                    .foregroundStyle(Palette.textSecondary)

                Spacer(minLength: Metric.s)

                Text(routeHeartEmoji.rawValue)
                    .font(.system(size: 22))

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.leading, 38)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var routeHeartAnimationDetailRow: some View {
        HStack(spacing: Metric.s) {
            Text("박동 애니메이션")
                .font(.rounded(.footnote, .medium))
                .foregroundStyle(Palette.textSecondary)

            Spacer(minLength: Metric.s)

            Toggle("", isOn: $animatesRouteHeart)
                .labelsHidden()
                .tint(.pink)
        }
        .padding(.leading, 38)
        .frame(minHeight: 48)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private func settingSheet(_ setting: PresentedSetting) -> some View {
        switch setting {
        case .time:
            ClockFormatPicker(selection: $clockFormat)
                .presentationDetents([.height(280)])
                .presentationBackground(Palette.space)

        case .city:
            RouteCityPicker { city in
                save(city: city)
            }
            .presentationDetents([.large])
            .presentationBackground(Palette.space)

        case .airport:
            if let profile = store.myProfile {
                RouteAirportPicker(city: profile.city) { airport in
                    save(defaultAirport: airport)
                }
                .presentationDetents([.large])
                .presentationBackground(Palette.space)
            }

        case .temperature:
            TemperatureUnitPicker(selection: $temperatureUnit)
                .presentationDetents([.height(250)])
                .presentationBackground(Palette.space)

        case .routeHeart:
            RouteHeartEmojiPicker(selection: $routeHeartEmoji)
                .presentationDetents([.height(430)])
                .presentationBackground(Palette.space)

        #if DEBUG
        case .debugMineCity:
            RouteCityPicker(
                title: "내 테스트 도시",
                prompt: "내 위치를 어디로 바꿀까요?",
                detail: "선택하면 홈의 내 위치가 즉시 바뀌어요."
            ) { city in
                store.setDebugCity(city, for: .mine)
            }
            .presentationDetents([.large])
            .presentationBackground(Palette.space)

        case .debugPartnerCity:
            RouteCityPicker(
                title: "상대 테스트 도시",
                prompt: "상대 위치를 어디로 바꿀까요?",
                detail: "선택하면 홈의 상대 위치가 즉시 바뀌어요."
            ) { city in
                store.setDebugCity(city, for: .partner)
            }
            .presentationDetents([.large])
            .presentationBackground(Palette.space)
        #endif
        }
    }

    private func save(city: RouteCity) {
        guard let profile = store.myProfile else { return }
        Task {
            await store.saveProfileToBackend(
                displayName: profile.displayName,
                city: city,
                defaultAirport: profile.defaultAirport
            )
        }
    }

    private func save(defaultAirport: RouteAirport) {
        guard let profile = store.myProfile else { return }
        Task {
            await store.saveProfileToBackend(
                displayName: profile.displayName,
                city: profile.city,
                defaultAirport: defaultAirport
            )
        }
    }
}

private struct RouteHeartEmojiPicker: View {
    @Binding var selection: RouteHeartEmoji
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Metric.s),
        count: 6
    )

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.spaceDeep.ignoresSafeArea()

                ScrollView {
                    LazyVGrid(columns: columns, spacing: Metric.s) {
                        ForEach(RouteHeartEmoji.allCases) { heart in
                            Button {
                                selection = heart
                            } label: {
                                Text(heart.rawValue)
                                    .font(.system(size: 28))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .background(
                                        selection == heart
                                            ? Color.white.opacity(0.14)
                                            : Color.clear,
                                        in: RoundedRectangle(
                                            cornerRadius: 14,
                                            style: .continuous
                                        )
                                    )
                                    .overlay {
                                        if selection == heart {
                                            RoundedRectangle(
                                                cornerRadius: 14,
                                                style: .continuous
                                            )
                                            .strokeBorder(Color.white.opacity(0.32), lineWidth: 1)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(heart.rawValue) 하트")
                            .accessibilityAddTraits(
                                selection == heart ? .isSelected : []
                            )
                        }
                    }
                    .padding(Metric.screenPadding)
                }
            }
            .navigationTitle("하트 고르기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

private struct TemperatureUnitPicker: View {
    @Binding var selection: TemperatureUnit
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.spaceDeep.ignoresSafeArea()

                VStack(spacing: 0) {
                    ForEach(TemperatureUnit.allCases) { unit in
                        Button {
                            selection = unit
                        } label: {
                            HStack {
                                Text(unit.title)
                                    .font(.rounded(.body, .semibold))
                                    .foregroundStyle(Palette.textPrimary)

                                Spacer()

                                if selection == unit {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(Palette.textPrimary)
                                }
                            }
                            .padding(.horizontal, Metric.l)
                            .frame(height: 62)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if unit != TemperatureUnit.allCases.last {
                            Divider().overlay(Palette.hairline)
                                .padding(.leading, Metric.l)
                        }
                    }
                }
                .glassPanel(radius: Metric.cardRadius)
                .padding(Metric.screenPadding)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .navigationTitle("기온 단위")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

private struct ClockFormatPicker: View {
    @Binding var selection: ClockDisplayFormat
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.spaceDeep.ignoresSafeArea()

                VStack(spacing: 0) {
                    ForEach(ClockDisplayFormat.allCases) { format in
                        Button {
                            selection = format
                        } label: {
                            HStack(spacing: Metric.m) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(format.title)
                                        .font(.rounded(.body, .semibold))
                                        .foregroundStyle(Palette.textPrimary)
                                    Text(format.example)
                                        .font(.rounded(.caption))
                                        .foregroundStyle(Palette.textTertiary)
                                }

                                Spacer()

                                if selection == format {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(Palette.textPrimary)
                                }
                            }
                            .padding(.horizontal, Metric.l)
                            .frame(height: 68)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if format != ClockDisplayFormat.allCases.last {
                            Divider().overlay(Palette.hairline)
                                .padding(.leading, Metric.l)
                        }
                    }
                }
                .glassPanel(radius: Metric.cardRadius)
                .padding(Metric.screenPadding)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .navigationTitle("시간 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}
