import MapKit
import SwiftUI
import UIKit

struct GlobeProfileMarker: Identifiable, Equatable {
    enum ID: String, Hashable {
        case mine
        case partner
    }

    let id: ID
    let displayName: String
    let city: CoupleCity
    let avatarData: Data?
}

/// MapKit의 기본 팬, 핀치, 관성을 그대로 사용하는 풀스크린 위성 지구.
/// 앱이 추가하는 카메라 제약은 극점 투영 붕괴를 막는 위도 ±70° 경계뿐이다.
struct GlobeMapView: UIViewRepresentable {
    let myMarker: GlobeProfileMarker
    let partnerMarker: GlobeProfileMarker

    func makeCoordinator() -> Coordinator {
        Coordinator(cameraRouteID: cameraRouteID)
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
        mapView.register(
            GlobeProfileAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: GlobeProfileAnnotationView.reuseIdentifier
        )

        context.coordinator.connect(to: mapView)
        context.coordinator.requestInitialFraming(cameraFraming)
        context.coordinator.sync(markers: markers, in: mapView)
        return mapView
    }

    func updateUIView(_ mapView: NativeGlobeMapView, context: Context) {
        if context.coordinator.cameraRouteID != cameraRouteID {
            context.coordinator.cameraRouteID = cameraRouteID
            context.coordinator.requestInitialFraming(cameraFraming)
        }

        // 사진과 이름은 매 갱신마다 annotation에 반영하되 카메라에는 영향을 주지 않는다.
        context.coordinator.sync(markers: markers, in: mapView)
    }

    static func dismantleUIView(
        _ mapView: NativeGlobeMapView,
        coordinator: Coordinator
    ) {
        mapView.onUsableLayout = nil
        mapView.delegate = nil
    }

    private var markers: [GlobeProfileMarker] {
        [myMarker, partnerMarker]
    }

    private var cameraRouteID: String {
        markers.map { marker in
            let city = marker.city
            return "\(city.id):\(city.latitude),\(city.longitude)"
        }
        .joined(separator: "|")
    }

    private var cameraFraming: CameraFraming {
        CameraFraming(first: myMarker.city, second: partnerMarker.city)
    }

    private static let latitudeBoundary: MKMapView.CameraBoundary? = {
        let world = MKMapRect.world
        let northY = MKMapPoint(
            CLLocationCoordinate2D(latitude: 70, longitude: 0)
        ).y
        let southY = MKMapPoint(
            CLLocationCoordinate2D(latitude: -70, longitude: 0)
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

    private static func longitudeMidpoint(
        between first: CLLocationDegrees,
        and second: CLLocationDegrees
    ) -> CLLocationDegrees {
        let firstLongitude = first * .pi / 180
        let secondLongitude = second * .pi / 180
        let x = cos(firstLongitude) + cos(secondLongitude)
        let y = sin(firstLongitude) + sin(secondLongitude)

        guard hypot(x, y) > .ulpOfOne else { return first }
        return atan2(y, x) * 180 / .pi
    }

    private struct SphereVector {
        let x: Double
        let y: Double
        let z: Double

        init(latitude: CLLocationDegrees, longitude: CLLocationDegrees) {
            let latitude = latitude * .pi / 180
            let longitude = longitude * .pi / 180
            x = cos(latitude) * cos(longitude)
            y = cos(latitude) * sin(longitude)
            z = sin(latitude)
        }

        init(x: Double, y: Double, z: Double) {
            self.x = x
            self.y = y
            self.z = z
        }

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(
                latitude: atan2(z, hypot(x, y)) * 180 / .pi,
                longitude: atan2(y, x) * 180 / .pi
            )
        }

        var magnitude: Double {
            sqrt(x * x + y * y + z * z)
        }

        func dot(_ other: Self) -> Double {
            x * other.x + y * other.y + z * other.z
        }

        func normalized() -> Self? {
            let magnitude = magnitude
            guard magnitude > Double.ulpOfOne.squareRoot() else { return nil }
            return self / magnitude
        }

        func angularDistance(to other: Self) -> Double {
            acos(min(max(dot(other), -1), 1))
        }

        /// 대척점처럼 합 벡터가 사라지는 경우에도 두 도시를 지평선에 놓을 수 있는 축이다.
        func stablePerpendicular() -> Self {
            let reference = abs(z) < 0.9
                ? Self(x: 0, y: 0, z: 1)
                : Self(x: 1, y: 0, z: 0)
            return Self(
                x: y * reference.z - z * reference.y,
                y: z * reference.x - x * reference.z,
                z: x * reference.y - y * reference.x
            ).normalized() ?? Self(x: 0, y: 1, z: 0)
        }

        func moved(toward target: Self, by angle: Double) -> Self {
            let projection = target - self * dot(target)
            let direction = projection.normalized() ?? stablePerpendicular()
            return self * cos(angle) + direction * sin(angle)
        }

        static func + (lhs: Self, rhs: Self) -> Self {
            Self(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
        }

        static func - (lhs: Self, rhs: Self) -> Self {
            Self(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
        }

        static func * (lhs: Self, rhs: Double) -> Self {
            Self(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs)
        }

        static func / (lhs: Self, rhs: Double) -> Self {
            Self(x: lhs.x / rhs, y: lhs.y / rhs, z: lhs.z / rhs)
        }
    }

    struct CameraFraming {
        let first: CoupleCity
        let second: CoupleCity

        func center(in mapView: MKMapView) -> CLLocationCoordinate2D {
            let firstVector = SphereVector(
                latitude: first.latitude,
                longitude: first.longitude
            )
            let secondVector = SphereVector(
                latitude: second.latitude,
                longitude: second.longitude
            )
            let routeMidpoint = (firstVector + secondVector).normalized()
                ?? firstVector.stablePerpendicular()
            let longitudeMidpoint = GlobeMapView.longitudeMidpoint(
                between: first.longitude,
                and: second.longitude
            )
            let visualLongitude = GlobeMapView.longitudeMidpoint(
                between: routeMidpoint.coordinate.longitude,
                and: longitudeMidpoint
            )

            let routeSpan = firstVector.angularDistance(to: secondVector)
            let mapHeight = max(mapView.bounds.height, 1)
            let bottomInsetFraction = min(
                max(mapView.layoutMargins.bottom / mapHeight, 0),
                0.5
            )
            let visualLatitude = (first.latitude + second.latitude) / 2
                - routeSpan * 180 / .pi * bottomInsetFraction
            let proposedCenter = SphereVector(
                latitude: min(max(visualLatitude, -70), 70),
                longitude: visualLongitude
            )

            // 사용자가 잡은 여백 기반 구도를 우선하되, 지구의 뒷면으로 도시가 넘어가지는 않게 한다.
            // 구면 중점에서 두 도시까지의 각도에 남은 지평선 여유만큼만 시점을 이동한다.
            let numericalTolerance = Double.ulpOfOne.squareRoot()
            let horizonHeadroom = max(.pi / 2 - routeSpan / 2, 0)
            let maximumShift = max(horizonHeadroom - numericalTolerance, 0)
            let proposedShift = routeMidpoint.angularDistance(to: proposedCenter)

            guard proposedShift > maximumShift else {
                return proposedCenter.coordinate
            }
            return routeMidpoint.moved(
                toward: proposedCenter,
                by: maximumShift
            ).coordinate
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var cameraRouteID: String

        private weak var mapView: NativeGlobeMapView?
        private var annotationsByID: [GlobeProfileMarker.ID: GlobeProfileAnnotation] = [:]
        private var latestMarkers: [GlobeProfileMarker] = []
        private var requestedFraming: CameraFraming?
        private var needsInitialFraming = false
        private var framingGeneration = 0

        init(cameraRouteID: String) {
            self.cameraRouteID = cameraRouteID
        }

        func connect(to mapView: NativeGlobeMapView) {
            self.mapView = mapView
            mapView.onUsableLayout = { [weak self, weak mapView] in
                guard let self, let mapView else { return }
                self.beginInitialFramingIfPossible(in: mapView)
            }
        }

        func sync(markers: [GlobeProfileMarker], in mapView: MKMapView) {
            latestMarkers = markers
            guard !needsInitialFraming else { return }
            applyLatestMarkers(in: mapView)
        }

        private func applyLatestMarkers(in mapView: MKMapView) {
            let markers = latestMarkers
            let desiredIDs = Set(markers.map(\.id))
            let removedIDs = annotationsByID.keys.filter { !desiredIDs.contains($0) }
            let removedAnnotations = removedIDs.compactMap { annotationsByID[$0] }
            if !removedAnnotations.isEmpty {
                mapView.removeAnnotations(removedAnnotations)
                removedIDs.forEach { annotationsByID.removeValue(forKey: $0) }
            }

            for marker in markers {
                if let annotation = annotationsByID[marker.id] {
                    guard annotation.marker != marker else { continue }
                    annotation.apply(marker)
                    (mapView.view(for: annotation) as? GlobeProfileAnnotationView)?
                        .configure(with: marker)
                } else {
                    let annotation = GlobeProfileAnnotation(marker: marker)
                    annotationsByID[marker.id] = annotation
                    mapView.addAnnotation(annotation)
                }
            }
        }

        func requestInitialFraming(_ framing: CameraFraming) {
            requestedFraming = framing
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
                  let requestedFraming,
                  mapView.bounds.width > 0,
                  mapView.bounds.height > 0 else { return }

            needsInitialFraming = false
            mapView.cameraZoomRange = nil
            mapView.setVisibleMapRect(MKMapRect.world, animated: false)
            mapView.setCenter(requestedFraming.center(in: mapView), animated: false)
            let camera = mapView.camera
            camera.centerCoordinateDistance *= 1000
            mapView.setCamera(camera, animated: false)

            // 최종 카메라가 반영된 다음 annotation을 추가해야 초기 가시성 계산이 지연되지 않는다.
            let generation = framingGeneration
            DispatchQueue.main.async { [weak self, weak mapView] in
                guard let self,
                      let mapView,
                      !self.needsInitialFraming,
                      self.framingGeneration == generation else { return }
                self.applyLatestMarkers(in: mapView)
            }
        }

        func mapView(
            _ mapView: MKMapView,
            viewFor annotation: any MKAnnotation
        ) -> MKAnnotationView? {
            guard let annotation = annotation as? GlobeProfileAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: GlobeProfileAnnotationView.reuseIdentifier,
                for: annotation
            )
            guard let profileView = view as? GlobeProfileAnnotationView else { return view }
            profileView.configure(with: annotation.marker)
            return profileView
        }
    }
}

private final class GlobeProfileAnnotation: NSObject, MKAnnotation {
    let id: GlobeProfileMarker.ID
    @objc dynamic var coordinate: CLLocationCoordinate2D
    private(set) var marker: GlobeProfileMarker

    init(marker: GlobeProfileMarker) {
        id = marker.id
        coordinate = CLLocationCoordinate2D(
            latitude: marker.city.latitude,
            longitude: marker.city.longitude
        )
        self.marker = marker
        super.init()
    }

    func apply(_ marker: GlobeProfileMarker) {
        self.marker = marker
        let newCoordinate = CLLocationCoordinate2D(
            latitude: marker.city.latitude,
            longitude: marker.city.longitude
        )
        if coordinate.latitude != newCoordinate.latitude
            || coordinate.longitude != newCoordinate.longitude {
            coordinate = newCoordinate
        }
    }
}

private final class GlobeProfileAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "GlobeProfileAnnotationView"

    private enum Layout {
        static let canvasSize = CGSize(width: 56, height: 68)
        static let avatarSize: CGFloat = 46
        static let dotSize: CGFloat = 6
        static let dotOriginY: CGFloat = 60
        static let dotCenterY = dotOriginY + dotSize / 2
    }

    private let stemView = UIView()
    private let dotView = UIView()
    private let avatarView = UIView()
    private let avatarImageView = UIImageView()
    private let fallbackLabel = UILabel()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)

        bounds = CGRect(origin: .zero, size: Layout.canvasSize)
        centerOffset = CGPoint(
            x: 0,
            y: Layout.canvasSize.height / 2 - Layout.dotCenterY
        )
        backgroundColor = .clear
        isOpaque = false
        canShowCallout = false
        displayPriority = .required
        collisionMode = .circle
        isAccessibilityElement = true

        stemView.backgroundColor = UIColor.white.withAlphaComponent(0.82)
        stemView.layer.cornerRadius = 0.5
        addSubview(stemView)

        dotView.backgroundColor = .white
        dotView.layer.cornerRadius = Layout.dotSize / 2
        dotView.layer.shadowColor = UIColor.black.cgColor
        dotView.layer.shadowOpacity = 0.25
        dotView.layer.shadowRadius = 2
        dotView.layer.shadowOffset = .zero
        addSubview(dotView)

        avatarView.backgroundColor = UIColor(white: 0.12, alpha: 1)
        avatarView.layer.cornerRadius = Layout.avatarSize / 2
        avatarView.layer.borderColor = UIColor.white.withAlphaComponent(0.92).cgColor
        avatarView.layer.borderWidth = max(Layout.avatarSize * 0.045, 2)
        avatarView.layer.shadowColor = UIColor.black.cgColor
        avatarView.layer.shadowOpacity = 0.3
        avatarView.layer.shadowRadius = 5
        avatarView.layer.shadowOffset = CGSize(width: 0, height: 2)
        addSubview(avatarView)

        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = Layout.avatarSize / 2
        avatarView.addSubview(avatarImageView)

        let font = UIFont.systemFont(
            ofSize: Layout.avatarSize * 0.34,
            weight: .semibold
        )
        fallbackLabel.font = font.fontDescriptor.withDesign(.rounded).map {
            UIFont(descriptor: $0, size: font.pointSize)
        } ?? font
        fallbackLabel.textColor = .white
        fallbackLabel.textAlignment = .center
        avatarView.addSubview(fallbackLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let avatarX = (bounds.width - Layout.avatarSize) / 2
        avatarView.frame = CGRect(
            x: avatarX,
            y: 0,
            width: Layout.avatarSize,
            height: Layout.avatarSize
        )
        avatarImageView.frame = avatarView.bounds
        fallbackLabel.frame = avatarView.bounds

        stemView.frame = CGRect(
            x: bounds.midX - 0.5,
            y: Layout.avatarSize - 2,
            width: 1,
            height: Layout.dotOriginY - Layout.avatarSize + 2
        )
        dotView.frame = CGRect(
            x: bounds.midX - Layout.dotSize / 2,
            y: Layout.dotOriginY,
            width: Layout.dotSize,
            height: Layout.dotSize
        )
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarImageView.image = nil
        fallbackLabel.text = nil
        accessibilityLabel = nil
    }

    func configure(with marker: GlobeProfileMarker) {
        if let data = marker.avatarData, let image = UIImage(data: data) {
            avatarImageView.image = image
            avatarImageView.isHidden = false
            fallbackLabel.isHidden = true
        } else {
            avatarImageView.image = nil
            avatarImageView.isHidden = true
            fallbackLabel.text = ProfileAvatarImage.fallbackInitial(for: marker.displayName)
            fallbackLabel.isHidden = false
        }

        accessibilityLabel = "\(marker.displayName), \(marker.city.name) 프로필"
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
        myMarker: GlobeProfileMarker(
            id: .mine,
            displayName: "미나",
            city: CoupleCity.city(id: "seoul"),
            avatarData: nil
        ),
        partnerMarker: GlobeProfileMarker(
            id: .partner,
            displayName: "Sofia",
            city: CoupleCity.city(id: "paris"),
            avatarData: nil
        )
    )
    .ignoresSafeArea()
}
