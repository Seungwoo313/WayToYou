import Foundation
import Supabase

struct RemoteProfile: Decodable {
    let id: UUID
    let displayName: String
    let endpoint: RouteEndpoint?
    let avatarPath: String?
    let avatarUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case endpoint = "route_endpoint"
        case avatarPath = "avatar_path"
        case avatarUpdatedAt = "avatar_updated_at"
    }

    var profile: UserProfile? {
        guard let endpoint else { return nil }
        return UserProfile(
            id: id,
            displayName: displayName,
            endpoint: endpoint,
            avatarPath: avatarPath,
            avatarUpdatedAt: avatarUpdatedAt
        )
    }
}

struct RemoteConnectionState: Decodable {
    let status: String?
    let me: RemoteProfile?
    let partner: RemoteProfile?
    let connectionID: UUID?
    let connectedAt: Date?
    let inviteID: UUID?
    let inviteExpiresAt: Date?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case status, me, partner, error
        case connectionID = "connection_id"
        case connectedAt = "connected_at"
        case inviteID = "invite_id"
        case inviteExpiresAt = "invite_expires_at"
    }
}

private struct RemoteInvite: Decodable {
    let id: UUID
    let code: String
    let createdByID: UUID
    let createdAt: Date
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id, code
        case createdByID = "created_by_id"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }

    var invitation: ConnectionInvite {
        ConnectionInvite(
            id: id,
            code: code,
            createdByID: createdByID,
            createdAt: createdAt,
            expiresAt: expiresAt
        )
    }
}

struct RemoteHeartBurst: Decodable {
    let id: UUID
    let senderID: UUID
    let count: Int
    let sentAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case senderID = "sender_id"
        case count = "heart_count"
        case sentAt = "sent_at"
    }
}

struct RemoteSignalEvent: Decodable {
    let id: UUID
    let senderID: UUID
    let signal: CoupleSignal
    let sentAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case senderID = "sender_id"
        case signal = "signal_type"
        case sentAt = "sent_at"
    }
}

struct SupabaseConnectionService {
    private static let profilePhotoBucket = "wty-profile-photos"

    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func connectionState() async throws -> RemoteConnectionState {
        try await client
            .rpc("wty_get_connection_state")
            .execute()
            .value
    }

    func saveProfile(displayName: String, endpoint: RouteEndpoint) async throws -> UserProfile {
        struct Parameters: Encodable {
            let p_display_name: String
            let p_route_endpoint: RouteEndpoint
        }

        let remote: RemoteProfile = try await client
            .rpc(
                "wty_save_profile",
                params: Parameters(p_display_name: displayName, p_route_endpoint: endpoint)
            )
            .execute()
            .value
        guard let profile = remote.profile else { throw SupabaseConnectionError.incompleteProfile }
        return profile
    }

    func createInvitation() async throws -> ConnectionInvite {
        let remote: RemoteInvite = try await client
            .rpc("wty_create_invite")
            .execute()
            .value
        return remote.invitation
    }

    func acceptInvitation(code: String) async throws -> RemoteConnectionState {
        struct Parameters: Encodable { let p_code: String }
        return try await client
            .rpc("wty_accept_invite", params: Parameters(p_code: code))
            .execute()
            .value
    }

    func cancelInvitation(id: UUID) async throws -> RemoteConnectionState {
        struct Parameters: Encodable { let p_invite_id: UUID }
        return try await client
            .rpc("wty_cancel_invite", params: Parameters(p_invite_id: id))
            .execute()
            .value
    }

    func sendHeartBurst(count: Int) async throws -> RemoteHeartBurst {
        struct Parameters: Encodable { let p_count: Int }
        return try await client
            .rpc("wty_send_heart_burst", params: Parameters(p_count: count))
            .execute()
            .value
    }

    func listHeartBursts(limit: Int = 40) async throws -> [RemoteHeartBurst] {
        struct Parameters: Encodable { let p_limit: Int }
        return try await client
            .rpc("wty_list_heart_bursts", params: Parameters(p_limit: limit))
            .execute()
            .value
    }

    func sendSignal(_ signal: CoupleSignal) async throws -> RemoteSignalEvent {
        struct Parameters: Encodable { let p_signal_type: String }
        return try await client
            .rpc("wty_send_signal", params: Parameters(p_signal_type: signal.rawValue))
            .execute()
            .value
    }

    func listSignals(limit: Int = 80) async throws -> [RemoteSignalEvent] {
        struct Parameters: Encodable { let p_limit: Int }
        return try await client
            .rpc("wty_list_signals", params: Parameters(p_limit: limit))
            .execute()
            .value
    }

    func uploadProfileAvatar(data: Data, userID: UUID) async throws -> UserProfile {
        guard !data.isEmpty, data.count <= 1_048_576 else {
            throw SupabaseConnectionError.invalidAvatarData
        }

        let path = Self.avatarPath(for: userID)
        try await client.storage
            .from(Self.profilePhotoBucket)
            .upload(
                path,
                data: data,
                options: FileOptions(
                    cacheControl: "0",
                    contentType: "image/jpeg",
                    upsert: true
                )
            )

        let remote: RemoteProfile = try await client
            .rpc("wty_set_profile_avatar")
            .execute()
            .value
        guard let profile = remote.profile else { throw SupabaseConnectionError.incompleteProfile }
        return profile
    }

    func downloadProfileAvatar(path: String, updatedAt: Date?) async throws -> Data {
        let cacheNonce = updatedAt.map {
            String(Int(($0.timeIntervalSince1970 * 1_000).rounded()))
        }
        return try await client.storage
            .from(Self.profilePhotoBucket)
            .download(path: path, cacheNonce: cacheNonce)
    }

    func clearProfileAvatar(userID: UUID) async throws -> UserProfile {
        let remote: RemoteProfile = try await client
            .rpc("wty_clear_profile_avatar")
            .execute()
            .value
        guard let profile = remote.profile else { throw SupabaseConnectionError.incompleteProfile }

        // RPC가 먼저 접근을 끊는다. 실제 객체 정리가 실패해도 상대는 더 이상 읽을 수 없다.
        _ = try? await client.storage
            .from(Self.profilePhotoBucket)
            .remove(paths: [Self.avatarPath(for: userID)])
        return profile
    }

    private static func avatarPath(for userID: UUID) -> String {
        "\(userID.uuidString.lowercased())/avatar.jpg"
    }
}

enum SupabaseConnectionError: Error {
    case incompleteProfile
    case invalidAvatarData
}
