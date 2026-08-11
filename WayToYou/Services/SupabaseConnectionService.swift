import Foundation
import Supabase

struct RemoteProfile: Decodable {
    let id: UUID
    let displayName: String
    let endpoint: RouteEndpoint?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case endpoint = "route_endpoint"
    }

    var profile: UserProfile? {
        guard let endpoint else { return nil }
        return UserProfile(id: id, displayName: displayName, endpoint: endpoint)
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

struct SupabaseConnectionService {
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
}

enum SupabaseConnectionError: Error {
    case incompleteProfile
}
