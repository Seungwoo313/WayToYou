import AuthenticationServices
import SwiftUI

struct AppleSignInView: View {
    @Bindable var backend: SupabaseSessionController

    /// 세션 복원(`.restoring`)은 이 화면에 오기 전에 LaunchView가 맡는다.
    /// 여기서 기다리게 되는 건 사람이 직접 버튼을 누른 뒤뿐이다.
    private var isBusy: Bool {
        backend.state == .signingIn
    }

    var body: some View {
        ZStack {
            Palette.spaceDeep.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                BrandMark()
                    .padding(.top, 56)

                Spacer(minLength: 32)

                headline

                Spacer(minLength: 40)

                VStack(spacing: Metric.l) {
                    if isBusy {
                        HStack(spacing: Metric.s) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Palette.textSecondary)
                            Text("안전하게 연결하고 있어요")
                                .font(.rounded(.footnote, .medium))
                                .foregroundStyle(Palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 116)
                    } else {
                        signInOptions
                    }

                    if let message = backend.userMessage {
                        Text(message)
                            .font(.rounded(.caption))
                            .foregroundStyle(Palette.you)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("로그인에 필요한 최소한의 계정 정보만 사용합니다.")
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

    /// 네 줄로 끊어서 `means nothing`과 `means everything`이 세로로 겹치게 둔다.
    /// 이 문장의 힘은 그 대구에서 나오니까, 줄바꿈이 곧 뜻이다.
    /// Text끼리 더하면 그룹이 달라도 행간이 흐트러지지 않는다.
    private var headline: some View {
        (
            Text("Distance\nmeans nothing\n")
                .foregroundStyle(Palette.textSecondary)
            + Text("when someone\nmeans everything")
                .foregroundStyle(Palette.textPrimary)
        )
        .font(.system(size: 34, weight: .semibold))
        .tracking(-0.6)
        .lineSpacing(1)
        .fixedSize(horizontal: false, vertical: true)
        .minimumScaleFactor(0.8)
        .accessibilityLabel("Distance means nothing when someone means everything")
    }

    /// 두 버튼을 같은 알약 모양·같은 높이로 맞춘다.
    /// Apple 버튼은 시스템이 그리므로, Google 쪽을 거기에 맞추는 방향으로 짠다.
    private var signInOptions: some View {
        VStack(spacing: Metric.m) {
            SignInWithAppleButton(.continue) { request in
                backend.prepareAppleRequest(request)
            } onCompletion: { result in
                Task { await backend.completeAppleSignIn(result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: Self.buttonHeight)
            .clipShape(Capsule())

            Button {
                Task { await backend.signInWithGoogle() }
            } label: {
                HStack(spacing: Metric.s) {
                    Image("GoogleMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 21, height: 21)

                    Text("Google로 계속하기")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(.black)
                }
                .frame(maxWidth: .infinity)
                .frame(height: Self.buttonHeight)
                .background(.white, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Google로 계속하기")
            .accessibilityHint("Google 계정 선택 화면을 엽니다")
        }
        .disabled(!backend.isConfigured)
    }

    private static let buttonHeight: CGFloat = 52
}
