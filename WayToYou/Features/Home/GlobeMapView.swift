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
    let signal: CoupleSignal?
    let battery: GlobeBatteryDisplay?
}

/// 마커 위 배터리 바가 그릴 값. freshness를 미리 단계로 접어 넣어
/// 시계가 매초 흘러도 단계가 바뀔 때만 marker 비교가 달라지게 한다.
struct GlobeBatteryDisplay: Equatable {
    let level: Int
    let isCharging: Bool
    /// 10분 이상 갱신이 없던 값. 흐리게 보여준다.
    let isMuted: Bool

    init(level: Int, isCharging: Bool, isMuted: Bool) {
        self.level = level
        self.isCharging = isCharging
        self.isMuted = isMuted
    }

    /// 60분이 지난 값은 아예 만들지 않아 바가 사라진다.
    init?(presence: DevicePresence?, at date: Date) {
        guard let presence else { return nil }
        switch presence.freshness(at: date) {
        case .expired:
            return nil
        case .stale:
            self.init(
                level: presence.batteryLevel,
                isCharging: presence.isCharging,
                isMuted: true
            )
        case .fresh:
            self.init(
                level: presence.batteryLevel,
                isCharging: presence.isCharging,
                isMuted: false
            )
        }
    }
}

struct GlobeMarkerSelection: Equatable {
    let id: GlobeProfileMarker.ID
    let anchor: CGPoint
}

struct GlobeMarkerOrder: Equatable {
    let left: GlobeProfileMarker.ID

    static let mineOnLeft = GlobeMarkerOrder(left: .mine)

    var right: GlobeProfileMarker.ID {
        left == .mine ? .partner : .mine
    }

    func side(for id: GlobeProfileMarker.ID) -> GlobeMarkerSide {
        id == left ? .left : .right
    }
}

enum GlobeMarkerSide: Equatable {
    case left
    case right
}

/// MapKit의 기본 팬, 핀치, 관성을 그대로 사용하는 풀스크린 위성 지구.
/// 앱이 추가하는 카메라 제약은 극점 투영 붕괴를 막는 위도 ±70° 경계뿐이다.
struct GlobeMapView: UIViewRepresentable {
    let myMarker: GlobeProfileMarker
    let partnerMarker: GlobeProfileMarker
    @Binding var markerOrder: GlobeMarkerOrder
    @Binding var selection: GlobeMarkerSelection?
    let showsRouteHeart: Bool
    let animatesRouteHeart: Bool
    let routeHeartEmoji: String

    func makeCoordinator() -> Coordinator {
        Coordinator(
            cameraRouteID: cameraRouteID,
            markerOrder: $markerOrder,
            selection: $selection
        )
    }

    func makeUIView(context: Context) -> NativeGlobeMapView {
        let mapView = NativeGlobeMapView(frame: .zero)
        mapView.preferredConfiguration = MKImageryMapConfiguration(
            elevationStyle: .realistic
        )
        mapView.delegate = context.coordinator
        mapView.overrideUserInterfaceStyle = .dark
        mapView.backgroundColor = .black

        // 이동, 확대·축소, 회전과 관성은 MapKit 기본 동작을 그대로 쓴다.
        // 경로와 지평선 마커가 같은 원형 투영을 공유하도록 기울기는 고정한다.
        mapView.isScrollEnabled = true
        mapView.isZoomEnabled = true
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = false

        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.setCameraBoundary(Self.latitudeBoundary, animated: false)
        mapView.register(
            GlobeProfileAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: GlobeProfileAnnotationView.reuseIdentifier
        )
        mapView.register(
            RouteHeartAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: RouteHeartAnnotationView.reuseIdentifier
        )

        context.coordinator.connect(to: mapView)
        context.coordinator.requestInitialFraming(cameraFraming)
        context.coordinator.sync(
            markers: markers,
            route: cityRoute,
            showsRouteHeart: showsRouteHeart,
            animatesRouteHeart: animatesRouteHeart,
            routeHeartEmoji: routeHeartEmoji,
            in: mapView
        )
        return mapView
    }

    func updateUIView(_ mapView: NativeGlobeMapView, context: Context) {
        context.coordinator.markerOrder = $markerOrder
        context.coordinator.selection = $selection
        if context.coordinator.cameraRouteID != cameraRouteID {
            context.coordinator.cameraRouteID = cameraRouteID
            context.coordinator.requestInitialFraming(cameraFraming)
        }

        // 사진, 이름, Signal과 배터리는 annotation에만 반영한다.
        // Route도 도시가 달라질 때만 교체하며 현재 카메라에는 영향을 주지 않는다.
        context.coordinator.sync(
            markers: markers,
            route: cityRoute,
            showsRouteHeart: showsRouteHeart,
            animatesRouteHeart: animatesRouteHeart,
            routeHeartEmoji: routeHeartEmoji,
            in: mapView
        )
    }

    static func dismantleUIView(
        _ mapView: NativeGlobeMapView,
        coordinator: Coordinator
    ) {
        coordinator.disconnect()
        mapView.onUsableLayout = nil
        mapView.delegate = nil
    }

    private var markers: [GlobeProfileMarker] {
        [myMarker, partnerMarker]
    }

    private var cameraRouteID: String {
        cityRoute.id
    }

    private var cameraFraming: CameraFraming {
        CameraFraming(first: myMarker.city, second: partnerMarker.city)
    }

    private var cityRoute: CityRoute {
        CityRoute(first: myMarker.city, second: partnerMarker.city)
    }

    fileprivate struct CityRoute: Equatable {
        let first: CoupleCity
        let second: CoupleCity

        var id: String {
            [first, second]
                .map { "\($0.id):\($0.latitude),\($0.longitude)" }
                .joined(separator: "|")
        }

        var hasVisibleSpan: Bool {
            first.latitude != second.latitude || first.longitude != second.longitude
        }

        var midpointCoordinate: CLLocationCoordinate2D {
            let firstVector = SphereVector(
                latitude: first.latitude,
                longitude: first.longitude
            )
            let secondVector = SphereVector(
                latitude: second.latitude,
                longitude: second.longitude
            )
            return (firstVector + secondVector).normalized()?.coordinate
                ?? firstVector.stablePerpendicular().coordinate
        }

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

    /// MapKit 지구본은 유한한 카메라 거리 때문에 한 번에 반구 전체를 보여주지 못한다.
    /// 프로필 좌표가 limb에 걸리면 annotation view 전체가 제거될 수 있어 여백도 둔다.
    private static let earthRadius: CLLocationDistance = 6_378_137
    private static func visibleAngularRadius(in mapView: MKMapView) -> Double {
        let camera = mapView.camera
        let pitch = camera.pitch * .pi / 180
        let effectiveAltitude = camera.centerCoordinateDistance * max(cos(pitch), 0)
        guard effectiveAltitude.isFinite, effectiveAltitude > 0 else {
            return .pi / 2
        }

        let ratio = earthRadius / (earthRadius + effectiveAltitude)
        return acos(min(max(ratio, 0), 1))
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

        func negated() -> Self {
            self * -1
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

        struct Placement {
            let center: CLLocationCoordinate2D
            let backsideHiddenArcLimit: Double
        }

        func placement(in mapView: MKMapView) -> Placement {
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

            // 원래의 시각적 중심을 유지하되 어느 도시도 이론적인 앞 반구를 넘지 않게 한다.
            // 실제 MapKit 지평선보다 먼 도시는 별도의 뒷면 방향 표시가 담당한다.
            let numericalTolerance = Double.ulpOfOne.squareRoot()
            let horizonHeadroom = max(.pi / 2 - routeSpan / 2, 0)
            let maximumShift = max(horizonHeadroom - numericalTolerance, 0)
            let proposedShift = routeMidpoint.angularDistance(to: proposedCenter)

            let originalCenter = proposedShift > maximumShift
                ? routeMidpoint.moved(toward: proposedCenter, by: maximumShift)
                : proposedCenter

            // 검증된 기존 framing은 그대로 둔다. 다만 준대척 Route가 현재
            // 시점에서 거의 수평으로 놓일 때는 두 profile canvas가 좌우 화면 밖으로
            // 밀리고, 중점이 극점 쪽이면 MapKit이 지구를 과도하게 확대한다.
            // 이 두 조건이 동시에 성립할 때만 동거리 적도 중심을 쓴다.
            let fallbackThreshold = 165 * Double.pi / 180
            let routeAxis = routeAxisAngle(
                at: originalCenter,
                first: firstVector,
                second: secondVector
            )
            guard routeSpan > fallbackThreshold,
                  routeAxis < 36 * Double.pi / 180,
                  let fallbackCenter = equidistantEquatorialCenter(
                    first: firstVector,
                    second: secondVector,
                    preferredHemisphere: routeMidpoint
                  ) else {
                return Placement(
                    center: originalCenter.coordinate,
                    backsideHiddenArcLimit: 20 * Double.pi / 180
                )
            }

            // 거의 정확한 대척점의 대권 중점이 극점에 걸리면 동거리 중심을
            // 유지하는 것만으로는 선이 극점 지평선에 붙는다. 이때만 대권 위의
            // 위도 약 35° 지점으로 이동해 Route가 지구 중앙을 통과하게 한다.
            let nearExactAntipode = routeSpan > 175 * Double.pi / 180
            let polarMidpoint = abs(routeMidpoint.coordinate.latitude) > 70
            if nearExactAntipode, polarMidpoint {
                return Placement(
                    center: routeMidpoint.moved(
                        toward: firstVector,
                        by: 55 * Double.pi / 180
                    ).coordinate,
                    backsideHiddenArcLimit: 70 * Double.pi / 180
                )
            }

            // 거의 정확한 대척점에서는 양쪽 도시가 동시에 MapKit의 유한한
            // 지평선 바로 뒤에 놓일 수 있다. Route 중점 방향으로만 조금
            // 기울여 경로의 앞면 샘플을 확보하고, 양 끝은 기존 backside
            // 표시가 서로 다른 지평선 끝에 놓이도록 한다.
            let routeRevealBias = 20 * Double.pi / 180
            return Placement(
                center: fallbackCenter.moved(
                    toward: routeMidpoint,
                    by: routeRevealBias
                ).coordinate,
                backsideHiddenArcLimit: 40 * Double.pi / 180
            )
        }

        private func equidistantEquatorialCenter(
            first: SphereVector,
            second: SphereVector,
            preferredHemisphere: SphereVector
        ) -> SphereVector? {
            let difference = first - second
            let horizontalMagnitude = hypot(difference.x, difference.y)
            guard horizontalMagnitude > Double.ulpOfOne.squareRoot() else { return nil }

            var center = SphereVector(
                x: -difference.y / horizontalMagnitude,
                y: difference.x / horizontalMagnitude,
                z: 0
            )
            if center.dot(preferredHemisphere) < 0 {
                center = center.negated()
            }
            return center
        }

        private func routeAxisAngle(
            at center: SphereVector,
            first: SphereVector,
            second: SphereVector
        ) -> Double {
            let coordinate = center.coordinate
            let latitude = coordinate.latitude * .pi / 180
            let longitude = coordinate.longitude * .pi / 180
            let east = SphereVector(
                x: -sin(longitude),
                y: cos(longitude),
                z: 0
            )
            let north = SphereVector(
                x: -sin(latitude) * cos(longitude),
                y: -sin(latitude) * sin(longitude),
                z: cos(latitude)
            )
            let difference = second - first
            return atan2(abs(difference.dot(north)), abs(difference.dot(east)))
        }

    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var cameraRouteID: String {
            didSet {
                guard cameraRouteID != oldValue else { return }
                resolvedMarkerOrderRouteID = nil
            }
        }
        var markerOrder: Binding<GlobeMarkerOrder>
        var selection: Binding<GlobeMarkerSelection?>

        private weak var mapView: NativeGlobeMapView?
        private var annotationsByID: [GlobeProfileMarker.ID: GlobeProfileAnnotation] = [:]
        private var latestMarkers: [GlobeProfileMarker] = []
        private var latestRoute: CityRoute?
        private var latestShowsRouteHeart = true
        private var latestAnimatesRouteHeart = true
        private var latestRouteHeartEmoji = RouteHeartEmoji.pink.rawValue
        private var appliedRoute: CityRoute?
        private var routeOverlay: MKGeodesicPolyline?
        private var routeHeartAnnotation: RouteHeartAnnotation?
        private var requestedFraming: CameraFraming?
        private var backsideHiddenArcLimit = 20 * Double.pi / 180
        private var needsInitialFraming = false
        private var defersMarkerSyncUntilCameraCommit = false
        private var framingGeneration = 0
        private var markerPlacementGeneration = 0
        private var markerPlacementFramesRemaining = 0
        private var markerPlacementDisplayLink: CADisplayLink?
        private var nearbyFramingGeneration = 0
        private var nearbyFramingFramesRemaining = 0
        private var nearbyFramingDisplayLink: CADisplayLink?
        private var backsideRevealFramesRemaining = 0
        private var backsideRevealDisplayLink: CADisplayLink?
        private var isUserCameraMotionActive = false
        private var markerOrderResolutionScheduled = false
        private var resolvedMarkerOrderRouteID: String?
        private var isSynchronizingSelection = false
        private var backsideIndicatorsByID: [
            GlobeProfileMarker.ID: GlobeBacksideIndicatorView
        ] = [:]
        private var backsideMarkerSnapshots: [
            GlobeProfileMarker.ID: GlobeProfileMarker
        ] = [:]
        private var backsideMarkerIDs: Set<GlobeProfileMarker.ID> = []
        private var hiddenMarkerIDs: Set<GlobeProfileMarker.ID> = []
        private var nativeFadeInMarkerIDs: Set<GlobeProfileMarker.ID> = []
        private var routeSampleProbeAnnotations: [GlobeProjectionProbeAnnotation] = []
        private var routeSampleVectors: [SphereVector] = []

        private enum MarkerRepresentation {
            case native
            case backside
            case hidden
        }

        private static let backsideIndicatorOpacity: CGFloat = 0.84

        private struct RouteEndpointPresentation {
            let point: CGPoint
            let outward: CGVector
            let isClippedByHorizon: Bool
            /// 숨은 도시에서 경로를 따라 현재 보이는 끝까지 남은 각거리.
            let hiddenArc: Double
        }


        init(
            cameraRouteID: String,
            markerOrder: Binding<GlobeMarkerOrder>,
            selection: Binding<GlobeMarkerSelection?>
        ) {
            self.cameraRouteID = cameraRouteID
            self.markerOrder = markerOrder
            self.selection = selection
        }

        func connect(to mapView: NativeGlobeMapView) {
            self.mapView = mapView
            mapView.onUsableLayout = { [weak self, weak mapView] in
                guard let self, let mapView else { return }
                self.beginInitialFramingIfPossible(in: mapView)
                self.updateMarkerRepresentations(in: mapView)
            }
        }

        func disconnect() {
            markerPlacementDisplayLink?.invalidate()
            markerPlacementDisplayLink = nil
            nearbyFramingDisplayLink?.invalidate()
            nearbyFramingDisplayLink = nil
            nearbyFramingFramesRemaining = 0
            backsideRevealDisplayLink?.invalidate()
            backsideRevealDisplayLink = nil
            backsideRevealFramesRemaining = 0
            isUserCameraMotionActive = false
            markerOrderResolutionScheduled = false
            mapView?.onUsableLayout = nil
            backsideIndicatorsByID.values.forEach { $0.removeFromSuperview() }
            backsideIndicatorsByID.removeAll()
            backsideMarkerSnapshots.removeAll()
            backsideMarkerIDs.removeAll()
            hiddenMarkerIDs.removeAll()
            nativeFadeInMarkerIDs.removeAll()
            routeSampleProbeAnnotations.removeAll()
            routeSampleVectors.removeAll()
            mapView = nil
        }

        fileprivate func sync(
            markers: [GlobeProfileMarker],
            route: CityRoute,
            showsRouteHeart: Bool,
            animatesRouteHeart: Bool,
            routeHeartEmoji: String,
            in mapView: NativeGlobeMapView
        ) {
            latestMarkers = markers
            latestRoute = route
            latestShowsRouteHeart = showsRouteHeart
            latestAnimatesRouteHeart = animatesRouteHeart
            latestRouteHeartEmoji = routeHeartEmoji
            guard !needsInitialFraming,
                  !defersMarkerSyncUntilCameraCommit else { return }
            applyLatestMapContent(in: mapView)
        }

        private func applyLatestMapContent(in mapView: NativeGlobeMapView) {
            applyLatestRoute(in: mapView)
            applyLatestMarkers(in: mapView)
        }

        private func applyLatestRoute(in mapView: MKMapView) {
            let routeChanged = appliedRoute != latestRoute

            if routeChanged {
                if !routeSampleProbeAnnotations.isEmpty {
                    mapView.removeAnnotations(routeSampleProbeAnnotations)
                    routeSampleProbeAnnotations.removeAll(keepingCapacity: true)
                }
                if let routeOverlay {
                    mapView.removeOverlay(routeOverlay)
                    self.routeOverlay = nil
                }
                routeSampleVectors.removeAll(keepingCapacity: true)
                if let routeHeartAnnotation {
                    mapView.removeAnnotation(routeHeartAnnotation)
                    self.routeHeartAnnotation = nil
                }
                appliedRoute = latestRoute

                if let latestRoute, latestRoute.hasVisibleSpan {
                    var coordinates = [
                        CLLocationCoordinate2D(
                            latitude: latestRoute.first.latitude,
                            longitude: latestRoute.first.longitude
                        ),
                        CLLocationCoordinate2D(
                            latitude: latestRoute.second.latitude,
                            longitude: latestRoute.second.longitude
                        )
                    ]
                    let overlay = MKGeodesicPolyline(
                        coordinates: &coordinates,
                        count: coordinates.count
                    )
                    routeOverlay = overlay
                    mapView.addOverlay(overlay, level: .aboveLabels)

                    let sampleCount = 256
                    let points = overlay.points()
                    var sampledIndices: Set<Int> = []
                    for sample in 0...sampleCount {
                        let index = Int(
                            (Double(overlay.pointCount - 1)
                                * Double(sample) / Double(sampleCount)).rounded()
                        )
                        guard sampledIndices.insert(index).inserted else { continue }
                        let coordinate = points[index].coordinate
                        routeSampleProbeAnnotations.append(
                            GlobeProjectionProbeAnnotation(
                                coordinate: coordinate
                            )
                        )
                        routeSampleVectors.append(
                            SphereVector(
                                latitude: coordinate.latitude,
                                longitude: coordinate.longitude
                            )
                        )
                    }
                    mapView.addAnnotations(routeSampleProbeAnnotations)
                }
            }

            syncRouteHeart(in: mapView)
        }

        private func syncRouteHeart(in mapView: MKMapView) {
            guard latestShowsRouteHeart,
                  let latestRoute,
                  latestRoute.hasVisibleSpan else {
                if let routeHeartAnnotation {
                    mapView.removeAnnotation(routeHeartAnnotation)
                    self.routeHeartAnnotation = nil
                }
                return
            }

            if let routeHeartAnnotation {
                if routeHeartAnnotation.emoji != latestRouteHeartEmoji {
                    routeHeartAnnotation.emoji = latestRouteHeartEmoji
                }
                (mapView.view(for: routeHeartAnnotation) as? RouteHeartAnnotationView)?
                    .configure(
                        emoji: latestRouteHeartEmoji,
                        animatesHeartbeat: latestAnimatesRouteHeart
                    )
                return
            }

            let annotation = RouteHeartAnnotation(
                coordinate: latestRoute.midpointCoordinate,
                emoji: latestRouteHeartEmoji
            )
            routeHeartAnnotation = annotation
            mapView.addAnnotation(annotation)
        }

        private func applyLatestMarkers(in mapView: NativeGlobeMapView) {
            let markers = latestMarkers
            let desiredIDs = Set(markers.map(\.id))
            let removedIDs = annotationsByID.keys.filter { !desiredIDs.contains($0) }
            let removedAnnotations = removedIDs.compactMap { annotationsByID[$0] }
            if !removedAnnotations.isEmpty {
                mapView.removeAnnotations(removedAnnotations)
                for id in removedIDs {
                    annotationsByID.removeValue(forKey: id)
                    backsideIndicatorsByID.removeValue(forKey: id)?.removeFromSuperview()
                    backsideMarkerSnapshots.removeValue(forKey: id)
                    backsideMarkerIDs.remove(id)
                    hiddenMarkerIDs.remove(id)
                    nativeFadeInMarkerIDs.remove(id)
                }
            }

            for marker in markers {
                let markerChanged: Bool
                if let annotation = annotationsByID[marker.id] {
                    markerChanged = annotation.marker != marker
                    if markerChanged {
                        annotation.apply(marker)
                        (mapView.view(for: annotation) as? GlobeProfileAnnotationView)?
                            .configure(with: marker)
                    }
                } else {
                    markerChanged = true
                    let annotation = GlobeProfileAnnotation(marker: marker)
                    annotationsByID[marker.id] = annotation
                    mapView.addAnnotation(annotation)
                }

                let indicator = backsideIndicator(for: marker, in: mapView)
                if markerChanged || backsideMarkerSnapshots[marker.id] != marker {
                    indicator.configure(with: marker)
                    backsideMarkerSnapshots[marker.id] = marker
                }
            }

            updateMarkerRepresentations(in: mapView)
            syncSelection(in: mapView)
            resolveMarkerOrderOnce(in: mapView)
            applyCoincidentMarkerOffsets(in: mapView)
        }

        /// 두 사람이 같은 도시 좌표를 쓰면 카메라를 확대해도 점이 분리되지 않는다.
        /// 도시 좌표 자체는 유지하면서 프로필 사진만 작은 한 쌍으로 나란히 놓는다.
        private func applyCoincidentMarkerOffsets(in mapView: MKMapView) {
            for (id, annotation) in annotationsByID {
                (mapView.view(for: annotation) as? GlobeProfileAnnotationView)?
                    .setCoordinateOffsetX(coincidentCoordinateOffsetX(for: id))
            }
        }

        private func coincidentCoordinateOffsetX(
            for id: GlobeProfileMarker.ID
        ) -> CGFloat {
            guard latestRoute?.hasVisibleSpan == false else { return 0 }
            // 두 annotation의 전체 접근성 canvas가 겹치지 않게 한 폭만큼 분리한다.
            let centerGap = GlobeProfileAnnotationView.canvasSize.width
            return markerOrder.wrappedValue.side(for: id) == .left
                ? -centerGap / 2
                : centerGap / 2
        }

        private func backsideIndicator(
            for marker: GlobeProfileMarker,
            in mapView: NativeGlobeMapView
        ) -> GlobeBacksideIndicatorView {
            if let indicator = backsideIndicatorsByID[marker.id] {
                return indicator
            }

            let indicator = GlobeBacksideIndicatorView()
            indicator.isHidden = true
            indicator.alpha = 0
            indicator.onActivate = { [weak self, weak mapView, weak indicator] in
                guard let self, let mapView, let indicator else { return }
                self.activateBacksideMarker(marker.id, indicator: indicator, in: mapView)
            }
            backsideIndicatorsByID[marker.id] = indicator
            mapView.presentationOverlayView.addSubview(indicator)
            return indicator
        }

        private func updateMarkerRepresentations(
            in mapView: NativeGlobeMapView,
            fadesInBacksideIndicators: Bool = false
        ) {
            guard !needsInitialFraming,
                  !defersMarkerSyncUntilCameraCommit,
                  !isUserCameraMotionActive,
                  mapView.bounds.width > 0,
                  mapView.bounds.height > 0 else { return }

            for marker in latestMarkers {
                guard let annotation = annotationsByID[marker.id],
                      let indicator = backsideIndicatorsByID[marker.id] else { continue }

                let endpoint = routeEndpointPresentation(for: marker.id, in: mapView)
                let nativeView = mapView.view(for: annotation) as? GlobeProfileAnnotationView
                // 기본 20° 숨김 정책은 유지하되, 준대척 framing에서만
                // Placement가 계산한 각도까지 뒷면 방향 표시를 유지한다.
                let hiddenArcLimit = backsideHiddenArcLimit
                let representation: MarkerRepresentation
                if let endpoint, endpoint.isClippedByHorizon {
                    representation = endpoint.hiddenArc < hiddenArcLimit
                        ? .backside
                        : .hidden
                } else if endpoint != nil {
                    representation = .native
                } else if backsideMarkerIDs.contains(marker.id) {
                    representation = .backside
                } else if hiddenMarkerIDs.contains(marker.id) {
                    representation = .hidden
                } else {
                    representation = .native
                }

                if let endpoint, representation == .backside {
                    positionBacksideIndicator(
                        indicator,
                        endpoint: endpoint,
                        in: mapView
                    )
                }
                setMarkerRepresentation(
                    representation,
                    for: marker.id,
                    nativeView: nativeView,
                    indicator: indicator,
                    fadesIn: fadesInBacksideIndicators
                )
            }
            syncSelection(in: mapView)
        }

        private func setMarkerRepresentation(
            _ representation: MarkerRepresentation,
            for id: GlobeProfileMarker.ID,
            nativeView: GlobeProfileAnnotationView?,
            indicator: GlobeBacksideIndicatorView,
            fadesIn: Bool
        ) {
            let previousRepresentation: MarkerRepresentation
            if backsideMarkerIDs.contains(id) {
                previousRepresentation = .backside
            } else if hiddenMarkerIDs.contains(id) {
                previousRepresentation = .hidden
            } else {
                previousRepresentation = .native
            }
            let stateChanged = previousRepresentation != representation

            backsideMarkerIDs.remove(id)
            hiddenMarkerIDs.remove(id)
            if representation == .backside {
                backsideMarkerIDs.insert(id)
            } else if representation == .hidden {
                hiddenMarkerIDs.insert(id)
            }

            indicator.setSelected(selection.wrappedValue?.id == id)
            if representation == .hidden, selection.wrappedValue?.id == id {
                selection.wrappedValue = nil
            }
            if stateChanged {
                indicator.layer.removeAllAnimations()
                nativeView?.layer.removeAllAnimations()
            }

            guard representation == .backside else {
                indicator.layer.removeAllAnimations()
                indicator.alpha = 0
                indicator.isHidden = true
                indicator.isUserInteractionEnabled = false
                indicator.accessibilityElementsHidden = true

                guard representation == .native else {
                    nativeFadeInMarkerIDs.remove(id)
                    nativeView?.alpha = 0
                    nativeView?.isHidden = true
                    nativeView?.isEnabled = false
                    return
                }

                nativeView?.isHidden = false
                nativeView?.isEnabled = true
                guard fadesIn, previousRepresentation != .native else {
                    nativeView?.alpha = nativeFadeInMarkerIDs.contains(id) ? 0 : 1
                    return
                }
                guard let nativeView else {
                    nativeFadeInMarkerIDs.insert(id)
                    return
                }
                nativeFadeInMarkerIDs.remove(id)
                nativeView.alpha = 0
                UIView.animate(
                    withDuration: 0.22,
                    delay: 0,
                    options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]
                ) {
                    nativeView.alpha = 1
                }
                return
            }

            nativeView?.alpha = 0
            nativeView?.isHidden = true
            nativeView?.isEnabled = false
            nativeFadeInMarkerIDs.remove(id)
            indicator.isHidden = false
            indicator.isUserInteractionEnabled = true
            indicator.accessibilityElementsHidden = false

            guard fadesIn else {
                indicator.alpha = Self.backsideIndicatorOpacity
                return
            }

            indicator.layer.removeAllAnimations()
            indicator.alpha = 0
            UIView.animate(
                withDuration: 0.22,
                delay: 0,
                options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]
            ) {
                indicator.alpha = Self.backsideIndicatorOpacity
            }
        }

        private func beginUserCameraMotion() {
            backsideRevealDisplayLink?.invalidate()
            backsideRevealDisplayLink = nil
            backsideRevealFramesRemaining = 0
            guard !isUserCameraMotionActive else { return }
            isUserCameraMotionActive = true

            for id in backsideMarkerIDs {
                guard let indicator = backsideIndicatorsByID[id] else { continue }
                indicator.layer.removeAllAnimations()
                indicator.isUserInteractionEnabled = false
                indicator.accessibilityElementsHidden = true
                UIView.animate(
                    withDuration: 0.14,
                    delay: 0,
                    options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]
                ) {
                    indicator.alpha = 0
                }
            }
            nativeFadeInMarkerIDs.removeAll()
            if let mapView {
                for annotation in annotationsByID.values {
                    mapView.view(for: annotation)?.layer.removeAllAnimations()
                }
            }
        }

        private func scheduleBacksideReveal(afterDisplayFrames frameCount: Int) {
            backsideRevealDisplayLink?.invalidate()
            backsideRevealFramesRemaining = max(frameCount, 1)
            let displayLink = CADisplayLink(
                target: self,
                selector: #selector(advanceBacksideReveal)
            )
            backsideRevealDisplayLink = displayLink
            displayLink.add(to: .main, forMode: .common)
        }

        @objc private func advanceBacksideReveal() {
            guard backsideRevealFramesRemaining > 1 else {
                backsideRevealDisplayLink?.invalidate()
                backsideRevealDisplayLink = nil
                backsideRevealFramesRemaining = 0
                guard let mapView else { return }

                for id in backsideMarkerIDs {
                    guard let indicator = backsideIndicatorsByID[id] else { continue }
                    indicator.layer.removeAllAnimations()
                    indicator.alpha = 0
                    indicator.isUserInteractionEnabled = false
                    indicator.accessibilityElementsHidden = true
                }
                isUserCameraMotionActive = false
                updateMarkerRepresentations(
                    in: mapView,
                    fadesInBacksideIndicators: true
                )
                return
            }
            backsideRevealFramesRemaining -= 1
        }

        private func positionBacksideIndicator(
            _ indicator: GlobeBacksideIndicatorView,
            endpoint: RouteEndpointPresentation,
            in mapView: NativeGlobeMapView
        ) {
            let outsidePlacement = outsideMarkerPlacement(
                at: endpoint.point,
                dx: endpoint.outward.dx,
                dy: endpoint.outward.dy,
                in: mapView
            )
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            indicator.center = outsidePlacement.center
            indicator.setProfileScale(outsidePlacement.scale)
            CATransaction.commit()
        }

        private func routeEndpointPresentation(
            for id: GlobeProfileMarker.ID,
            in mapView: NativeGlobeMapView
        ) -> RouteEndpointPresentation? {
            guard routeSampleProbeAnnotations.count > 1,
                  routeSampleVectors.count == routeSampleProbeAnnotations.count,
                  let endpointIndex = latestMarkers.firstIndex(where: { $0.id == id }) else {
                return nil
            }
            let searchesFromStart = endpointIndex == 0
            let indices = searchesFromStart
                ? Array(routeSampleProbeAnnotations.indices)
                : Array(routeSampleProbeAnnotations.indices.reversed())
            let visibleBounds = mapView.bounds.insetBy(dx: -8, dy: -8)
            let cameraCenter = SphereVector(
                latitude: mapView.camera.centerCoordinate.latitude,
                longitude: mapView.camera.centerCoordinate.longitude
            )
            let horizon = GlobeMapView.visibleAngularRadius(in: mapView)
            // MapKit은 뒤쪽 annotation view도 잠시 화면 좌표를 가질 수 있다.
            // 화면 bounds만 검사하면 그 점을 경로 끝으로 오인하므로, 실제 앞면에
            // 들어온 대권 샘플만 후보로 사용한다.
            let frontRadius = max(
                horizon - min(0.04 * Double.pi / 180, horizon * 0.001),
                0
            )
            var endpoint: (index: Int, point: CGPoint, distance: Double)?
            var neighbor: CGPoint?

            for index in indices {
                let distance = cameraCenter.angularDistance(to: routeSampleVectors[index])
                guard distance <= frontRadius else { continue }
                guard let point = projectionPoint(
                    for: routeSampleProbeAnnotations[index],
                    in: mapView
                ), visibleBounds.contains(point) else { continue }
                if endpoint == nil {
                    endpoint = (index, point, distance)
                } else {
                    neighbor = point
                    break
                }
            }
            guard let endpoint else { return nil }

            var dx: CGFloat
            var dy: CGFloat
            if let neighbor {
                dx = endpoint.point.x - neighbor.x
                dy = endpoint.point.y - neighbor.y
            } else {
                dx = endpoint.point.x - mapView.bounds.midX
                dy = endpoint.point.y - mapView.bounds.midY
            }
            let length = hypot(dx, dy)
            if length.isFinite, length > 0.5 {
                dx /= length
                dy /= length
            } else {
                dx = id == .mine ? -1 : 1
                dy = 0
            }

            let trueEndpointIndex = searchesFromStart
                ? routeSampleProbeAnnotations.startIndex
                : routeSampleProbeAnnotations.index(before: routeSampleProbeAnnotations.endIndex)
            let isClippedByHorizon = endpoint.index != trueEndpointIndex
            var renderedBoundaryPoint = endpoint.point
            if isClippedByHorizon, let neighbor {
                let step = searchesFromStart ? 1 : -1
                let hiddenIndex = endpoint.index - step
                if routeSampleVectors.indices.contains(hiddenIndex) {
                    let hiddenDistance = cameraCenter.angularDistance(
                        to: routeSampleVectors[hiddenIndex]
                    )
                    let insideAmount = max(frontRadius - endpoint.distance, 0)
                    let outsideAmount = max(hiddenDistance - frontRadius, 0)
                    let denominator = insideAmount + outsideAmount
                    if denominator > Double.ulpOfOne {
                        // 앞/뒤 두 샘플 사이의 실제 horizon 교차 비율을 써서
                        // 샘플이 바뀌는 프레임에도 위치가 연속적으로 이어진다.
                        let fraction = CGFloat(insideAmount / denominator)
                        let segmentLength = hypot(
                            endpoint.point.x - neighbor.x,
                            endpoint.point.y - neighbor.y
                        )
                        renderedBoundaryPoint.x += dx * segmentLength * fraction
                        renderedBoundaryPoint.y += dy * segmentLength * fraction
                    }
                }
            }
            // MapKit의 선 renderer는 지구 실루엣보다 조금 안쪽에서 대시를 잘라낸다.
            // 숨은 도시일 때만 실제 화면에서 보이는 마지막 대시 쪽으로 들어간다.
            let renderedRouteEndInset: CGFloat = isClippedByHorizon ? 16 : 0
            let renderedEndpoint = CGPoint(
                x: renderedBoundaryPoint.x - dx * renderedRouteEndInset,
                y: renderedBoundaryPoint.y - dy * renderedRouteEndInset
            )
            let hiddenArc = cameraCenter.angularDistance(
                to: routeSampleVectors[trueEndpointIndex]
            ) - frontRadius
            return RouteEndpointPresentation(
                point: renderedEndpoint,
                outward: CGVector(dx: dx, dy: dy),
                isClippedByHorizon: isClippedByHorizon,
                hiddenArc: max(hiddenArc, 0)
            )
        }

        private func projectionPoint(
            for annotation: GlobeProjectionProbeAnnotation,
            in mapView: NativeGlobeMapView
        ) -> CGPoint? {
            guard let view = mapView.view(for: annotation),
                  view.superview != nil else { return nil }
            let frame = mapView.convert(view.bounds, from: view)
            guard frame.midX.isFinite, frame.midY.isFinite else { return nil }
            return CGPoint(x: frame.midX, y: frame.midY)
        }

        private func outsideMarkerPlacement(
            at rimPoint: CGPoint,
            dx: CGFloat,
            dy: CGFloat,
            in mapView: NativeGlobeMapView
        ) -> (center: CGPoint, scale: CGFloat) {
            let preferredScale: CGFloat = 0.78
            let minimumScale: CGFloat = 0.62
            let gap: CGFloat = 1
            let usableBounds = mapView.bounds.inset(by: UIEdgeInsets(
                top: 4,
                left: 4,
                bottom: mapView.layoutMargins.bottom + 4,
                right: 4
            ))

            func placement(scale: CGFloat) -> (CGPoint, Bool) {
                let halfWidth = GlobeProfileAnnotationView.canvasSize.width / 2
                let halfCanvasHeight = GlobeProfileAnnotationView.canvasSize.height / 2
                let minX = -halfWidth * scale
                let maxX = halfWidth * scale
                let minY = -halfCanvasHeight * scale
                let maxY = (GlobeProfileAnnotationView.backsideContentHeight
                    - halfCanvasHeight) * scale
                // 캔버스의 빈 여백이 아니라 실제 원형 사진이 점선 끝에 닿는다.
                let distance = GlobeProfileAnnotationView.avatarRadius * scale + gap
                let center = CGPoint(
                    x: rimPoint.x + dx * distance,
                    y: rimPoint.y + dy * distance
                )
                let visualFrame = CGRect(
                    x: center.x + minX,
                    y: center.y + minY,
                    width: maxX - minX,
                    height: maxY - minY
                )
                return (center, usableBounds.contains(visualFrame))
            }

            if placement(scale: preferredScale).1 {
                return (placement(scale: preferredScale).0, preferredScale)
            }
            var lower = minimumScale
            var upper = preferredScale
            for _ in 0..<12 {
                let candidate = (lower + upper) / 2
                if placement(scale: candidate).1 {
                    lower = candidate
                } else {
                    upper = candidate
                }
            }
            let minimumPlacement = placement(scale: lower).0
            let halfWidth = GlobeProfileAnnotationView.canvasSize.width / 2 * lower
            let halfCanvasHeight = GlobeProfileAnnotationView.canvasSize.height / 2 * lower
            let contentBottom = (
                GlobeProfileAnnotationView.backsideContentHeight
                    - GlobeProfileAnnotationView.canvasSize.height / 2
            ) * lower
            // 최소 표시 크기에서도 화면 밖이라면 카메라를 다시 움직이지 않고
            // 실제 profile content만 usable bounds 안으로 제한한다.
            let clampedCenter = CGPoint(
                x: min(
                    max(minimumPlacement.x, usableBounds.minX + halfWidth),
                    usableBounds.maxX - halfWidth
                ),
                y: min(
                    max(minimumPlacement.y, usableBounds.minY + halfCanvasHeight),
                    usableBounds.maxY - contentBottom
                )
            )
            return (clampedCenter, lower)
        }

        func syncSelection(in mapView: MKMapView) {
            let selectedID = selection.wrappedValue?.id
            for (id, indicator) in backsideIndicatorsByID {
                indicator.setSelected(selectedID == id)
            }

            let desiredNativeID = selectedID.flatMap {
                backsideMarkerIDs.contains($0) || hiddenMarkerIDs.contains($0)
                    ? nil
                    : $0
            }
            let selectedAnnotation = mapView.selectedAnnotations
                .compactMap { $0 as? GlobeProfileAnnotation }
                .first
            guard selectedAnnotation?.id != desiredNativeID else { return }

            isSynchronizingSelection = true
            defer { isSynchronizingSelection = false }

            if let selectedAnnotation {
                mapView.deselectAnnotation(selectedAnnotation, animated: false)
            }
            if let desiredNativeID,
               let annotation = annotationsByID[desiredNativeID] {
                mapView.selectAnnotation(annotation, animated: false)
            }
        }

        func requestInitialFraming(_ framing: CameraFraming) {
            requestedFraming = framing
            needsInitialFraming = true
            defersMarkerSyncUntilCameraCommit = true
            markerPlacementDisplayLink?.invalidate()
            markerPlacementDisplayLink = nil
            nearbyFramingDisplayLink?.invalidate()
            nearbyFramingDisplayLink = nil
            nearbyFramingFramesRemaining = 0
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
            let camera = mapView.camera
            camera.pitch = 0
            camera.centerCoordinateDistance *= 1000
            mapView.setCamera(camera, animated: false)
            let placement = requestedFraming.placement(in: mapView)
            backsideHiddenArcLimit = placement.backsideHiddenArcLimit
            mapView.setCenter(placement.center, animated: false)

            scheduleMarkerPlacement(afterDisplayFrames: 2)
        }

        private func scheduleMarkerPlacement(afterDisplayFrames frameCount: Int) {
            markerPlacementDisplayLink?.invalidate()
            markerPlacementGeneration = framingGeneration
            markerPlacementFramesRemaining = max(frameCount, 1)
            let displayLink = CADisplayLink(
                target: self,
                selector: #selector(advanceMarkerPlacement)
            )
            markerPlacementDisplayLink = displayLink
            displayLink.add(to: .main, forMode: .common)
        }

        @objc private func advanceMarkerPlacement() {
            guard markerPlacementFramesRemaining > 1 else {
                markerPlacementDisplayLink?.invalidate()
                markerPlacementDisplayLink = nil
                guard let mapView,
                      !needsInitialFraming,
                      framingGeneration == markerPlacementGeneration else { return }
                defersMarkerSyncUntilCameraCommit = false
                mapView.layoutIfNeeded()
                applyLatestMapContent(in: mapView)
                scheduleNearbyFraming(afterDisplayFrames: 2)
                return
            }
            markerPlacementFramesRemaining -= 1
        }

        /// 먼저 검증된 전 지구 카메라와 annotation을 화면에 커밋한 다음,
        /// 실제 profile 또는 중앙 Heart가 겹치는 Route만 MapKit 기본 카메라로 확대한다.
        private func scheduleNearbyFraming(afterDisplayFrames frameCount: Int) {
            nearbyFramingDisplayLink?.invalidate()
            nearbyFramingGeneration = framingGeneration
            nearbyFramingFramesRemaining = max(frameCount, 1)
            let displayLink = CADisplayLink(
                target: self,
                selector: #selector(advanceNearbyFraming)
            )
            nearbyFramingDisplayLink = displayLink
            displayLink.add(to: .main, forMode: .common)
        }

        @objc private func advanceNearbyFraming() {
            guard nearbyFramingFramesRemaining > 1 else {
                nearbyFramingDisplayLink?.invalidate()
                nearbyFramingDisplayLink = nil
                nearbyFramingFramesRemaining = 0
                guard let mapView,
                      !needsInitialFraming,
                      !defersMarkerSyncUntilCameraCommit,
                      framingGeneration == nearbyFramingGeneration,
                      !hasActiveMapGesture(in: mapView) else { return }
                applyNearbyFramingIfNeeded(in: mapView)
                return
            }
            nearbyFramingFramesRemaining -= 1
        }

        private func applyNearbyFramingIfNeeded(in mapView: MKMapView) {
            guard let route = latestRoute,
                  route.id == cameraRouteID,
                  route.hasVisibleSpan else { return }

            let firstCoordinate = CLLocationCoordinate2D(
                latitude: route.first.latitude,
                longitude: route.first.longitude
            )
            let secondCoordinate = CLLocationCoordinate2D(
                latitude: route.second.latitude,
                longitude: route.second.longitude
            )

            // MapKit은 지구 뒷면 좌표도 유한한 화면 점으로 변환할 수 있다.
            // 실제 카메라 앞면에 두 도시가 모두 있을 때만 근거리 확대를 허용한다.
            let cameraCenter = SphereVector(
                latitude: mapView.camera.centerCoordinate.latitude,
                longitude: mapView.camera.centerCoordinate.longitude
            )
            let visibleRadius = GlobeMapView.visibleAngularRadius(in: mapView)
            let horizonHeadroom = 1 * Double.pi / 180
            let firstVector = SphereVector(
                latitude: firstCoordinate.latitude,
                longitude: firstCoordinate.longitude
            )
            let secondVector = SphereVector(
                latitude: secondCoordinate.latitude,
                longitude: secondCoordinate.longitude
            )
            guard cameraCenter.angularDistance(to: firstVector)
                    < visibleRadius - horizonHeadroom,
                  cameraCenter.angularDistance(to: secondVector)
                    < visibleRadius - horizonHeadroom else { return }

            let firstPoint = mapView.convert(firstCoordinate, toPointTo: mapView)
            let secondPoint = mapView.convert(secondCoordinate, toPointTo: mapView)
            guard firstPoint.x.isFinite,
                  firstPoint.y.isFinite,
                  secondPoint.x.isFinite,
                  secondPoint.y.isFinite,
                  mapView.bounds.contains(firstPoint),
                  mapView.bounds.contains(secondPoint) else { return }

            let currentGap = hypot(
                secondPoint.x - firstPoint.x,
                secondPoint.y - firstPoint.y
            )
            // profile끼리 닿지 않더라도 Route 중앙의 heartbeat 최대 크기까지
            // 양쪽 profile과 4pt 이상 떨어져야 한다. Heart 설정을 껐다 켜도
            // 카메라가 다시 움직이지 않도록 초기 framing에서 항상 이 공간을 예약한다.
            let profileOverlapTrigger = GlobeProfileAnnotationView.avatarRadius * 2 + 4
            let heartPoint = mapView.convert(route.midpointCoordinate, toPointTo: mapView)
            let heartClearance = GlobeProfileAnnotationView.avatarRadius
                + RouteHeartAnnotationView.maximumVisualRadius
                + 4
            let heartNeedsRoom: Bool
            if heartPoint.x.isFinite,
               heartPoint.y.isFinite,
               mapView.bounds.contains(heartPoint) {
                let firstHeartGap = hypot(
                    heartPoint.x - firstPoint.x,
                    heartPoint.y - firstPoint.y
                )
                let secondHeartGap = hypot(
                    heartPoint.x - secondPoint.x,
                    heartPoint.y - secondPoint.y
                )
                heartNeedsRoom = min(firstHeartGap, secondHeartGap) < heartClearance
            } else {
                heartNeedsRoom = false
            }
            guard currentGap > 0,
                  currentGap < profileOverlapTrigger || heartNeedsRoom else { return }

            let usableWidth = max(
                mapView.bounds.width
                    - mapView.layoutMargins.left
                    - mapView.layoutMargins.right,
                1
            )
            // 한 번 지역 화면으로 전환됐다면 두 도시가 화면 너비의 약 2/3를
            // 쓰도록 충분히 들어가, 지역과 두 사람의 위치 관계가 분명하게 읽힌다.
            let targetGap = min(max(usableWidth * 0.65, 236), 248)
            // Heart 때문에 새로 확대되는 경계 조합도 반쯤 잘린 지구에 멈추지 않고
            // 지역 지도까지 들어가도록 최소 확대량을 보장한다.
            let requestedGap = max(targetGap, currentGap * 3.35)

            // 작은 iPhone이나 가로 화면에서는 같은 확대율을 강제하지 않는다.
            // Route 방향을 따라 두 68×92pt profile canvas 전체가 usable rect에
            // 남을 수 있는 최대 중심 간격까지만 허용한다.
            let usableBounds = mapView.bounds.inset(by: UIEdgeInsets(
                top: 8,
                left: mapView.layoutMargins.left + 8,
                bottom: mapView.layoutMargins.bottom + 8,
                right: mapView.layoutMargins.right + 8
            ))
            let routeUnitX = abs((secondPoint.x - firstPoint.x) / currentGap)
            let routeUnitY = abs((secondPoint.y - firstPoint.y) / currentGap)
            let availableHorizontalSpan = max(
                usableBounds.width - GlobeProfileAnnotationView.canvasSize.width,
                0
            )
            let availableVerticalSpan = max(
                usableBounds.height - GlobeProfileAnnotationView.canvasSize.height,
                0
            )
            let horizontalGapLimit = routeUnitX > 0.001
                ? availableHorizontalSpan / routeUnitX
                : CGFloat.greatestFiniteMagnitude
            let verticalGapLimit = routeUnitY > 0.001
                ? availableVerticalSpan / routeUnitY
                : CGFloat.greatestFiniteMagnitude
            let safeGapLimit = min(horizontalGapLimit, verticalGapLimit) * 0.9
            let zoomScale = min(requestedGap, safeGapLimit) / currentGap
            guard zoomScale > 1 else { return }

            let camera = mapView.camera
            camera.centerCoordinateDistance /= zoomScale
            camera.centerCoordinate = route.midpointCoordinate
            camera.pitch = 0
            commitNativeMarkersForNearbyFraming(in: mapView)
            mapView.setCamera(
                camera,
                animated: !UIAccessibility.isReduceMotionEnabled
            )
        }

        /// 이전 Route에서 뒷면/숨김이었던 profile도 새 근거리 확대가 시작되기
        /// 직전에 실제 도시 annotation으로 확정해, 사람 없이 지도만 확대되지 않게 한다.
        private func commitNativeMarkersForNearbyFraming(in mapView: MKMapView) {
            for id in [GlobeProfileMarker.ID.mine, .partner] {
                guard let annotation = annotationsByID[id],
                      let indicator = backsideIndicatorsByID[id] else { continue }
                nativeFadeInMarkerIDs.remove(id)
                setMarkerRepresentation(
                    .native,
                    for: id,
                    nativeView: mapView.view(for: annotation)
                        as? GlobeProfileAnnotationView,
                    indicator: indicator,
                    fadesIn: false
                )
            }
        }

        private func cancelNearbyFraming() {
            nearbyFramingDisplayLink?.invalidate()
            nearbyFramingDisplayLink = nil
            nearbyFramingFramesRemaining = 0
        }

        private func hasActiveMapGesture(in view: UIView) -> Bool {
            if view.gestureRecognizers?.contains(where: {
                $0.state == .began || $0.state == .changed
            }) == true {
                return true
            }
            return view.subviews.contains(where: hasActiveMapGesture(in:))
        }

        func mapView(
            _ mapView: MKMapView,
            viewFor annotation: any MKAnnotation
        ) -> MKAnnotationView? {
            if annotation is GlobeProjectionProbeAnnotation {
                return GlobeProjectionProbeView(
                    annotation: annotation,
                    reuseIdentifier: nil
                )
            }
            if annotation is RouteHeartAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: RouteHeartAnnotationView.reuseIdentifier,
                    for: annotation
                )
                if let heartAnnotation = annotation as? RouteHeartAnnotation,
                   let heartView = view as? RouteHeartAnnotationView {
                    heartView.configure(
                        emoji: heartAnnotation.emoji,
                        animatesHeartbeat: latestAnimatesRouteHeart
                    )
                }
                return view
            }

            guard let annotation = annotation as? GlobeProfileAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: GlobeProfileAnnotationView.reuseIdentifier,
                for: annotation
            )
            guard let profileView = view as? GlobeProfileAnnotationView else { return view }
            profileView.configure(with: annotation.marker)
            profileView.setBacksidePresentation(false)
            profileView.setSide(markerOrder.wrappedValue.side(for: annotation.id))
            profileView.setCoordinateOffsetX(
                coincidentCoordinateOffsetX(for: annotation.id)
            )
            profileView.onActivate = { [weak self, weak mapView] in
                guard let self, let mapView else { return }
                self.activate(annotation, in: mapView)
            }
            let hidesNative = backsideMarkerIDs.contains(annotation.id)
                || hiddenMarkerIDs.contains(annotation.id)
            let fadesInNative = nativeFadeInMarkerIDs.remove(annotation.id) != nil
            profileView.alpha = hidesNative || fadesInNative ? 0 : 1
            profileView.isHidden = hidesNative
            profileView.isEnabled = !hidesNative
            if fadesInNative, !hidesNative {
                UIView.animate(
                    withDuration: 0.22,
                    delay: 0,
                    options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]
                ) {
                    profileView.alpha = 1
                }
            }
            return profileView
        }

        private func resolveMarkerOrderOnce(in mapView: MKMapView) {
            guard resolvedMarkerOrderRouteID != cameraRouteID,
                  !markerOrderResolutionScheduled else { return }
            markerOrderResolutionScheduled = true
            let routeID = cameraRouteID
            DispatchQueue.main.async { [weak self, weak mapView] in
                guard let self else { return }
                self.markerOrderResolutionScheduled = false
                guard let mapView,
                      self.cameraRouteID == routeID else { return }
                self.resolveMarkerOrder(in: mapView)
            }
        }

        private func resolveMarkerOrder(in mapView: MKMapView) {
            guard resolvedMarkerOrderRouteID != cameraRouteID else { return }
            guard let mine = annotationsByID[.mine],
                  let partner = annotationsByID[.partner] else { return }

            let mineX = displayedX(for: mine, in: mapView)
            let partnerX = displayedX(for: partner, in: mapView)
            let currentOrder = markerOrder.wrappedValue
            let nextOrder: GlobeMarkerOrder
            let horizontalGap = partnerX - mineX
            let crossingTolerance: CGFloat = 8
            if horizontalGap > crossingTolerance {
                nextOrder = .mineOnLeft
            } else if horizontalGap < -crossingTolerance {
                nextOrder = GlobeMarkerOrder(left: .partner)
            } else {
                nextOrder = currentOrder
            }

            if nextOrder != currentOrder {
                markerOrder.wrappedValue = nextOrder
            }
            resolvedMarkerOrderRouteID = cameraRouteID
            applyMarkerSides(nextOrder, in: mapView)
        }

        private func displayedX(
            for annotation: GlobeProfileAnnotation,
            in mapView: MKMapView
        ) -> CGFloat {
            if backsideMarkerIDs.contains(annotation.id),
               let indicator = backsideIndicatorsByID[annotation.id],
               !indicator.isHidden {
                return mapView.convert(
                    CGPoint(x: indicator.bounds.midX, y: indicator.bounds.midY),
                    from: indicator
                ).x
            }
            if let view = mapView.view(for: annotation) as? GlobeProfileAnnotationView {
                return mapView.convert(view.bounds, from: view).midX
            }
            return mapView.convert(annotation.coordinate, toPointTo: mapView).x
        }

        private func applyMarkerSides(
            _ order: GlobeMarkerOrder,
            in mapView: MKMapView
        ) {
            for (id, annotation) in annotationsByID {
                (mapView.view(for: annotation) as? GlobeProfileAnnotationView)?
                    .setSide(order.side(for: id))
                backsideIndicatorsByID[id]?.setSide(order.side(for: id))
            }
            applyCoincidentMarkerOffsets(in: mapView)
        }

        private func activate(
            _ annotation: GlobeProfileAnnotation,
            in mapView: MKMapView
        ) {
            guard selection.wrappedValue?.id != annotation.id else { return }
            let anchor: CGPoint
            if let view = mapView.view(for: annotation) as? GlobeProfileAnnotationView {
                let frame = mapView.convert(view.bounds, from: view)
                anchor = CGPoint(x: frame.midX, y: frame.midY)
            } else {
                anchor = mapView.convert(annotation.coordinate, toPointTo: mapView)
            }
            selection.wrappedValue = GlobeMarkerSelection(
                id: annotation.id,
                anchor: anchor
            )
        }

        private func activateBacksideMarker(
            _ id: GlobeProfileMarker.ID,
            indicator: GlobeBacksideIndicatorView,
            in mapView: NativeGlobeMapView
        ) {
            guard selection.wrappedValue?.id != id else { return }
            let anchor = mapView.convert(
                CGPoint(x: indicator.bounds.midX, y: indicator.bounds.midY),
                from: indicator
            )
            selection.wrappedValue = GlobeMarkerSelection(id: id, anchor: anchor)
            syncSelection(in: mapView)
        }

        func mapView(
            _ mapView: MKMapView,
            rendererFor overlay: any MKOverlay
        ) -> MKOverlayRenderer {
            guard let route = overlay as? MKGeodesicPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: route)
            renderer.strokeColor = UIColor.white.withAlphaComponent(0.7)
            renderer.lineWidth = 1.35
            renderer.lineCap = .round
            renderer.lineJoin = .round
            renderer.lineDashPattern = [4, 5]
            return renderer
        }

        func mapView(
            _ mapView: MKMapView,
            didSelect view: MKAnnotationView
        ) {
            guard !isSynchronizingSelection,
                  let annotation = view.annotation as? GlobeProfileAnnotation,
                  !backsideMarkerIDs.contains(annotation.id),
                  !hiddenMarkerIDs.contains(annotation.id),
                  selection.wrappedValue?.id != annotation.id else { return }
            let frame = mapView.convert(view.bounds, from: view)
            selection.wrappedValue = GlobeMarkerSelection(
                id: annotation.id,
                anchor: CGPoint(x: frame.midX, y: frame.midY)
            )
        }

        func mapView(
            _ mapView: MKMapView,
            didDeselect view: MKAnnotationView
        ) {
            guard !isSynchronizingSelection,
                  let annotation = view.annotation as? GlobeProfileAnnotation else { return }
            DispatchQueue.main.async { [weak self, weak mapView] in
                guard let self,
                      let mapView,
                      !self.backsideMarkerIDs.contains(annotation.id),
                      !self.hiddenMarkerIDs.contains(annotation.id),
                      !mapView.selectedAnnotations.contains(where: {
                          $0 is GlobeProfileAnnotation
                      }),
                      self.selection.wrappedValue?.id == annotation.id else { return }
                self.selection.wrappedValue = nil
            }
        }

        func mapView(
            _ mapView: MKMapView,
            regionWillChangeAnimated animated: Bool
        ) {
            if hasActiveMapGesture(in: mapView) {
                cancelNearbyFraming()
            }
            beginUserCameraMotion()
            selection.wrappedValue = nil
            backsideIndicatorsByID.values.forEach { $0.setSelected(false) }
            mapView.selectedAnnotations.forEach {
                mapView.deselectAnnotation($0, animated: true)
            }
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            guard let mapView = mapView as? NativeGlobeMapView else { return }
            guard isUserCameraMotionActive else {
                updateMarkerRepresentations(in: mapView)
                return
            }
            if backsideRevealDisplayLink != nil {
                backsideRevealFramesRemaining = 3
            }
        }

        func mapView(
            _ mapView: MKMapView,
            regionDidChangeAnimated animated: Bool
        ) {
            guard let mapView = mapView as? NativeGlobeMapView else { return }
            guard isUserCameraMotionActive else {
                updateMarkerRepresentations(in: mapView)
                return
            }
            // MapKit이 regionDidChange 뒤에도 마지막 투영값을 몇 프레임 보정하므로,
            // 최종 위치가 안정된 후 한 번만 뒷면 표시를 드러낸다.
            scheduleBacksideReveal(afterDisplayFrames: 3)
        }

        func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
            guard views.contains(where: {
                $0 is GlobeProfileAnnotationView || $0 is GlobeProjectionProbeView
            }),
                  let mapView = mapView as? NativeGlobeMapView else { return }
            DispatchQueue.main.async { [weak self, weak mapView] in
                guard let self, let mapView else { return }
                self.updateMarkerRepresentations(in: mapView)
            }
        }

    }
}

private final class RouteHeartAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var emoji: String

    init(coordinate: CLLocationCoordinate2D, emoji: String) {
        self.coordinate = coordinate
        self.emoji = emoji
        super.init()
    }
}

private final class RouteHeartAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "RouteHeartAnnotationView"
    static let canvasSize = CGSize(width: 32, height: 32)
    static let maximumHeartbeatScale: CGFloat = 1.24
    static let maximumVisualRadius = canvasSize.width / 2 * maximumHeartbeatScale

    private let heartLabel = UILabel()
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var animatesHeartbeat = true

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)

        bounds = CGRect(origin: .zero, size: Self.canvasSize)
        backgroundColor = .clear
        isOpaque = false
        canShowCallout = false
        displayPriority = .required
        collisionMode = .none
        isAccessibilityElement = true
        accessibilityLabel = "두 사람을 잇는 하트"

        heartLabel.font = .systemFont(ofSize: 22)
        heartLabel.textAlignment = .center
        heartLabel.frame = bounds
        heartLabel.layer.shadowColor = UIColor.black.cgColor
        heartLabel.layer.shadowOpacity = 0.45
        heartLabel.layer.shadowRadius = 3
        heartLabel.layer.shadowOffset = .zero
        addSubview(heartLabel)

        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.restartHeartbeatIfVisible()
            },
            center.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.stopHeartbeat()
            },
            center.addObserver(
                forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.restartHeartbeatIfVisible()
            }
        ]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        window == nil ? stopHeartbeat() : startHeartbeatIfVisible()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        stopHeartbeat()
    }

    func configure(emoji: String, animatesHeartbeat: Bool) {
        heartLabel.text = emoji
        accessibilityLabel = "두 사람을 잇는 \(emoji)"
        self.animatesHeartbeat = animatesHeartbeat
        if animatesHeartbeat {
            startHeartbeatIfVisible()
        } else {
            stopHeartbeat()
        }
    }

    private func startHeartbeatIfVisible() {
        guard window != nil,
              UIApplication.shared.applicationState == .active,
              animatesHeartbeat,
              !UIAccessibility.isReduceMotionEnabled,
              heartLabel.layer.animation(forKey: "singleHeartbeat") == nil else { return }

        let heartbeat = CAKeyframeAnimation(keyPath: "transform.scale")
        heartbeat.values = [1, Self.maximumHeartbeatScale, 1, 1]
        heartbeat.keyTimes = [0, 0.12, 0.26, 1]
        heartbeat.duration = 1.45
        heartbeat.repeatCount = .infinity
        heartbeat.calculationMode = .cubic
        heartLabel.layer.add(heartbeat, forKey: "singleHeartbeat")
    }

    private func restartHeartbeatIfVisible() {
        stopHeartbeat()
        startHeartbeatIfVisible()
    }

    private func stopHeartbeat() {
        heartLabel.layer.removeAnimation(forKey: "singleHeartbeat")
    }
}

private final class GlobeProjectionProbeAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init()
    }

}

private final class GlobeProjectionProbeView: MKAnnotationView {
    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        backgroundColor = .clear
        isOpaque = false
        alpha = 0.001
        isEnabled = false
        displayPriority = .required
        collisionMode = .none
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
    static let canvasSize = CGSize(width: 68, height: 92)
    static let avatarRadius: CGFloat = 23
    /// 지구 뒷면 방향 표현의 실제 표시 영역(배터리·아바타·배지).
    static let backsideContentHeight: CGFloat = 77

    private enum Layout {
        static let canvasSize = GlobeProfileAnnotationView.canvasSize
        static let avatarSize = GlobeProfileAnnotationView.avatarRadius * 2
        /// 배터리 바(17pt) + 여백(5pt) 아래에서 아바타가 시작한다.
        static let avatarTop: CGFloat = 22
        static let avatarCenterY = avatarTop + avatarSize / 2
        static let batteryHeight: CGFloat = 17
        static let batteryBodySize = CGSize(width: 21, height: 10.5)
        static let batteryCapSize = CGSize(width: 1.6, height: 4.4)
    }

    /// 도시 좌표가 프로필 원의 중심과 정확히 겹치도록 annotation 캔버스를 보정한다.
    static var avatarCenterOffset: CGPoint {
        CGPoint(
            x: 0,
            y: Layout.canvasSize.height / 2 - Layout.avatarCenterY
        )
    }

    private let selectionHaloView = UIView()
    private let avatarView = UIView()
    private let avatarImageView = UIImageView()
    private let fallbackLabel = UILabel()
    private let signalBadgeView = UIView()
    private let signalBadgeImageView = UIImageView()
    private let tapControl = UIControl()
    private let batteryPillView = UIView()
    private let batteryBodyView = UIView()
    private let batteryFillView = UIView()
    private let batteryCapView = UIView()
    private let batteryBoltImageView = UIImageView()
    private var batteryDisplay: GlobeBatteryDisplay?
    private var markerSide = GlobeMarkerSide.left
    private var isBacksidePresentation = false
    private let tapFeedback = UIImpactFeedbackGenerator(style: .medium)
    var onActivate: (() -> Void)?

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)

        bounds = CGRect(origin: .zero, size: Layout.canvasSize)
        centerOffset = Self.avatarCenterOffset
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
        canShowCallout = false
        displayPriority = .required
        collisionMode = .circle
        isAccessibilityElement = true
        accessibilityTraits = [.button]

        selectionHaloView.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        selectionHaloView.alpha = 0
        addSubview(selectionHaloView)

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

        signalBadgeView.backgroundColor = .clear
        addSubview(signalBadgeView)

        signalBadgeImageView.contentMode = .center
        signalBadgeImageView.layer.shadowColor = UIColor.black.cgColor
        signalBadgeImageView.layer.shadowOpacity = 0.22
        signalBadgeImageView.layer.shadowRadius = 1.5
        signalBadgeImageView.layer.shadowOffset = CGSize(width: 0, height: 1)
        signalBadgeView.addSubview(signalBadgeImageView)

        // iOS 상태 바 배터리를 닮은 작은 배터리 바. 아바타 바로 위에 뜬다.
        batteryPillView.backgroundColor = .clear
        batteryPillView.layer.cornerRadius = Layout.batteryHeight / 2
        batteryPillView.layer.borderWidth = 0
        batteryPillView.isHidden = true
        addSubview(batteryPillView)

        batteryBodyView.backgroundColor = .clear
        batteryBodyView.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        batteryBodyView.layer.borderWidth = 1
        batteryBodyView.layer.cornerRadius = 3
        batteryPillView.addSubview(batteryBodyView)

        batteryFillView.layer.cornerRadius = 1.2
        batteryBodyView.addSubview(batteryFillView)

        batteryCapView.backgroundColor = UIColor.white.withAlphaComponent(0.9)
        batteryCapView.layer.cornerRadius = Layout.batteryCapSize.width / 2
        batteryPillView.addSubview(batteryCapView)

        batteryBoltImageView.image = UIImage(
            systemName: "bolt.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 7, weight: .bold)
        )
        batteryBoltImageView.tintColor = .white
        batteryBoltImageView.contentMode = .center
        batteryBoltImageView.layer.shadowColor = UIColor.black.cgColor
        batteryBoltImageView.layer.shadowOpacity = 0.5
        batteryBoltImageView.layer.shadowRadius = 1
        batteryBoltImageView.layer.shadowOffset = .zero
        batteryBoltImageView.isHidden = true
        batteryPillView.addSubview(batteryBoltImageView)

        tapControl.backgroundColor = .clear
        tapControl.isAccessibilityElement = false
        tapControl.addTarget(
            self,
            action: #selector(handleTouchDown),
            for: .touchDown
        )
        addSubview(tapControl)

        tapFeedback.prepare()

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
            y: Layout.avatarTop,
            width: Layout.avatarSize,
            height: Layout.avatarSize
        )
        selectionHaloView.frame = avatarView.frame.insetBy(dx: -5, dy: -5)
        selectionHaloView.layer.cornerRadius = selectionHaloView.bounds.width / 2
        avatarImageView.frame = avatarView.bounds
        fallbackLabel.frame = avatarView.bounds
        let badgeSize: CGFloat = 24
        let badgeX: CGFloat
        switch markerSide {
        case .left:
            badgeX = avatarView.frame.minX - badgeSize / 2 + 3
        case .right:
            badgeX = avatarView.frame.maxX - badgeSize / 2 - 3
        }
        signalBadgeView.frame = CGRect(
            x: badgeX,
            y: avatarView.frame.maxY - badgeSize / 2 - 3,
            width: badgeSize,
            height: badgeSize
        )
        signalBadgeImageView.frame = signalBadgeView.bounds
        tapControl.frame = avatarView.frame.insetBy(dx: -7, dy: -7)

        layoutBatteryPill()
    }

    private func layoutBatteryPill() {
        let horizontalPadding: CGFloat = 6
        let body = Layout.batteryBodySize
        let cap = Layout.batteryCapSize

        let glyphWidth = body.width + 1 + cap.width
        let pillWidth = glyphWidth + horizontalPadding * 2
        batteryPillView.frame = CGRect(
            x: (bounds.width - pillWidth) / 2,
            y: 0,
            width: pillWidth,
            height: Layout.batteryHeight
        )

        batteryBodyView.frame = CGRect(
            x: horizontalPadding,
            y: (Layout.batteryHeight - body.height) / 2,
            width: body.width,
            height: body.height
        )
        batteryCapView.frame = CGRect(
            x: batteryBodyView.frame.maxX + 1,
            y: batteryBodyView.frame.midY - cap.height / 2,
            width: cap.width,
            height: cap.height
        )
        batteryBoltImageView.frame = batteryBodyView.frame
        updateBatteryFillFrame()
    }

    private func updateBatteryFillFrame() {
        guard let display = batteryDisplay else { return }
        let inner = batteryBodyView.bounds.insetBy(dx: 2, dy: 2)
        let ratio = CGFloat(min(max(display.level, 0), 100)) / 100
        let width = display.level > 0 ? max(inner.width * ratio, 1.5) : 0
        batteryFillView.frame = CGRect(
            x: inner.minX,
            y: inner.minY,
            width: width,
            height: inner.height
        )
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onActivate = nil
        avatarView.layer.removeAllAnimations()
        selectionHaloView.layer.removeAllAnimations()
        avatarView.transform = .identity
        selectionHaloView.transform = .identity
        selectionHaloView.alpha = 0
        avatarImageView.image = nil
        signalBadgeImageView.image = nil
        signalBadgeView.isHidden = true
        fallbackLabel.text = nil
        batteryDisplay = nil
        batteryPillView.isHidden = true
        batteryPillView.alpha = 1
        batteryBoltImageView.isHidden = true
        accessibilityLabel = nil
        accessibilityValue = nil
        setBacksidePresentation(false)
        setCoordinateOffsetX(0)
        accessibilityTraits = [.button]
        tapFeedback.prepare()
    }

    func setSide(_ side: GlobeMarkerSide) {
        guard markerSide != side else { return }
        markerSide = side
        setNeedsLayout()
    }

    func setCoordinateOffsetX(_ horizontalOffset: CGFloat) {
        let nextOffset = CGPoint(
            x: horizontalOffset,
            y: Self.avatarCenterOffset.y
        )
        guard centerOffset != nextOffset else { return }
        centerOffset = nextOffset
    }

    func setBacksidePresentation(_ isBacksidePresentation: Bool) {
        self.isBacksidePresentation = isBacksidePresentation
        avatarView.alpha = isBacksidePresentation ? 0.94 : 1
        accessibilityHint = "두 번 탭하면 프로필 상태를 표시합니다"
        updateAccessibilityValue()
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        let selectionChanged = selected != isSelected
        super.setSelected(selected, animated: animated)
        guard selectionChanged else { return }

        accessibilityTraits = selected ? [.button, .selected] : [.button]
        updateAccessibilityValue()
        if !selected {
            clearSelection()
        }
    }

    override func accessibilityActivate() -> Bool {
        handleTouchDown()
        return true
    }

    @objc private func handleTouchDown() {
        playTapFeedback()
        tapFeedback.impactOccurred(intensity: 0.9)
        tapFeedback.prepare()
        onActivate?()
    }

    private func playTapFeedback() {
        avatarView.layer.removeAllAnimations()
        selectionHaloView.layer.removeAllAnimations()
        avatarView.transform = .identity
        selectionHaloView.transform = .identity
        selectionHaloView.alpha = 0

        guard !UIAccessibility.isReduceMotionEnabled else { return }

        avatarView.transform = CGAffineTransform(scaleX: 0.82, y: 0.82)
        UIView.animate(
            withDuration: 0.32,
            delay: 0,
            usingSpringWithDamping: 0.5,
            initialSpringVelocity: 0.8,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.avatarView.transform = .identity
        }
    }

    private func clearSelection() {
        avatarView.layer.removeAllAnimations()
        selectionHaloView.layer.removeAllAnimations()
        avatarView.transform = .identity
        selectionHaloView.transform = .identity
        selectionHaloView.alpha = 0
    }

    func configure(with marker: GlobeProfileMarker) {
        if let signal = marker.signal {
            signalBadgeImageView.image = EmojiStickerRenderer.image(
                for: signal.emoji
            )
            signalBadgeView.isHidden = false
        } else {
            signalBadgeImageView.image = nil
            signalBadgeView.isHidden = true
        }

        if let data = marker.avatarData, let image = UIImage(data: data) {
            avatarView.backgroundColor = UIColor(white: 0.12, alpha: 1)
            avatarImageView.image = image
            avatarImageView.isHidden = false
            fallbackLabel.isHidden = true
        } else {
            avatarView.backgroundColor = UIColor(white: 0.12, alpha: 1)
            avatarImageView.image = nil
            avatarImageView.isHidden = true
            fallbackLabel.text = ProfileAvatarImage.fallbackInitial(for: marker.displayName)
            fallbackLabel.isHidden = false
        }

        applyBattery(marker.battery)

        let signalDescription = marker.signal.map { ", Signal \($0.title)" } ?? ""
        let batteryDescription = marker.battery.map { display in
            var text = ", 배터리 약 \(display.level)퍼센트"
            if display.isCharging { text += " 충전 중" }
            if display.isMuted { text += ", 조금 전 값" }
            return text
        } ?? ""
        accessibilityLabel =
            "\(marker.displayName), \(marker.city.name) 프로필\(signalDescription)\(batteryDescription)"
        updateAccessibilityValue()
    }

    private func updateAccessibilityValue() {
        var values: [String] = []
        if isBacksidePresentation {
            values.append("지구 반대편 방향")
        }
        if isSelected {
            values.append("선택됨")
        }
        accessibilityValue = values.isEmpty ? nil : values.joined(separator: ", ")
    }

    private func applyBattery(_ display: GlobeBatteryDisplay?) {
        batteryDisplay = display
        guard let display else {
            batteryPillView.isHidden = true
            batteryPillView.alpha = 1
            batteryBoltImageView.isHidden = true
            return
        }

        batteryPillView.isHidden = false
        batteryBoltImageView.isHidden = !display.isCharging

        let fillColor: UIColor
        if display.isMuted {
            fillColor = UIColor(white: 0.72, alpha: 0.9)
        } else if display.isCharging {
            fillColor = .systemGreen
        } else if display.level <= 20 {
            fillColor = .systemRed
        } else {
            fillColor = .systemGreen
        }
        batteryFillView.backgroundColor = fillColor
        batteryPillView.alpha = display.isMuted ? 0.62 : 1

        setNeedsLayout()
    }
}

/// 지도 좌표를 바꾸지 않고, 실제 도시가 뒷면에 있다는 방향만 화면 위에 표시한다.
private final class GlobeBacksideIndicatorView: UIView {
    private static let size = CGSize(width: 92, height: 92)

    private let profileView = GlobeProfileAnnotationView(
        annotation: nil,
        reuseIdentifier: nil
    )

    var onActivate: (() -> Void)? {
        didSet {
            profileView.onActivate = onActivate
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        bounds = CGRect(origin: .zero, size: Self.size)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
        isAccessibilityElement = false

        profileView.setBacksidePresentation(true)
        addSubview(profileView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        profileView.bounds = CGRect(origin: .zero, size: profileView.bounds.size)
        profileView.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let profilePoint = convert(point, to: profileView)
        guard profileView.bounds.insetBy(dx: 4, dy: 14).contains(profilePoint) else {
            return nil
        }
        return profileView.hitTest(profilePoint, with: event)
    }

    func configure(with marker: GlobeProfileMarker) {
        profileView.configure(with: marker)
        profileView.setBacksidePresentation(true)
    }

    func setSide(_ side: GlobeMarkerSide) {
        profileView.setSide(side)
    }

    func setSelected(_ selected: Bool) {
        profileView.setSelected(selected, animated: false)
    }

    func setProfileScale(_ scale: CGFloat) {
        profileView.transform = CGAffineTransform(scaleX: scale, y: scale)
    }

}

private final class GlobePresentationOverlayView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        return hitView === self ? nil : hitView
    }
}

/// 어떤 유니코드 이모지든 같은 크기와 외곽선 규칙으로 스티커 이미지로 만든다.
private enum EmojiStickerRenderer {
    private static var cache: [String: UIImage] = [:]

    static func image(
        for emoji: String,
        pointSize: CGFloat = 15,
        outlineWidth: CGFloat = 1.5
    ) -> UIImage {
        let scale = UIScreen.main.scale
        let cacheKey = "\(emoji)-\(pointSize)-\(outlineWidth)-\(scale)"
        if let cached = cache[cacheKey] {
            return cached
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: pointSize)
        ]
        let measuredSize = (emoji as NSString).size(withAttributes: attributes)
        let glyphSize = CGSize(
            width: max(1, ceil(measuredSize.width)),
            height: max(1, ceil(measuredSize.height))
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        let glyphRenderer = UIGraphicsImageRenderer(size: glyphSize, format: format)
        let glyphImage = glyphRenderer.image { _ in
            (emoji as NSString).draw(
                in: CGRect(origin: .zero, size: glyphSize),
                withAttributes: attributes
            )
        }
        let silhouette = glyphRenderer.image { context in
            glyphImage.draw(in: CGRect(origin: .zero, size: glyphSize))
            context.cgContext.setBlendMode(.sourceIn)
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: glyphSize))
        }

        let padding = outlineWidth + 1
        let outputSize = CGSize(
            width: glyphSize.width + padding * 2,
            height: glyphSize.height + padding * 2
        )
        let outputRenderer = UIGraphicsImageRenderer(size: outputSize, format: format)
        let output = outputRenderer.image { context in
            context.cgContext.interpolationQuality = .high
            let origin = CGPoint(x: padding, y: padding)
            let samples = 24
            for index in 0..<samples {
                let angle = CGFloat(index) / CGFloat(samples) * .pi * 2
                silhouette.draw(
                    at: CGPoint(
                        x: origin.x + cos(angle) * outlineWidth,
                        y: origin.y + sin(angle) * outlineWidth
                    )
                )
            }
            glyphImage.draw(at: origin)
        }

        cache[cacheKey] = output
        return output
    }
}

final class NativeGlobeMapView: MKMapView {
    var onUsableLayout: (() -> Void)?
    fileprivate let presentationOverlayView = GlobePresentationOverlayView()

    private var lastUsableSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(presentationOverlayView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // 탭 바 안전 영역 + 54pt CTA + 8pt 여백 + Apple 권장 간격 10pt.
        layoutMargins = UIEdgeInsets(
            top: 0,
            left: 7,
            bottom: safeAreaInsets.bottom + 72,
            right: 7
        )

        presentationOverlayView.frame = bounds
        bringSubviewToFront(presentationOverlayView)

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
            avatarData: nil,
            signal: .free,
            battery: GlobeBatteryDisplay(level: 18, isCharging: false, isMuted: false)
        ),
        partnerMarker: GlobeProfileMarker(
            id: .partner,
            displayName: "Sofia",
            city: CoupleCity.city(id: "paris"),
            avatarData: nil,
            signal: .resting,
            battery: GlobeBatteryDisplay(level: 87, isCharging: true, isMuted: false)
        ),
        markerOrder: .constant(.mineOnLeft),
        selection: .constant(nil),
        showsRouteHeart: true,
        animatesRouteHeart: true,
        routeHeartEmoji: RouteHeartEmoji.pink.rawValue
    )
    .ignoresSafeArea()
}
