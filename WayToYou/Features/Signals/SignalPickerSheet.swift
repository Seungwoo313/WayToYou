import SwiftUI

/// 한 번의 탭으로 현재 상태만 보내는 화면.
///
/// 레트로 계산기·넘패드를 그대로 옮긴 형태다. 화면 전체가 하나의 기계이고
/// 위쪽 7세그먼트 창은 상대 쪽 정보를, 아래 3×3 키캡은 내가 보낼 신호를 담는다.
/// 키캡 이모지는 사용자가 길게 눌러 직접 바꾼다.
///
/// 여기 쓰는 플라스틱·LED 색은 이 기계 안에서만 쓰는 재질이라
/// 전역 `Palette`에 넣지 않고 `Keypad`에 가둔다.
struct SignalPickerSheet: View {
    let keys: [SignalKey]
    let selectedSignal: CoupleSignal?
    let partnerName: String
    let partnerCityName: String
    let partnerTimeZone: TimeZone
    let myTimeZone: TimeZone
    let distanceKilometers: Int
    let now: Date
    let onSelect: (CoupleSignal) -> Void
    let onEditKey: (Int, SignalKey) -> Void

    @State private var isEditingKeys = false
    @State private var editingIndex: Int?
    @State private var draftEmoji = ""
    @State private var draftLabel = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: Keypad.chassisGap) {
                Nameplate(isEditing: isEditingKeys, onToggleEditing: toggleEditing)

                DisplayPanel(
                    value: distanceDigits,
                    unit: "KM",
                    topLeft: isEditingKeys ? "EDIT" : partnerName,
                    topRight: isEditingKeys ? "TAP KEY" : partnerCityName,
                    bottomLeft: isEditingKeys ? "EMOJI" : timeOffset,
                    bottomRight: isEditingKeys ? "+ LABEL" : partnerClock
                )

                KeyWell(
                    keys: keys,
                    selectedSignal: selectedSignal,
                    isEditing: isEditingKeys,
                    onSelect: onSelect,
                    onEdit: beginEditing
                )
            }
            .padding(Keypad.chassisPadding)
            .background(ChassisSurface())
            .padding(.horizontal, Metric.screenPadding)
            .padding(.vertical, Metric.l)
        }
        .presentationBackground(Palette.space)
        .alert("키캡 바꾸기", isPresented: isPresentingEditor) {
            TextField("이모지", text: $draftEmoji)
            TextField("설명 \(SignalKey.labelLimit)자 이내", text: $draftLabel)
            Button("취소", role: .cancel) { editingIndex = nil }
            Button("저장") { commitEditing() }
        } message: {
            Text("설명은 기계에 새기지 않고 나중에 알림에만 써요")
        }
    }

    private var isPresentingEditor: Binding<Bool> {
        Binding(
            get: { editingIndex != nil },
            set: { if !$0 { editingIndex = nil } }
        )
    }

    private func toggleEditing() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isEditingKeys.toggle()
        }
    }

    private func beginEditing(_ index: Int) {
        guard keys.indices.contains(index) else { return }
        draftEmoji = keys[index].emoji
        draftLabel = keys[index].label
        editingIndex = index
    }

    private func commitEditing() {
        defer { editingIndex = nil }
        guard let index = editingIndex,
              let signal = CoupleSignal.keycap(from: draftEmoji) else { return }
        onEditKey(index, SignalKey(signal: signal, label: draftLabel))
    }

    /// 큰 숫자는 두 도시 사이 거리다. 이 기계가 켜져 있는 이유 그 자체라 시각보다 앞에 둔다.
    private var distanceDigits: String {
        String(max(0, distanceKilometers))
    }

    private var partnerClock: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = partnerTimeZone
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// 상대가 나보다 몇 시간 앞인지. 30분 시차가 있는 도시가 있어 분도 함께 본다.
    private var timeOffset: String {
        let delta = partnerTimeZone.secondsFromGMT(for: now) - myTimeZone.secondsFromGMT(for: now)
        if delta == 0 { return "SAME HOUR" }
        let sign = delta > 0 ? "+" : "-"
        let minutes = abs(delta) / 60
        let remainder = minutes % 60
        return remainder == 0
            ? "\(sign)\(minutes / 60)H"
            : String(format: "%@%d:%02d", sign, minutes / 60, remainder)
    }
}

// MARK: - 몸통

/// 아이보리 플라스틱 몸통. 위에서 오는 빛 하나를 기준으로 위가 밝고 아래가 어둡다.
private struct ChassisSurface: View {
    private let shape = RoundedRectangle(cornerRadius: Keypad.chassisRadius, style: .continuous)

    var body: some View {
        shape
            .fill(Keypad.chassisFill)
            .overlay { shape.strokeBorder(Keypad.topLightEdge, lineWidth: 1) }
            .overlay { PlasticGrain().clipShape(shape) }
            .shadow(color: .black.opacity(0.55), radius: 24, y: 12)
    }
}

/// 기계 위쪽 명판. 왼쪽은 각인된 상표, 오른쪽은 설정 톱니바퀴다.
private struct Nameplate: View {
    let isEditing: Bool
    let onToggleEditing: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("WAY TO YOU")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .tracking(2.2)
                .foregroundStyle(Keypad.engraved)

            Spacer(minLength: 0)

            Text("SIG-9")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Keypad.engravedFaint)

            GearButton(isOn: isEditing, action: onToggleEditing)
        }
        .padding(.horizontal, 3)
    }
}

/// 플라스틱에 박힌 작은 금속 톱니. 켜면 살짝 돌아가고 LED 색이 든다.
private struct GearButton: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isOn ? Keypad.led : Keypad.engraved)
                .rotationEffect(.degrees(isOn ? 45 : 0))
                .frame(width: 24, height: 24)
                .background {
                    Circle()
                        .fill(Keypad.gearWell)
                        .innerShadow(radius: 12, color: .black.opacity(0.45), width: 3)
                }
        }
        .buttonStyle(PressableCard())
        .accessibilityLabel("키캡 설정")
        .accessibilityValue(isOn ? "켜짐" : "꺼짐")
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isOn)
    }
}

// MARK: - 디스플레이

private struct DisplayPanel: View {
    let value: String
    let unit: String
    let topLeft: String
    let topRight: String
    let bottomLeft: String
    let bottomRight: String

    private let shape = RoundedRectangle(cornerRadius: Keypad.glassRadius, style: .continuous)

    var body: some View {
        VStack(spacing: 8) {
            LabelStrip(left: topLeft, right: topRight)
            readout
            LabelStrip(left: bottomLeft, right: bottomRight)
        }
        .padding(9)
        .background { glass }
        .overlay { sheen }
        .overlay { shape.strokeBorder(.black.opacity(0.6), lineWidth: 1) }
    }

    private var readout: some View {
        HStack(alignment: .bottom, spacing: 8) {
            SevenSegmentReadout(text: value)
            Text(unit)
                .font(.system(size: 14, weight: .black, design: .monospaced))
                .tracking(1)
                .foregroundStyle(Keypad.ledDim)
                .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    private var glass: some View {
        shape
            .fill(Keypad.glass)
            .innerShadow(radius: Keypad.glassRadius, color: .black.opacity(0.9), width: 5)
    }

    /// 유리 위를 비스듬히 지나가는 반사 한 줄.
    private var sheen: some View {
        shape
            .fill(Keypad.glassSheen)
            .allowsHitTesting(false)
    }
}

/// 레퍼런스의 `SOC(%)` / `INPUT(W)` 자리. 기능은 없고 기계처럼 보이게 하는 타이포다.
private struct LabelStrip: View {
    let left: String
    let right: String

    var body: some View {
        HStack(spacing: 5) {
            tag(left)
            Spacer(minLength: 8)
            tag(right)
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(Keypad.glass)
            .padding(.horizontal, 5)
            .padding(.vertical, 2.5)
            .background(Keypad.ledDim, in: RoundedRectangle(cornerRadius: 2.5, style: .continuous))
            .lineLimit(1)
    }
}

private struct SevenSegmentReadout: View {
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                if let value = character.wholeNumberValue {
                    SevenSegmentDigit(value: value)
                        .frame(width: Keypad.digitWidth, height: Keypad.digitHeight)
                } else {
                    Colon()
                        .frame(width: 7, height: Keypad.digitHeight)
                }
            }
        }
    }
}

/// 꺼진 획도 어둡게 남겨 둔다. 진짜 계산기는 `88:88`이 유령처럼 비쳐 보인다.
private struct SevenSegmentDigit: View {
    let value: Int

    var body: some View {
        segments(onlyLit: false)
            .overlay { glow }
    }

    private func segments(onlyLit: Bool) -> some View {
        Canvas { context, size in
            let lit = SegmentGeometry.mask(for: value)
            for index in 0..<7 {
                let isLit = lit.contains(index)
                if onlyLit && !isLit { continue }
                context.fill(
                    SegmentGeometry.path(index: index, in: size),
                    with: .color(isLit ? Keypad.led : Keypad.ledOff)
                )
            }
        }
    }

    private var glow: some View {
        segments(onlyLit: true)
            .blur(radius: 4)
            .opacity(0.55)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }
}

private struct Colon: View {
    var body: some View {
        GeometryReader { proxy in
            let dot = proxy.size.width * 0.62
            VStack(spacing: proxy.size.height * 0.2) {
                Circle().fill(Keypad.led).frame(width: dot, height: dot)
                Circle().fill(Keypad.led).frame(width: dot, height: dot)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .padding(.vertical, proxy.size.height * 0.18)
        }
        .shadow(color: Keypad.led.opacity(0.6), radius: 4)
    }
}

private enum SegmentGeometry {
    /// 0 a · 1 b · 2 c · 3 d · 4 e · 5 f · 6 g
    static func mask(for value: Int) -> Set<Int> {
        switch value {
        case 0: [0, 1, 2, 3, 4, 5]
        case 1: [1, 2]
        case 2: [0, 1, 6, 4, 3]
        case 3: [0, 1, 6, 2, 3]
        case 4: [5, 6, 1, 2]
        case 5: [0, 5, 6, 2, 3]
        case 6: [0, 5, 6, 4, 2, 3]
        case 7: [0, 1, 2]
        case 8: [0, 1, 2, 3, 4, 5, 6]
        case 9: [0, 1, 2, 3, 5, 6]
        default: []
        }
    }

    static func path(index: Int, in size: CGSize) -> Path {
        let thickness = size.width * 0.20
        let half = thickness / 2
        let gap = thickness * 0.34
        let midY = size.height / 2

        switch index {
        case 0: return horizontal(centerY: half, width: size.width, half: half, gap: gap)
        case 3: return horizontal(centerY: size.height - half, width: size.width, half: half, gap: gap)
        case 6: return horizontal(centerY: midY, width: size.width, half: half, gap: gap)
        case 5: return vertical(centerX: half, from: half + gap, to: midY - gap, half: half)
        case 1: return vertical(centerX: size.width - half, from: half + gap, to: midY - gap, half: half)
        case 4: return vertical(centerX: half, from: midY + gap, to: size.height - half - gap, half: half)
        default: return vertical(centerX: size.width - half, from: midY + gap, to: size.height - half - gap, half: half)
        }
    }

    private static func horizontal(centerY: CGFloat, width: CGFloat, half: CGFloat, gap: CGFloat) -> Path {
        let left = gap
        let right = width - gap
        var path = Path()
        path.move(to: CGPoint(x: left, y: centerY))
        path.addLine(to: CGPoint(x: left + half, y: centerY - half))
        path.addLine(to: CGPoint(x: right - half, y: centerY - half))
        path.addLine(to: CGPoint(x: right, y: centerY))
        path.addLine(to: CGPoint(x: right - half, y: centerY + half))
        path.addLine(to: CGPoint(x: left + half, y: centerY + half))
        path.closeSubpath()
        return path
    }

    private static func vertical(centerX: CGFloat, from top: CGFloat, to bottom: CGFloat, half: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: centerX, y: top))
        path.addLine(to: CGPoint(x: centerX + half, y: top + half))
        path.addLine(to: CGPoint(x: centerX + half, y: bottom - half))
        path.addLine(to: CGPoint(x: centerX, y: bottom))
        path.addLine(to: CGPoint(x: centerX - half, y: bottom - half))
        path.addLine(to: CGPoint(x: centerX - half, y: top + half))
        path.closeSubpath()
        return path
    }
}

// MARK: - 키

/// 키가 판 위에 얹힌 게 아니라 우물에 박혀 있어야 넘패드로 읽힌다.
private struct KeyWell: View {
    let keys: [SignalKey]
    let selectedSignal: CoupleSignal?
    let isEditing: Bool
    let onSelect: (CoupleSignal) -> Void
    let onEdit: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Keypad.keyGap), count: 3)
    private let shape = RoundedRectangle(cornerRadius: Keypad.wellRadius, style: .continuous)

    var body: some View {
        LazyVGrid(columns: columns, spacing: Keypad.keyGap) {
            ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                Button {
                    if isEditing {
                        onEdit(index)
                    } else {
                        onSelect(key.signal)
                    }
                } label: {
                    KeycapFace(
                        emoji: key.emoji,
                        isSelected: !isEditing && key.signal == selectedSignal,
                        isEditing: isEditing
                    )
                }
                .buttonStyle(KeycapPress())
                .onLongPressGesture(minimumDuration: 0.45) {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    onEdit(index)
                }
                .accessibilityLabel(key.label.isEmpty ? key.signal.title : key.label)
                .accessibilityValue(key.signal == selectedSignal ? "현재 내 Signal" : "")
                .accessibilityHint("길게 누르면 이 키를 바꿔요")
            }
        }
        .padding(Keypad.wellPadding)
        .background {
            shape
                .fill(Keypad.well)
                .innerShadow(radius: Keypad.wellRadius, color: .black.opacity(0.45), width: 4)
        }
    }
}

private struct KeycapFace: View {
    let emoji: String
    let isSelected: Bool
    let isEditing: Bool
    @Environment(\.keycapIsPressed) private var isPressed

    private let shape = RoundedRectangle(cornerRadius: Keypad.keyRadius - 2, style: .continuous)

    /// 눌린 키는 옆면이 사라진 만큼 내려앉는다. 선택된 키는 조금 눌린 채로 머문다.
    private var sink: CGFloat {
        if isPressed { return Keypad.keyDepth - 1.5 }
        return isSelected ? Keypad.keyDepth - 3 : 0
    }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: Keypad.keyRadius, style: .continuous)
                .fill(Keypad.skirtFill)

            cap
                .padding(.horizontal, 3)
                .padding(.top, sink)
                .padding(.bottom, Keypad.keyDepth - sink)
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.spring(response: 0.16, dampingFraction: 0.72), value: isPressed)
        .animation(.spring(response: 0.24, dampingFraction: 0.75), value: isSelected)
    }

    private var cap: some View {
        shape
            .fill(Keypad.capFill)
            .overlay { dish }
            .overlay { shape.strokeBorder(Keypad.capEdge, lineWidth: 1) }
            .overlay { Text(emoji).font(.system(size: Keypad.emojiSize)) }
            .overlay(alignment: .topTrailing) { activeLamp }
            .overlay { PlasticGrain().clipShape(shape) }
    }

    /// 손가락이 닿는 면은 살짝 파여 있다.
    private var dish: some View {
        shape.fill(Keypad.capDish)
    }

    @ViewBuilder
    private var activeLamp: some View {
        if isSelected {
            Circle()
                .fill(Keypad.led)
                .frame(width: 5, height: 5)
                .shadow(color: Keypad.led.opacity(0.8), radius: 3)
                .padding(6)
        } else if isEditing {
            Image(systemName: "pencil")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.white.opacity(0.55))
                .padding(5)
        }
    }
}

/// 키캡은 스케일이 아니라 실제로 내려앉아야 해서 눌림 상태만 내려보낸다.
private struct KeycapPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.keycapIsPressed, configuration.isPressed)
    }
}

private struct KeycapPressedKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var keycapIsPressed: Bool {
        get { self[KeycapPressedKey.self] }
        set { self[KeycapPressedKey.self] = newValue }
    }
}

// MARK: - 재질

/// 완전히 매끈하면 CG처럼 보인다. 아주 옅은 알갱이만 얹는다.
private struct PlasticGrain: View {
    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
            func next() -> CGFloat {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return CGFloat((seed >> 33) % 1_000) / 1_000
            }
            let count = Int(size.width * size.height / 14)
            for _ in 0..<count {
                let point = CGPoint(x: next() * size.width, y: next() * size.height)
                let bright = next() > 0.5
                context.fill(
                    Path(CGRect(origin: point, size: CGSize(width: 1, height: 1))),
                    with: .color(bright ? .white : .black)
                )
            }
        }
        .opacity(0.05)
        .blendMode(.overlay)
        .allowsHitTesting(false)
    }
}

private extension View {
    /// SwiftUI에 inner shadow가 없어서 안쪽으로 번지는 테두리로 만든다.
    func innerShadow(radius: CGFloat, color: Color, width: CGFloat) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(color, lineWidth: width)
                .blur(radius: width)
                .mask { RoundedRectangle(cornerRadius: radius, style: .continuous) }
                .allowsHitTesting(false)
        }
    }
}

private enum Keypad {
    static let chassisRadius: CGFloat = 26
    static let chassisPadding: CGFloat = 14
    static let chassisGap: CGFloat = 13
    static let glassRadius: CGFloat = 12
    static let wellRadius: CGFloat = 16
    static let wellPadding: CGFloat = 10
    static let keyGap: CGFloat = 8
    static let keyRadius: CGFloat = 12
    static let keyDepth: CGFloat = 7
    static let emojiSize: CGFloat = 38
    static let digitWidth: CGFloat = 25
    static let digitHeight: CGFloat = 42

    static let led = Color(red: 0.25, green: 1.00, blue: 0.52)
    static let ledDim = Color(red: 0.11, green: 0.72, blue: 0.35)
    static let ledOff = Color(red: 0.035, green: 0.16, blue: 0.08)
    static let glass = Color(red: 0.030, green: 0.055, blue: 0.040)
    static let well = Color(red: 0.700, green: 0.688, blue: 0.660)
    static let gearWell = Color(red: 0.760, green: 0.748, blue: 0.720)
    static let engraved = Color(red: 0.38, green: 0.37, blue: 0.35)
    static let engravedFaint = Color(red: 0.55, green: 0.54, blue: 0.52)

    static let chassisFill = LinearGradient(
        colors: [Color(red: 0.945, green: 0.935, blue: 0.910), Color(red: 0.820, green: 0.808, blue: 0.780)],
        startPoint: .top,
        endPoint: .bottom
    )

    static let capFill = LinearGradient(
        colors: [Color(red: 0.255, green: 0.250, blue: 0.245), Color(red: 0.170, green: 0.166, blue: 0.162)],
        startPoint: .top,
        endPoint: .bottom
    )

    static let skirtFill = LinearGradient(
        colors: [Color(red: 0.130, green: 0.127, blue: 0.124), Color(red: 0.075, green: 0.073, blue: 0.070)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// 어두운 키캡에는 흰 하이라이트를 몸통만큼 세게 주면 플라스틱이 아니라 유리처럼 보인다.
    static let capEdge = LinearGradient(
        colors: [.white.opacity(0.28), .black.opacity(0.45)],
        startPoint: .top,
        endPoint: .bottom
    )

    static let capDish = RadialGradient(
        colors: [.black.opacity(0.10), .clear],
        center: .center,
        startRadius: 1,
        endRadius: 30
    )

    static let topLightEdge = LinearGradient(
        colors: [.white.opacity(0.9), .black.opacity(0.16)],
        startPoint: .top,
        endPoint: .bottom
    )

    static let glassSheen = LinearGradient(
        colors: [.white.opacity(0.10), .clear, .white.opacity(0.03)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// 누를 때 살짝 들어가는 반응. 커스텀 카드에는 시스템 버튼 하이라이트가 없어서 직접 준다.
struct PressableCard: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
