import SwiftUI

/// 소포를 포장하는 화면. 예전 버전은 제목과 편지에 예시 문장이 미리 박혀 있어서
/// 사용자가 먼저 지워야 했고, 개발용 배송 토글까지 노출돼 있었다.
struct ParcelComposerSheet: View {
    let homeCity: CoupleCity
    let partnerCity: CoupleCity
    let flightDuration: TimeInterval
    let onSend: (String, String, ParcelWrap) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var message = ""
    @State private var wrap = ParcelWrap.coral
    @FocusState private var focusedField: Field?

    private enum Field { case title, message }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedMessage: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { !trimmedTitle.isEmpty && !trimmedMessage.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                SpaceBackground().equatable()

                ScrollView {
                    VStack(alignment: .leading, spacing: Metric.xl) {
                        ParcelPreview(wrap: wrap, title: trimmedTitle)

                        deliveryNote

                        field(title: "소포 이름") {
                            TextField("", text: $title, prompt: placeholder("한 마디로 부른다면"))
                                .font(.rounded(.body, .medium))
                                .focused($focusedField, equals: .title)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .message }
                        }

                        field(title: "편지") {
                            TextEditor(text: $message)
                                .font(.system(.body, design: .serif))
                                .lineSpacing(5)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 150)
                                .focused($focusedField, equals: .message)
                                .overlay(alignment: .topLeading) {
                                    if message.isEmpty {
                                        Text("도착할 때쯤 읽었으면 하는 이야기를 적어보세요")
                                            .font(.system(.body, design: .serif))
                                            .foregroundStyle(Palette.textTertiary)
                                            .padding(.top, 8)
                                            .padding(.leading, 5)
                                            .allowsHitTesting(false)
                                    }
                                }
                        }

                        wrapPicker

                        sendButton
                            .padding(.top, Metric.xs)
                    }
                    .padding(Metric.screenPadding)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .tint(wrap.color)
            .navigationTitle("소포 포장하기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .presentationBackground(Palette.space)
    }

    // MARK: - Pieces

    /// 어디로 얼마나 걸려서 가는지. 보내기 전에 알아야 할 유일한 사실이라 한 줄로 둔다.
    private var deliveryNote: some View {
        HStack(spacing: Metric.s) {
            Text(homeCity.name)
                .foregroundStyle(Palette.me)
            Text("→")
                .foregroundStyle(Palette.textTertiary)
            Text(partnerCity.name)
                .foregroundStyle(Palette.you)

            Spacer(minLength: Metric.s)

            Text("도착까지 \(flightDuration.shortKoreanDuration)")
                .foregroundStyle(Palette.textSecondary)
        }
        .font(.rounded(.footnote, .semibold))
        .frame(maxWidth: .infinity)
    }

    private func field<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Metric.s) {
            Text(title)
                .font(.rounded(.footnote, .semibold))
                .foregroundStyle(Palette.textSecondary)

            content()
                .foregroundStyle(Palette.textPrimary)
                .padding(Metric.m)
                .background(
                    Palette.surface,
                    in: RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                }
        }
    }

    private func placeholder(_ text: String) -> Text {
        Text(text).foregroundStyle(Palette.textTertiary)
    }

    private var wrapPicker: some View {
        VStack(alignment: .leading, spacing: Metric.m) {
            Text("포장지")
                .font(.rounded(.footnote, .semibold))
                .foregroundStyle(Palette.textSecondary)

            HStack(spacing: Metric.l) {
                ForEach(ParcelWrap.allCases) { option in
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) { wrap = option }
                    } label: {
                        VStack(spacing: Metric.s) {
                            Circle()
                                .fill(option.color.gradient)
                                .frame(width: 44, height: 44)
                                .overlay {
                                    Circle()
                                        .strokeBorder(.white, lineWidth: wrap == option ? 2.5 : 0)
                                        .padding(3)
                                }
                                .shadow(
                                    color: option.color.opacity(wrap == option ? 0.6 : 0),
                                    radius: 10
                                )
                            Text(option.title)
                                .font(.rounded(.caption2, wrap == option ? .bold : .regular))
                                .foregroundStyle(wrap == option ? Palette.textPrimary : Palette.textTertiary)
                        }
                    }
                    .buttonStyle(PressableCard())
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(wrap == option ? [.isSelected] : [])
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var sendButton: some View {
        Button {
            onSend(trimmedTitle, trimmedMessage, wrap)
        } label: {
            Label("소포 보내기", systemImage: "paperplane.fill")
                .font(.rounded(.headline, .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
        }
        .buttonStyle(.glassProminent)
        .tint(wrap.color)
        .disabled(!canSend)
        .opacity(canSend ? 1 : 0.45)
        .animation(.easeInOut(duration: 0.2), value: canSend)
    }
}

/// 포장지를 고르는 즉시 결과가 보이도록. 리본은 그대로 두되 비율을 낮췄다.
private struct ParcelPreview: View {
    let wrap: ParcelWrap
    let title: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(wrap.color.gradient)

            Rectangle().fill(.white.opacity(0.28)).frame(width: 26)
            Rectangle().fill(.white.opacity(0.28)).frame(height: 26)

            Image(systemName: "heart.fill")
                .font(.system(size: 22))
                .foregroundStyle(wrap.color)
                .frame(width: 46, height: 46)
                .background(.white, in: Circle())

            if !title.isEmpty {
                VStack {
                    Spacer()
                    Text(title)
                        .font(.rounded(.caption, .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, Metric.m)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.28), in: Capsule())
                        .padding(.bottom, Metric.m)
                }
            }
        }
        .frame(height: 148)
        .shadow(color: wrap.color.opacity(0.35), radius: 24, y: 12)
        .animation(.easeInOut(duration: 0.25), value: wrap)
        .accessibilityHidden(true)
    }
}
