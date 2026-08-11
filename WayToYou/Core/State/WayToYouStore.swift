import Foundation
import Observation
import Supabase
import SwiftUI

/// 앱의 단일 상태. 예전엔 @AppStorage 값 여덟 개가 뷰에 흩어져 있었고
/// 소포·시그널을 각각 한 개씩만 기억할 수 있었다. 여기서 전부 배열로 남긴다.
@Observable
final class WayToYouStore {
    private(set) var myProfile: UserProfile?
    private(set) var connectionStatus: ConnectionStatus
    private(set) var homeCityID: String
    private(set) var partnerCityID: String
    private(set) var parcels: [Parcel]
    private(set) var signals: [SignalEvent]
    private(set) var heartBursts: [HeartBurst]
    private(set) var backendIsReady = false
    private(set) var connectionIsWorking = false
    private(set) var connectionMessage: String?
    private(set) var heartMessage: String?
    private(set) var signalMessage: String?
    private(set) var avatarIsWorking = false
    private(set) var avatarMessage: String?
    private(set) var avatarDataByUserID: [UUID: Data] = [:]

    /// 서버가 없는 동안 상대 쪽 반응을 흉내 낸다.
    /// 배송 시간도 압축돼서 전체 루프를 몇 분 안에 볼 수 있다.
    var demoMode: Bool {
        didSet {
            guard demoMode != oldValue else { return }
            defaults.set(demoMode, forKey: storageKey(Key.demoMode))
        }
    }

    var homeCity: CoupleCity { myProfile?.city ?? CoupleCity.city(id: homeCityID) }
    var partnerCity: CoupleCity { partnerProfile?.city ?? CoupleCity.city(id: partnerCityID) }
    var partnerProfile: UserProfile? {
        guard let myProfile,
              case .connected(let connection) = connectionStatus else { return nil }
        return connection.partner(for: myProfile.id)
    }
    var isConnected: Bool {
        if case .connected = connectionStatus { return true }
        return false
    }
    var coupleRoute: CoupleRoute? {
        guard let mine = myProfile?.endpoint,
              let partner = partnerProfile?.endpoint else { return nil }
        return CoupleRoute(mine: mine, partner: partner)
    }

    private let defaults: UserDefaults
    private let localConnectionService: any ConnectionServicing
    private var backendConnectionService: SupabaseConnectionService?
    private var activeUserID: UUID?
    private var hasSyncedHearts = false
    private var hasSyncedSignals = false
    private var avatarRevisionByUserID: [UUID: String] = [:]
    #if DEBUG
    private var debugAccount: DebugAccount?
    #endif

    private enum Key {
        static let myProfile = "wty.myProfile"
        static let connectionStatus = "wty.connectionStatus"
        static let home = "wty.homeCityID"
        static let partner = "wty.partnerCityID"
        static let parcels = "wty.parcels"
        static let signals = "wty.signals"
        static let heartBursts = "wty.heartBursts"
        static let demoMode = "wty.demoMode"
    }

    /// 데모 모드 타이밍. 실제 모드에서는 거리 기반 시간을 그대로 쓴다.
    private enum Demo {
        static let flightDuration: TimeInterval = 100
        static let partnerOpensAfter: TimeInterval = 18
        static let replyLeavesAfter: TimeInterval = 22
    }

    private enum Live {
        static let partnerOpensAfter: TimeInterval = 45 * 60
        static let replyLeavesAfter: TimeInterval = 3 * 60 * 60
    }

    init(
        defaults: UserDefaults = .standard,
        connectionService: any ConnectionServicing = LocalConnectionService()
    ) {
        self.defaults = defaults
        self.localConnectionService = connectionService
        myProfile = Self.decode(UserProfile.self, from: defaults.data(forKey: Key.myProfile))
        connectionStatus = Self.decode(
            ConnectionStatus.self,
            from: defaults.data(forKey: Key.connectionStatus)
        ) ?? .notConnected
        homeCityID = defaults.string(forKey: Key.home) ?? "seoul"
        partnerCityID = defaults.string(forKey: Key.partner) ?? "paris"
        demoMode = defaults.object(forKey: Key.demoMode) as? Bool ?? true
        parcels = Self.decode([Parcel].self, from: defaults.data(forKey: Key.parcels)) ?? []
        signals = Self.decode([SignalEvent].self, from: defaults.data(forKey: Key.signals)) ?? []
        heartBursts = Self.decode([HeartBurst].self, from: defaults.data(forKey: Key.heartBursts)) ?? []

        if let myProfile {
            homeCityID = myProfile.cityID
        }
        if let partnerProfile = Self.partnerProfile(in: connectionStatus, for: myProfile?.id) {
            partnerCityID = partnerProfile.cityID
        }
        if case .inviting(let invitation) = connectionStatus,
           invitation.isExpired(at: .now) {
            connectionStatus = .notConnected
            defaults.set(Self.encode(connectionStatus), forKey: Key.connectionStatus)
        }
    }

    #if DEBUG
    convenience init(debugAccount: DebugAccount) {
        self.init(defaults: debugAccount.defaults)
        self.debugAccount = debugAccount

        let profile = debugAccount.profile
        let partner = debugAccount.partnerProfile
        activeUserID = profile.id
        myProfile = profile
        homeCityID = profile.cityID
        partnerCityID = partner.cityID
        connectionStatus = .connected(debugAccount.connection)
        backendIsReady = true
        demoMode = true
        save()
    }
    #endif

    // MARK: - Derived state

    /// 지금 하늘에 떠 있는 소포들. 오래된 것이 앞에 온다.
    func inFlight(at date: Date) -> [Parcel] {
        parcels.filter { $0.isActive(at: date) }.sorted { $0.arrivesAt < $1.arrivesAt }
    }

    /// 나에게 도착했지만 아직 열지 않은 소포.
    func waitingToOpen(at date: Date) -> [Parcel] {
        parcels
            .filter { $0.direction == .incoming && $0.phase(at: date) == .arrived }
            .sorted { $0.arrivesAt < $1.arrivesAt }
    }

    /// 최근에 연 편지 하나. 홈에서 "다시 읽기"로 노출한다.
    func lastOpenedIncoming() -> Parcel? {
        parcels
            .filter { $0.direction == .incoming && $0.openedAt != nil }
            .max { ($0.openedAt ?? .distantPast) < ($1.openedAt ?? .distantPast) }
    }

    func latestSignal(_ direction: ParcelDirection, at date: Date) -> SignalEvent? {
        signals
            .filter { $0.direction == direction && $0.isFresh(at: date) }
            .max { $0.sentAt < $1.sentAt }
    }

    func latestHeartBurst(_ direction: ParcelDirection, at date: Date) -> HeartBurst? {
        heartBursts
            .filter { $0.direction == direction && $0.isFresh(at: date) }
            .max { $0.sentAt < $1.sentAt }
    }

    /// 홈 상태 패널이 무엇을 보여줄지 한 곳에서 정한다.
    /// 급한 것부터: 열 소포 > 오는 중 > 보낸 게 가는 중 > 상대가 열어봄 > 조용함
    func focus(at date: Date) -> HomeFocus {
        if let waiting = waitingToOpen(at: date).first {
            return .readyToOpen(waiting)
        }
        let flying = inFlight(at: date)
        if let incoming = flying.first(where: { $0.direction == .incoming }) {
            return .incomingFlight(incoming)
        }
        if let outgoing = flying.first(where: { $0.direction == .outgoing }) {
            return .outgoingFlight(outgoing)
        }
        // 최근 24시간 안에 상대가 내 소포를 열어봤다면 그걸 알려준다.
        let recentlyRead = parcels
            .filter { $0.direction == .outgoing }
            .compactMap { parcel -> (Parcel, Date)? in
                guard let openedAt = parcel.openedAt, date.timeIntervalSince(openedAt) < 86_400 else { return nil }
                return (parcel, openedAt)
            }
            .max { $0.1 < $1.1 }
        if let recentlyRead {
            return .partnerRead(recentlyRead.0)
        }
        return .quiet
    }

    var distanceKilometers: Int {
        Int(CoupleDistance.distanceInKilometers(from: homeCity, to: partnerCity).rounded())
    }

    /// 두 사람의 시차. 상대가 나보다 몇 시간 뒤/앞인지.
    func timeDifferenceCaption(at date: Date) -> String {
        let mine = homeCity.timeZone.secondsFromGMT(for: date)
        let theirs = partnerCity.timeZone.secondsFromGMT(for: date)
        let delta = Double(theirs - mine) / 3_600
        if abs(delta) < 0.01 { return "같은 시간" }
        let magnitude = abs(delta)
        let text = magnitude == magnitude.rounded()
            ? "\(Int(magnitude))시간"
            : String(format: "%.1f시간", magnitude)
        return delta > 0 ? "\(text) 빠름" : "\(text) 느림"
    }

    func flightDuration() -> TimeInterval {
        demoMode ? Demo.flightDuration : CoupleDistance.deliveryDuration(from: homeCity, to: partnerCity)
    }

    func avatarData(for profile: UserProfile) -> Data? {
        avatarDataByUserID[profile.id]
    }

    // MARK: - Intents

    /// 인증 계정마다 로컬 캐시를 분리하고, 서버의 최신 프로필·연결 상태를 불러온다.
    func activateBackend(client: SupabaseClient, userID: UUID) async {
        backendIsReady = false
        backendConnectionService = SupabaseConnectionService(client: client)

        if activeUserID != userID {
            activeUserID = userID
            loadActiveUserState()
            avatarDataByUserID = [:]
            avatarRevisionByUserID = [:]
        }

        await refreshConnection()
        backendIsReady = true
    }

    func saveProfile(displayName: String, endpoint: RouteEndpoint) {
        let cleanedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return }

        if var profile = myProfile {
            profile.displayName = cleanedName
            profile.endpoint = endpoint
            myProfile = profile
        } else {
            myProfile = UserProfile(
                id: activeUserID ?? UUID(),
                displayName: cleanedName,
                endpoint: endpoint
            )
        }
        homeCityID = endpoint.city.id
        synchronizeMyProfileIntoConnection()
        save()
    }

    @discardableResult
    func saveProfileToBackend(displayName: String, endpoint: RouteEndpoint) async -> Bool {
        let cleanedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        #if DEBUG
        if debugAccount != nil {
            guard !cleanedName.isEmpty else { return false }
            saveProfile(displayName: cleanedName, endpoint: endpoint)
            return true
        }
        #endif
        guard !cleanedName.isEmpty, let backendConnectionService else { return false }

        connectionIsWorking = true
        connectionMessage = nil
        defer { connectionIsWorking = false }

        do {
            let profile = try await backendConnectionService.saveProfile(
                displayName: cleanedName,
                endpoint: endpoint
            )
            myProfile = profile
            homeCityID = profile.cityID
            synchronizeMyProfileIntoConnection()
            save()
            return true
        } catch {
            connectionMessage = Self.friendlyConnectionError(error)
            return false
        }
    }

    @discardableResult
    func uploadProfileAvatar(_ data: Data) async -> Bool {
        #if DEBUG
        if debugAccount != nil, var profile = myProfile {
            avatarIsWorking = true
            defer { avatarIsWorking = false }
            profile.avatarPath = "debug/\(profile.id.uuidString.lowercased())/avatar.jpg"
            profile.avatarUpdatedAt = .now
            applyMyProfile(profile)
            avatarDataByUserID[profile.id] = data
            avatarRevisionByUserID[profile.id] = Self.avatarRevision(for: profile)
            return true
        }
        #endif
        guard let backendConnectionService, let activeUserID else { return false }

        avatarIsWorking = true
        avatarMessage = nil
        defer { avatarIsWorking = false }

        do {
            let profile = try await backendConnectionService.uploadProfileAvatar(
                data: data,
                userID: activeUserID
            )
            applyMyProfile(profile)
            avatarDataByUserID[profile.id] = data
            avatarRevisionByUserID[profile.id] = Self.avatarRevision(for: profile)
            return true
        } catch {
            avatarMessage = Self.friendlyAvatarError(error)
            return false
        }
    }

    @discardableResult
    func clearProfileAvatar() async -> Bool {
        #if DEBUG
        if debugAccount != nil, var profile = myProfile {
            avatarIsWorking = true
            defer { avatarIsWorking = false }
            profile.avatarPath = nil
            profile.avatarUpdatedAt = .now
            applyMyProfile(profile)
            avatarDataByUserID.removeValue(forKey: profile.id)
            avatarRevisionByUserID.removeValue(forKey: profile.id)
            return true
        }
        #endif
        guard let backendConnectionService, let activeUserID else { return false }

        avatarIsWorking = true
        avatarMessage = nil
        defer { avatarIsWorking = false }

        do {
            let profile = try await backendConnectionService.clearProfileAvatar(userID: activeUserID)
            applyMyProfile(profile)
            avatarDataByUserID.removeValue(forKey: profile.id)
            avatarRevisionByUserID.removeValue(forKey: profile.id)
            return true
        } catch {
            avatarMessage = Self.friendlyAvatarError(error)
            return false
        }
    }

    func clearAvatarMessage() {
        avatarMessage = nil
    }

    func refreshProfileAvatars() async {
        guard let backendConnectionService else { return }

        let profiles = [myProfile, partnerProfile].compactMap { $0 }
        let activeIDs = Set(profiles.map(\.id))
        avatarDataByUserID = avatarDataByUserID.filter { activeIDs.contains($0.key) }
        avatarRevisionByUserID = avatarRevisionByUserID.filter { activeIDs.contains($0.key) }

        for profile in profiles {
            guard let path = profile.avatarPath else {
                avatarDataByUserID.removeValue(forKey: profile.id)
                avatarRevisionByUserID.removeValue(forKey: profile.id)
                continue
            }

            let revision = Self.avatarRevision(for: profile)
            guard avatarRevisionByUserID[profile.id] != revision else { continue }

            do {
                let remoteData = try await backendConnectionService.downloadProfileAvatar(
                    path: path,
                    updatedAt: profile.avatarUpdatedAt
                )
                let displayData = try ProfileAvatarProcessor.jpegData(from: remoteData)
                avatarDataByUserID[profile.id] = displayData
                avatarRevisionByUserID[profile.id] = revision
            } catch {
                // 네트워크가 잠깐 끊겨도 이미 표시 중인 사진은 유지한다.
            }
        }
    }

    func createInvitation() async {
        guard myProfile != nil, let backendConnectionService else { return }

        connectionIsWorking = true
        connectionMessage = nil
        defer { connectionIsWorking = false }

        do {
            connectionStatus = .inviting(try await backendConnectionService.createInvitation())
            save()
        } catch {
            connectionMessage = Self.friendlyConnectionError(error)
        }
    }

    func createPreviewInvitation(now: Date = .now) {
        guard let myProfile else { return }
        connectionStatus = .inviting(localConnectionService.makeInvite(for: myProfile, at: now))
        save()
    }

    func cancelInvitation() async {
        guard case .inviting(let invitation) = connectionStatus,
              let backendConnectionService else { return }

        connectionIsWorking = true
        connectionMessage = nil
        defer { connectionIsWorking = false }

        do {
            let state = try await backendConnectionService.cancelInvitation(id: invitation.id)
            applyRemoteConnectionState(state)
        } catch {
            connectionMessage = Self.friendlyConnectionError(error)
        }
    }

    @discardableResult
    func acceptInvitation(code: String) async -> Bool {
        guard let backendConnectionService else { return false }

        connectionIsWorking = true
        connectionMessage = nil
        defer { connectionIsWorking = false }

        do {
            let state = try await backendConnectionService.acceptInvitation(code: code)
            if let errorCode = state.error {
                connectionMessage = Self.friendlyConnectionError(code: errorCode)
                return false
            }
            applyRemoteConnectionState(state)
            await refreshProfileAvatars()
            return isConnected
        } catch {
            connectionMessage = Self.friendlyConnectionError(error)
            return false
        }
    }

    /// 초대를 만든 기기는 상대가 입력했는지 짧게 폴링해 자동으로 홈을 연다.
    func refreshConnection() async {
        guard !connectionIsWorking, let backendConnectionService else { return }

        do {
            let state = try await backendConnectionService.connectionState()
            applyRemoteConnectionState(state)
            await refreshProfileAvatars()
            connectionMessage = nil
        } catch {
            connectionMessage = Self.friendlyConnectionError(error)
        }
    }

    func sendParcel(title: String, message: String, wrap: ParcelWrap, now: Date = .now) {
        let parcel = Parcel(
            direction: .outgoing,
            title: title,
            message: message,
            wrap: wrap,
            fromCityID: homeCityID,
            toCityID: partnerCityID,
            sentAt: now,
            arrivesAt: now.addingTimeInterval(flightDuration())
        )
        parcels.append(parcel)
        save()
    }

    func open(_ parcel: Parcel, now: Date = .now) {
        guard let index = parcels.firstIndex(where: { $0.id == parcel.id }), parcels[index].openedAt == nil else { return }
        parcels[index].openedAt = now
        save()
    }

    @discardableResult
    func sendSignal(_ signal: CoupleSignal) async -> Bool {
        #if DEBUG
        if debugAccount != nil {
            let event = SignalEvent(
                id: UUID(),
                signal: signal,
                direction: .outgoing,
                sentAt: .now
            )
            signals.append(event)
            trimSignals()
            save()
            return true
        }
        #endif
        guard isConnected, let backendConnectionService, let activeUserID else { return false }

        signalMessage = nil

        do {
            let remote = try await backendConnectionService.sendSignal(signal)
            let event = SignalEvent(
                id: remote.id,
                signal: remote.signal,
                direction: remote.senderID == activeUserID ? .outgoing : .incoming,
                sentAt: remote.sentAt
            )
            if !signals.contains(where: { $0.id == event.id }) {
                signals.append(event)
                trimSignals()
                save()
            }
            return true
        } catch {
            signalMessage = Self.friendlySignalError(error)
            return false
        }
    }

    /// 앱이 활성화된 동안 두 사람의 최근 상태를 동기화한다.
    /// 최초 동기화는 과거 알림을 울리지 않고, 이후 새로 온 상태만 반환한다.
    @discardableResult
    func refreshSignals() async -> [SignalEvent] {
        guard isConnected, let backendConnectionService, let activeUserID else { return [] }

        do {
            let previousIDs = Set(signals.map(\.id))
            let remote = try await backendConnectionService.listSignals()
            let fetched = remote.map { event in
                SignalEvent(
                    id: event.id,
                    signal: event.signal,
                    direction: event.senderID == activeUserID ? .outgoing : .incoming,
                    sentAt: event.sentAt
                )
            }
            let receivedSignals = hasSyncedSignals ? fetched.filter {
                $0.direction == .incoming && !previousIDs.contains($0.id)
            } : []
            signals = fetched
            hasSyncedSignals = true
            trimSignals()
            save()
            return receivedSignals
        } catch {
            return []
        }
    }

    func clearSignalMessage() {
        signalMessage = nil
    }

    @discardableResult
    func sendHeartBurst(count: Int) async -> Bool {
        #if DEBUG
        if debugAccount != nil {
            let burst = HeartBurst(
                id: UUID(),
                direction: .outgoing,
                count: min(max(count, 1), 50),
                sentAt: .now
            )
            heartBursts.append(burst)
            trimHeartBursts()
            save()
            return true
        }
        #endif
        guard isConnected, let backendConnectionService, let activeUserID else { return false }
        let boundedCount = min(max(count, 1), 50)

        heartMessage = nil

        do {
            let remote = try await backendConnectionService.sendHeartBurst(count: boundedCount)
            let burst = HeartBurst(
                id: remote.id,
                direction: remote.senderID == activeUserID ? .outgoing : .incoming,
                count: remote.count,
                sentAt: remote.sentAt
            )
            if !heartBursts.contains(where: { $0.id == burst.id }) {
                heartBursts.append(burst)
                trimHeartBursts()
                save()
            }
            return true
        } catch {
            heartMessage = Self.friendlyHeartError(error)
            return false
        }
    }

    /// 앱이 활성화된 동안 서버의 최근 Heart Burst를 가볍게 동기화한다.
    /// 읽음 상태는 만들지 않고, 새로 도착했는지만 호출자에게 알려준다.
    @discardableResult
    func refreshHeartBursts() async -> [HeartBurst] {
        guard isConnected, let backendConnectionService, let activeUserID else { return [] }

        do {
            let previousIDs = Set(heartBursts.map(\.id))
            let remote = try await backendConnectionService.listHeartBursts()
            let fetched = remote.map { burst in
                HeartBurst(
                    id: burst.id,
                    direction: burst.senderID == activeUserID ? .outgoing : .incoming,
                    count: burst.count,
                    sentAt: burst.sentAt
                )
            }
            let receivedBursts = hasSyncedHearts ? fetched.filter {
                $0.direction == .incoming && !previousIDs.contains($0.id)
            } : []
            heartBursts = fetched
            hasSyncedHearts = true
            trimHeartBursts()
            save()
            return receivedBursts
        } catch {
            return []
        }
    }

    func clearHeartMessage() {
        heartMessage = nil
    }

    func clearHistory() {
        parcels = []
        signals = []
        heartBursts = []
        save()
    }

    // MARK: - Demo simulation

    /// 저장된 타임스탬프만 보고 상대의 다음 행동을 결정한다.
    /// 난수를 쓰지 않으므로 앱을 껐다 켜도 같은 결과가 나온다.
    /// 서버가 붙기 전까지는 실제 모드에서도 상대를 흉내 내야 앱이 성립한다.
    /// demoMode는 그 반응이 얼마나 빨리 오는지만 바꾼다.
    func advance(to now: Date) {
        var changed = false

        let opensAfter = demoMode ? Demo.partnerOpensAfter : Live.partnerOpensAfter
        let replyAfter = demoMode ? Demo.replyLeavesAfter : Live.replyLeavesAfter

        // 1. 상대가 내 소포를 열어본다.
        for index in parcels.indices
        where parcels[index].direction == .outgoing && parcels[index].openedAt == nil {
            let openMoment = parcels[index].arrivesAt.addingTimeInterval(opensAfter)
            if now >= openMoment {
                parcels[index].openedAt = openMoment
                changed = true
            }
        }

        // 2. 열어본 소포마다 답장이 한 번 출발한다.
        let alreadyReplied = Set(parcels.compactMap(\.replyToID))
        let pendingReplies = parcels.filter { parcel in
            parcel.direction == .outgoing
                && parcel.openedAt != nil
                && !alreadyReplied.contains(parcel.id)
        }
        for origin in pendingReplies {
            guard let openedAt = origin.openedAt else { continue }
            let departure = openedAt.addingTimeInterval(replyAfter)
            guard now >= departure else { continue }
            parcels.append(makeReply(to: origin, departingAt: departure))
            changed = true
        }

        if changed {
            trimSignals()
            save()
        }
    }

    private func makeReply(to origin: Parcel, departingAt departure: Date) -> Parcel {
        let letter = Self.replyLetters[parcels.count % Self.replyLetters.count]
        let duration = demoMode
            ? Demo.flightDuration
            : CoupleDistance.deliveryDuration(from: origin.toCity, to: origin.fromCity)
        return Parcel(
            direction: .incoming,
            title: letter.title,
            message: letter.body,
            wrap: Self.replyWraps[parcels.count % Self.replyWraps.count],
            fromCityID: origin.toCityID,
            toCityID: origin.fromCityID,
            sentAt: departure,
            arrivesAt: departure.addingTimeInterval(duration),
            replyToID: origin.id,
            isSimulated: true
        )
    }

    private static let replyWraps: [ParcelWrap] = [.lavender, .sage, .midnight, .coral]

    private static let replyLetters: [(title: String, body: String)] = [
        (
            "잘 받았어",
            "소포가 도착한 날, 하루 종일 기분이 좋았어. 상자를 여는 데 한참 걸렸어. 열면 끝나버릴 것 같아서.\n\n여기는 요즘 해가 늦게 져. 창밖이 오래 밝아서, 그만큼 네 생각을 더 오래 해."
        ),
        (
            "오늘의 창밖",
            "아침에 비가 왔어. 우산을 안 챙겨서 그냥 맞고 걸었는데 생각보다 나쁘지 않더라.\n\n너랑 같이 걸었으면 분명히 웃었을 거야. 다음엔 같은 우산을 쓰자."
        ),
        (
            "시차 없는 곳",
            "우리 사이엔 시차가 있지만, 자기 전에 하는 생각은 늘 같은 것 같아.\n\n네가 아침을 먹을 때 나는 잠들고, 내가 눈을 뜰 때 너는 하루를 정리하겠지. 그렇게 하루를 이어 붙이면 우리는 계속 같이 있는 셈이야."
        ),
        (
            "작은 것들",
            "오늘 길에서 네가 좋아하는 색을 봤어. 사진을 찍어두려다가 그냥 오래 봤어.\n\n말로 옮기면 사라지는 것들이 있어서, 이번엔 그냥 기억해두기로 했어. 만나면 얘기해줄게."
        ),
        (
            "곧 만나",
            "달력을 자꾸 보게 돼. 남은 날짜를 세는 게 습관이 됐어.\n\n기다리는 게 힘들지 않다고는 못 하겠지만, 기다릴 사람이 있다는 게 좋아. 그때까지 잘 지내고 있어."
        )
    ]

    // MARK: - Persistence

    private func trimSignals() {
        signals.sort { $0.sentAt < $1.sentAt }
        if signals.count > 120 {
            signals.removeFirst(signals.count - 120)
        }
    }

    private func trimHeartBursts() {
        heartBursts.sort { $0.sentAt < $1.sentAt }
        if heartBursts.count > 40 {
            heartBursts.removeFirst(heartBursts.count - 40)
        }
    }

    private func save() {
        defaults.set(Self.encode(myProfile), forKey: storageKey(Key.myProfile))
        defaults.set(Self.encode(connectionStatus), forKey: storageKey(Key.connectionStatus))
        defaults.set(homeCityID, forKey: storageKey(Key.home))
        defaults.set(partnerCityID, forKey: storageKey(Key.partner))
        defaults.set(Self.encode(parcels), forKey: storageKey(Key.parcels))
        defaults.set(Self.encode(signals), forKey: storageKey(Key.signals))
        defaults.set(Self.encode(heartBursts), forKey: storageKey(Key.heartBursts))
    }

    private static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func synchronizeMyProfileIntoConnection() {
        guard let myProfile,
              case .connected(var connection) = connectionStatus else { return }
        connection.members = connection.members.map { member in
            member.id == myProfile.id ? myProfile : member
        }
        connectionStatus = .connected(connection)
    }

    private func applyMyProfile(_ profile: UserProfile) {
        myProfile = profile
        homeCityID = profile.cityID
        synchronizeMyProfileIntoConnection()
        save()
    }

    private static func avatarRevision(for profile: UserProfile) -> String {
        let timestamp = profile.avatarUpdatedAt?.timeIntervalSince1970 ?? 0
        return "\(profile.avatarPath ?? "none")|\(timestamp)"
    }

    private func storageKey(_ base: String) -> String {
        guard let activeUserID else { return base }
        return "wty.user.\(activeUserID.uuidString).\(base)"
    }

    private func loadActiveUserState() {
        myProfile = Self.decode(UserProfile.self, from: defaults.data(forKey: storageKey(Key.myProfile)))
        connectionStatus = Self.decode(
            ConnectionStatus.self,
            from: defaults.data(forKey: storageKey(Key.connectionStatus))
        ) ?? .notConnected
        homeCityID = defaults.string(forKey: storageKey(Key.home)) ?? "seoul"
        partnerCityID = defaults.string(forKey: storageKey(Key.partner)) ?? "paris"
        demoMode = defaults.object(forKey: storageKey(Key.demoMode)) as? Bool ?? true
        parcels = Self.decode([Parcel].self, from: defaults.data(forKey: storageKey(Key.parcels))) ?? []
        signals = Self.decode([SignalEvent].self, from: defaults.data(forKey: storageKey(Key.signals))) ?? []
        heartBursts = Self.decode(
            [HeartBurst].self,
            from: defaults.data(forKey: storageKey(Key.heartBursts))
        ) ?? []
        hasSyncedHearts = false
        hasSyncedSignals = false

        if let myProfile {
            homeCityID = myProfile.cityID
        }
        if let partner = Self.partnerProfile(in: connectionStatus, for: myProfile?.id) {
            partnerCityID = partner.cityID
        }
        if case .inviting(let invitation) = connectionStatus,
           invitation.isExpired(at: .now) {
            connectionStatus = .notConnected
        }
    }

    private func applyRemoteConnectionState(_ state: RemoteConnectionState) {
        if let profile = state.me?.profile {
            myProfile = profile
            homeCityID = profile.cityID
        }

        switch state.status {
        case "connected":
            guard let me = state.me?.profile,
                  let partner = state.partner?.profile,
                  let connectionID = state.connectionID,
                  let connectedAt = state.connectedAt else { return }
            myProfile = me
            homeCityID = me.cityID
            partnerCityID = partner.cityID
            connectionStatus = .connected(
                CoupleConnection(
                    id: connectionID,
                    members: [me, partner],
                    connectedAt: connectedAt
                )
            )

        case "inviting":
            if case .inviting(let localInvite) = connectionStatus,
               localInvite.id == state.inviteID,
               !localInvite.isExpired(at: .now) {
                connectionStatus = .inviting(localInvite)
            } else {
                // 서버는 코드를 해시로만 보관하므로, 이 기기에 원문이 없으면 새 코드를 만든다.
                connectionStatus = .notConnected
            }

        default:
            connectionStatus = .notConnected
        }

        save()
    }

    private static func friendlyConnectionError(_ error: Error) -> String {
        if let postgrestError = error as? PostgrestError {
            return friendlyConnectionError(code: postgrestError.message)
        }
        return "연결 상태를 확인하지 못했어요. 잠시 후 다시 시도해주세요."
    }

    private static func friendlyConnectionError(code: String) -> String {
        switch code {
        case "invalid_code":
            "코드가 올바르지 않거나 만료됐어요."
        case "rate_limited":
            "입력 횟수가 많아요. 10분 뒤 다시 시도해주세요."
        case "already_connected":
            "이미 다른 상대와 연결되어 있어요."
        case "profile_required":
            "먼저 내 이름과 도시를 저장해주세요."
        case "invalid_display_name", "invalid_city":
            "입력한 프로필 정보를 다시 확인해주세요."
        default:
            "서버 연결을 완료하지 못했어요. 잠시 후 다시 시도해주세요."
        }
    }

    private static func friendlyHeartError(_ error: Error) -> String {
        if let postgrestError = error as? PostgrestError,
           postgrestError.message == "connection_required" {
            return "상대와 연결된 뒤 Heart를 보낼 수 있어요."
        }
        return "Heart를 보내지 못했어요. 잠시 후 다시 시도해주세요."
    }

    private static func friendlySignalError(_ error: Error) -> String {
        if let postgrestError = error as? PostgrestError {
            switch postgrestError.message {
            case "connection_required":
                return "상대와 연결된 뒤 Signal을 보낼 수 있어요."
            case "invalid_signal_type":
                return "Signal 종류를 다시 선택해주세요."
            default:
                break
            }
        }
        return "Signal을 보내지 못했어요. 잠시 후 다시 시도해주세요."
    }

    private static func friendlyAvatarError(_ error: Error) -> String {
        if let postgrestError = error as? PostgrestError {
            switch postgrestError.message {
            case "profile_required":
                return "이름과 도시를 먼저 저장해주세요."
            case "avatar_upload_required":
                return "사진 업로드가 완료되지 않았어요. 다시 선택해주세요."
            default:
                break
            }
        }
        return "프로필 사진을 저장하지 못했어요. 잠시 후 다시 시도해주세요."
    }

    private static func partnerProfile(
        in status: ConnectionStatus,
        for profileID: UUID?
    ) -> UserProfile? {
        guard let profileID,
              case .connected(let connection) = status else { return nil }
        return connection.partner(for: profileID)
    }
}

/// 홈 상태 패널이 그릴 한 가지 상황.
enum HomeFocus: Hashable {
    case quiet
    case outgoingFlight(Parcel)
    case incomingFlight(Parcel)
    case readyToOpen(Parcel)
    case partnerRead(Parcel)

    var parcel: Parcel? {
        switch self {
        case .quiet: nil
        case .outgoingFlight(let parcel), .incomingFlight(let parcel),
             .readyToOpen(let parcel), .partnerRead(let parcel):
            parcel
        }
    }
}
