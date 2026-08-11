import Foundation

/// MapKit 검색 결과에서 앱이 보관해야 하는 도시 정보만 분리한 값.
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

/// 공항 목록은 앱에 넣지 않는다. 선택 시점의 MapKit 결과를 값으로 보관한다.
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

struct RouteEndpoint: Codable, Hashable {
    let city: RouteCity
    let airport: RouteAirport
}

struct CoupleRoute: Codable, Hashable {
    let mine: RouteEndpoint
    let partner: RouteEndpoint

    var label: String {
        if let origin = mine.airport.displayCode,
           let destination = partner.airport.displayCode {
            return "\(origin) ↔ \(destination)"
        }
        return "\(mine.city.name) ↔ \(partner.city.name)"
    }
}
