import Foundation

public protocol Queue {
    var client: Client { get }

    func submit(_ id: String, input: [String: Any]?, webhookUrl: String?) async throws -> String

    func status(_ id: String, of requestId: String, includeLogs: Bool) async throws -> QueueStatus

    func response(_ id: String, of requestId: String) async throws -> [String: Any]

    func response<T: Decodable>(_ id: String, of requestId: String) async throws -> T
}

public extension Queue {
    func submit(_ id: String, input: [String: Any]? = nil, webhookUrl: String? = nil) async throws -> String {
        try await submit(id, input: input, webhookUrl: webhookUrl)
    }

    func status(_ id: String, of requestId: String, includeLogs: Bool = false) async throws -> QueueStatus {
        try await status(id, of: requestId, includeLogs: includeLogs)
    }
}

public struct QueueStatusInput: Encodable {
    let logs: Bool

    enum CodingKeys: String, CodingKey {
        case logs
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(logs ? 1 : 0, forKey: .logs)
    }
}

public struct QueueClient: Queue {
    public let client: Client

    public func submit(_ id: String, input: [String: Any]?, webhookUrl _: String?) async throws -> String {
        let result = try await client.run(id, input: input, options: .route("/fal/queue/submit"))
        guard let requestId = result["request_id"] as? String else {
            preconditionFailure("The response is invalid, `request_id` not found")
        }
        return requestId
    }

    public func status(_ id: String, of requestId: String, includeLogs: Bool) async throws -> QueueStatus {
        try await client.run(
            id,
            input: QueueStatusInput(logs: includeLogs),
            options: .route("/fal/queue/requests/\(requestId)/status", withMethod: .get)
        )
    }

    public func response(_ id: String, of requestId: String) async throws -> [String: Any] {
        try await client.run(
            id,
            input: nil as ([String: Any])?,
            options: .route("/fal/queue/requests/\(requestId)/response", withMethod: .get)
        )
    }
}
