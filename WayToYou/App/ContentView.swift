import SwiftUI
import UIKit

struct ContentView: View {
    private enum AppTab: Hashable {
        case home, keepsakes, us
    }

    @State private var store = WayToYouStore()
    @State private var backend = SupabaseSessionController()
    @State private var now = Date()
    @State private var route = SheetRoute.none
    @State private var selectedTab = AppTab.home
    @Environment(\.scenePhase) private var scenePhase

    private var focus: HomeFocus { store.focus(at: now) }

    var body: some View {
        Group {
            if backend.authenticatedUserID == nil {
                AppleSignInView(backend: backend)
            } else if !store.backendIsReady {
                connectionLoading
            } else {
                if store.isConnected {
                    connectedApp
                } else {
                    ConnectionOnboardingView(
                        store: store,
                        suggestedName: backend.suggestedDisplayName
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await backend.restoreSession() }
        .task(id: backend.authenticatedUserID) {
            guard let userID = backend.authenticatedUserID,
                  let client = backend.client else { return }
            await store.activateBackend(client: client, userID: userID)
        }
        .task(id: "\(scenePhase)-\(store.isConnected)") { await runClock() }
        .sheet(item: $route.presented) { destination in
            sheet(for: destination)
        }
        #if DEBUG
        // 스크린샷용. `simctl launch ... -previewSheet compose`처럼 띄운다.
        .onAppear {
            guard store.isConnected else { return }
            switch UserDefaults.standard.string(forKey: "previewSheet") {
            case "compose": route = .compose
            case "signal": route = .signal
            case "keepsakes": selectedTab = .keepsakes
            case "us": selectedTab = .us
            case "letter":
                if let parcel = store.waitingToOpen(at: .now).first ?? store.lastOpenedIncoming() {
                    route = .letter(parcel)
                }
            default: break
            }
        }
        #endif
    }

    private var connectionLoading: some View {
        ZStack {
            Palette.spaceDeep.ignoresSafeArea()
            VStack(spacing: Metric.m) {
                ProgressView()
                    .tint(Palette.me)
                Text("연결 상태를 확인하고 있어요")
                    .font(.rounded(.subheadline, .medium))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private var connectedApp: some View {
        TabView(selection: $selectedTab) {
            Tab("홈", systemImage: "globe.asia.australia.fill", value: AppTab.home) {
                home
            }

            Tab("간직함", systemImage: "archivebox", value: AppTab.keepsakes) {
                KeepsakesView(
                    store: store,
                    now: now,
                    presentedAsSheet: false
                ) { parcel in
                    route = .letter(parcel)
                }
            }

            Tab("우리", systemImage: "person.2", value: AppTab.us) {
                UsView(store: store, presentedAsSheet: false)
            }
        }
    }

    private var home: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                ClockRow(store: store, now: now)
                    .padding(.horizontal, Metric.screenPadding)
                    .padding(.top, Metric.s)
                    .padding(.bottom, Metric.m)

                ZStack(alignment: .bottom) {
                    GlobeMapView(
                        homeCity: store.homeCity,
                        partnerCity: store.partnerCity
                    )

                    Actions(
                        focus: focus,
                        onPrimary: primaryAction,
                        onSignal: { route = .signal }
                    )
                    .padding(.horizontal, Metric.screenPadding)
                    .padding(.bottom, Metric.s)
                }
                .clipped()
            }
            .overlay(alignment: .bottom) {
                Color.black.frame(height: 1)
            }
        }
        .background(Palette.spaceDeep.ignoresSafeArea())
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheet(for destination: SheetRoute.Destination) -> some View {
        switch destination {
        case .signal:
            SignalPickerSheet { signal in
                store.sendSignal(signal)
                route = .none
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
            .presentationDetents([.height(400)])
            .presentationDragIndicator(.visible)

        case .compose:
            ParcelComposerSheet(
                homeCity: store.homeCity,
                partnerCity: store.partnerCity,
                flightDuration: store.flightDuration()
            ) { title, message, wrap in
                store.sendParcel(title: title, message: message, wrap: wrap)
                route = .none
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }

        case .letter(let parcel):
            ParcelLetterSheet(parcel: parcel) {
                store.open(parcel)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }

        case .keepsakes:
            KeepsakesView(store: store, now: now) { parcel in
                route = .letter(parcel)
            }

        case .us:
            UsView(store: store)
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Actions

    private func primaryAction() {
        if case .readyToOpen(let parcel) = focus {
            route = .letter(parcel)
        } else {
            route = .compose
        }
    }

    /// 하늘에 뜬 소포가 없으면 굳이 1초마다 깨울 이유가 없다.
    /// 예전엔 TimelineView가 화면 전체를 매초 다시 그렸다.
    private func runClock() async {
        guard scenePhase == .active, store.isConnected else { return }
        while !Task.isCancelled {
            let moment = Date()
            now = moment
            store.advance(to: moment)
            let busy = !store.inFlight(at: moment).isEmpty
            try? await Task.sleep(for: .seconds(busy ? 1 : 10))
        }
    }
}

// MARK: - Clock

/// 두 사람의 지금. 상자도 구분선도 없이 글자만 둔다.
private struct ClockRow: View {
    let store: WayToYouStore
    let now: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            clock(store.homeCity, alignment: .leading)
            Spacer(minLength: Metric.l)
            clock(store.partnerCity, alignment: .trailing)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func clock(_ city: CoupleCity, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(city.name)
                .font(.rounded(.caption2, .medium))
                .foregroundStyle(Palette.textTertiary)
                .tracking(1.4)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(now.hourMinute(in: city.timeZone))
                    .font(.system(.title2, design: .rounded).weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)

                if let offset = dayOffsetLabel(for: city) {
                    Text(offset)
                        .font(.rounded(.caption2, .medium))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(city.name) \(now.hourMinute(in: city.timeZone))")
    }

    /// 시차 때문에 날짜가 넘어간 경우에만 붙인다. 같은 날이면 아무것도 안 보인다.
    private func dayOffsetLabel(for city: CoupleCity) -> String? {
        var here = Calendar(identifier: .gregorian)
        here.timeZone = store.homeCity.timeZone
        var there = Calendar(identifier: .gregorian)
        there.timeZone = city.timeZone

        let mine = here.startOfDay(for: now)
        let theirs = there.startOfDay(for: now)
        let days = there.dateComponents([.day], from: mine, to: theirs).day ?? 0
        switch days {
        case 1...: return "내일"
        case ..<0: return "어제"
        default: return nil
        }
    }
}

// MARK: - Status

/// 홈 중앙에 보여주는 현재 상태.
private struct StatusLine: View {
    let focus: HomeFocus
    let store: WayToYouStore
    let now: Date

    var body: some View {
        VStack(spacing: Metric.s) {
            switch focus {
            case .quiet:
                quiet
            case .outgoingFlight(let parcel), .incomingFlight(let parcel):
                flight(parcel)
            case .readyToOpen(let parcel):
                headline("소포가 도착했어요", detail: "\(parcel.fromCity.name)에서 · \(parcel.arrivesAt.koreanRelative(to: now))")
            case .partnerRead(let parcel):
                headline(
                    "\(parcel.toCity.name)에서 편지를 읽었어요",
                    detail: "“\(parcel.title)” · \((parcel.openedAt ?? parcel.arrivesAt).koreanRelative(to: now))"
                )
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .softSpring(focus)
    }

    @ViewBuilder
    private var quiet: some View {
        if let theirs = store.latestSignal(.incoming, at: now) {
            headline(
                theirs.signal.partnerCaption,
                detail: "\(store.partnerCity.name) · \(theirs.sentAt.koreanRelative(to: now))"
            )
        } else if let mine = store.latestSignal(.outgoing, at: now) {
            headline(
                "‘\(mine.signal.title)’를 보내뒀어요",
                detail: "\(store.partnerCity.name)에 닿아 있어요 · \(mine.sentAt.koreanRelative(to: now))"
            )
        } else {
            // 상단 시계에서 뺀 거리·시차를 여기서 되돌려준다. 늘 붙어 있으면 잡음이지만
            // 아무 일도 없을 때는 이게 유일하게 말할 거리다.
            headline(
                "아직 조용해요",
                detail: "\(store.distanceKilometers.grouped)km · \(store.timeDifferenceCaption(at: now))"
            )
        }
    }

    private func flight(_ parcel: Parcel) -> some View {
        let isMine = parcel.direction == .outgoing
        let remaining = max(parcel.arrivesAt.timeIntervalSince(now), 0)
        return VStack(spacing: Metric.m) {
            VStack(spacing: 3) {
                Text("\(parcel.toCity.name)까지 \(remaining.shortKoreanDuration)")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text(isMine ? "내 소포 · “\(parcel.title)”" : "\(parcel.fromCity.name)에서 오는 중")
                    .font(.rounded(.footnote))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }

            ProgressHairline(progress: parcel.progress(at: now), tint: Palette.tint(for: parcel.direction))
        }
    }

    private func headline(_ title: String, detail: String?) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(.rounded(.footnote))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}

/// 2pt 짜리 진행선. ProgressView의 기본 트랙은 이 화면에서 너무 두껍고 밝다.
private struct ProgressHairline: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(tint)
                    .frame(width: max(geometry.size.width * progress, 2))
            }
        }
        .frame(height: 2)
        .frame(maxWidth: 190)
        .animation(.linear(duration: 0.9), value: progress)
        .accessibilityHidden(true)
    }
}

// MARK: - Actions

/// 홈의 유일한 두 행동. 기록과 설정은 시스템 탭 바로 이동했다.
private struct Actions: View {
    let focus: HomeFocus
    let onPrimary: () -> Void
    let onSignal: () -> Void

    private var isArrived: Bool {
        if case .readyToOpen = focus { return true }
        return false
    }

    private var primaryTitle: String { isArrived ? "소포 열어보기" : "소포 보내기" }

    /// 평상시엔 흰색. 소포가 도착했을 때만 포장지 색으로 바뀐다.
    /// 늘 색이 차 있으면 도착이 특별해 보이지 않는다.
    private var arrivedWrap: ParcelWrap? {
        if case .readyToOpen(let parcel) = focus { return parcel.wrap }
        return nil
    }

    var body: some View {
        HStack(spacing: Metric.m) {
            Button(action: onPrimary) {
                Label(primaryTitle, systemImage: isArrived ? "shippingbox.fill" : "shippingbox")
                    .foregroundStyle(arrivedWrap == nil ? Color.black : .white)
                    .font(.rounded(.subheadline, .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .buttonStyle(.glassProminent)
            .tint(arrivedWrap?.color ?? .white)

            Button(action: onSignal) {
                Label("시그널", systemImage: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(Palette.textPrimary)
                    .font(.rounded(.subheadline, .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .buttonStyle(.glass)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

// MARK: - Routing

/// 시트를 하나의 상태로 모아서, 시트끼리 갈아탈 때 깜빡임이 없게 한다.
struct SheetRoute {
    enum Destination: Identifiable, Hashable {
        case signal
        case compose
        case letter(Parcel)
        case keepsakes
        case us

        var id: String {
            switch self {
            case .signal: "signal"
            case .compose: "compose"
            case .letter(let parcel): "letter-\(parcel.id)"
            case .keepsakes: "keepsakes"
            case .us: "us"
            }
        }
    }

    var presented: Destination?

    static let none = SheetRoute(presented: nil)
    static let signal = SheetRoute(presented: .signal)
    static let compose = SheetRoute(presented: .compose)
    static let keepsakes = SheetRoute(presented: .keepsakes)
    static let us = SheetRoute(presented: .us)
    static func letter(_ parcel: Parcel) -> SheetRoute { SheetRoute(presented: .letter(parcel)) }
}

#Preview("홈 화면 전체") {
    ContentView()
}
