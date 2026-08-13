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
    /// 닫혀 있을 때 화면 밖으로 내려가 있는 거리. 어떤 기기에서도 완전히 벗어난다.
    static let parkedTravel: CGFloat = 1_000

    let keys: [SignalKey]
    let selectedSignal: CoupleSignal?
    /// 기계는 항상 트리에 있으므로 닫혔다는 사실을 직접 받아 고른 키를 되돌린다.
    let isPresented: Bool
    let partnerName: String
    let partnerCityName: String
    /// 초마다 바뀌는 `Date`를 그대로 받으면, 여는 프레임에 값이 달라져 있을 때
    /// 하필 그 순간 텍스처를 다시 굽는다. 이미 만들어진 문자열만 받는다.
    let partnerClock: String
    let timeOffset: String
    let distanceKilometers: Int
    let onSelect: (CoupleSignal) -> Void
    let onEditKey: (Int, SignalKey) -> Void
    let onDismiss: () -> Void

    @State private var isEditingKeys = false
    @State private var editingIndex: Int?
    @State private var draftEmoji = ""
    @State private var draftLabel = ""
    @State private var dragOffset: CGFloat = 0
    /// 키를 누르면 눌리기만 하고, 보내는 것은 엔터가 맡는다.
    @State private var stagedSignal: CoupleSignal?
    /// 한 번이라도 키를 만졌는지. 골랐다가 풀면 아무것도 눌리지 않은 상태로 돌아가야 하는데,
    /// 그때 마지막으로 보낸 신호가 다시 켜지면 풀린 것처럼 보이지 않는다.
    @State private var hasTouchedKeys = false

    /// 지금 램프가 켜져 있어야 하는 신호. 손대기 전에는 마지막으로 보낸 것.
    private var activeSignal: CoupleSignal? {
        hasTouchedKeys ? stagedSignal : selectedSignal
    }

    var body: some View {
        machine
            .offset(y: dragOffset)
            .gesture(dismissDrag)
            .onChange(of: isPresented) { _, presented in
                if !presented {
                    stagedSignal = nil
                    hasTouchedKeys = false
                    isEditingKeys = false
                }
            }
            .alert("키캡 바꾸기", isPresented: isPresentingEditor) {
                TextField("이모지", text: $draftEmoji)
                    .onChange(of: draftEmoji) { _, typed in
                        // 글자나 숫자를 눌러도 키캡에 올라가지 않게 이모지 하나만 남긴다.
                        draftEmoji = CoupleSignal.keycap(from: typed)?.emoji ?? ""
                    }
                TextField("설명 \(SignalKey.labelLimit)자 이내", text: $draftLabel)
                    .onChange(of: draftLabel) { _, typed in
                        draftLabel = String(typed.prefix(SignalKey.labelLimit))
                    }
                Button("취소", role: .cancel) { editingIndex = nil }
                Button("저장") { commitEditing() }
            }
    }

    private var machine: some View {
        VStack(spacing: Keypad.chassisGap) {
            Nameplate(isEditing: isEditingKeys, onToggleEditing: toggleEditing)

            DisplayPanel(
                value: distanceDigits,
                unit: "KM",
                topLeft: isEditingKeys ? "EDIT" : "TO",
                topRight: isEditingKeys ? "KEYS" : partnerName,
                bottomLeft: isEditingKeys ? "EMOJI" : partnerClock,
                bottomRight: isEditingKeys ? "+ LABEL" : partnerCityName
            )

            KeyWell(
                keys: keys,
                activeSignal: activeSignal,
                isEditing: isEditingKeys,
                canSend: stagedSignal != nil,
                onStage: stage,
                onSend: send,
                onEdit: beginEditing
            )
        }
        .padding(Keypad.chassisPadding)
        .background(ChassisSurface())
        // 기계 전체를 텍스처 한 장으로 굳힌다. 올라오고 내려갈 때 그 한 장만 움직이면 되므로
        // 알갱이·그림자·번짐을 매 프레임 다시 그리지 않는다.
        // 여백을 줬다 빼는 건 바깥으로 번지는 그림자가 잘리지 않게 하려는 것이다.
        .padding(.horizontal, Keypad.rasterMargin)
        .padding(.vertical, Keypad.rasterMargin)
        .drawingGroup()
        .padding(.horizontal, -Keypad.rasterMargin)
        .padding(.vertical, -Keypad.rasterMargin)
        .frame(maxWidth: Keypad.chassisMaxWidth)
        .padding(.horizontal, Metric.screenPadding)
        .padding(.bottom, Keypad.chassisThickness + Metric.m)
    }

    /// 시트처럼 아래로 끌어 내려 닫는다. 판이 없어도 손에 익은 동작은 남긴다.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                if value.translation.height > 90 || value.predictedEndTranslation.height > 220 {
                    onDismiss()
                }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    dragOffset = 0
                }
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

    /// 눌린 키를 다시 누르면 풀린다.
    private func stage(_ signal: CoupleSignal) {
        hasTouchedKeys = true
        stagedSignal = stagedSignal == signal ? nil : signal
    }

    /// 엔터를 눌러야 실제로 나간다. 고른 것이 없으면 그냥 내려간다.
    private func send() {
        guard let stagedSignal else {
            onDismiss()
            return
        }
        self.stagedSignal = nil
        onSelect(stagedSignal)
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

    /// 창에 띄울 상대 도시의 현재 시각.
    static func clock(in timeZone: TimeZone, at date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// 상대가 나보다 몇 시간 앞인지. 30분 시차가 있는 도시가 있어 분도 함께 본다.
    static func offset(from mine: TimeZone, to theirs: TimeZone, at date: Date) -> String {
        let delta = theirs.secondsFromGMT(for: date) - mine.secondsFromGMT(for: date)
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
    private let outer = RoundedRectangle(cornerRadius: Keypad.chassisRadius, style: .continuous)
    private let inner = RoundedRectangle(
        cornerRadius: Keypad.chassisRadius - Keypad.chassisRim,
        style: .continuous
    )

    var body: some View {
        ZStack {
            // 아래로 삐져나온 옆면. 판때기가 아니라 상자로 보이게 하는 두께다.
            // 그림자는 번지는 반지름보다 더 아래로 내려야 한다. 반지름이 y보다 크면
            // 위쪽으로도 번져 나와 몸통 상단에 검은 테가 둘린다.
            outer
                .fill(Keypad.chassisSideFill)
                .offset(y: Keypad.chassisThickness)
                .shadow(color: .black.opacity(0.72), radius: 14, y: 18)

            // 위로 삐져나온 윗면. 아래에 옆면 두께가 보이는 만큼 위에도 실제 띠가 있어야
            // 같은 물건으로 읽힌다. 위에서 빛이 오니 이 면이 몸통에서 가장 밝다.
            outer
                .fill(Keypad.chassisCrownFill)
                .offset(y: -Keypad.chassisCrown)

            // 사방을 두르는 테두리. 빛을 정면으로 받아 가장 밝다.
            outer
                .fill(Keypad.chassisRimFill)
                .overlay { outer.strokeBorder(Keypad.rimEdge, lineWidth: 1.4) }
                // 위 모서리가 빛을 받아 도는 면. 아래는 옆면 두께가 보이지만 위는 이것뿐이라
                // 이게 없으면 상단만 잘려 나간 것처럼 납작해 보인다.
                .overlay { outer.strokeBorder(Keypad.rimCrown, lineWidth: 3) }
                .overlay { PlasticGrain().clipShape(outer) }

            // 테두리 안으로 한 단 내려앉은 윗판.
            inner
                .fill(Keypad.chassisFill)
                .innerShadow(
                    radius: Keypad.chassisRadius - Keypad.chassisRim,
                    color: .black.opacity(0.16),
                    width: 4
                )
                .overlay { inner.strokeBorder(Keypad.recessEdge, lineWidth: 1) }
                .padding(Keypad.chassisRim)
        }
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
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(isOn ? Keypad.led : Keypad.engraved)
                .rotationEffect(.degrees(isOn ? 45 : 0))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
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
        .padding(11)
        .background { glass }
        .overlay { sheen }
        .overlay { shape.strokeBorder(Keypad.recessEdge, lineWidth: 1.2) }
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
            .innerShadow(radius: Keypad.glassRadius, color: .black.opacity(0.95), width: 8)
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
            if !right.isEmpty {
                tag(right)
            }
        }
    }

    /// 역 안내판처럼 검은 판 위에서 글자 자체가 빛난다. 칠한 칩을 두면 종이 라벨로 보인다.
    private func tag(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .tracking(1.4)
            .foregroundStyle(Keypad.led)
            .shadow(color: Keypad.led.opacity(0.55), radius: 4)
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
    let activeSignal: CoupleSignal?
    let isEditing: Bool
    let canSend: Bool
    let onStage: (CoupleSignal) -> Void
    let onSend: () -> Void
    let onEdit: (Int) -> Void

    private let shape = RoundedRectangle(cornerRadius: Keypad.wellRadius, style: .continuous)

    /// 아홉 자리뿐이라 lazy로 둘 이유가 없다. `LazyVGrid`는 키캡을 몸통과 따로
    /// 나타나게 만들어서 기계가 두 번에 나눠 올라오는 것처럼 보인다.
    /// 마지막 자리는 신호가 아니라 보내기 키다.
    var body: some View {
        VStack(spacing: Keypad.keyGap) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: Keypad.keyGap) {
                    ForEach(0..<3, id: \.self) { column in
                        let index = row * 3 + column
                        if index == SignalKey.count {
                            enterKey
                        } else {
                            keycap(at: index)
                        }
                    }
                }
            }
        }
        .padding(Keypad.wellPadding)
        .background {
            shape
                .fill(Keypad.wellFill)
                .innerShadow(radius: Keypad.wellRadius, color: .black.opacity(0.6), width: 8)
                .overlay { shape.strokeBorder(Keypad.recessEdge, lineWidth: 1.2) }
        }
    }

    @ViewBuilder
    private func keycap(at index: Int) -> some View {
        if keys.indices.contains(index) {
            let key = keys[index]
            Button {
                if isEditing {
                    onEdit(index)
                } else {
                    UISelectionFeedbackGenerator().selectionChanged()
                    onStage(key.signal)
                }
            } label: {
                KeycapFace(
                    emoji: key.emoji,
                    isSelected: !isEditing && key.signal == activeSignal,
                    isEditing: isEditing
                )
            }
            .buttonStyle(KeycapPress())
            .onLongPressGesture(minimumDuration: 0.45) {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                onEdit(index)
            }
            .accessibilityLabel(key.label.isEmpty ? key.signal.title : key.label)
            .accessibilityValue(key.signal == activeSignal ? "선택됨" : "")
            .accessibilityHint("길게 누르면 이 키를 바꿔요")
        }
    }

    /// 누른 신호는 눌린 채로 남고, 실제로 나가는 것은 이 키를 눌렀을 때다.
    private var enterKey: some View {
        Button(action: onSend) {
            EnterKeyFace(isArmed: canSend)
        }
        .buttonStyle(KeycapPress())
        .accessibilityLabel("보내기")
        .accessibilityHint(canSend ? "고른 Signal을 보내요" : "기계를 닫아요")
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
            // 키캡 옆면. 빛이 왼쪽 위에서 오니까 왼쪽 벽이 밝고 오른쪽 아래가 어둡다.
            RoundedRectangle(cornerRadius: Keypad.keyRadius, style: .continuous)
                .fill(Keypad.skirtFill)
                .shadow(color: .black.opacity(0.55), radius: 4, y: 3)

            cap
                .padding(.horizontal, Keypad.keyInset)
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
            .overlay(alignment: .top) { specular }
            .overlay { shape.strokeBorder(Keypad.capEdge, lineWidth: 1.2) }
            .overlay {
                Text(emoji)
                    .font(.system(size: Keypad.emojiSize))
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1.5)
            }
            .overlay(alignment: .topTrailing) { activeLamp }
    }

    /// 손가락이 닿는 면은 살짝 파여 있다.
    private var dish: some View {
        shape.fill(Keypad.capDish)
    }

    /// 윗면이 받는 반사. 위쪽 절반에만 얹어야 면이 휘어 보인다.
    private var specular: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: Keypad.keyRadius - 2,
            bottomLeadingRadius: 2,
            bottomTrailingRadius: 2,
            topTrailingRadius: Keypad.keyRadius - 2,
            style: .continuous
        )
        .fill(Keypad.capSpecular)
        .padding(.horizontal, 1)
        .padding(.top, 1)
        .frame(maxHeight: 26, alignment: .top)
        .allowsHitTesting(false)
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
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(.white.opacity(0.55))
                .padding(6)
        }
    }
}

/// 신호 키와 같은 몸이지만 색이 다르다. 레퍼런스의 회색 기능키 자리다.
private struct EnterKeyFace: View {
    let isArmed: Bool
    @Environment(\.keycapIsPressed) private var isPressed

    private let shape = RoundedRectangle(cornerRadius: Keypad.keyRadius - 2, style: .continuous)

    private var sink: CGFloat {
        isPressed ? Keypad.keyDepth - 1.5 : 0
    }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: Keypad.keyRadius, style: .continuous)
                .fill(Keypad.skirtFill)
                .shadow(color: .black.opacity(0.55), radius: 4, y: 3)

            shape
                .fill(isArmed ? Keypad.enterArmedFill : Keypad.enterFill)
                .overlay { shape.fill(Keypad.capDish) }
                .overlay { shape.strokeBorder(Keypad.capEdge, lineWidth: 1.2) }
                .overlay {
                    Image(systemName: "return")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(isArmed ? Keypad.glass : .white.opacity(0.5))
                }
                .padding(.horizontal, Keypad.keyInset)
                .padding(.top, sink)
                .padding(.bottom, Keypad.keyDepth - sink)
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.spring(response: 0.16, dampingFraction: 0.72), value: isPressed)
        .animation(.easeOut(duration: 0.16), value: isArmed)
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
            // 밀도를 높여도 5% 불투명도에서는 차이가 안 보이는데, 굽는 비용만 그만큼 늘어난다.
            let count = Int(size.width * size.height / 44)
            for _ in 0..<count {
                let point = CGPoint(x: next() * size.width, y: next() * size.height)
                let bright = next() > 0.5
                context.fill(
                    Path(CGRect(origin: point, size: CGSize(width: 1, height: 1))),
                    with: .color(bright ? .white : .black)
                )
            }
        }
        // 알갱이는 한 번 그려 텍스처로 굳힌다. 움직일 때마다 수천 개를 다시 찍으면 프레임이 튄다.
        .drawingGroup()
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
    static let chassisRadius: CGFloat = 28
    /// 손에 잡히는 기계로 보이려면 화면 폭을 다 먹으면 안 된다.
    static let chassisMaxWidth: CGFloat = 330
    static let chassisRim: CGFloat = 7
    /// 위로 보이는 윗면 띠. 아래 옆면 두께와 짝이 맞게 그보다 조금 얇다.
    static let chassisCrown: CGFloat = 5
    /// 텍스처로 굳힐 때 바깥 그림자가 잘리지 않도록 잡아 두는 여백.
    /// 몸통 그림자가 아래로 `y + radius`만큼 번지므로 그보다 넉넉해야 한다.
    /// 넓힐수록 굽는 면적이 그대로 늘어나므로 딱 필요한 만큼만 둔다.
    static let rasterMargin: CGFloat = 36
    /// 테두리가 배경 안쪽으로 들어오므로 내용은 테두리 두께만큼 더 물러난다.
    static let chassisPadding: CGFloat = 18
    static let chassisGap: CGFloat = 13
    static let glassRadius: CGFloat = 12
    static let wellRadius: CGFloat = 16
    static let wellPadding: CGFloat = 10
    static let keyGap: CGFloat = 9
    static let keyRadius: CGFloat = 13
    static let keyDepth: CGFloat = 10
    static let keyInset: CGFloat = 4
    static let chassisThickness: CGFloat = 9
    static let emojiSize: CGFloat = 38
    static let digitWidth: CGFloat = 25
    static let digitHeight: CGFloat = 42

    static let led = Color(red: 1.00, green: 0.68, blue: 0.13)
    static let ledDim = Color(red: 0.90, green: 0.55, blue: 0.06)
    static let ledOff = Color(red: 0.20, green: 0.105, blue: 0.012)
    static let glass = Color(red: 0.045, green: 0.038, blue: 0.030)
    /// 보낼 준비가 되면 LED 색으로 물든다.
    static let enterArmedFill = LinearGradient(
        colors: [Color(red: 1.00, green: 0.72, blue: 0.20), Color(red: 0.88, green: 0.52, blue: 0.05)],
        startPoint: .top,
        endPoint: .bottom
    )

    static let enterFill = LinearGradient(
        colors: [Color(red: 0.400, green: 0.392, blue: 0.382), Color(red: 0.290, green: 0.284, blue: 0.276)],
        startPoint: .top,
        endPoint: .bottom
    )
    static let engraved = Color(red: 0.38, green: 0.37, blue: 0.35)
    static let engravedFaint = Color(red: 0.55, green: 0.54, blue: 0.52)

    /// 테두리는 빛을 정면으로 받는 면이라 가장 밝고, 왼쪽 위에서 오른쪽 아래로 어두워진다.
    static let chassisRimFill = LinearGradient(
        colors: [
            Color(red: 0.975, green: 0.968, blue: 0.948),
            Color(red: 0.900, green: 0.890, blue: 0.866),
            Color(red: 0.790, green: 0.778, blue: 0.752)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let rimEdge = LinearGradient(
        colors: [.white.opacity(0.95), .white.opacity(0.2), .black.opacity(0.28)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// 위 모서리에만 얹는 하이라이트. 중간에서 사라져 아래 옆면과 부딪히지 않는다.
    static let rimCrown = LinearGradient(
        colors: [.white.opacity(0.55), .white.opacity(0.08), .clear],
        startPoint: .top,
        endPoint: .center
    )

    /// 위로 삐져나오는 윗면. 아래 옆면과 짝이 되는 띠라 몸통에서 가장 밝다.
    static let chassisCrownFill = LinearGradient(
        colors: [Color(red: 0.995, green: 0.992, blue: 0.982), Color(red: 0.930, green: 0.922, blue: 0.902)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// 테두리 안쪽 윗판은 한 단 내려앉아 있어 조금 어둡다.
    static let chassisFill = LinearGradient(
        colors: [Color(red: 0.880, green: 0.870, blue: 0.846), Color(red: 0.815, green: 0.803, blue: 0.776)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// 우물 바닥. 위가 어둡고 아래가 밝아야 안으로 파인 것처럼 보인다.
    static let wellFill = LinearGradient(
        colors: [Color(red: 0.560, green: 0.548, blue: 0.522), Color(red: 0.735, green: 0.722, blue: 0.694)],
        startPoint: .top,
        endPoint: .bottom
    )

    static let chassisSideFill = LinearGradient(
        colors: [Color(red: 0.600, green: 0.588, blue: 0.562), Color(red: 0.430, green: 0.420, blue: 0.400)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// 파인 자리의 테두리. 위쪽은 그늘, 아래쪽은 빛을 받는다.
    /// 위아래 대비를 세게 주면 같은 한 줄이 위에서는 검은 선, 아래에서는 흰 선으로 갈려
    /// 옆면을 따라 올라갈수록 다른 물건처럼 보인다. 가운데를 거의 투명하게 두어 잇는다.
    static let recessEdge = LinearGradient(
        colors: [.black.opacity(0.28), .black.opacity(0.05), .white.opacity(0.22)],
        startPoint: .top,
        endPoint: .bottom
    )

    static let capSpecular = LinearGradient(
        colors: [.white.opacity(0.16), .white.opacity(0.02), .clear],
        startPoint: .top,
        endPoint: .bottom
    )

    static let capFill = LinearGradient(
        colors: [Color(red: 0.255, green: 0.250, blue: 0.245), Color(red: 0.170, green: 0.166, blue: 0.162)],
        startPoint: .top,
        endPoint: .bottom
    )

    static let skirtFill = LinearGradient(
        colors: [
            Color(red: 0.185, green: 0.180, blue: 0.176),
            Color(red: 0.105, green: 0.102, blue: 0.099),
            Color(red: 0.055, green: 0.053, blue: 0.051)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
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
