import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import OSLog
import Supabase

// 로그인 상태 6가지 정의 ( 상태는 enum으로 짜는 것이 건강한 코드 )
enum BackendSessionState: Equatable {
    case idle           // 아직 아무것도 안 함
    case restoring      // 저장된 로그인 확인 중
    case signedOut      // 로그인 필요
    case signingIn      // 로그인 진행중
    case authenticated(userID: UUID) // 로그인 완료 + 누구인지
    case unavailable    // 설정 오류 / 서버 장애
}

// 설정 오류 3가지 정의
enum SupabaseConfigurationError: LocalizedError {
    case missingValue
    case invalidURL
    case unsafeKey

    var errorDescription: String? {
        switch self {
        case .missingValue:
            "Supabase 연결 설정이 비어 있습니다."
        case .invalidURL:
            "Supabase 프로젝트 주소가 올바르지 않습니다."
        case .unsafeKey:
            "iOS 앱에는 Publishable key만 사용할 수 있습니다."
        }
    }
}

/// Apple이 발급한 ID 토큰은 nonce로 검증하고, Supabase 세션은 Keychain에만 보관한다.
/// 토큰과 서버의 상세 오류는 화면이나 로그에 남기지 않는다.
@Observable
final class SupabaseSessionController {
    private static let oauthRedirectURL = URL(string: "waytoyou://auth-callback")!

    private static let logger = Logger(
        subsystem: "com.seungwoo.WayToYou",
        category: "SupabaseAuth"
    )

    private(set) var state = BackendSessionState.idle
    private(set) var userMessage: String?
    private(set) var suggestedDisplayName: String?

    let client: SupabaseClient?
    private var pendingAppleNonce: String?

    var authenticatedUserID: UUID? {
        guard case .authenticated(let userID) = state else { return nil }
        return userID
    }

    var isConfigured: Bool { client != nil }

    init(bundle: Bundle = .main) {
        client = try? Self.makeClient(bundle: bundle)
        if client == nil {
            state = .unavailable
            userMessage = "앱의 연결 설정을 확인해주세요."
        }
    }

    /// Keychain의 세션을 복원한다. 익명 세션은 이 앱의 인증 방식으로 인정하지 않는다.
    /// 앱을 켤 때마다 저장된 로그인 정보가 있나 확인하는 작업, Keychain에 저장한 토큰을 꺼내서 Restore
    func restoreSession() async {
        guard let client, state == .idle else { return }

        state = .restoring
        userMessage = nil

        do {
            let session = try await client.auth.session
            guard !session.user.isAnonymous else {
                try? await client.auth.signOut(scope: .local)
                state = .signedOut
                return
            }
            // Keychain은 앱 삭제 뒤에도 남는다. 로컬 세션의 사용자가 서버에도
            // 존재하는지 확인해야 개발 초기화나 서버 삭제 뒤 유령 세션을 복원하지 않는다.
            let remoteUser = try await client.auth.user(jwt: session.accessToken)
            guard remoteUser.id == session.user.id else {
                try? await client.auth.signOut(scope: .local)
                state = .signedOut
                return
            }
            applyAuthenticatedSession(session)
            Self.logger.notice("기존 Supabase 인증 세션을 복원했습니다.")
        } catch let authError as AuthError where Self.isStaleSession(authError) {
            try? await client.auth.signOut(scope: .local)
            state = .signedOut
            userMessage = nil
            Self.logger.notice("서버에 존재하지 않는 로컬 인증 세션을 삭제했습니다.")
        } catch {
            state = .unavailable
            userMessage = "계정을 확인하지 못했어요. 잠시 후 다시 시도해주세요."
            Self.logger.notice("Supabase 인증 세션을 복원하지 못했습니다.")
        }
    }

    /// Apple 요청과 Supabase 검증에 같은 원본 nonce를 사용해 재전송 공격을 막는다.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        guard client != nil else {
            state = .unavailable
            userMessage = "앱의 연결 설정을 확인해주세요."
            return
        }

        let nonce = Self.randomNonceString()
        pendingAppleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
        // 시스템 인증 시트가 완료될 때까지 버튼과 completion 핸들러를 뷰에 유지한다.
        // 요청 단계에서 로딩 화면으로 교체하면 인증 콜백이 유실될 수 있다.
        userMessage = nil
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        guard let client else {
            state = .unavailable
            userMessage = "앱의 연결 설정을 확인해주세요."
            return
        }

        switch result {
        case .failure(let error):
            pendingAppleNonce = nil
            state = .signedOut
            if let authorizationError = error as? ASAuthorizationError,
               authorizationError.code == .canceled {
                userMessage = nil
            } else {
                userMessage = "Apple 로그인을 완료하지 못했어요. 다시 시도해주세요."
                Self.logger.notice("Apple 인증 화면을 완료하지 못했습니다.")
            }

        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = pendingAppleNonce,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                pendingAppleNonce = nil
                state = .signedOut
                userMessage = "Apple 인증 정보를 확인하지 못했어요. 다시 시도해주세요."
                return
            }

            pendingAppleNonce = nil
            state = .signingIn

            do {
                let session = try await client.auth.signInWithIdToken(
                    credentials: OpenIDConnectCredentials(
                        provider: .apple,
                        idToken: idToken,
                        nonce: nonce
                    )
                )

                if let fullName = Self.displayName(from: credential.fullName) {
                    suggestedDisplayName = fullName
                    // 이름은 Apple이 최초 승인 시에만 주므로 즉시 보관한다.
                    _ = try? await client.auth.update(
                        user: UserAttributes(data: ["full_name": .string(fullName)])
                    )
                }

                applyAuthenticatedSession(session)
                Self.logger.notice("Apple ID로 Supabase 인증을 완료했습니다.")
            } catch let authError as AuthError where authError.errorCode == .providerDisabled {
                state = .signedOut
                userMessage = "Supabase에서 Apple 로그인을 먼저 활성화해주세요."
                Self.logger.notice("Supabase 프로젝트에서 Apple 로그인을 활성화해야 합니다.")
            } catch {
                state = .signedOut
                userMessage = "로그인을 완료하지 못했어요. 잠시 후 다시 시도해주세요."
                Self.logger.notice("Apple ID 토큰을 Supabase에서 검증하지 못했습니다.")
            }
        }
    }

    /// Google Client Secret은 앱에 두지 않고 Supabase에만 보관한다.
    /// iOS의 ASWebAuthenticationSession과 PKCE를 사용해 계정 선택 결과를 세션으로 교환한다.
    func signInWithGoogle() async {
        guard let client else {
            state = .unavailable
            userMessage = "앱의 연결 설정을 확인해주세요."
            return
        }

        state = .signingIn
        userMessage = nil

        do {
            let session = try await client.auth.signInWithOAuth(
                provider: .google,
                redirectTo: Self.oauthRedirectURL,
                queryParams: [(name: "prompt", value: "select_account")]
            )
            applyAuthenticatedSession(session)
            Self.logger.notice("Google 계정으로 Supabase 인증을 완료했습니다.")
        } catch let webError as ASWebAuthenticationSessionError
        where webError.code == .canceledLogin {
            state = .signedOut
            userMessage = nil
        } catch let authError as AuthError where authError.errorCode == .providerDisabled {
            state = .signedOut
            userMessage = "Supabase에서 Google 로그인을 먼저 활성화해주세요."
            Self.logger.notice("Supabase 프로젝트에서 Google 로그인을 활성화해야 합니다.")
        } catch {
            state = .signedOut
            userMessage = "Google 로그인을 완료하지 못했어요. 설정을 확인하고 다시 시도해주세요."
            Self.logger.notice("Google OAuth 세션을 Supabase에서 검증하지 못했습니다.")
        }
    }

    private func applyAuthenticatedSession(_ session: Session) {
        if suggestedDisplayName == nil {
            suggestedDisplayName = session.user.userMetadata["full_name"]?.stringValue
        }
        userMessage = nil
        state = .authenticated(userID: session.user.id)
    }

    private static func makeClient(bundle: Bundle) throws -> SupabaseClient {
        // 검사 1 : 값이 있나
        guard let urlText = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let key = bundle.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String,
              !urlText.isEmpty,
              !key.isEmpty else {
            throw SupabaseConfigurationError.missingValue
        }

        // 검사 2 : 주소가 정상인가
        guard let url = URL(string: urlText),
              url.scheme == "https",
              url.host?.hasSuffix(".supabase.co") == true else {
            throw SupabaseConfigurationError.invalidURL
        }

        // 검사 3 : 안전한 키인가
        guard key.hasPrefix("sb_publishable_"),
              !key.hasPrefix("sb_secret_"),
              !key.localizedCaseInsensitiveContains("service_role") else {
            throw SupabaseConfigurationError.unsafeKey
        }

        // SupabaseClient 만들기
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: .init(
                    storage: KeychainLocalStorage(
                        service: "com.seungwoo.WayToYou.supabase.auth"
                    ),
                    redirectToURL: Self.oauthRedirectURL,
                    storageKey: "way-to-you.auth.session",
                    flowType: .pkce,
                    autoRefreshToken: true,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }

    private static func isStaleSession(_ error: AuthError) -> Bool {
        switch error.errorCode {
        case .userNotFound, .sessionNotFound, .sessionExpired,
             .refreshTokenNotFound, .refreshTokenAlreadyUsed:
            true
        default:
            false
        }
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in
            characters.randomElement(using: &generator)!
        })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func displayName(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let name = PersonNameComponentsFormatter()
            .string(from: components)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}
