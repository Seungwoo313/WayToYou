import CoreLocation
import SwiftUI

struct RouteEndpointPicker: View {
    let onSelect: (RouteEndpoint) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var location = CurrentLocationController()
    @State private var cityQuery = ""
    @State private var airportQuery = ""
    @State private var cityResults: [RouteCity] = []
    @State private var airportResults: [RouteAirport] = []
    @State private var selectedCity: RouteCity?
    @State private var isSearching = false
    @State private var message: String?

    private let searchService = RoutePlaceSearchService()

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.spaceDeep.ignoresSafeArea()

                Group {
                    if let selectedCity {
                        airportStep(city: selectedCity)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else {
                        cityStep
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                .animation(.snappy(duration: 0.32), value: selectedCity?.id)
            }
            .navigationTitle(selectedCity == nil ? "나의 도시" : "만남의 공항")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if selectedCity == nil {
                        Button("닫기") { dismiss() }
                    } else {
                        Button {
                            selectedCity = nil
                            airportQuery = ""
                            airportResults = []
                        } label: {
                            Label("도시", systemImage: "chevron.left")
                        }
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .alert("검색을 완료하지 못했어요", isPresented: messageBinding) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(message ?? "잠시 후 다시 시도해주세요.")
            }
            .onChange(of: location.state) { _, state in
                switch state {
                case .located(let current):
                    Task { await recommendEndpoint(near: current) }
                case .failed(let text):
                    message = text
                default:
                    break
                }
            }
        }
        .presentationBackground(Palette.space)
    }

    private var cityStep: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Metric.xl) {
                VStack(alignment: .leading, spacing: Metric.s) {
                    Text("어디에서 기다리고 있나요?")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(Palette.textPrimary)
                    Text("위치는 가까운 공항을 추천할 때 한 번만 사용하고 저장하지 않아요.")
                        .font(.rounded(.subheadline))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    location.requestLocation()
                } label: {
                    HStack(spacing: Metric.m) {
                        Group {
                            if location.state == .requesting {
                                ProgressView().tint(Palette.me)
                            } else {
                                Image(systemName: "location.fill")
                                    .foregroundStyle(Palette.me)
                            }
                        }
                        .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("현재 위치로 찾기")
                                .font(.rounded(.body, .semibold))
                                .foregroundStyle(Palette.textPrimary)
                            Text("위치 권한은 이 버튼을 누를 때 요청해요")
                                .font(.rounded(.caption))
                                .foregroundStyle(Palette.textTertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .padding(Metric.l)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
                }
                .buttonStyle(PressableCard())
                .disabled(location.state == .requesting)

                HStack(spacing: Metric.m) {
                    Rectangle().fill(Palette.hairline).frame(height: 1)
                    Text("또는 직접 검색")
                        .font(.rounded(.caption, .medium))
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize()
                    Rectangle().fill(Palette.hairline).frame(height: 1)
                }

                searchField(
                    placeholder: "도시 또는 지역",
                    text: $cityQuery,
                    systemImage: "magnifyingglass"
                )

                if isSearching && cityResults.isEmpty {
                    loadingRow("도시를 찾고 있어요")
                } else if cityQuery.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2,
                          cityResults.isEmpty {
                    emptyRow("검색 결과가 없어요", detail: "도시 이름을 다른 언어로도 입력해보세요.")
                } else {
                    ForEach(cityResults) { city in
                        Button {
                            Task { await select(city: city) }
                        } label: {
                            resultRow(
                                icon: "building.2",
                                title: city.name,
                                detail: city.country
                            )
                        }
                        .buttonStyle(PressableCard())
                    }
                }
            }
            .padding(Metric.screenPadding)
        }
        .scrollDismissesKeyboard(.interactively)
        .task(id: cityQuery) { await searchCitiesAfterDelay() }
    }

    private func airportStep(city: RouteCity) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Metric.xl) {
                VStack(alignment: .leading, spacing: Metric.s) {
                    Label("\(city.name), \(city.country)", systemImage: "mappin.and.ellipse")
                        .font(.rounded(.subheadline, .semibold))
                        .foregroundStyle(Palette.me)
                    Text("연인이 당신을 만나러 올 때 어느 공항으로 오나요?")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                searchField(
                    placeholder: "공항 이름 검색",
                    text: $airportQuery,
                    systemImage: "airplane"
                )

                if isSearching && airportResults.isEmpty {
                    loadingRow("가까운 공항을 찾고 있어요")
                } else if airportResults.isEmpty {
                    emptyRow("공항을 찾지 못했어요", detail: "공항의 전체 이름으로 다시 검색해보세요.")
                } else {
                    ForEach(airportResults) { airport in
                        Button {
                            onSelect(RouteEndpoint(city: city, airport: airport))
                            dismiss()
                        } label: {
                            resultRow(
                                icon: "airplane.departure",
                                title: airport.name,
                                detail: airport.displayCode.map { "공항 코드 \($0)" } ?? "MapKit 공항"
                            )
                        }
                        .buttonStyle(PressableCard())
                    }
                }
            }
            .padding(Metric.screenPadding)
        }
        .scrollDismissesKeyboard(.interactively)
        .task(id: airportQuery) { await searchAirportsAfterDelay(in: city) }
    }

    private func searchField(
        placeholder: String,
        text: Binding<String>,
        systemImage: String
    ) -> some View {
        HStack(spacing: Metric.m) {
            Image(systemName: systemImage)
                .foregroundStyle(Palette.textTertiary)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .font(.rounded(.body, .medium))
            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Metric.l)
        .frame(height: 54)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.5)
        }
    }

    private func resultRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: Metric.m) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Palette.me)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.rounded(.body, .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.leading)
                Text(detail)
                    .font(.rounded(.caption))
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer(minLength: Metric.s)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(Metric.l)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
    }

    private func loadingRow(_ text: String) -> some View {
        HStack(spacing: Metric.m) {
            ProgressView().tint(Palette.me)
            Text(text)
                .font(.rounded(.subheadline))
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, Metric.xxl)
    }

    private func emptyRow(_ title: String, detail: String) -> some View {
        VStack(spacing: Metric.s) {
            Text(title)
                .font(.rounded(.headline, .semibold))
                .foregroundStyle(Palette.textPrimary)
            Text(detail)
                .font(.rounded(.caption))
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Metric.xxl)
    }

    private var messageBinding: Binding<Bool> {
        Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )
    }

    private func searchCitiesAfterDelay() async {
        let query = cityQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            cityResults = []
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            cityResults = try await searchService.searchCities(query)
        } catch {
            cityResults = []
            message = "도시 검색을 완료하지 못했어요. 네트워크를 확인해주세요."
        }
    }

    private func searchAirportsAfterDelay(in city: RouteCity) async {
        if !airportQuery.isEmpty {
            try? await Task.sleep(for: .milliseconds(300))
        }
        guard !Task.isCancelled else { return }
        await loadAirports(near: city)
    }

    private func select(city: RouteCity) async {
        selectedCity = city
        airportQuery = ""
        await loadAirports(near: city)
    }

    private func loadAirports(near city: RouteCity) async {
        isSearching = true
        defer { isSearching = false }
        do {
            airportResults = try await searchService.airports(near: city, query: airportQuery)
        } catch {
            airportResults = []
            message = "공항 검색을 완료하지 못했어요. 공항 이름을 다시 입력해주세요."
        }
    }

    private func recommendEndpoint(near current: CLLocation) async {
        isSearching = true
        defer { isSearching = false }
        do {
            let city = try await searchService.city(near: current)
            selectedCity = city
            airportQuery = ""
            airportResults = try await searchService.airports(near: city)
        } catch {
            message = error.localizedDescription
        }
    }
}
