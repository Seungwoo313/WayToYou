import CoreLocation
import SwiftUI

struct RouteCityPicker: View {
    let onSelect: (RouteCity) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var location = CurrentLocationController()
    @State private var cityQuery = ""
    @State private var cityResults: [RouteCity] = []
    @State private var isSearching = false
    @State private var message: String?

    private let searchService = RoutePlaceSearchService()

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.spaceDeep.ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Metric.xl) {
                        VStack(alignment: .leading, spacing: Metric.s) {
                            Text("어디에서 지내고 있나요?")
                                .font(.system(.title2, design: .rounded).weight(.bold))
                                .foregroundStyle(Palette.textPrimary)
                            Text("도시는 두 사람의 프로필과 지구본 Route에 사용해요.")
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
                                    Text("위치 권한은 이 버튼을 누를 때만 요청해요")
                                        .font(.rounded(.caption))
                                        .foregroundStyle(Palette.textTertiary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Palette.textTertiary)
                            }
                            .padding(Metric.l)
                            .background(
                                Palette.surface,
                                in: RoundedRectangle(
                                    cornerRadius: Metric.cardRadius,
                                    style: .continuous
                                )
                            )
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

                        searchField

                        if isSearching && cityResults.isEmpty {
                            loadingRow
                        } else if cityQuery.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2,
                                  cityResults.isEmpty {
                            emptyRow
                        } else {
                            ForEach(cityResults) { city in
                                Button { select(city) } label: {
                                    resultRow(city)
                                }
                                .buttonStyle(PressableCard())
                            }
                        }
                    }
                    .padding(Metric.screenPadding)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("나의 도시")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
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
                    Task { await recommendCity(near: current) }
                case .failed(let text):
                    message = text
                default:
                    break
                }
            }
        }
        .presentationBackground(Palette.space)
    }

    private var searchField: some View {
        HStack(spacing: Metric.m) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Palette.textTertiary)
            TextField("도시 또는 지역", text: $cityQuery)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .font(.rounded(.body, .medium))
            if !cityQuery.isEmpty {
                Button { cityQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Metric.l)
        .frame(height: 54)
        .background(
            Palette.surface,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.5)
        }
        .task(id: cityQuery) { await searchCitiesAfterDelay() }
    }

    private func resultRow(_ city: RouteCity) -> some View {
        HStack(spacing: Metric.m) {
            Image(systemName: "building.2")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Palette.me)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(city.name)
                    .font(.rounded(.body, .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.leading)
                Text(city.country)
                    .font(.rounded(.caption))
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer(minLength: Metric.s)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(Metric.l)
        .background(
            Palette.surface,
            in: RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
        )
    }

    private var loadingRow: some View {
        HStack(spacing: Metric.m) {
            ProgressView().tint(Palette.me)
            Text("도시를 찾고 있어요")
                .font(.rounded(.subheadline))
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, Metric.xxl)
    }

    private var emptyRow: some View {
        VStack(spacing: Metric.s) {
            Text("검색 결과가 없어요")
                .font(.rounded(.headline, .semibold))
                .foregroundStyle(Palette.textPrimary)
            Text("도시 이름을 다른 언어로도 입력해보세요.")
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

    private func recommendCity(near current: CLLocation) async {
        isSearching = true
        defer { isSearching = false }
        do {
            select(try await searchService.city(near: current))
        } catch {
            message = error.localizedDescription
        }
    }

    private func select(_ city: RouteCity) {
        onSelect(city)
        dismiss()
    }
}
