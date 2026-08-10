import MapKit
import SwiftUI

/// MapKit의 기본 팬, 핀치, 관성을 그대로 사용하는 풀스크린 위성 지구.
/// 앱이 추가하는 카메라 제약은 극점 투영 붕괴를 막는 위도 ±40° 경계뿐이다.
struct GlobeMapView: UIViewRepresentable {
    let homeCity: CoupleCity
    let partnerCity: CoupleCity

    func makeCoordinator() -> Coordinator {
        Coordinator(routeID: routeID)
    }

    func makeUIView(context: Context) -> NativeGlobeMapView {
        let mapView = NativeGlobeMapView(frame: .zero)
        mapView.preferredConfiguration = MKImageryMapConfiguration(
            elevationStyle: .realistic
        )
        mapView.delegate = context.coordinator
        mapView.overrideUserInterfaceStyle = .dark
        mapView.backgroundColor = .black

        // 이동, 확대·축소, 회전, 기울기와 관성은 모두 MapKit 기본 동작이다.
        mapView.isScrollEnabled = true
        mapView.isZoomEnabled = true
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = true

        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.setCameraBoundary(Self.latitudeBoundary, animated: false)

        context.coordinator.connect(to: mapView)
        context.coordinator.requestInitialFraming(at: initialLongitude)
        return mapView
    }

    func updateUIView(_ mapView: NativeGlobeMapView, context: Context) {
        guard context.coordinator.routeID != routeID else { return }
        context.coordinator.routeID = routeID
        context.coordinator.requestInitialFraming(at: initialLongitude)
    }

    static func dismantleUIView(
        _ mapView: NativeGlobeMapView,
        coordinator: Coordinator
    ) {
        mapView.onUsableLayout = nil
        mapView.delegate = nil
    }

    private var routeID: String {
        "\(homeCity.id)-\(partnerCity.id)"
    }

    private var initialLongitude: CLLocationDegrees {
        Self.midpoint(between: homeCity, and: partnerCity).longitude
    }

    private static let latitudeBoundary: MKMapView.CameraBoundary? = {
        let world = MKMapRect.world
        let northY = MKMapPoint(
            CLLocationCoordinate2D(latitude: 40, longitude: 0)
        ).y
        let southY = MKMapPoint(
            CLLocationCoordinate2D(latitude: -40, longitude: 0)
        ).y
        return MKMapView.CameraBoundary(
            mapRect: MKMapRect(
                x: world.minX,
                y: northY,
                width: world.width,
                height: southY - northY
            )
        )
    }()

    private static func midpoint(
        between first: CoupleCity,
        and second: CoupleCity
    ) -> CLLocationCoordinate2D {
        let firstLatitude = first.latitude * .pi / 180
        let firstLongitude = first.longitude * .pi / 180
        let secondLatitude = second.latitude * .pi / 180
        let secondLongitude = second.longitude * .pi / 180

        let x = cos(firstLatitude) * cos(firstLongitude)
            + cos(secondLatitude) * cos(secondLongitude)
        let y = cos(firstLatitude) * sin(firstLongitude)
            + cos(secondLatitude) * sin(secondLongitude)
        let z = sin(firstLatitude) + sin(secondLatitude)
        let horizontal = hypot(x, y)

        guard horizontal > .ulpOfOne || abs(z) > .ulpOfOne else {
            return CLLocationCoordinate2D(
                latitude: first.latitude,
                longitude: first.longitude
            )
        }

        return CLLocationCoordinate2D(
            latitude: atan2(z, horizontal) * 180 / .pi,
            longitude: atan2(y, x) * 180 / .pi
        )
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var routeID: String

        private weak var mapView: NativeGlobeMapView?
        private var requestedLongitude: CLLocationDegrees = 0
        private var needsInitialFraming = false
        private var framingGeneration = 0

        init(routeID: String) {
            self.routeID = routeID
        }

        func connect(to mapView: NativeGlobeMapView) {
            self.mapView = mapView
            mapView.onUsableLayout = { [weak self, weak mapView] in
                guard let self, let mapView else { return }
                self.beginInitialFramingIfPossible(in: mapView)
            }
        }

        func requestInitialFraming(at longitude: CLLocationDegrees) {
            requestedLongitude = longitude
            needsInitialFraming = true
            framingGeneration += 1

            guard let mapView else { return }
            let generation = framingGeneration
            DispatchQueue.main.async { [weak self, weak mapView] in
                guard let self,
                      let mapView,
                      self.framingGeneration == generation else { return }
                mapView.layoutIfNeeded()
                self.beginInitialFramingIfPossible(in: mapView)
            }
        }

        private func beginInitialFramingIfPossible(in mapView: MKMapView) {
            guard needsInitialFraming,
                  mapView.bounds.width > 0,
                  mapView.bounds.height > 0 else { return }

            needsInitialFraming = false
            mapView.cameraZoomRange = nil
            mapView.setVisibleMapRect(MKMapRect.world, animated: false)
            let camera = mapView.camera
            camera.centerCoordinateDistance *= 1000
            mapView.setCamera(camera, animated: false)
            mapView.setCenter(
                CLLocationCoordinate2D(
                    latitude: 0,
                    longitude: requestedLongitude
                ),
                animated: false
            )
        }
    }
}

final class NativeGlobeMapView: MKMapView {
    var onUsableLayout: (() -> Void)?

    private var lastUsableSize = CGSize.zero

    override func layoutSubviews() {
        super.layoutSubviews()

        // 탭 바 안전 영역 + 54pt CTA + 8pt 여백 + Apple 권장 간격 10pt.
        layoutMargins = UIEdgeInsets(
            top: 0,
            left: 7,
            bottom: safeAreaInsets.bottom + 72,
            right: 7
        )

        guard bounds.width > 0,
              bounds.height > 0,
              bounds.size != lastUsableSize else { return }
        lastUsableSize = bounds.size
        onUsableLayout?()
    }
}

#Preview("MapKit 지구본만") {
    GlobeMapView(
        homeCity: CoupleCity.city(id: "seoul"),
        partnerCity: CoupleCity.city(id: "paris")
    )
    .ignoresSafeArea()
}
