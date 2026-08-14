import Foundation

/// 하트 한 개가 두 프로필 사이를 자유로운 곡선으로 이동하라는 일회성 이벤트.
/// 실제 위치 애니메이션은 지도의 현재 투영을 알아야 하므로 GlobeMapView가 맡는다.
struct RouteHeartFlight: Identifiable, Equatable {
    let id = UUID()
    let incoming: Bool
}
