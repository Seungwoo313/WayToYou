import AuthenticationServices
import SwiftUI

struct AppleSignInView: View {
    @Bindable var backend: SupabaseSessionController

    private var isBusy: Bool {
        backend.state == .restoring || backend.state == .signingIn
    }

    var body: some View {
        ZStack {
            Palette.spaceDeep.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                brandMark
                    .padding(.top, 56)

                Spacer(minLength: 72)

                VStack(alignment: .leading, spacing: Metric.l) {
                    Text("멀리 있어도,\n같은 곳을 바라보도록")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                        .tracking(-1.1)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("두 사람의 시간과 마음을 하나의 지구 위에 이어보세요.")
                        .font(.rounded(.body))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 88)

                VStack(spacing: Metric.m) {
                    if isBusy {
                        HStack(spacing: Metric.s) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Palette.textSecondary)
                            Text(backend.state == .restoring ? "계정을 확인하고 있어요" : "안전하게 연결하고 있어요")
                                .font(.rounded(.footnote, .medium))
                                .foregroundStyle(Palette.textSecondary)
                        }
                        .frame(height: 56)
                    } else {
                        VStack(spacing: Metric.m) {
                            SignInWithAppleButton(.continue) { request in
                                backend.prepareAppleRequest(request)
                            } onCompletion: { result in
                                Task { await backend.completeAppleSignIn(result) }
                            }
                            .signInWithAppleButtonStyle(.white)
                            .frame(height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                            Button {
                                Task { await backend.signInWithGoogle() }
                            } label: {
                                Text("Google로 계속하기")
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                                    .foregroundStyle(Palette.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 56)
                                    .background(
                                        Palette.surface,
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(Palette.hairline, lineWidth: 0.5)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Google 계정 선택 화면을 엽니다")
                        }
                        .disabled(!backend.isConfigured)
                    }

                    if let message = backend.userMessage {
                        Text(message)
                            .font(.rounded(.caption))
                            .foregroundStyle(Palette.you)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("로그인하면 서비스 이용을 위한 최소한의 계정 식별 정보만 사용합니다.")
                        .font(.rounded(.caption2))
                        .foregroundStyle(Palette.textTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 24)
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, Metric.screenPadding)
        }
    }

    private var brandMark: some View {
        HStack(spacing: Metric.m) {
            ZStack {
                Circle()
                    .strokeBorder(Palette.hairline, lineWidth: 1)
                    .frame(width: 36, height: 36)

                Circle()
                    .fill(Palette.me)
                    .frame(width: 6, height: 6)
                    .offset(x: -7, y: 4)

                Circle()
                    .fill(Palette.you)
                    .frame(width: 6, height: 6)
                    .offset(x: 7, y: -4)
            }

            Text("Way to You")
                .font(.rounded(.headline, .semibold))
                .foregroundStyle(Palette.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}
