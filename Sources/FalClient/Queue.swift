import Foundation

/// This establishes the contract of the client with the queue API.
public protocol Queue {
    var client: Client { get }

    /// Submits a request to the given [id], an optional [path]. This method
    /// uses the [queue] API to initiate the request. Next you need to rely on
    /// [status] and [result] to poll for the result.
    func submit(_ id: String, path: String?, input: Payload?, webhookUrl: String?) async throws -> String

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
    func submit(_ id: String, path: String? = nil, input: Payload? = nil, webhookUrl: String? = nil) async throws -> String {
        try await submit(id, path: path, input: input, webhookUrl: webhookUrl)
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

    func runOnQueue(_ app: String, input: Payload?, options: RunOptions) async throws -> Payload {
        var requestInput = input
        if let storage = client.storage as? StorageClient,
           let input,
           options.httpMethod != .get,
           input.hasBinaryData
        {
            requestInput = try await storage.autoUpload(input: input)
        }
        let queryParams = options.httpMethod == .get ? input : nil
        let url = buildUrl(fromId: app, path: options.path, subdomain: "queue")
        let data = try await client.sendRequest(to: url, input: requestInput?.json(), queryParams: queryParams?.asDictionary, options: options)
        return try .create(fromJSON: data)
    }

    public func submit(_ id: String, path: String?, input: Payload?, webhookUrl _: String?) async throws -> String {
        let result = try await runOnQueue(id, input: input, options: .route(path ?? "", withMethod: .post))
        guard case let .string(requestId) = result["request_id"] else {
            throw FalError.invalidResultFormat
        }
        return requestId
    }

    public func status(_ id: String, of requestId: String, includeLogs: Bool) async throws -> QueueStatus {
        let appId = try AppId.parse(id: id)
        let result = try await runOnQueue(
            "\(appId.ownerId)/\(appId.appAlias)",
            input: ["logs": .bool(includeLogs)],
            options: .route("/requests/\(requestId)/status", withMethod: .get)
        )
        let json = try result.json()
        return try JSONDecoder().decode(QueueStatus.self, from: json)
    }

    public func response(_ id: String, of requestId: String) async throws -> Payload {
        let appId = try AppId.parse(id: id)
        return try await runOnQueue(
            "\(appId.ownerId)/\(appId.appAlias)",
            input: nil as Payload?,
            options: .route("/requests/\(requestId)", withMethod: .get)
        )
    }
}
