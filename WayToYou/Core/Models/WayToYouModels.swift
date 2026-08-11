import Foundation
import CoreLocation
import SwiftUI

// MARK: - City

struct CoupleCity: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let country: String
    let latitude: Double
    let longitude: Double
    let timeZoneID: String

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneID) ?? .gmt
    }

    static let presets: [CoupleCity] = [
        CoupleCity(id: "seoul", name: "서울", country: "대한민국", latitude: 37.5665, longitude: 126.9780, timeZoneID: "Asia/Seoul"),
        CoupleCity(id: "tokyo", name: "도쿄", country: "일본", latitude: 35.6762, longitude: 139.6503, timeZoneID: "Asia/Tokyo"),
        CoupleCity(id: "shanghai", name: "상하이", country: "중국", latitude: 31.2304, longitude: 121.4737, timeZoneID: "Asia/Shanghai"),
        CoupleCity(id: "singapore", name: "싱가포르", country: "싱가포르", latitude: 1.3521, longitude: 103.8198, timeZoneID: "Asia/Singapore"),
        CoupleCity(id: "jakarta", name: "자카르타", country: "인도네시아", latitude: -6.2088, longitude: 106.8456, timeZoneID: "Asia/Jakarta"),
        CoupleCity(id: "hanoi", name: "하노이", country: "베트남", latitude: 21.0278, longitude: 105.8342, timeZoneID: "Asia/Bangkok"),
        CoupleCity(id: "dubai", name: "두바이", country: "아랍에미리트", latitude: 25.2048, longitude: 55.2708, timeZoneID: "Asia/Dubai"),
        CoupleCity(id: "berlin", name: "베를린", country: "독일", latitude: 52.5200, longitude: 13.4050, timeZoneID: "Europe/Berlin"),
        CoupleCity(id: "paris", name: "파리", country: "프랑스", latitude: 48.8566, longitude: 2.3522, timeZoneID: "Europe/Paris"),
        CoupleCity(id: "lisbon", name: "리스본", country: "포르투갈", latitude: 38.7223, longitude: -9.1393, timeZoneID: "Europe/Lisbon"),
        CoupleCity(id: "london", name: "런던", country: "영국", latitude: 51.5072, longitude: -0.1276, timeZoneID: "Europe/London"),
        CoupleCity(id: "new-york", name: "뉴욕", country: "미국", latitude: 40.7128, longitude: -74.0060, timeZoneID: "America/New_York"),
        CoupleCity(id: "toronto", name: "토론토", country: "캐나다", latitude: 43.6532, longitude: -79.3832, timeZoneID: "America/Toronto"),
        CoupleCity(id: "los-angeles", name: "로스앤젤레스", country: "미국", latitude: 34.0522, longitude: -118.2437, timeZoneID: "America/Los_Angeles"),
        CoupleCity(id: "vancouver", name: "밴쿠버", country: "캐나다", latitude: 49.2827, longitude: -123.1207, timeZoneID: "America/Vancouver"),
        CoupleCity(id: "sydney", name: "시드니", country: "호주", latitude: -33.8688, longitude: 151.2093, timeZoneID: "Australia/Sydney"),
        CoupleCity(id: "melbourne", name: "멜버른", country: "호주", latitude: -37.8136, longitude: 144.9631, timeZoneID: "Australia/Melbourne")
    ]

    static func city(id: String) -> CoupleCity {
        presets.first(where: { $0.id == id }) ?? presets[0]
    }
}

// MARK: - Signal

enum CoupleSignal: String, CaseIterable, Identifiable, Codable {
    case thinking
    case missYou
    case busy
    case resting
    case cheering
    case hug

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thinking: "생각 중"
        case .missYou: "보고 싶어"
        case .busy: "조금 바빠"
        case .resting: "쉬는 중"
        case .cheering: "응원해"
        case .hug: "안아줄게"
        }
    }

    /// 상대 비콘 아래에 붙는, 한 사람이 다른 사람에게 읽히는 문장.
    var partnerCaption: String {
        switch self {
        case .thinking: "네 생각을 하고 있대요"
        case .missYou: "보고 싶어 하고 있어요"
        case .busy: "지금은 조금 바쁘대요"
        case .resting: "잠깐 쉬고 있어요"
        case .cheering: "너를 응원하고 있어요"
        case .hug: "안아주고 싶대요"
        }
    }

    var symbol: String {
        switch self {
        case .thinking: "cloud.fill"
        case .missYou: "moon.stars.fill"
        case .busy: "bolt.fill"
        case .resting: "cup.and.heat.waves.fill"
        case .cheering: "sparkles"
        case .hug: "heart.fill"
        }
    }

    var color: Color {
        switch self {
        case .thinking: Color(red: 0.72, green: 0.80, blue: 0.92)
        case .missYou: Color(red: 0.78, green: 0.70, blue: 1.00)
        case .busy: Color(red: 1.00, green: 0.78, blue: 0.43)
        case .resting: Color(red: 0.62, green: 0.86, blue: 0.82)
        case .cheering: Color(red: 0.76, green: 0.91, blue: 0.55)
        case .hug: Color(red: 1.00, green: 0.58, blue: 0.62)
        }
    }
}

struct SignalEvent: Identifiable, Codable, Hashable {
    var id = UUID()
    var signal: CoupleSignal
    var direction: ParcelDirection
    var sentAt: Date
    /// 데모 모드에서 내 시그널에 대한 응답으로 만들어진 경우 원본 id.
    var replyToID: UUID?
    var isSimulated = false

    /// 시그널은 "지금의 마음"이라 하루가 지나면 흐려진다.
    func isFresh(at date: Date) -> Bool {
        date.timeIntervalSince(sentAt) < 24 * 60 * 60
    }
}

// MARK: - Parcel

enum ParcelDirection: String, Codable, Hashable {
    /// 내가 상대에게 보낸 것.
    case outgoing
    /// 상대가 나에게 보낸 것.
    case incoming
}

// MARK: - Heart

struct HeartBurst: Identifiable, Codable, Hashable {
    let id: UUID
    let direction: ParcelDirection
    let count: Int
    let sentAt: Date

    func isFresh(at date: Date) -> Bool {
        date.timeIntervalSince(sentAt) < 24 * 60 * 60
    }
}

enum ParcelPhase: Hashable {
    case inTransit
    case arrived
    case opened
}

enum ParcelWrap: String, CaseIterable, Identifiable, Codable {
    case coral
    case lavender
    case midnight
    case sage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coral: "노을"
        case .lavender: "라벤더"
        case .midnight: "한밤"
        case .sage: "세이지"
        }
    }

    var color: Color {
        switch self {
        case .coral: Color(red: 0.93, green: 0.47, blue: 0.40)
        case .lavender: Color(red: 0.62, green: 0.52, blue: 0.86)
        case .midnight: Color(red: 0.24, green: 0.33, blue: 0.55)
        case .sage: Color(red: 0.40, green: 0.62, blue: 0.52)
        }
    }
}

struct Parcel: Identifiable, Codable, Hashable {
    var id = UUID()
    var direction: ParcelDirection
    var title: String
    var message: String
    var wrap: ParcelWrap
    var fromCityID: String
    var toCityID: String
    var sentAt: Date
    var arrivesAt: Date
    /// 받는 쪽이 실제로 연 시각. incoming이면 내가, outgoing이면 상대가 연 것.
    var openedAt: Date?
    /// 데모 모드가 만들어낸 답장이면 원본 소포 id.
    var replyToID: UUID?
    var isSimulated = false

    var fromCity: CoupleCity { CoupleCity.city(id: fromCityID) }
    var toCity: CoupleCity { CoupleCity.city(id: toCityID) }

    func phase(at date: Date) -> ParcelPhase {
        if openedAt != nil { return .opened }
        return date >= arrivesAt ? .arrived : .inTransit
    }

    func progress(at date: Date) -> Double {
        let total = arrivesAt.timeIntervalSince(sentAt)
        guard total > 0 else { return 1 }
        return min(max(date.timeIntervalSince(sentAt) / total, 0), 1)
    }

    func isActive(at date: Date) -> Bool {
        phase(at: date) == .inTransit
    }
}

// MARK: - Distance

enum CoupleDistance {
    static func distanceInKilometers(from: CoupleCity, to: CoupleCity) -> Double {
        let source = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let destination = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return source.distance(from: destination) / 1_000
    }

    /// 실제 거리를 비행 시간으로 환산한다. 최소 30분, 최대 하루.
    static func deliveryDuration(from: CoupleCity, to: CoupleCity) -> TimeInterval {
        let distance = distanceInKilometers(from: from, to: to)
        let flyingTime = distance / 760 * 3_600
        return min(max(flyingTime + 30 * 60, 30 * 60), 24 * 60 * 60)
    }

}

// MARK: - Formatting

extension TimeInterval {
    /// "약 3시간 20분" — 남은 시간 표시용.
    var shortKoreanDuration: String {
        if self < 60 { return "\(max(Int(self), 1))초" }
        let totalMinutes = Int(self / 60)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes % (60 * 24)) / 60
        let minutes = totalMinutes % 60

        if days > 0 { return hours == 0 ? "\(days)일" : "\(days)일 \(hours)시간" }
        if hours == 0 { return "\(minutes)분" }
        if minutes == 0 { return "\(hours)시간" }
        return "\(hours)시간 \(minutes)분"
    }
}

extension Date {
    private static let korean = Locale(identifier: "ko_KR")

    private static func style(in timeZone: TimeZone) -> Date.FormatStyle {
        Date.FormatStyle(locale: korean, timeZone: timeZone)
    }

    /// "02:03" — 상대 도시의 지금 시각.
    func hourMinute(in timeZone: TimeZone) -> String {
        formatted(Self.style(in: timeZone).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    /// "화" — 시차 때문에 요일이 다를 수 있어서 시각 옆에 붙인다.
    func weekdayShort(in timeZone: TimeZone) -> String {
        formatted(Self.style(in: timeZone).weekday(.abbreviated))
    }

    /// "2026년 8월 9일" — 편지에 찍는 소인.
    func dayStamp(in timeZone: TimeZone) -> String {
        formatted(Self.style(in: timeZone).year().month().day())
    }

    /// "8월 9일 (화)" — 기록의 날짜 구분선.
    func dayHeader(in timeZone: TimeZone) -> String {
        formatted(Self.style(in: timeZone).month().day().weekday(.abbreviated))
    }

    /// "3분 전" — 기록과 시그널 타임스탬프용.
    func koreanRelative(to now: Date) -> String {
        let elapsed = now.timeIntervalSince(self)
        if elapsed < 60 { return "방금" }
        if elapsed < 3_600 { return "\(Int(elapsed / 60))분 전" }
        if elapsed < 86_400 { return "\(Int(elapsed / 3_600))시간 전" }
        return "\(Int(elapsed / 86_400))일 전"
    }
}

extension Int {
    /// 8969 -> "8,969"
    var grouped: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: self)) ?? String(self)
    }
}
