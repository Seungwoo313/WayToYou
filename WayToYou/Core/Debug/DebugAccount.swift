#if DEBUG
import Foundation

/// 시뮬레이터 UI 개발용 가상 계정. Release 빌드에는 이 타입 자체가 포함되지 않는다.
enum DebugAccount: String, CaseIterable {
    case mina
    case sofia

    static var launched: DebugAccount? {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil,
              let value = UserDefaults.standard.string(forKey: "debugAccount") else {
            return nil
        }
        return DebugAccount(rawValue: value.lowercased())
    }

    var profile: UserProfile {
        switch self {
        case .mina: Self.minaProfile
        case .sofia: Self.sofiaProfile
        }
    }

    var partnerProfile: UserProfile {
        switch self {
        case .mina: Self.sofiaProfile
        case .sofia: Self.minaProfile
        }
    }

    var connection: CoupleConnection {
        CoupleConnection(
            id: Self.connectionID,
            members: [Self.minaProfile, Self.sofiaProfile],
            connectedAt: Date(timeIntervalSince1970: 1_723_348_800)
        )
    }

    var defaults: UserDefaults {
        let suiteName = "com.seungwoo.WayToYou.debug.\(rawValue)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("DEBUG 계정 UserDefaults suite를 만들 수 없습니다.")
        }
        if UserDefaults.standard.bool(forKey: "debugReset") {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    private static let connectionID = UUID(
        uuidString: "33333333-3333-4333-8333-333333333333"
    )!

    private static let minaProfile = UserProfile(
        id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
        displayName: "미나",
        endpoint: RouteEndpoint(
            city: RouteCity(
                id: "debug-seoul",
                name: "서울",
                country: "대한민국",
                latitude: 37.5665,
                longitude: 126.9780,
                timeZoneID: "Asia/Seoul"
            ),
            airport: RouteAirport(
                id: "debug-icn",
                name: "인천국제공항",
                latitude: 37.4602,
                longitude: 126.4407,
                code: "ICN"
            )
        )
    )

    private static let sofiaProfile = UserProfile(
        id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
        displayName: "Sofia",
        endpoint: RouteEndpoint(
            city: RouteCity(
                id: "debug-paris",
                name: "Paris",
                country: "France",
                latitude: 48.8566,
                longitude: 2.3522,
                timeZoneID: "Europe/Paris"
            ),
            airport: RouteAirport(
                id: "debug-cdg",
                name: "Paris Charles de Gaulle Airport",
                latitude: 49.0097,
                longitude: 2.5479,
                code: "CDG"
            )
        )
    )
}
#endif
