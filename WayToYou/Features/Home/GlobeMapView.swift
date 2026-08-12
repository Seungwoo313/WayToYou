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

        context.coordinator.connect(to: mapView)
        context.coordinator.requestInitialFraming(cameraFraming)
        context.coordinator.sync(
            markers: markers,
            route: cityRoute,
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
        private var appliedRoute: CityRoute?
        private var routeOverlay: MKGeodesicPolyline?
        private var requestedFraming: CameraFraming?
        private var needsInitialFraming = false
        private var defersMarkerSyncUntilCameraCommit = false
        private var framingGeneration = 0
        private var markerPlacementGeneration = 0
        private var markerPlacementFramesRemaining = 0
        private var markerPlacementDisplayLink: CADisplayLink?
        private var markerOrderResolutionScheduled = false
        private var resolvedMarkerOrderRouteID: String?
        private var isSynchronizingSelection = false

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
            }
        }

        func disconnect() {
            markerPlacementDisplayLink?.invalidate()
            markerPlacementDisplayLink = nil
            markerOrderResolutionScheduled = false
            mapView = nil
        }

        fileprivate func sync(
            markers: [GlobeProfileMarker],
            route: CityRoute,
            in mapView: MKMapView
        ) {
            latestMarkers = markers
            latestRoute = route
            guard !needsInitialFraming,
                  !defersMarkerSyncUntilCameraCommit else { return }
            applyLatestMapContent(in: mapView)
        }

        private func applyLatestMapContent(in mapView: MKMapView) {
            applyLatestRoute(in: mapView)
            applyLatestMarkers(in: mapView)
        }

        private func applyLatestRoute(in mapView: MKMapView) {
            guard appliedRoute != latestRoute else { return }

            if let routeOverlay {
                mapView.removeOverlay(routeOverlay)
                self.routeOverlay = nil
            }
            appliedRoute = latestRoute

            guard let latestRoute,
                  latestRoute.hasVisibleSpan else { return }
            var coordinates = latestRoute.coordinates
            let overlay = MKGeodesicPolyline(
                coordinates: &coordinates,
                count: coordinates.count
            )
            routeOverlay = overlay
            mapView.addOverlay(overlay, level: .aboveLabels)
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
            syncSelection(in: mapView)
            resolveMarkerOrderOnce(in: mapView)
        }

        func syncSelection(in mapView: MKMapView) {
            let selectedAnnotation = mapView.selectedAnnotations
                .compactMap { $0 as? GlobeProfileAnnotation }
                .first
            guard selectedAnnotation?.id != selection.wrappedValue?.id else { return }

            isSynchronizingSelection = true
            defer { isSynchronizingSelection = false }

            if let selectedAnnotation {
                mapView.deselectAnnotation(selectedAnnotation, animated: false)
            }
            if let selectedID = selection.wrappedValue?.id,
               let annotation = annotationsByID[selectedID] {
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
            mapView.setCenter(requestedFraming.center(in: mapView), animated: false)
            let camera = mapView.camera
            camera.centerCoordinateDistance *= 1000
            mapView.setCamera(camera, animated: false)

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
            guard let annotation = annotation as? GlobeProfileAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: GlobeProfileAnnotationView.reuseIdentifier,
                for: annotation
            )
            guard let profileView = view as? GlobeProfileAnnotationView else { return view }
            profileView.configure(with: annotation.marker)
            profileView.setSide(markerOrder.wrappedValue.side(for: annotation.id))
            profileView.onActivate = { [weak self, weak mapView] in
                guard let self, let mapView else { return }
                self.activate(annotation, in: mapView)
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

            let mineX = mapView.convert(mine.coordinate, toPointTo: mapView).x
            let partnerX = mapView.convert(partner.coordinate, toPointTo: mapView).x
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

        private func applyMarkerSides(
            _ order: GlobeMarkerOrder,
            in mapView: MKMapView
        ) {
            for (id, annotation) in annotationsByID {
                (mapView.view(for: annotation) as? GlobeProfileAnnotationView)?
                    .setSide(order.side(for: id))
            }
        }

        private func activate(
            _ annotation: GlobeProfileAnnotation,
            in mapView: MKMapView
        ) {
            guard selection.wrappedValue?.id != annotation.id else { return }
            selection.wrappedValue = GlobeMarkerSelection(
                id: annotation.id,
                anchor: mapView.convert(annotation.coordinate, toPointTo: mapView)
            )
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
                  selection.wrappedValue?.id != annotation.id else { return }
            selection.wrappedValue = GlobeMarkerSelection(
                id: annotation.id,
                anchor: mapView.convert(annotation.coordinate, toPointTo: mapView)
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
            let userIsMovingMap = mapView.gestureRecognizers?.contains {
                $0.state == .began || $0.state == .changed
            } ?? false
            guard userIsMovingMap else { return }
            mapView.selectedAnnotations.forEach {
                mapView.deselectAnnotation($0, animated: true)
            }
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
        static let canvasSize = CGSize(width: 68, height: 92)
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
    private let tapFeedback = UIImpactFeedbackGenerator(style: .medium)
    var onActivate: (() -> Void)?

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)

        bounds = CGRect(origin: .zero, size: Layout.canvasSize)
        centerOffset = CGPoint(
            x: 0,
            y: Layout.canvasSize.height / 2 - Layout.dotCenterY
        )
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
        batteryPillView.backgroundColor = UIColor.black.withAlphaComponent(0.42)
        batteryPillView.layer.cornerRadius = Layout.batteryHeight / 2
        batteryPillView.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        batteryPillView.layer.borderWidth = 0.5
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
        accessibilityTraits = [.button]
        tapFeedback.prepare()
    }

    func setSide(_ side: GlobeMarkerSide) {
        guard markerSide != side else { return }
        markerSide = side
        setNeedsLayout()
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        let selectionChanged = selected != isSelected
        super.setSelected(selected, animated: animated)
        guard selectionChanged else { return }

        accessibilityTraits = selected ? [.button, .selected] : [.button]
        accessibilityValue = selected ? "선택됨" : nil
        if !selected {
            clearSelection()
        }
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
        accessibilityHint = "두 번 탭하면 프로필 상태를 표시합니다"
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
            fillColor = .white
        }
        batteryFillView.backgroundColor = fillColor
        batteryPillView.alpha = display.isMuted ? 0.62 : 1

        setNeedsLayout()
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
        selection: .constant(nil)
    )
    .ignoresSafeArea()
}
