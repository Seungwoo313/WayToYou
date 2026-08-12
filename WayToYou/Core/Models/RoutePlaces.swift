import Foundation

/// MapKit 검색 결과에서 프로필에 보관해야 하는 도시 정보만 분리한 값.
struct RouteCity: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let country: String
    let latitude: Double
    let longitude: Double
    let timeZoneID: String

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneID) ?? .gmt
    }

    var coupleCity: CoupleCity {
        CoupleCity(
            id: id,
            name: name,
            country: country,
            latitude: latitude,
            longitude: longitude,
            timeZoneID: timeZoneID
        )
    }
}

/// 공항 목록은 앱에 넣지 않는다. 소포 Route를 정할 때의 MapKit 결과를 보관한다.
struct RouteAirport: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let code: String?

    var displayCode: String? {
        guard let code, code.count == 3 else { return nil }
        return code.uppercased()
    }
}
