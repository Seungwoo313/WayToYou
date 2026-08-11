import SwiftUI
import UIKit

struct ContentView: View {
    private enum AppTab: Hashable {
        case home, keepsakes, us
    }

    @State private var store: WayToYouStore
    @State private var backend: SupabaseSessionController
    @State private var now = Date()
    @State private var route = SheetRoute.none
    @State private var selectedTab = AppTab.home
    @State private var floatingHearts: [HeartParticle] = []
    @State private var pendingHeartCount = 0
    @State private var heartSequence = 0
    @State private var heartSendTask: Task<Void, Never>?
    @State private var signalPulse = 0
    @State private var selectedGlobeMarkerID: GlobeProfileMarker.ID?
    @Environment(\.scenePhase) private var scenePhase
    #if DEBUG
    private let debugAccount: DebugAccount?
    #endif

    init() {
        #if DEBUG
        let debugAccount = DebugAccount.launched
        self.debugAccount = debugAccount
        _store = State(
            initialValue: debugAccount.map(WayToYouStore.init(debugAccount:))
                ?? WayToYouStore()
        )
        #else
        _store = State(initialValue: WayToYouStore())
        #endif
        _backend = State(initialValue: SupabaseSessionController())
    }

    private var focus: HomeFocus { store.focus(at: now) }

    private var isDebugSession: Bool {
        #if DEBUG
        debugAccount != nil
        #else
        false
        #endif
    }

    var body: some View {
        appContent
            .preferredColorScheme(.dark)
            .task {
                guard !isDebugSession else { return }
                await backend.restoreSession()
            }
            .task(id: backend.authenticatedUserID) {
                guard !isDebugSession else { return }
                guard let userID = backend.authenticatedUserID,
                      let client = backend.client else { return }
                await store.activateBackend(client: client, userID: userID)
            }
            .task(id: "\(scenePhase)-\(store.isConnected)") { await runClock() }
            .task(id: "heart-\(scenePhase)-\(store.isConnected)") { await syncHeartBursts() }
            .task(id: "signal-\(scenePhase)-\(store.isConnected)") { await syncSignals() }
            .task(id: "profile-\(scenePhase)-\(store.isConnected)") { await syncProfiles() }
            .onChange(of: selectedTab) { _, tab in
                if tab != .home { selectedGlobeMarkerID = nil }
            }
            .sheet(item: $route.presented) { destination in
                sheet(for: destination)
            }
            .alert("Heart를 보내지 못했어요", isPresented: heartMessageBinding) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(store.heartMessage ?? "잠시 후 다시 시도해주세요.")
            }
            .alert("Signal을 보내지 못했어요", isPresented: signalMessageBinding) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(store.signalMessage ?? "잠시 후 다시 시도해주세요.")
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

    @ViewBuilder
    private var appContent: some View {
        if isDebugSession {
            connectedApp
        } else if backend.authenticatedUserID == nil {
            AppleSignInView(backend: backend)
        } else if !store.backendIsReady {
            connectionLoading
        } else if store.isConnected {
            connectedApp
        } else {
            ConnectionOnboardingView(
                store: store,
                suggestedName: backend.suggestedDisplayName
            )
        }
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

                ZStack {
                    GlobeMapView(
                        myMarker: myGlobeMarker,
                        partnerMarker: partnerGlobeMarker,
                        selectedMarkerID: $selectedGlobeMarkerID
                    )

                    if selectedGlobeMarkerID == nil,
                       let partnerSignal = store.latestSignal(.incoming, at: now) {
                        PartnerSignalPill(
                            event: partnerSignal,
                            partnerName: store.partnerProfile?.displayName ?? "상대",
                            now: now,
                            pulse: signalPulse
                        )
                        .padding(.top, Metric.m)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    VStack(spacing: Metric.s) {
                        if let details = selectedGlobeDetails {
                            GlobeProfileDetailCard(details: details, now: now)
                                .id(details.id)
                                .transition(
                                    .move(edge: .bottom)
                                        .combined(with: .opacity)
                                        .combined(with: .scale(scale: 0.96, anchor: .bottom))
                                )
                        }

                        Actions(
                            focus: focus,
                            heartPulse: heartSequence,
                            currentSignal: store.latestSignal(.outgoing, at: now)?.signal,
                            onHeart: queueHeart,
                            onPrimary: primaryAction,
                            onSignal: { route = .signal }
                        )
                    }
                    .padding(.horizontal, Metric.screenPadding)
                    .padding(.bottom, Metric.s)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .clipped()
                .animation(.spring(response: 0.42, dampingFraction: 0.82), value: store.latestSignal(.incoming, at: now)?.id)
                .animation(.spring(response: 0.38, dampingFraction: 0.82), value: selectedGlobeMarkerID)
            }
            .overlay(alignment: .bottom) {
                Color.black.frame(height: 1)
            }

            HeartBurstOverlay(particles: floatingHearts)
        }
        .background(Palette.spaceDeep.ignoresSafeArea())
    }

    private var myGlobeMarker: GlobeProfileMarker {
        GlobeProfileMarker(
            id: .mine,
            displayName: store.myProfile?.displayName ?? "나",
            city: store.homeCity,
            avatarData: store.myProfile.flatMap { store.avatarData(for: $0) }
        )
    }

    private var partnerGlobeMarker: GlobeProfileMarker {
        GlobeProfileMarker(
            id: .partner,
            displayName: store.partnerProfile?.displayName ?? "상대",
            city: store.partnerCity,
            avatarData: store.partnerProfile.flatMap { store.avatarData(for: $0) }
        )
    }

    private var selectedGlobeDetails: GlobeProfileDetails? {
        guard let selectedGlobeMarkerID else { return nil }
        let marker = selectedGlobeMarkerID == .mine ? myGlobeMarker : partnerGlobeMarker
        let direction: ParcelDirection = selectedGlobeMarkerID == .mine ? .outgoing : .incoming
        return GlobeProfileDetails(
            id: selectedGlobeMarkerID,
            displayName: marker.displayName,
            city: marker.city,
            avatarData: marker.avatarData,
            signal: store.latestSignal(direction, at: now)
        )
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheet(for destination: SheetRoute.Destination) -> some View {
        switch destination {
        case .signal:
            SignalPickerSheet(
                selectedSignal: store.latestSignal(.outgoing, at: now)?.signal
            ) { signal in
                route = .none
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                Task { _ = await store.sendSignal(signal) }
            }
            .presentationDetents([.height(270), .medium])
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

    private func queueHeart() {
        guard store.isConnected else { return }

        pendingHeartCount = min(pendingHeartCount + 1, 50)
        emitHeart(incoming: false)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.45)

        heartSendTask?.cancel()
        heartSendTask = Task {
            if pendingHeartCount < 50 {
                try? await Task.sleep(for: .milliseconds(700))
            }
            guard !Task.isCancelled else { return }
            await flushPendingHearts()
        }
    }

    private func flushPendingHearts() async {
        // 다음 연타가 이미 전송 중인 Task를 취소하지 않도록 debounce 소유권을 먼저 놓는다.
        heartSendTask = nil
        let count = pendingHeartCount
        guard count > 0 else { return }
        pendingHeartCount = 0
        _ = await store.sendHeartBurst(count: count)
    }

    private func syncHeartBursts() async {
        guard !isDebugSession, scenePhase == .active, store.isConnected else { return }

        while !Task.isCancelled {
            let received = await store.refreshHeartBursts()
            for burst in received {
                await playIncoming(burst)
            }
            try? await Task.sleep(for: .seconds(4))
        }
    }

    private func playIncoming(_ burst: HeartBurst) async {
        for index in 0..<burst.count {
            guard !Task.isCancelled else { return }
            emitHeart(incoming: true)
            if index.isMultiple(of: 4) {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.35)
            }
            try? await Task.sleep(for: .milliseconds(110))
        }
    }

    private func syncSignals() async {
        guard !isDebugSession, scenePhase == .active, store.isConnected else { return }

        while !Task.isCancelled {
            let received = await store.refreshSignals()
            if !received.isEmpty {
                signalPulse += 1
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            try? await Task.sleep(for: .seconds(4))
        }
    }

    private func syncProfiles() async {
        guard !isDebugSession, scenePhase == .active, store.isConnected else { return }

        while !Task.isCancelled {
            await store.refreshConnection()
            try? await Task.sleep(for: .seconds(30))
        }
    }

    private func emitHeart(incoming: Bool) {
        heartSequence += 1
        let particle = HeartParticle.make(sequence: heartSequence, incoming: incoming)
        floatingHearts.append(particle)

        Task {
            try? await Task.sleep(for: .milliseconds(1_600))
            floatingHearts.removeAll { $0.id == particle.id }
        }
    }

    private var heartMessageBinding: Binding<Bool> {
        Binding(
            get: { store.heartMessage != nil },
            set: { if !$0 { store.clearHeartMessage() } }
        )
    }

    private var signalMessageBinding: Binding<Bool> {
        Binding(
            get: { store.signalMessage != nil },
            set: { if !$0 { store.clearSignalMessage() } }
        )
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

// MARK: - Globe profile details

private struct GlobeProfileDetails: Identifiable, Equatable {
    let id: GlobeProfileMarker.ID
    let displayName: String
    let city: CoupleCity
    let avatarData: Data?
    let signal: SignalEvent?
}

private struct GlobeProfileDetailCard: View {
    let details: GlobeProfileDetails
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.m) {
            HStack(spacing: Metric.m) {
                ProfileAvatarImage(
                    data: details.avatarData,
                    displayName: details.displayName,
                    size: 40
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(details.displayName)
                        .font(.rounded(.subheadline, .semibold))
                        .foregroundStyle(Palette.textPrimary)

                    Text("\(details.city.name) · \(details.city.country) · \(now.hourMinute(in: details.city.timeZone))")
                        .font(.rounded(.caption))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: Metric.s) {
                if let signal = details.signal {
                    Label(signal.signal.title, systemImage: signal.signal.symbol)
                    Text(signal.sentAt.koreanRelative(to: now))
                        .foregroundStyle(Palette.textTertiary)
                } else {
                    Label("상태 없음", systemImage: "minus.circle")
                }
            }
            .font(.rounded(.caption, .medium))
            .foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, Metric.l)
        .padding(.vertical, Metric.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let location = "\(details.city.name), \(details.city.country), 현지 시간 \(now.hourMinute(in: details.city.timeZone))"
        guard let signal = details.signal else {
            return "\(details.displayName), \(location), 현재 Signal 없음"
        }
        return "\(details.displayName), \(location), \(signal.signal.title), \(signal.sentAt.koreanRelative(to: now))"
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

// MARK: - Signal status

private struct PartnerSignalPill: View {
    let event: SignalEvent
    let partnerName: String
    let now: Date
    let pulse: Int

    var body: some View {
        HStack(spacing: Metric.m) {
            Image(systemName: event.signal.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .symbolEffect(.bounce, value: pulse)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.signal.partnerCaption)
                    .font(.rounded(.footnote, .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text("\(partnerName) · \(event.sentAt.koreanRelative(to: now))")
                    .font(.rounded(.caption2))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.horizontal, Metric.l)
        .frame(height: 52)
        .glassEffect(.regular, in: Capsule())
        .overlay { Capsule().strokeBorder(Palette.hairline, lineWidth: 0.5) }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Actions

/// 감정의 무게가 작은 순서대로 둔, 홈의 세 가지 아이콘 액션.
private struct Actions: View {
    let focus: HomeFocus
    let heartPulse: Int
    let currentSignal: CoupleSignal?
    let onHeart: () -> Void
    let onPrimary: () -> Void
    let onSignal: () -> Void

    private var isArrived: Bool {
        if case .readyToOpen = focus { return true }
        return false
    }

    /// 평상시엔 흰색. 소포가 도착했을 때만 포장지 색으로 바뀐다.
    /// 늘 색이 차 있으면 도착이 특별해 보이지 않는다.
    private var arrivedWrap: ParcelWrap? {
        if case .readyToOpen(let parcel) = focus { return parcel.wrap }
        return nil
    }

    var body: some View {
        HStack(spacing: Metric.s) {
            Button(action: onHeart) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.pink)
                    .symbolEffect(.bounce, value: heartPulse)
                    .frame(width: 52, height: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .accessibilityLabel("Heart 보내기")
            .accessibilityHint("연속으로 누르면 누른 횟수만큼 상대에게 전달됩니다")

            Button(action: onSignal) {
                Image(systemName: currentSignal?.symbol ?? "antenna.radiowaves.left.and.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 52, height: 44)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .accessibilityLabel(currentSignal.map { "내 Signal \($0.title). Signal 바꾸기" } ?? "Signal 보내기")

            Button(action: onPrimary) {
                Image(systemName: isArrived ? "shippingbox.fill" : "shippingbox")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(arrivedWrap?.color ?? Palette.textPrimary)
                    .frame(width: 52, height: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .accessibilityLabel(isArrived ? "도착한 소포 열기" : "소포 보내기")
        }
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
