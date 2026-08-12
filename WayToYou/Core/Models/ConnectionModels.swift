import Foundation

// MARK: - Profiles

/// 서버 계정이 붙기 전에도 앱 전체가 같은 사용자 표현을 사용하도록 하는 최소 프로필.
struct UserProfile: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String
    var city: RouteCity
    var defaultAirport: RouteAirport
    var avatarPath: String?
    var avatarUpdatedAt: Date?

    init(
        id: UUID = UUID(),
        displayName: String,
        city: RouteCity,
        defaultAirport: RouteAirport,
        avatarPath: String? = nil,
        avatarUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.city = city
        self.defaultAirport = defaultAirport
        self.avatarPath = avatarPath
        self.avatarUpdatedAt = avatarUpdatedAt
    }

    var mapCity: CoupleCity { city.coupleCity }
    var cityID: String { city.id }
}

// MARK: - Device Presence

enum DeviceBatteryState: String, Codable, Hashable {
    case charging
    case full
    case unplugged
}

/// 연결 상대에게만 보이는 기기 배터리 상태. 서버 timestamp 기준의 transient 값이라
/// 로컬에 저장하지 않고, 오래된 값은 실시간 수치처럼 보이지 않게 단계적으로 흐려진다.
struct DevicePresence: Codable, Hashable {
    let batteryLevel: Int
    let batteryState: DeviceBatteryState
    let updatedAt: Date

    enum Freshness: Hashable {
        /// 10분 이내. 그대로 보여준다.
        case fresh
        /// 10분~60분. muted 처리해 오래된 값임을 드러낸다.
        case stale
        /// 60분 이후. 수치를 숨긴다.
        case expired
    }

    func freshness(at date: Date) -> Freshness {
        let elapsed = date.timeIntervalSince(updatedAt)
        if elapsed < 10 * 60 { return .fresh }
        if elapsed < 60 * 60 { return .stale }
        return .expired
    }

    var isCharging: Bool {
        batteryState == .charging || batteryState == .full
    }
}

// MARK: - Connection

struct ConnectionInvite: Identifiable, Codable, Hashable {
    let id: UUID
    let code: String
    let createdByID: UUID
    let createdAt: Date
    let expiresAt: Date

    init(
        id: UUID = UUID(),
        code: String,
        createdByID: UUID,
        createdAt: Date,
        expiresAt: Date
    ) {
        self.id = id
        self.code = code
        self.createdByID = createdByID
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    func isExpired(at date: Date) -> Bool {
        date >= expiresAt
    }
}

struct CoupleConnection: Identifiable, Codable, Hashable {
    let id: UUID
    var members: [UserProfile]
    let connectedAt: Date

    init(id: UUID = UUID(), members: [UserProfile], connectedAt: Date) {
        self.id = id
        self.members = members
        self.connectedAt = connectedAt
    }

    func partner(for profileID: UUID) -> UserProfile? {
        members.first { $0.id != profileID }
    }
}

enum ConnectionStatus: Codable, Hashable {
    case notConnected
    case inviting(ConnectionInvite)
    case connected(CoupleConnection)
}

/// 이후 Supabase 구현으로 교체할 경계. 화면과 Store는 초대 코드 생성 방식을 모른다.
protocol ConnectionServicing {
    func makeInvite(for profile: UserProfile, at date: Date) -> ConnectionInvite
}

/// 서버를 붙이기 전 온보딩과 연결 상태 전환을 검증하기 위한 로컬 구현.
struct LocalConnectionService: ConnectionServicing {
    func makeInvite(for profile: UserProfile, at date: Date) -> ConnectionInvite {
        ConnectionInvite(
            code: String(format: "%06d", Int.random(in: 0...999_999)),
            createdByID: profile.id,
            createdAt: date,
            expiresAt: date.addingTimeInterval(24 * 60 * 60)
        )
    }
}
