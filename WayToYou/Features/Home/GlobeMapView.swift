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

        var coordinates: [CLLocationCoordinate2D] {
            [first, second].map {
                CLLocationCoordinate2D(
                    latitude: $0.latitude,
                    longitude: $0.longitude
                )
            }
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

            // 원래의 시각적 중심을 유지하되 어느 도시도 이론적인 앞 반구를 넘지 않게 한다.
            // 실제 MapKit 지평선보다 먼 도시는 별도의 뒷면 방향 표시가 담당한다.
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
        private var needsInitialFraming = false
        private var defersMarkerSyncUntilCameraCommit = false
        private var framingGeneration = 0
        private var markerPlacementGeneration = 0
        private var markerPlacementFramesRemaining = 0
        private var markerPlacementDisplayLink: CADisplayLink?
        private var markerTrackingDisplayLink: CADisplayLink?
        private var markerTrackingFramesRemaining: Int?
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
        private var maximumCameraDistance: CLLocationDistance?

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
                self.updateMarkerRepresentations(in: mapView, animated: false)
            }
        }

        func disconnect() {
            markerPlacementDisplayLink?.invalidate()
            markerPlacementDisplayLink = nil
            markerTrackingDisplayLink?.invalidate()
            markerTrackingDisplayLink = nil
            markerTrackingFramesRemaining = nil
            markerOrderResolutionScheduled = false
            backsideIndicatorsByID.values.forEach { $0.removeFromSuperview() }
            backsideIndicatorsByID.removeAll()
            backsideMarkerSnapshots.removeAll()
            backsideMarkerIDs.removeAll()
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
                if let routeOverlay {
                    mapView.removeOverlay(routeOverlay)
                    self.routeOverlay = nil
                }
                if let routeHeartAnnotation {
                    mapView.removeAnnotation(routeHeartAnnotation)
                    self.routeHeartAnnotation = nil
                }
                appliedRoute = latestRoute

                if let latestRoute, latestRoute.hasVisibleSpan {
                    var coordinates = latestRoute.coordinates
                    let overlay = MKGeodesicPolyline(
                        coordinates: &coordinates,
                        count: coordinates.count
                    )
                    routeOverlay = overlay
                    mapView.addOverlay(overlay, level: .aboveLabels)
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

            updateMarkerRepresentations(in: mapView, animated: false)
            syncSelection(in: mapView)
            resolveMarkerOrderOnce(in: mapView)
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
            mapView.backsideOverlayView.addSubview(indicator)
            return indicator
        }

        private func updateMarkerRepresentations(
            in mapView: NativeGlobeMapView,
            animated: Bool
        ) {
            guard !needsInitialFraming,
                  !defersMarkerSyncUntilCameraCommit,
                  mapView.bounds.width > 0,
                  mapView.bounds.height > 0 else { return }

            let cameraCenter = SphereVector(
                latitude: mapView.camera.centerCoordinate.latitude,
                longitude: mapView.camera.centerCoordinate.longitude
            )
            let horizon = GlobeMapView.visibleAngularRadius(in: mapView)
            // 들어올 때와 나갈 때 경계를 조금 다르게 둬 limb 근처 깜빡임을 막는다.
            let frontMargin = min(0.25 * Double.pi / 180, horizon * 0.01)
            let backMargin = min(0.05 * Double.pi / 180, horizon * 0.002)
            let frontRadius = max(horizon - frontMargin, 0)
            let backRadius = max(horizon - backMargin, 0)

            for marker in latestMarkers {
                guard let annotation = annotationsByID[marker.id],
                      let indicator = backsideIndicatorsByID[marker.id] else { continue }

                let city = SphereVector(
                    latitude: marker.city.latitude,
                    longitude: marker.city.longitude
                )
                let distance = cameraCenter.angularDistance(to: city)
                let nativeView = mapView.view(for: annotation) as? GlobeProfileAnnotationView
                let nativeIsSafe = nativeView.map {
                    nativeViewIsSafelyVisible($0, in: mapView)
                } ?? false
                let isCurrentlyBackside = backsideMarkerIDs.contains(marker.id)
                let cameraIsLevel = abs(mapView.camera.pitch) < 1

                let shouldShowBackside: Bool
                if cameraIsLevel {
                    if isCurrentlyBackside {
                        shouldShowBackside = !(distance <= frontRadius && nativeIsSafe)
                    } else {
                        shouldShowBackside = distance >= backRadius
                    }
                } else if nativeIsSafe {
                    // 기울어진 카메라는 horizon이 비대칭이므로 실제 렌더링 결과를 우선한다.
                    shouldShowBackside = false
                } else {
                    shouldShowBackside = isCurrentlyBackside || distance >= backRadius
                }

                if shouldShowBackside || isCurrentlyBackside {
                    positionBacksideIndicator(
                        indicator,
                        annotation: annotation,
                        nativeView: nativeView,
                        toward: city,
                        from: cameraCenter,
                        distanceFromCenter: distance,
                        handoffRadius: backRadius,
                        horizon: horizon,
                        in: mapView
                    )
                }
                setBacksideRepresentation(
                    shouldShowBackside,
                    for: marker.id,
                    nativeView: nativeView,
                    indicator: indicator,
                    animated: animated
                )
            }
            syncSelection(in: mapView)
        }

        private func nativeViewIsSafelyVisible(
            _ view: GlobeProfileAnnotationView,
            in mapView: NativeGlobeMapView
        ) -> Bool {
            guard view.superview != nil else { return false }
            let frame = mapView.convert(view.bounds, from: view)
            let safeRect = mapView.bounds.inset(by: UIEdgeInsets(
                top: 4,
                left: 4,
                bottom: mapView.layoutMargins.bottom + 4,
                right: 4
            ))
            return frame.minX.isFinite
                && frame.minY.isFinite
                && frame.maxX.isFinite
                && frame.maxY.isFinite
                && safeRect.contains(frame)
        }

        private func setBacksideRepresentation(
            _ showsBackside: Bool,
            for id: GlobeProfileMarker.ID,
            nativeView: GlobeProfileAnnotationView?,
            indicator: GlobeBacksideIndicatorView,
            animated: Bool
        ) {
            let stateChanged = backsideMarkerIDs.contains(id) != showsBackside
            if showsBackside {
                backsideMarkerIDs.insert(id)
            } else {
                backsideMarkerIDs.remove(id)
            }

            indicator.setSelected(selection.wrappedValue?.id == id)
            guard stateChanged else { return }

            // 두 표현은 전환 직전에 같은 프레임에 놓인다. 애니메이션을 겹치지 않고
            // 소유권만 즉시 바꾸면 드래그 중에도 위치가 한 프레임도 튀지 않는다.
            indicator.layer.removeAllAnimations()
            nativeView?.layer.removeAllAnimations()
            indicator.alpha = showsBackside ? 1 : 0
            indicator.isHidden = !showsBackside
            nativeView?.alpha = showsBackside ? 0 : 1
            nativeView?.isHidden = showsBackside
            nativeView?.isEnabled = !showsBackside
        }

        private func positionBacksideIndicator(
            _ indicator: GlobeBacksideIndicatorView,
            annotation: GlobeProfileAnnotation,
            nativeView: GlobeProfileAnnotationView?,
            toward city: SphereVector,
            from cameraCenter: SphereVector,
            distanceFromCenter: Double,
            handoffRadius: Double,
            horizon: Double,
            in mapView: NativeGlobeMapView
        ) {
            let cityDistance = cameraCenter.angularDistance(to: city)
            // 지평선 바로 위 좌표는 MapKit convert가 뒤쪽 값으로 튈 수 있다.
            // 안전한 앞면 지점을 투영한 뒤 구면 원근식으로 실제 limb까지 확장한다.
            let probeAngle = min(
                cityDistance,
                max(horizon * 0.82, min(5 * .pi / 180, horizon * 0.5))
            )
            let probeCoordinate = cameraCenter.moved(toward: city, by: probeAngle).coordinate
            let fallbackCenter = CGPoint(x: mapView.bounds.midX, y: mapView.bounds.midY)
            let convertedCenter = mapView.convert(
                mapView.camera.centerCoordinate,
                toPointTo: mapView
            )
            let mapCenter = convertedCenter.x.isFinite && convertedCenter.y.isFinite
                ? convertedCenter
                : fallbackCenter
            // 실제 대권 경로가 지구 뒤로 사라지는 지평선 교차점.
            // 도시 방향을 쓰는 것보다 보이는 점선 끝에 정확히 붙는다.
            let routeEndPoint = routeLimbPoint(
                for: annotation.id,
                hiddenCity: city,
                cameraCenter: cameraCenter,
                visibleRadius: max(horizon - 0.12 * .pi / 180, 0),
                in: mapView
            )
            var directionPoint = routeEndPoint
                ?? mapView.convert(probeCoordinate, toPointTo: mapView)

            if !directionPoint.x.isFinite
                || !directionPoint.y.isFinite
                || hypot(directionPoint.x - mapCenter.x, directionPoint.y - mapCenter.y) < 1 {
                let fallbackProbeAngle = min(
                    cityDistance,
                    max(horizon * 0.45, 5 * .pi / 180)
                )
                directionPoint = mapView.convert(
                    cameraCenter.moved(toward: city, by: fallbackProbeAngle).coordinate,
                    toPointTo: mapView
                )
            }

            var dx = directionPoint.x - mapCenter.x
            var dy = directionPoint.y - mapCenter.y
            let length = hypot(dx, dy)
            if !length.isFinite || length < 1 {
                dx = indicator === backsideIndicatorsByID[.mine] ? -1 : 1
                dy = 0
            } else {
                dx /= length
                dy /= length
            }

            // MapKit이 투영한 실제 limb 거리를 그대로 쓴다. 추정 반지름을 쓰지 않아
            // 회전·확대 중에도 프로필이 지구 표면과 따로 노는 현상이 없다.
            let fallbackRimDistance = apparentGlobeRadius(in: mapView)
            let calculatedRimDistance = projectedHorizonDistance(
                fromProbeDistance: length,
                probeAngle: probeAngle,
                in: mapView
            ) ?? fallbackRimDistance
            // MapKit은 뒷면에 가까운 convert 결과를 화면 밖으로 크게 보낼 수 있다.
            // 실제 globe 크기 범위로만 제한해 방향은 투영값을, 반경은 안정된 silhouette을 따른다.
            let projectedRimDistance = min(
                max(calculatedRimDistance, fallbackRimDistance * 0.85),
                fallbackRimDistance * 1.05
            )
            let rimPoint = routeEndPoint ?? CGPoint(
                x: mapCenter.x + dx * projectedRimDistance,
                y: mapCenter.y + dy * projectedRimDistance
            )
            let outsidePlacement = outsideMarkerPlacement(
                at: rimPoint,
                dx: dx,
                dy: dy,
                in: mapView
            )

            let transitionBand = min(6 * Double.pi / 180, max(horizon * 0.1, 1 * .pi / 180))
            let rawProgress = min(max(
                (handoffRadius + transitionBand - distanceFromCenter) / transitionBand,
                0
            ), 1)
            let transitionProgress = rawProgress * rawProgress * (3 - 2 * rawProgress)
            let nativeTarget = nativeMarkerCenter(
                for: annotation,
                nativeView: nativeView,
                in: mapView
            )
            indicator.center = CGPoint(
                x: outsidePlacement.center.x
                    + (nativeTarget.x - outsidePlacement.center.x) * transitionProgress,
                y: outsidePlacement.center.y
                    + (nativeTarget.y - outsidePlacement.center.y) * transitionProgress
            )
            let scale = outsidePlacement.scale
                + (1 - outsidePlacement.scale) * transitionProgress
            indicator.setProfileScale(scale)
        }

        private func routeLimbPoint(
            for id: GlobeProfileMarker.ID,
            hiddenCity: SphereVector,
            cameraCenter: SphereVector,
            visibleRadius: Double,
            in mapView: NativeGlobeMapView
        ) -> CGPoint? {
            guard let otherMarker = latestMarkers.first(where: { $0.id != id }) else {
                return nil
            }
            let otherCity = SphereVector(
                latitude: otherMarker.city.latitude,
                longitude: otherMarker.city.longitude
            )
            let routeSpan = hiddenCity.angularDistance(to: otherCity)
            guard routeSpan > Double.ulpOfOne,
                  cameraCenter.angularDistance(to: hiddenCity) > visibleRadius else {
                return nil
            }

            // 뒤면 도시에서 쌍의 도시 쪽으로 점선을 따라가며
            // 처음 앞면으로 들어오는 지점을 찾는다.
            let sampleCount = 64
            var outsideAngle = 0.0
            for sample in 1...sampleCount {
                let angle = routeSpan * Double(sample) / Double(sampleCount)
                let candidate = hiddenCity.moved(toward: otherCity, by: angle)
                guard cameraCenter.angularDistance(to: candidate) <= visibleRadius else {
                    outsideAngle = angle
                    continue
                }

                var lower = outsideAngle
                var upper = angle
                for _ in 0..<18 {
                    let midpoint = (lower + upper) / 2
                    let midpointCity = hiddenCity.moved(toward: otherCity, by: midpoint)
                    if cameraCenter.angularDistance(to: midpointCity) <= visibleRadius {
                        upper = midpoint
                    } else {
                        lower = midpoint
                    }
                }
                let point = mapView.convert(
                    hiddenCity.moved(toward: otherCity, by: upper).coordinate,
                    toPointTo: mapView
                )
                guard point.x.isFinite, point.y.isFinite else { return nil }
                return point
            }
            return nil
        }

        private func projectedHorizonDistance(
            fromProbeDistance probeDistance: CGFloat,
            probeAngle: Double,
            in mapView: NativeGlobeMapView
        ) -> CGFloat? {
            guard probeDistance.isFinite,
                  probeDistance > 1,
                  probeAngle > 0 else { return nil }
            let pitch = mapView.camera.pitch * .pi / 180
            let altitude = mapView.camera.centerCoordinateDistance * max(cos(pitch), 0)
            let cameraDistance = GlobeMapView.earthRadius + altitude
            let limbDenominatorSquared = cameraDistance * cameraDistance
                - GlobeMapView.earthRadius * GlobeMapView.earthRadius
            guard cameraDistance.isFinite,
                  limbDenominatorSquared > 0 else { return nil }
            let denominator = sin(probeAngle) * sqrt(limbDenominatorSquared)
            guard abs(denominator) > Double.ulpOfOne else { return nil }
            let scale = (cameraDistance
                - GlobeMapView.earthRadius * cos(probeAngle)) / denominator
            guard scale.isFinite, scale > 0 else { return nil }
            return probeDistance * CGFloat(scale)
        }

        private func nativeMarkerCenter(
            for annotation: GlobeProfileAnnotation,
            nativeView: GlobeProfileAnnotationView?,
            in mapView: NativeGlobeMapView
        ) -> CGPoint {
            if let nativeView, nativeView.superview != nil {
                let frame = mapView.convert(nativeView.bounds, from: nativeView)
                if frame.midX.isFinite, frame.midY.isFinite {
                    return CGPoint(x: frame.midX, y: frame.midY)
                }
            }
            let anchor = mapView.convert(annotation.coordinate, toPointTo: mapView)
            return CGPoint(
                x: anchor.x + GlobeProfileAnnotationView.pinCenterOffset.x,
                y: anchor.y + GlobeProfileAnnotationView.pinCenterOffset.y
            )
        }

        private func outsideMarkerPlacement(
            at rimPoint: CGPoint,
            dx: CGFloat,
            dy: CGFloat,
            in mapView: NativeGlobeMapView
        ) -> (center: CGPoint, scale: CGFloat) {
            let preferredScale: CGFloat = 0.58
            let minimumScale: CGFloat = 0.38
            let gap: CGFloat = 2
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
                let nearestProjection = min(dx * minX, dx * maxX)
                    + min(dy * minY, dy * maxY)
                let distance = -nearestProjection + gap
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
            return (placement(scale: lower).0, lower)
        }

        private func apparentGlobeRadius(in mapView: NativeGlobeMapView) -> CGFloat {
            let baseRadius = max(min(mapView.bounds.width, mapView.bounds.height) / 2 - 30, 40)
            guard let maximumCameraDistance,
                  maximumCameraDistance > 0 else { return baseRadius }

            let pitch = mapView.camera.pitch * .pi / 180
            let currentAltitude = max(
                mapView.camera.centerCoordinateDistance * max(cos(pitch), 0),
                1
            )
            let baseAngle = asin(min(GlobeMapView.earthRadius
                / (GlobeMapView.earthRadius + maximumCameraDistance), 1))
            let currentAngle = asin(min(GlobeMapView.earthRadius
                / (GlobeMapView.earthRadius + currentAltitude), 1))
            guard baseAngle > 0 else { return baseRadius }
            return min(
                baseRadius * CGFloat(tan(currentAngle) / tan(baseAngle)),
                hypot(mapView.bounds.width, mapView.bounds.height)
            )
        }

        func syncSelection(in mapView: MKMapView) {
            let selectedID = selection.wrappedValue?.id
            for (id, indicator) in backsideIndicatorsByID {
                indicator.setSelected(selectedID == id)
            }

            let desiredNativeID = selectedID.flatMap {
                backsideMarkerIDs.contains($0) ? nil : $0
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
            maximumCameraDistance = mapView.camera.centerCoordinateDistance
            mapView.setCenter(requestedFraming.center(in: mapView), animated: false)

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
                return
            }
            markerPlacementFramesRemaining -= 1
        }

        func mapView(
            _ mapView: MKMapView,
            viewFor annotation: any MKAnnotation
        ) -> MKAnnotationView? {
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
            profileView.onActivate = { [weak self, weak mapView] in
                guard let self, let mapView else { return }
                self.activate(annotation, in: mapView)
            }
            let showsBackside = backsideMarkerIDs.contains(annotation.id)
            profileView.alpha = showsBackside ? 0 : 1
            profileView.isHidden = showsBackside
            profileView.isEnabled = !showsBackside
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
            startMarkerTracking()
            let userIsMovingMap = mapView.gestureRecognizers?.contains {
                $0.state == .began || $0.state == .changed
            } ?? false
            guard userIsMovingMap else { return }
            selection.wrappedValue = nil
            backsideIndicatorsByID.values.forEach { $0.setSelected(false) }
            mapView.selectedAnnotations.forEach {
                mapView.deselectAnnotation($0, animated: true)
            }
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            guard let mapView = mapView as? NativeGlobeMapView else { return }
            updateMarkerRepresentations(in: mapView, animated: true)
        }

        func mapView(
            _ mapView: MKMapView,
            regionDidChangeAnimated animated: Bool
        ) {
            guard let mapView = mapView as? NativeGlobeMapView else { return }
            updateMarkerRepresentations(in: mapView, animated: false)
            markerTrackingFramesRemaining = 2
        }

        private func startMarkerTracking() {
            markerTrackingFramesRemaining = nil
            guard markerTrackingDisplayLink == nil else { return }
            let displayLink = CADisplayLink(
                target: self,
                selector: #selector(advanceMarkerTracking)
            )
            markerTrackingDisplayLink = displayLink
            displayLink.add(to: .main, forMode: .common)
        }

        @objc private func advanceMarkerTracking() {
            if let mapView {
                updateMarkerRepresentations(in: mapView, animated: false)
            }
            guard let remaining = markerTrackingFramesRemaining else { return }
            if remaining <= 1 {
                markerTrackingDisplayLink?.invalidate()
                markerTrackingDisplayLink = nil
                markerTrackingFramesRemaining = nil
            } else {
                markerTrackingFramesRemaining = remaining - 1
            }
        }

        func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
            guard views.contains(where: { $0 is GlobeProfileAnnotationView }),
                  let mapView = mapView as? NativeGlobeMapView else { return }
            DispatchQueue.main.async { [weak self, weak mapView] in
                guard let self, let mapView else { return }
                self.updateMarkerRepresentations(in: mapView, animated: true)
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

    private let heartLabel = UILabel()
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var animatesHeartbeat = true

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)

        bounds = CGRect(x: 0, y: 0, width: 32, height: 32)
        backgroundColor = .clear
        isOpaque = false
        canShowCallout = false
        displayPriority = .required
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
        heartbeat.values = [1, 1.24, 1, 1]
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
    /// 핀/줄을 숨긴 뒤면 표현의 실제 표시 영역(배터리·아바타·배지).
    static let backsideContentHeight: CGFloat = 77

    private enum Layout {
        static let canvasSize = GlobeProfileAnnotationView.canvasSize
        static let avatarSize: CGFloat = 46
        /// 배터리 바(17pt) + 여백(5pt) 아래에서 아바타가 시작한다.
        static let avatarTop: CGFloat = 22
        static let batteryHeight: CGFloat = 17
        static let batteryBodySize = CGSize(width: 21, height: 10.5)
        static let batteryCapSize = CGSize(width: 1.6, height: 4.4)
        static let dotSize: CGFloat = 6
        static let dotOriginY: CGFloat = 84
        static let dotCenterY = dotOriginY + dotSize / 2
    }

    static var pinCenterOffset: CGPoint {
        CGPoint(
            x: 0,
            y: Layout.canvasSize.height / 2 - Layout.dotCenterY
        )
    }

    private let stemView = UIView()
    private let dotView = UIView()
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
        centerOffset = Self.pinCenterOffset
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
        canShowCallout = false
        displayPriority = .required
        collisionMode = .circle
        isAccessibilityElement = true
        accessibilityTraits = [.button]

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

        let avatarBottom = Layout.avatarTop + Layout.avatarSize
        stemView.frame = CGRect(
            x: bounds.midX - 0.5,
            y: avatarBottom - 2,
            width: 1,
            height: Layout.dotOriginY - avatarBottom + 2
        )
        dotView.frame = CGRect(
            x: bounds.midX - Layout.dotSize / 2,
            y: Layout.dotOriginY,
            width: Layout.dotSize,
            height: Layout.dotSize
        )
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
        accessibilityTraits = [.button]
        tapFeedback.prepare()
    }

    func setSide(_ side: GlobeMarkerSide) {
        guard markerSide != side else { return }
        markerSide = side
        setNeedsLayout()
    }

    func setBacksidePresentation(_ isBacksidePresentation: Bool) {
        self.isBacksidePresentation = isBacksidePresentation
        stemView.isHidden = isBacksidePresentation
        dotView.isHidden = isBacksidePresentation
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

private final class PassthroughOverlayView: UIView {
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
    fileprivate let backsideOverlayView = PassthroughOverlayView()

    private var lastUsableSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backsideOverlayView.backgroundColor = .clear
        backsideOverlayView.isOpaque = false
        backsideOverlayView.clipsToBounds = false
        addSubview(backsideOverlayView)
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

        backsideOverlayView.frame = bounds
        bringSubviewToFront(backsideOverlayView)

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
