import CoreLocation
import MapKit
import Observation

struct RoutePlaceSearchService {
    func searchCities(_ query: String) async throws -> [RouteCity] {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 2,
              let request = MKGeocodingRequest(addressString: cleaned) else { return [] }

        request.preferredLocale = .current
        let items = try await request.mapItems
        return uniqueCities(from: items)
    }

    func city(near location: CLLocation) async throws -> RouteCity {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            throw RoutePlaceSearchError.locationUnavailable
        }
        request.preferredLocale = .current
        let items = try await request.mapItems
        guard let city = uniqueCities(from: items).first else {
            throw RoutePlaceSearchError.cityNotFound
        }
        return city
    }

    func airports(near city: RouteCity, query: String = "") async throws -> [RouteAirport] {
        let center = CLLocationCoordinate2D(latitude: city.latitude, longitude: city.longitude)
        let region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: 180_000,
            longitudinalMeters: 180_000
        )
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = MKLocalSearch.Request(
            naturalLanguageQuery: cleaned.isEmpty ? "airport" : cleaned,
            region: region
        )
        request.regionPriority = .required
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.airport])

        let response = try await MKLocalSearch(request: request).start()
        let cityLocation = CLLocation(latitude: city.latitude, longitude: city.longitude)
        return response.mapItems
            .filter { $0.pointOfInterestCategory == .airport }
            .compactMap(makeAirport)
            .uniqued(on: \RouteAirport.id)
            .sorted {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                    .distance(from: cityLocation)
                < CLLocation(latitude: $1.latitude, longitude: $1.longitude)
                    .distance(from: cityLocation)
            }
    }

    private func uniqueCities(from items: [MKMapItem]) -> [RouteCity] {
        items.compactMap { item in
            guard let representations = item.addressRepresentations,
                  let name = representations.cityName,
                  !name.isEmpty else { return nil }
            let location = item.location
            return RouteCity(
                id: item.identifier?.rawValue
                    ?? String(format: "%.5f,%.5f", location.coordinate.latitude, location.coordinate.longitude),
                name: name,
                country: representations.regionName ?? "",
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                timeZoneID: item.timeZone?.identifier ?? TimeZone.current.identifier
            )
        }
        .uniqued(on: \RouteCity.id)
    }

    private func makeAirport(from item: MKMapItem) -> RouteAirport? {
        guard let name = item.name, !name.isEmpty else { return nil }
        let location = item.location
        return RouteAirport(
            id: item.identifier?.rawValue
                ?? String(format: "%.5f,%.5f", location.coordinate.latitude, location.coordinate.longitude),
            name: name,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            code: Self.inferredAirportCode(from: name)
        )
    }

    /// MapKit 이름에 `(ABC)`처럼 명시된 경우만 사용한다. 추측한 코드를 저장하지 않는다.
    private static func inferredAirportCode(from name: String) -> String? {
        guard let opening = name.firstIndex(of: "("),
              let closing = name[opening...].firstIndex(of: ")") else { return nil }
        let candidate = name[name.index(after: opening)..<closing].uppercased()
        guard candidate.count == 3, candidate.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            return nil
        }
        return candidate
    }
}

enum RoutePlaceSearchError: LocalizedError {
    case cityNotFound
    case locationUnavailable
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .cityNotFound:
            "도시를 찾지 못했어요. 도시 이름을 직접 검색해주세요."
        case .locationUnavailable:
            "현재 위치를 확인하지 못했어요. 잠시 후 다시 시도해주세요."
        case .permissionDenied:
            "위치 권한이 꺼져 있어요. 설정에서 허용하거나 도시를 직접 검색해주세요."
        }
    }
}

@MainActor
@Observable
final class CurrentLocationController: NSObject, CLLocationManagerDelegate {
    enum State: Equatable {
        case idle
        case requesting
        case located(CLLocation)
        case failed(String)
    }

    private(set) var state: State = .idle
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestLocation() {
        state = .requesting
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            state = .failed(RoutePlaceSearchError.permissionDenied.localizedDescription)
        @unknown default:
            state = .failed(RoutePlaceSearchError.locationUnavailable.localizedDescription)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard state == .requesting else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            state = .failed(RoutePlaceSearchError.permissionDenied.localizedDescription)
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            state = .failed(RoutePlaceSearchError.locationUnavailable.localizedDescription)
            return
        }
        state = .located(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        state = .failed(RoutePlaceSearchError.locationUnavailable.localizedDescription)
    }
}

private extension Array {
    func uniqued<Key: Hashable>(on keyPath: KeyPath<Element, Key>) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
