import UIKit

/// 서버로 올릴 수 있는 유효한 배터리 판독값. unknown은 이 타입으로 만들어지지 않는다.
struct DeviceBatteryReading: Equatable, Sendable {
    /// 0...100
    let level: Int
    let state: DeviceBatteryState
}

/// foreground·연결 상태 동안만 UIDevice 배터리를 관찰한다.
/// UIDevice의 unknown(-1) 값은 절대 밖으로 내보내지 않는다.
@MainActor
final class DeviceBatteryMonitor {
    /// 배터리 수치나 충전 상태가 바뀔 때마다 유효한 값만 전달한다.
    var onChange: ((DeviceBatteryReading) -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var isActive = false
    /// 다른 기능이 먼저 monitoring을 켜둔 경우 stop에서 그 상태를 끄지 않는다.
    private var enabledMonitoringForThisSession = false

    /// 지금 읽을 수 있는 값. unknown이면 nil이라 호출자가 업로드를 건너뛴다.
    var currentReading: DeviceBatteryReading? {
        guard isActive else { return nil }
        return Self.reading(from: .current)
    }

    func start() {
        guard !isActive else { return }
        isActive = true
        let device = UIDevice.current
        enabledMonitoringForThisSession = !device.isBatteryMonitoringEnabled
        if enabledMonitoringForThisSession {
            device.isBatteryMonitoringEnabled = true
        }

        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UIDevice.batteryLevelDidChangeNotification,
            UIDevice.batteryStateDidChangeNotification
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.publishCurrentReading()
                }
            }
        }
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if enabledMonitoringForThisSession {
            UIDevice.current.isBatteryMonitoringEnabled = false
        }
        enabledMonitoringForThisSession = false
    }

    private func publishCurrentReading() {
        guard let reading = currentReading else { return }
        onChange?(reading)
    }

    private static func reading(from device: UIDevice) -> DeviceBatteryReading? {
        let rawLevel = device.batteryLevel
        guard rawLevel >= 0 else { return nil }

        let state: DeviceBatteryState
        switch device.batteryState {
        case .charging: state = .charging
        case .full: state = .full
        case .unplugged: state = .unplugged
        case .unknown: return nil
        @unknown default: return nil
        }
        return DeviceBatteryReading(
            level: min(max(Int((rawLevel * 100).rounded()), 0), 100),
            state: state
        )
    }
}
