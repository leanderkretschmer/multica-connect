import Foundation

/// A workspace the signed-in token can reach.
public struct Workspace: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let slug: String?

    public init(id: String, name: String, slug: String? = nil) {
        self.id = id
        self.name = name
        self.slug = slug
    }
}

/// The identity behind the current token, from `/api/me`.
public struct CurrentUser: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String?
    public let email: String?
    public let avatarURL: String?

    /// Best available label for the signed-in identity.
    public var displayName: String {
        if let name, !name.isEmpty { return name }
        if let email, !email.isEmpty { return email }
        return "Signed in"
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, email
        case avatarURL = "avatar_url"
    }

    public init(id: String, name: String? = nil, email: String? = nil, avatarURL: String? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.avatarURL = avatarURL
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // /api/me may nest the user under `user`; accept both shapes.
        if let id = try? c.decode(String.self, forKey: .id) {
            self.id = id
            self.name = try c.decodeIfPresent(String.self, forKey: .name)
            self.email = try c.decodeIfPresent(String.self, forKey: .email)
            self.avatarURL = try c.decodeIfPresent(String.self, forKey: .avatarURL)
        } else {
            let outer = try decoder.container(keyedBy: WrapperKeys.self)
            self = try outer.decode(CurrentUser.self, forKey: .user)
        }
    }

    private enum WrapperKeys: String, CodingKey { case user }
}

/// An agent in the workspace. The app cares about who it can hand work to.
public struct Agent: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let description: String?
    /// `emoji:🦄` or an uploads path, depending on how the agent was set up.
    public let avatarURL: String?
    public let status: String?
    public let model: String?
    public let archivedAt: Date?

    public var isArchived: Bool { archivedAt != nil }

    /// The emoji an `emoji:`-style avatar carries, when that is what it is.
    public var avatarEmoji: String? {
        guard let avatarURL, avatarURL.hasPrefix("emoji:") else { return nil }
        return String(avatarURL.dropFirst("emoji:".count))
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, status, model
        case avatarURL = "avatar_url"
        case archivedAt = "archived_at"
    }

    public init(
        id: String,
        name: String,
        description: String? = nil,
        avatarURL: String? = nil,
        status: String? = nil,
        model: String? = nil,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.avatarURL = avatarURL
        self.status = status
        self.model = model
        self.archivedAt = archivedAt
    }
}
