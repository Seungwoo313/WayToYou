import SwiftUI
import UIKit

struct ContentView: View {
    private enum AppTab: Hashable {
        case home, keepsakes, us, settings
    }

    @State private var store: WayToYouStore
    @State private var backend: SupabaseSessionController
    @State private var now = Date()
    @State private var route = SheetRoute.none
    @State private var selectedTab = AppTab.home
    @State private var heartFlights: [RouteHeartFlight] = []
    @State private var pendingHeartCount = 0
    @State private var outgoingHeartCycleCount = 0
    @State private var isHeartButtonDisabled = false
    @State private var heartSequence = 0
    @State private var heartSendTask: Task<Void, Never>?
    @State private var outgoingHeartCycleResetTask: Task<Void, Never>?
    @State private var heartCooldownTask: Task<Void, Never>?
    @State private var signalToast: SignalEvent?
    @State private var signalToastDismissTask: Task<Void, Never>?
    @State private var selectedGlobeMarker: GlobeMarkerSelection?
    @State private var launchHoldElapsed = false
    @State private var globeMarkerOrder = GlobeMarkerOrder.mineOnLeft
    @State private var editingKeycap: EditingKeycap?
    @State private var weatherByCityID: [String: CurrentCityWeather] = [:]
    @State private var batteryMonitor = DeviceBatteryMonitor()
    @AppStorage("clockDisplayFormat") private var clockDisplayFormatRawValue =
        ClockDisplayFormat.twentyFourHour.rawValue
    @AppStorage("temperatureUnit") private var temperatureUnitRawValue =
        TemperatureUnit.celsius.rawValue
    // 보일지, 뛸지는 이 기기의 취향이라 기기에 남는다.
    // 어떤 하트인지만 연결에 올라가 두 사람이 같은 것을 본다.
    @AppStorage("showsRouteHeart") private var showsRouteHeart = true
    @AppStorage("animatesRouteHeart") private var animatesRouteHeart = true
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
            .animation(.easeInOut(duration: 0.3), value: isPreparingSession)
            // 세션 복원이 순식간에 끝나면 로고를 알아보기도 전에 화면이 넘어간다.
            // 하트가 한 번 다 밝아질 때까지는 붙잡아둔다.
            .task {
                try? await Task.sleep(for: LaunchView.brightenDuration)
                launchHoldElapsed = true
            }
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
            .task(id: "presence-\(scenePhase)-\(store.activeConnectionID?.uuidString ?? "none")") {
                await syncDevicePresence()
            }
            .task(id: weatherSyncID) { await syncWeather() }
            .onChange(of: selectedTab) { _, tab in
                if tab != .home {
                    selectedGlobeMarker = nil
                    signalToastDismissTask?.cancel()
                    signalToast = nil
                }
            }
            // Signal 기계는 시트가 아니라 오버레이다. iOS 26 시트는 배경 유리를 강제로
            // 그려서 기계 옆에 판이 남는데, 이건 기계만 화면 밑에서 올라와야 한다.
            // 기계를 넣었다 뺐다 하지 않고 화면 밖에 세워 둔 채 위치만 옮긴다.
            // 뷰를 만들고 텍스처를 굽는 일이 애니메이션 첫 프레임에 몰리면 그때만 끊긴다.
            .overlay { signalScrim }
            .overlay(alignment: .bottom) { signalMachine }
            .overlay { keycapEditor }
            .sheet(item: $route.sheetPresented) { destination in
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
            // 스크린샷용. `simctl launch ... -previewSheet signal`처럼 띄운다.
            .onAppear {
                guard store.isConnected else { return }
                switch UserDefaults.standard.string(forKey: "previewSheet") {
                case "signal": route = .signal
                case "keepsakes": selectedTab = .keepsakes
                case "us": selectedTab = .us
                case "settings": selectedTab = .settings
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
        } else if isPreparingSession {
            LaunchView().transition(.opacity)
        } else if backend.authenticatedUserID == nil {
            AppleSignInView(backend: backend)
        } else if store.isConnected {
            connectedApp
        } else {
            ConnectionOnboardingView(
                store: store,
                suggestedName: backend.suggestedDisplayName
            )
        }
    }

    /// 저장된 로그인을 복원하는 동안과, 그 뒤 연결 정보를 받아오는 동안.
    /// 두 단계를 한 조건으로 묶어야 그 사이에 로그인 화면이 한 번 스쳐 지나가지 않는다.
    /// `.signingIn`은 여기서 제외한다. 그건 사람이 버튼을 누른 뒤라 로그인 화면에서 답해야 한다.
    private var isPreparingSession: Bool {
        guard launchHoldElapsed else { return true }

        switch backend.state {
        case .idle, .restoring:
            return true
        default:
            return backend.authenticatedUserID != nil && !store.backendIsReady
        }
    }

    private var connectedApp: some View {
        TabView(selection: $selectedTab) {
            Tab(value: AppTab.home) {
                home
            } label: {
                Image(systemName: "globe.asia.australia.fill")
                    .accessibilityLabel("홈")
            }

            Tab(value: AppTab.keepsakes) {
                KeepsakesView(
                    store: store,
                    now: now,
                    presentedAsSheet: false
                ) { parcel in
                    route = .letter(parcel)
                }
            } label: {
                Image(systemName: "archivebox")
                    .accessibilityLabel("간직함")
            }

            Tab(value: AppTab.us) {
                UsView(store: store, presentedAsSheet: false)
            } label: {
                Image(systemName: "person.2")
                    .accessibilityLabel("우리")
            }

            Tab(value: AppTab.settings) {
                SettingsView(
                    store: store,
                    clockFormat: clockDisplayFormatBinding,
                    temperatureUnit: temperatureUnitBinding,
                    showsRouteHeart: $showsRouteHeart,
                    animatesRouteHeart: $animatesRouteHeart,
                    routeHeartEmoji: routeHeartEmojiBinding
                )
            } label: {
                Image(systemName: "gearshape")
                    .accessibilityLabel("설정")
            }
        }
        .statusBarHidden(selectedTab == .home)
    }

    private var home: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                ClockRow(
                    store: store,
                    now: now,
                    markerOrder: globeMarkerOrder,
                    clockFormat: clockDisplayFormat,
                    temperatureUnit: temperatureUnit,
                    weatherByCityID: weatherByCityID
                )
                    .padding(.horizontal, Metric.screenPadding)
                    .padding(.bottom, Metric.m)

                ZStack {
                    GlobeMapView(
                        myMarker: myGlobeMarker,
                        partnerMarker: partnerGlobeMarker,
                        markerOrder: $globeMarkerOrder,
                        selection: $selectedGlobeMarker,
                        showsRouteHeart: showsRouteHeart,
                        animatesRouteHeart: animatesRouteHeart,
                        routeHeartEmoji: routeHeartEmoji.rawValue,
                        heartFlights: heartFlights
                    )

                    if let signalToast {
                        PartnerSignalToast(
                            event: signalToast,
                            partnerName: store.partnerProfile?.displayName ?? "상대",
                            now: now
                        )
                        .padding(.top, Metric.m)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    Actions(
                        heartPulse: heartSequence,
                        isHeartDisabled: isHeartButtonDisabled,
                        currentSignal: store.latestSignal(.outgoing, at: now)?.signal,
                        onHeart: queueHeart,
                        onSignal: { route = .signal }
                    )
                    .padding(.horizontal, Metric.screenPadding)
                    .padding(.bottom, Metric.xl)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .clipped()
            }
            .overlay(alignment: .bottom) {
                Color.black.frame(height: 1)
            }

        }
        .background(Palette.spaceDeep.ignoresSafeArea())
    }

    private var myGlobeMarker: GlobeProfileMarker {
        GlobeProfileMarker(
            id: .mine,
            displayName: store.myProfile?.displayName ?? "나",
            city: store.homeCity,
            avatarData: store.myProfile.flatMap { store.avatarData(for: $0) },
            signal: store.latestSignal(.outgoing, at: now)?.signal,
            battery: GlobeBatteryDisplay(presence: store.myDevicePresence, at: now)
        )
    }

    private var partnerGlobeMarker: GlobeProfileMarker {
        GlobeProfileMarker(
            id: .partner,
            displayName: store.partnerProfile?.displayName ?? "상대",
            city: store.partnerCity,
            avatarData: store.partnerProfile.flatMap { store.avatarData(for: $0) },
            signal: store.latestSignal(.incoming, at: now)?.signal,
            battery: GlobeBatteryDisplay(presence: store.partnerDevicePresence, at: now)
        )
    }

    private var clockDisplayFormat: ClockDisplayFormat {
        ClockDisplayFormat(rawValue: clockDisplayFormatRawValue) ?? .twentyFourHour
    }

    private var clockDisplayFormatBinding: Binding<ClockDisplayFormat> {
        Binding(
            get: { clockDisplayFormat },
            set: { clockDisplayFormatRawValue = $0.rawValue }
        )
    }

    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRawValue) ?? .celsius
    }

    private var temperatureUnitBinding: Binding<TemperatureUnit> {
        Binding(
            get: { temperatureUnit },
            set: { temperatureUnitRawValue = $0.rawValue }
        )
    }

    private var routeHeartEmoji: RouteHeartEmoji {
        RouteHeartEmoji(rawValue: store.routeHeartEmoji) ?? .red
    }

    private var routeHeartEmojiBinding: Binding<RouteHeartEmoji> {
        Binding(
            get: { routeHeartEmoji },
            set: { store.setRouteHeartEmoji($0.rawValue) }
        )
    }

    private var weatherSyncID: String {
        [
            String(describing: scenePhase),
            store.homeCity.id,
            String(store.homeCity.latitude),
            String(store.homeCity.longitude),
            store.partnerCity.id,
            String(store.partnerCity.latitude),
            String(store.partnerCity.longitude)
        ].joined(separator: "|")
    }

    // MARK: - Sheets

    private var isSignalOpen: Bool { route.presented == .signal }

    /// 화면 밖에서 끌어올리는 방식은 한 프레임에 46pt씩 움직인다. 프레임 하나만 빠져도
    /// 기계가 90pt 넘게 점프해 그대로 눈에 걸린다. 거리를 24pt로 줄이고 나타나는 일은
    /// 투명도에 맡긴다. 투명도는 값이 건너뛰어도 "틀린 자리"로 보이지 않는다.
    private var signalMachineMotion: Animation {
        isSignalOpen
            ? .easeOut(duration: 0.24)
            : .easeIn(duration: 0.16)
    }

    /// 떠오르는 높이. 물건이 올라온다는 인상만 남기고 거리는 최소로 둔다.
    private static let signalMachineRise: CGFloat = 40

    /// 기계 밖을 누르면 내려간다. 지구를 가리지 않게 옅게만 덮는다.
    private var signalScrim: some View {
        Color.black
            .opacity(isSignalOpen ? 0.28 : 0)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { route = .none }
            .allowsHitTesting(isSignalOpen)
            .animation(signalMachineMotion, value: isSignalOpen)
    }

    /// 키캡 하나를 바꾸는 패널. 기계보다 위에, 화면 전체를 덮는다.
    @ViewBuilder
    private var keycapEditor: some View {
        if let editingKeycap {
            KeycapEditorPanel(target: editingKeycap) {
                self.editingKeycap = nil
            } onSave: { key in
                store.setSignalKey(key, at: editingKeycap.index)
                self.editingKeycap = nil
            }
            .transition(.opacity)
        }
    }

    /// 시트가 아니라 오버레이로 올라오는 Signal 기계.
    private var signalMachine: some View {
        SignalPickerSheet(
            keys: store.signalKeys,
            isPresented: isSignalOpen,
            partnerName: store.partnerProfile?.displayName ?? "상대",
            partnerCityName: store.partnerCity.name,
            partnerClock: SignalPickerSheet.clock(in: store.partnerCity.timeZone, at: now),
            timeOffset: SignalPickerSheet.offset(
                from: store.homeCity.timeZone,
                to: store.partnerCity.timeZone,
                at: now
            ),
            distanceKilometers: store.distanceKilometers,
            // 내려가는 것은 기계가 확인을 한 박자 보여준 뒤 스스로 한다.
            onSelect: { signal in
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                // 상대에게는 즉시 보내되, 내 아이콘만 기계가 내려간 뒤 바뀐다.
                Task {
                    _ = await store.sendSignal(
                        signal,
                        localDisplayDelay: .milliseconds(900)
                    )
                }
            },
            onEditKey: { index in
                guard store.signalKeys.indices.contains(index) else { return }
                editingKeycap = EditingKeycap(index: index, key: store.signalKeys[index])
            },
            onDismiss: { route = .none }
        )
        // 닫혀 있을 때도 제자리에 그대로 서 있다. 여는 프레임에 뷰 생성이나
        // 텍스처 굽기가 끼어들지 않는다.
        .offset(y: isSignalOpen ? 0 : Self.signalMachineRise)
        .opacity(isSignalOpen ? 1 : 0)
        .allowsHitTesting(isSignalOpen)
        .animation(signalMachineMotion, value: isSignalOpen)
    }

    @ViewBuilder
    private func sheet(for destination: SheetRoute.Destination) -> some View {
        switch destination {
        case .signal:
            EmptyView()

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

    private func queueHeart() {
        guard store.isConnected,
              !isHeartButtonDisabled,
              outgoingHeartCycleCount < 30 else { return }

        outgoingHeartCycleCount += 1
        pendingHeartCount = min(pendingHeartCount + 1, 30)
        emitHeart(incoming: false)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.78)

        outgoingHeartCycleResetTask?.cancel()
        if outgoingHeartCycleCount == 30 {
            beginHeartCooldown()
        } else {
            outgoingHeartCycleResetTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                outgoingHeartCycleCount = 0
                outgoingHeartCycleResetTask = nil
            }
        }

        heartSendTask?.cancel()
        heartSendTask = Task {
            if outgoingHeartCycleCount < 30 {
                try? await Task.sleep(for: .milliseconds(700))
            }
            guard !Task.isCancelled else { return }
            await flushPendingHearts()
        }
    }

    /// 채운 직후부터 31번째 입력을 막고, 30번째 하트가 도착해 터지면 바로 푼다.
    private func beginHeartCooldown() {
        isHeartButtonDisabled = true
        outgoingHeartCycleResetTask?.cancel()
        outgoingHeartCycleResetTask = nil
        heartCooldownTask?.cancel()
        heartCooldownTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_600))
            guard !Task.isCancelled else { return }
            outgoingHeartCycleCount = 0
            isHeartButtonDisabled = false
            heartCooldownTask = nil
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
        for _ in 0..<burst.count {
            guard !Task.isCancelled else { return }
            emitHeart(incoming: true)
            try? await Task.sleep(for: .milliseconds(110))
        }
    }

    private func syncSignals() async {
        guard !isDebugSession, scenePhase == .active, store.isConnected else { return }

        while !Task.isCancelled {
            let received = await store.refreshSignals()
            if let newest = received.max(by: { $0.sentAt < $1.sentAt }) {
                showSignalToast(newest)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            try? await Task.sleep(for: .seconds(4))
        }
    }

    private func showSignalToast(_ event: SignalEvent) {
        signalToastDismissTask?.cancel()
        withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
            signalToast = event
        }
        signalToastDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, signalToast?.id == event.id else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                signalToast = nil
            }
        }
    }

    private func syncProfiles() async {
        guard !isDebugSession, scenePhase == .active, store.isConnected else { return }

        while !Task.isCancelled {
            await store.refreshConnection()
            try? await Task.sleep(for: .seconds(30))
        }
    }

    /// foreground·연결 상태 동안만 배터리를 관찰한다.
    /// 상태 변화는 monitor 콜백이 즉시 올리고, 같은 값의 주기 갱신은 store가 5분으로 제한한다.
    /// DEBUG 시뮬레이터 계정도 이 경로를 그대로 타되 store가 fixture로 응답한다.
    private func syncDevicePresence() async {
        guard scenePhase == .active, store.isConnected else {
            batteryMonitor.stop()
            return
        }

        batteryMonitor.onChange = { reading in
            Task { await store.publishDevicePresence(reading) }
        }
        batteryMonitor.start()

        while !Task.isCancelled {
            if let reading = batteryMonitor.currentReading {
                await store.publishDevicePresence(reading)
            }
            await store.refreshPartnerDevicePresence()
            try? await Task.sleep(for: .seconds(30))
        }
        batteryMonitor.stop()
    }

    private func syncWeather() async {
        guard scenePhase == .active, store.isConnected else { return }

        while !Task.isCancelled {
            await refreshWeather()
            do {
                try await Task.sleep(for: .seconds(15 * 60))
            } catch {
                return
            }
        }
    }

    private func refreshWeather() async {
        let homeCity = store.homeCity
        let partnerCity = store.partnerCity
        let service = WeatherService()

        async let homeResult = try? service.currentWeather(for: homeCity)
        async let partnerResult = try? service.currentWeather(for: partnerCity)
        let (homeWeather, partnerWeather) = await (homeResult, partnerResult)

        if let homeWeather {
            weatherByCityID[homeCity.id] = homeWeather
        }
        if let partnerWeather {
            weatherByCityID[partnerCity.id] = partnerWeather
        }
    }

    private func emitHeart(incoming: Bool) {
        heartSequence += 1
        let flight = RouteHeartFlight(incoming: incoming)
        heartFlights.append(flight)

        Task {
            try? await Task.sleep(for: .milliseconds(1_600))
            heartFlights.removeAll { $0.id == flight.id }
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

// MARK: - Clock

/// 두 사람의 지금. 상자도 구분선도 없이 글자만 둔다.
private struct ClockRow: View {
    let store: WayToYouStore
    let now: Date
    let markerOrder: GlobeMarkerOrder
    let clockFormat: ClockDisplayFormat
    let temperatureUnit: TemperatureUnit
    let weatherByCityID: [String: CurrentCityWeather]

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            clock(markerOrder.left, edge: .leading)
            Spacer(minLength: Metric.l)
            clock(markerOrder.right, edge: .trailing)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func city(for markerID: GlobeProfileMarker.ID) -> CoupleCity {
        markerID == .mine ? store.homeCity : store.partnerCity
    }

    private func clock(
        _ markerID: GlobeProfileMarker.ID,
        edge: Alignment
    ) -> some View {
        let city = city(for: markerID)
        let timeText = clockFormat.text(for: now, in: city.timeZone)
        return VStack(alignment: .center, spacing: 2) {
            Text(city.name)
                .font(.rounded(.caption2, .medium))
                .foregroundStyle(Palette.textTertiary)
                .tracking(1.4)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(timeText)
                    .font(.system(size: 25, weight: .bold, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.38), value: timeText)

                if let offset = dayOffsetLabel(for: city) {
                    Text(offset)
                        .font(.rounded(.caption2, .medium))
                        .foregroundStyle(Palette.textTertiary)
                }
            }

            weatherRow(for: city)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: edge)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(clockAccessibilityLabel(for: city, timeText: timeText))
    }

    private func clockAccessibilityLabel(
        for city: CoupleCity,
        timeText: String
    ) -> String {
        guard let weather = weatherByCityID[city.id] else {
            return "\(city.name) \(timeText)"
        }
        return "\(city.name) \(timeText), \(weather.conditionDescription), "
            + temperatureUnit.accessibilityTemperature(
                fromCelsius: weather.temperatureCelsius
            )
    }

    @ViewBuilder
    private func weatherRow(for city: CoupleCity) -> some View {
        if let weather = weatherByCityID[city.id] {
            let temperatureText = temperatureUnit.displayTemperature(
                fromCelsius: weather.temperatureCelsius
            )
            HStack(spacing: 5) {
                Image(systemName: weather.symbolName)
                    .symbolRenderingMode(.multicolor)
                Text(temperatureText)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.38), value: temperatureText)
                    .foregroundStyle(Palette.textSecondary)
            }
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .frame(height: 18)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(weather.conditionDescription), "
                    + temperatureUnit.accessibilityTemperature(
                        fromCelsius: weather.temperatureCelsius
                    )
            )
        } else {
            Color.clear.frame(width: 1, height: 18)
        }
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

private struct PartnerSignalToast: View {
    let event: SignalEvent
    let partnerName: String
    let now: Date

    var body: some View {
        HStack(spacing: Metric.s) {
            Text(event.signal.emoji)
                .font(.title3)

            Text("\(partnerName) · \(event.sentAt.koreanRelative(to: now))")
                .font(.rounded(.footnote, .semibold))
                .foregroundStyle(Palette.textPrimary)
        }
        .padding(.horizontal, Metric.m)
        .frame(height: 38)
        .glassEffect(.regular, in: Capsule())
        .overlay { Capsule().strokeBorder(Palette.hairline, lineWidth: 0.5) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(partnerName), \(event.signal.title), \(event.sentAt.koreanRelative(to: now))"
        )
    }
}

// MARK: - Actions

/// 가장 가볍게 자주 주고받는, 홈의 두 가지 아이콘 액션.
private struct Actions: View {
    let heartPulse: Int
    let isHeartDisabled: Bool
    let currentSignal: CoupleSignal?
    let onHeart: () -> Void
    let onSignal: () -> Void

    var body: some View {
        HStack(spacing: Metric.m) {
            Button(action: onHeart) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.pink)
                    .symbolEffect(.bounce, value: heartPulse)
                    .frame(width: 46, height: 46)
            }
            .buttonStyle(.glass(.clear))
            .buttonBorderShape(.circle)
            .disabled(isHeartDisabled)
            .accessibilityLabel("Heart 보내기")
            .accessibilityHint(
                isHeartDisabled
                    ? "잠시 후 다시 보낼 수 있습니다"
                    : "30개까지 연속으로 상대에게 보낼 수 있습니다"
            )

            Button(action: onSignal) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 46, height: 46)
            }
            .buttonStyle(.glass(.clear))
            .buttonBorderShape(.circle)
            .accessibilityLabel(currentSignal.map { "내 Signal \($0.title). Signal 바꾸기" } ?? "Signal 보내기")
        }
    }
}

// MARK: - Routing

/// 시트를 하나의 상태로 모아서, 시트끼리 갈아탈 때 깜빡임이 없게 한다.
struct SheetRoute {
    enum Destination: Identifiable, Hashable {
        case signal
        case letter(Parcel)
        case keepsakes
        case us

        var id: String {
            switch self {
            case .signal: "signal"
            case .letter(let parcel): "letter-\(parcel.id)"
            case .keepsakes: "keepsakes"
            case .us: "us"
            }
        }
    }

    var presented: Destination?

    /// Signal은 시트가 아니라 오버레이로 올라오므로 시트 경로에서 빼 둔다.
    var sheetPresented: Destination? {
        get { presented == .signal ? nil : presented }
        set { presented = newValue }
    }

    static let none = SheetRoute(presented: nil)
    static let signal = SheetRoute(presented: .signal)
    static let keepsakes = SheetRoute(presented: .keepsakes)
    static let us = SheetRoute(presented: .us)
    static func letter(_ parcel: Parcel) -> SheetRoute { SheetRoute(presented: .letter(parcel)) }
}

#Preview("홈 화면 전체") {
    ContentView()
}
