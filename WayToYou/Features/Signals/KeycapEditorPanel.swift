import SwiftUI
import UIKit

/// 지금 편집 중인 키캡 한 자리.
struct EditingKeycap: Identifiable {
    let index: Int
    let key: SignalKey

    var id: Int { index }
}

/// 키캡 하나를 바꾸는 패널.
///
/// iOS 기본 알림창을 쓰면 레트로 기계 위에 시스템 카드가 얹혀 튀고, 무엇보다
/// 알림창 안에는 커스텀 입력 필드를 넣을 수 없어 이모지 키보드를 띄울 방법이 없다.
struct KeycapEditorPanel: View {
    let target: EditingKeycap
    let onCancel: () -> Void
    let onSave: (SignalKey) -> Void

    @State private var emoji: String = ""
    @State private var label: String = ""
    @FocusState private var labelIsFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)

            panel
                .padding(.horizontal, Metric.screenPadding)
                .padding(.top, 96)
        }
        .onAppear {
            emoji = target.key.emoji
            label = target.key.label
        }
    }

    private var panel: some View {
        VStack(spacing: 16) {
            header

            EmojiTextField(text: $emoji) { labelIsFocused = true }
                .frame(height: 74)
                .frame(maxWidth: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Editor.keycap)
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                        }
                }

            TextField("", text: $label, prompt: labelPrompt)
                .focused($labelIsFocused)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .tint(Editor.led)
                .multilineTextAlignment(.center)
                .submitLabel(.done)
                .onSubmit(save)
                .onChange(of: label) { _, typed in
                    label = String(typed.prefix(SignalKey.labelLimit))
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Editor.field)
                }

            HStack(spacing: 10) {
                action("취소", isPrimary: false, perform: onCancel)
                action("저장", isPrimary: true, perform: save)
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Editor.panel)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.6), radius: 24, y: 12)
        }
        .frame(maxWidth: 330)
    }

    private var header: some View {
        HStack {
            Text("KEY \(target.index + 1)")
            Spacer(minLength: 8)
            Text("EMOJI + LABEL")
        }
        .font(.system(size: 11, weight: .bold, design: .monospaced))
        .tracking(1.4)
        .foregroundStyle(Editor.led)
    }

    private var labelPrompt: Text {
        Text("설명 \(SignalKey.labelLimit)자 이내")
            .foregroundColor(.white.opacity(0.3))
    }

    private func action(_ title: String, isPrimary: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isPrimary ? Editor.panel : .white.opacity(0.75))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isPrimary ? AnyShapeStyle(Editor.led) : AnyShapeStyle(Editor.field))
                }
        }
        .buttonStyle(PressableCard())
        .disabled(isPrimary && emoji.isEmpty)
        .opacity(isPrimary && emoji.isEmpty ? 0.45 : 1)
    }

    private func save() {
        guard let signal = CoupleSignal.keycap(from: emoji) else { return }
        onSave(SignalKey(signal: signal, label: label))
    }
}

/// 커서가 들어가는 순간 이모지 키보드가 뜬다.
///
/// `textInputMode`를 이모지 모드로 고정하는 방식이다. 사용자가 이모지 키보드를
/// 꺼 두었다면 일반 키보드가 뜨므로, 글자가 들어오는 경우는 입력 단계에서 막는다.
private struct EmojiTextField: UIViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = EmojiInputTextField()
        field.delegate = context.coordinator
        field.text = text
        field.textAlignment = .center
        field.font = .systemFont(ofSize: 42)
        field.backgroundColor = .clear
        field.tintColor = UIColor(Editor.led)
        field.autocorrectionType = .no
        field.returnKeyType = .next
        DispatchQueue.main.async { field.becomeFirstResponder() }
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        /// 한 칸에 이모지 하나만 둔다. 새 이모지를 누르면 앞의 것을 갈아치운다.
        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            if string.isEmpty {
                textField.text = ""
                text.wrappedValue = ""
                return false
            }
            guard let signal = CoupleSignal.keycap(from: string) else { return false }
            textField.text = signal.emoji
            text.wrappedValue = signal.emoji
            return false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            onSubmit()
            return false
        }
    }
}

private final class EmojiInputTextField: UITextField {
    /// 비워 두면 이전에 쓰던 키보드를 물려받지 않는다.
    override var textInputContextIdentifier: String? { "" }

    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" }
            ?? super.textInputMode
    }
}

private enum Editor {
    static let panel = Color(red: 0.09, green: 0.085, blue: 0.08)
    static let field = Color(red: 0.16, green: 0.155, blue: 0.15)
    static let keycap = Color(red: 0.215, green: 0.21, blue: 0.205)
    static let led = Color(red: 1.00, green: 0.68, blue: 0.13)
}
