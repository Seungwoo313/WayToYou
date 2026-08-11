import Foundation

// MARK: - Profiles

/// 서버 계정이 붙기 전에도 앱 전체가 같은 사용자 표현을 사용하도록 하는 최소 프로필.
struct UserProfile: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String
    var endpoint: RouteEndpoint

    init(id: UUID = UUID(), displayName: String, endpoint: RouteEndpoint) {
        self.id = id
        self.displayName = displayName
        self.endpoint = endpoint
    }

    var city: CoupleCity { endpoint.city.coupleCity }
    var cityID: String { endpoint.city.id }
    var airport: RouteAirport { endpoint.airport }
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
