import SwiftUI

struct RouteAirportPicker: View {
    let city: RouteCity
    let onSelect: (RouteAirport) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [RouteAirport] = []
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
                            Label(
                                "\(city.name), \(city.country)",
                                systemImage: "mappin.and.ellipse"
                            )
                            .font(.rounded(.subheadline, .semibold))
                            .foregroundStyle(Palette.me)

                            Text("기본으로 사용할 공항은 어디인가요?")
                                .font(.system(.title2, design: .rounded).weight(.bold))
                                .foregroundStyle(Palette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("소포마다 다시 고르지 않아도 되고, 필요할 때 언제든 바꿀 수 있어요.")
                                .font(.rounded(.subheadline))
                                .foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        searchField

                        if isSearching && results.isEmpty {
                            loadingRow
                        } else if results.isEmpty {
                            emptyRow
                        } else {
                            ForEach(results) { airport in
                                Button { select(airport) } label: {
                                    resultRow(airport)
                                }
                                .buttonStyle(PressableCard())
                            }
                        }
                    }
                    .padding(Metric.screenPadding)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("기본 배송 공항")
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
        }
        .presentationBackground(Palette.space)
    }

    private var searchField: some View {
        HStack(spacing: Metric.m) {
            Image(systemName: "airplane")
                .foregroundStyle(Palette.textTertiary)
            TextField("공항 이름 검색", text: $query)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .font(.rounded(.body, .medium))
            if !query.isEmpty {
                Button { query = "" } label: {
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
        .task(id: query) { await searchAirportsAfterDelay() }
    }

    private func resultRow(_ airport: RouteAirport) -> some View {
        HStack(spacing: Metric.m) {
            Image(systemName: "airplane.departure")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Palette.me)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(airport.name)
                    .font(.rounded(.body, .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.leading)
                Text(airport.displayCode.map { "공항 코드 \($0)" } ?? "MapKit 공항")
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
            Text("가까운 공항을 찾고 있어요")
                .font(.rounded(.subheadline))
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, Metric.xxl)
    }

    private var emptyRow: some View {
        VStack(spacing: Metric.s) {
            Text("공항을 찾지 못했어요")
                .font(.rounded(.headline, .semibold))
                .foregroundStyle(Palette.textPrimary)
            Text("공항의 전체 이름으로 다시 검색해보세요.")
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

    private func searchAirportsAfterDelay() async {
        if !query.isEmpty {
            try? await Task.sleep(for: .milliseconds(300))
        }
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            results = try await searchService.airports(near: city, query: query)
        } catch {
            results = []
            message = "공항 검색을 완료하지 못했어요. 공항 이름을 다시 입력해주세요."
        }
    }

    private func select(_ airport: RouteAirport) {
        onSelect(airport)
        dismiss()
    }
}
