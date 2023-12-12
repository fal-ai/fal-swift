import Foundation

/// This establishes the contract of the client with the queue API.
public protocol Queue {
    var client: Client { get }

    /// Submits a request to the given [id], an optional [path]. This method
    /// uses the [queue] API to initiate the request. Next you need to rely on
    /// [status] and [result] to poll for the result.
    func submit(_ id: String, input: Payload?, webhookUrl: String?) async throws -> String

    /// Checks the queue for the status of the request with the given [requestId].
    /// See [QueueStatus] for the different statuses.
    func status(_ id: String, of requestId: String, includeLogs: Bool) async throws -> QueueStatus

    /// Retrieves the result of the request with the given [requestId] once
    /// the queue status is [QueueStatus.completed].
    func response(_ id: String, of requestId: String) async throws -> Payload

    /// Retrieves the result of the request with the given [requestId] once
    /// the queue status is [QueueStatus.completed]. This method is type-safe
    /// based on the [Decodable] protocol.
    func response<T: Decodable>(_ id: String, of requestId: String) async throws -> T
}

public extension Queue {
    func submit(_ id: String, input: Payload? = nil, webhookUrl: String? = nil) async throws -> String {
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

    public func submit(_ id: String, input: Payload?, webhookUrl _: String?) async throws -> String {
        let result = try await client.run(id, input: input, options: .route("/fal/queue/submit"))
        guard case let .string(requestId) = result["request_id"] else {
            throw FalError.invalidResultFormat
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

    public func response(_ id: String, of requestId: String) async throws -> Payload {
        try await client.run(
            id,
            input: nil as Payload?,
            options: .route("/fal/queue/requests/\(requestId)/response", withMethod: .get)
        )
    }
}
