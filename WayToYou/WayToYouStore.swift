import Foundation
import Observation
import SwiftUI

/// 앱의 단일 상태. 예전엔 @AppStorage 값 여덟 개가 뷰에 흩어져 있었고
/// 소포·시그널을 각각 한 개씩만 기억할 수 있었다. 여기서 전부 배열로 남긴다.
@Observable
final class WayToYouStore {
    private(set) var homeCityID: String
    private(set) var partnerCityID: String
    private(set) var parcels: [Parcel]
    private(set) var signals: [SignalEvent]

    /// 서버가 없는 동안 상대 쪽 반응을 흉내 낸다.
    /// 배송 시간도 압축돼서 전체 루프를 몇 분 안에 볼 수 있다.
    var demoMode: Bool {
        didSet {
            guard demoMode != oldValue else { return }
            defaults.set(demoMode, forKey: Key.demoMode)
        }
    }

    var homeCity: CoupleCity { CoupleCity.city(id: homeCityID) }
    var partnerCity: CoupleCity { CoupleCity.city(id: partnerCityID) }

    private let defaults: UserDefaults

    private enum Key {
        static let home = "wty.homeCityID"
        static let partner = "wty.partnerCityID"
        static let parcels = "wty.parcels"
        static let signals = "wty.signals"
        static let demoMode = "wty.demoMode"
    }

    /// 데모 모드 타이밍. 실제 모드에서는 거리 기반 시간을 그대로 쓴다.
    private enum Demo {
        static let flightDuration: TimeInterval = 100
        static let partnerOpensAfter: TimeInterval = 18
        static let replyLeavesAfter: TimeInterval = 22
        static let signalReplyAfter: TimeInterval = 26
    }

    private enum Live {
        static let partnerOpensAfter: TimeInterval = 45 * 60
        static let replyLeavesAfter: TimeInterval = 3 * 60 * 60
        static let signalReplyAfter: TimeInterval = 40 * 60
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        homeCityID = defaults.string(forKey: Key.home) ?? "seoul"
        partnerCityID = defaults.string(forKey: Key.partner) ?? "paris"
        demoMode = defaults.object(forKey: Key.demoMode) as? Bool ?? true
        parcels = Self.decode([Parcel].self, from: defaults.data(forKey: Key.parcels)) ?? []
        signals = Self.decode([SignalEvent].self, from: defaults.data(forKey: Key.signals)) ?? []
    }

    // MARK: - Derived state

    /// 지금 하늘에 떠 있는 소포들. 오래된 것이 앞에 온다.
    func inFlight(at date: Date) -> [Parcel] {
        parcels.filter { $0.isActive(at: date) }.sorted { $0.arrivesAt < $1.arrivesAt }
    }

    /// 나에게 도착했지만 아직 열지 않은 소포.
    func waitingToOpen(at date: Date) -> [Parcel] {
        parcels
            .filter { $0.direction == .incoming && $0.phase(at: date) == .arrived }
            .sorted { $0.arrivesAt < $1.arrivesAt }
    }

    /// 최근에 연 편지 하나. 홈에서 "다시 읽기"로 노출한다.
    func lastOpenedIncoming() -> Parcel? {
        parcels
            .filter { $0.direction == .incoming && $0.openedAt != nil }
            .max { ($0.openedAt ?? .distantPast) < ($1.openedAt ?? .distantPast) }
    }

    func latestSignal(_ direction: ParcelDirection, at date: Date) -> SignalEvent? {
        signals
            .filter { $0.direction == direction && $0.isFresh(at: date) }
            .max { $0.sentAt < $1.sentAt }
    }

    /// 홈 상태 패널이 무엇을 보여줄지 한 곳에서 정한다.
    /// 급한 것부터: 열 소포 > 오는 중 > 보낸 게 가는 중 > 상대가 열어봄 > 조용함
    func focus(at date: Date) -> HomeFocus {
        if let waiting = waitingToOpen(at: date).first {
            return .readyToOpen(waiting)
        }
        let flying = inFlight(at: date)
        if let incoming = flying.first(where: { $0.direction == .incoming }) {
            return .incomingFlight(incoming)
        }
        if let outgoing = flying.first(where: { $0.direction == .outgoing }) {
            return .outgoingFlight(outgoing)
        }
        // 최근 24시간 안에 상대가 내 소포를 열어봤다면 그걸 알려준다.
        let recentlyRead = parcels
            .filter { $0.direction == .outgoing }
            .compactMap { parcel -> (Parcel, Date)? in
                guard let openedAt = parcel.openedAt, date.timeIntervalSince(openedAt) < 86_400 else { return nil }
                return (parcel, openedAt)
            }
            .max { $0.1 < $1.1 }
        if let recentlyRead {
            return .partnerRead(recentlyRead.0)
        }
        return .quiet
    }

    var distanceKilometers: Int {
        Int(CoupleDistance.distanceInKilometers(from: homeCity, to: partnerCity).rounded())
    }

    /// 두 사람의 시차. 상대가 나보다 몇 시간 뒤/앞인지.
    func timeDifferenceCaption(at date: Date) -> String {
        let mine = homeCity.timeZone.secondsFromGMT(for: date)
        let theirs = partnerCity.timeZone.secondsFromGMT(for: date)
        let delta = Double(theirs - mine) / 3_600
        if abs(delta) < 0.01 { return "같은 시간" }
        let magnitude = abs(delta)
        let text = magnitude == magnitude.rounded()
            ? "\(Int(magnitude))시간"
            : String(format: "%.1f시간", magnitude)
        return delta > 0 ? "\(text) 빠름" : "\(text) 느림"
    }

    func flightDuration() -> TimeInterval {
        demoMode ? Demo.flightDuration : CoupleDistance.deliveryDuration(from: homeCity, to: partnerCity)
    }

    // MARK: - Intents

    func sendParcel(title: String, message: String, wrap: ParcelWrap, now: Date = .now) {
        let parcel = Parcel(
            direction: .outgoing,
            title: title,
            message: message,
            wrap: wrap,
            fromCityID: homeCityID,
            toCityID: partnerCityID,
            sentAt: now,
            arrivesAt: now.addingTimeInterval(flightDuration())
        )
        parcels.append(parcel)
        save()
    }

    func open(_ parcel: Parcel, now: Date = .now) {
        guard let index = parcels.firstIndex(where: { $0.id == parcel.id }), parcels[index].openedAt == nil else { return }
        parcels[index].openedAt = now
        save()
    }

    func sendSignal(_ signal: CoupleSignal, now: Date = .now) {
        signals.append(SignalEvent(signal: signal, direction: .outgoing, sentAt: now))
        trimSignals()
        save()
    }

    func updateCities(home: String, partner: String) {
        guard home != homeCityID || partner != partnerCityID else { return }
        homeCityID = home
        partnerCityID = partner
        // 경로가 바뀌면 아직 하늘에 있는 소포는 갈 곳을 잃는다. 도착 처리해서 기록에 남긴다.
        let now = Date()
        for index in parcels.indices where parcels[index].isActive(at: now) {
            parcels[index].arrivesAt = now
        }
        save()
    }

    func clearHistory() {
        parcels = []
        signals = []
        save()
    }

    // MARK: - Demo simulation

    /// 저장된 타임스탬프만 보고 상대의 다음 행동을 결정한다.
    /// 난수를 쓰지 않으므로 앱을 껐다 켜도 같은 결과가 나온다.
    /// 서버가 붙기 전까지는 실제 모드에서도 상대를 흉내 내야 앱이 성립한다.
    /// demoMode는 그 반응이 얼마나 빨리 오는지만 바꾼다.
    func advance(to now: Date) {
        var changed = false

        let opensAfter = demoMode ? Demo.partnerOpensAfter : Live.partnerOpensAfter
        let replyAfter = demoMode ? Demo.replyLeavesAfter : Live.replyLeavesAfter
        let signalAfter = demoMode ? Demo.signalReplyAfter : Live.signalReplyAfter

        // 1. 상대가 내 소포를 열어본다.
        for index in parcels.indices
        where parcels[index].direction == .outgoing && parcels[index].openedAt == nil {
            let openMoment = parcels[index].arrivesAt.addingTimeInterval(opensAfter)
            if now >= openMoment {
                parcels[index].openedAt = openMoment
                changed = true
            }
        }

        // 2. 열어본 소포마다 답장이 한 번 출발한다.
        let alreadyReplied = Set(parcels.compactMap(\.replyToID))
        let pendingReplies = parcels.filter { parcel in
            parcel.direction == .outgoing
                && parcel.openedAt != nil
                && !alreadyReplied.contains(parcel.id)
        }
        for origin in pendingReplies {
            guard let openedAt = origin.openedAt else { continue }
            let departure = openedAt.addingTimeInterval(replyAfter)
            guard now >= departure else { continue }
            parcels.append(makeReply(to: origin, departingAt: departure))
            changed = true
        }

        // 3. 내가 보낸 시그널에 상대가 한 번 답한다.
        let answeredSignals = Set(signals.compactMap(\.replyToID))
        for origin in signals where origin.direction == .outgoing && !answeredSignals.contains(origin.id) {
            let moment = origin.sentAt.addingTimeInterval(signalAfter)
            guard now >= moment else { continue }
            signals.append(
                SignalEvent(
                    signal: Self.partnerResponse(to: origin.signal),
                    direction: .incoming,
                    sentAt: moment,
                    replyToID: origin.id,
                    isSimulated: true
                )
            )
            changed = true
        }

        if changed {
            trimSignals()
            save()
        }
    }

    private func makeReply(to origin: Parcel, departingAt departure: Date) -> Parcel {
        let letter = Self.replyLetters[parcels.count % Self.replyLetters.count]
        let duration = demoMode
            ? Demo.flightDuration
            : CoupleDistance.deliveryDuration(from: origin.toCity, to: origin.fromCity)
        return Parcel(
            direction: .incoming,
            title: letter.title,
            message: letter.body,
            wrap: Self.replyWraps[parcels.count % Self.replyWraps.count],
            fromCityID: origin.toCityID,
            toCityID: origin.fromCityID,
            sentAt: departure,
            arrivesAt: departure.addingTimeInterval(duration),
            replyToID: origin.id,
            isSimulated: true
        )
    }

    private static func partnerResponse(to signal: CoupleSignal) -> CoupleSignal {
        switch signal {
        case .thinking: .missYou
        case .missYou: .hug
        case .busy: .cheering
        case .resting: .resting
        case .cheering: .hug
        case .hug: .missYou
        }
    }

    private static let replyWraps: [ParcelWrap] = [.lavender, .sage, .midnight, .coral]

    private static let replyLetters: [(title: String, body: String)] = [
        (
            "잘 받았어",
            "소포가 도착한 날, 하루 종일 기분이 좋았어. 상자를 여는 데 한참 걸렸어. 열면 끝나버릴 것 같아서.\n\n여기는 요즘 해가 늦게 져. 창밖이 오래 밝아서, 그만큼 네 생각을 더 오래 해."
        ),
        (
            "오늘의 창밖",
            "아침에 비가 왔어. 우산을 안 챙겨서 그냥 맞고 걸었는데 생각보다 나쁘지 않더라.\n\n너랑 같이 걸었으면 분명히 웃었을 거야. 다음엔 같은 우산을 쓰자."
        ),
        (
            "시차 없는 곳",
            "우리 사이엔 시차가 있지만, 자기 전에 하는 생각은 늘 같은 것 같아.\n\n네가 아침을 먹을 때 나는 잠들고, 내가 눈을 뜰 때 너는 하루를 정리하겠지. 그렇게 하루를 이어 붙이면 우리는 계속 같이 있는 셈이야."
        ),
        (
            "작은 것들",
            "오늘 길에서 네가 좋아하는 색을 봤어. 사진을 찍어두려다가 그냥 오래 봤어.\n\n말로 옮기면 사라지는 것들이 있어서, 이번엔 그냥 기억해두기로 했어. 만나면 얘기해줄게."
        ),
        (
            "곧 만나",
            "달력을 자꾸 보게 돼. 남은 날짜를 세는 게 습관이 됐어.\n\n기다리는 게 힘들지 않다고는 못 하겠지만, 기다릴 사람이 있다는 게 좋아. 그때까지 잘 지내고 있어."
        )
    ]

    // MARK: - Persistence

    private func trimSignals() {
        signals.sort { $0.sentAt < $1.sentAt }
        if signals.count > 120 {
            signals.removeFirst(signals.count - 120)
        }
    }

    private func save() {
        defaults.set(homeCityID, forKey: Key.home)
        defaults.set(partnerCityID, forKey: Key.partner)
        defaults.set(Self.encode(parcels), forKey: Key.parcels)
        defaults.set(Self.encode(signals), forKey: Key.signals)
    }

    private static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// 홈 상태 패널이 그릴 한 가지 상황.
enum HomeFocus: Hashable {
    case quiet
    case outgoingFlight(Parcel)
    case incomingFlight(Parcel)
    case readyToOpen(Parcel)
    case partnerRead(Parcel)

    var parcel: Parcel? {
        switch self {
        case .quiet: nil
        case .outgoingFlight(let parcel), .incomingFlight(let parcel),
             .readyToOpen(let parcel), .partnerRead(let parcel):
            parcel
        }
    }
}
