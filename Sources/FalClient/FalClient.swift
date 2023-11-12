import Foundation

func buildUrl(fromId id: String, path: String? = nil) -> String {
    "https://\(id).gateway.alpha.fal.ai" + (path ?? "")
}

public struct FalClient: Client {
    public let config: ClientConfig

    public var queue: Queue { QueueClient(client: self) }

    public func run(_ id: String, input: [String: Any]?, options: RunOptions) async throws -> [String: Any] {
        let inputData = input != nil ? try JSONSerialization.data(withJSONObject: input as Any) : nil
        let queryParams = options.httpMethod == .get ? input : nil
        let data = try await sendRequest(id, input: inputData, queryParams: queryParams, options: options)
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FalError.invalidResultFormat
        }
        return result
    }

    public func subscribe(
        _ id: String,
        input: [String: Any]?,
        pollInterval: FalTimeInterval,
        timeout: FalTimeInterval,
        includeLogs: Bool,
        options _: RunOptions,
        onQueueUpdate: OnQueueUpdate?
    ) async throws -> [String: Any] {
        let requestId = try await queue.submit(id, input: input)
        let start = Int(Date().timeIntervalSince1970 * 1000)
        var elapsed = 0
        var isCompleted = false
        while elapsed < timeout.milliseconds {
            let update = try await queue.status(id, of: requestId, includeLogs: includeLogs)
            if let onQueueUpdateCallback = onQueueUpdate {
                onQueueUpdateCallback(update)
            }
            isCompleted = update.isCompleted
            if isCompleted {
                break
            }
            try await Task.sleep(nanoseconds: UInt64(Int(pollInterval.milliseconds * 1_000_000)))
            elapsed += Int(Date().timeIntervalSince1970 * 1000) - start
        }
        if !isCompleted {
            throw FalError.queueTimeout
        }
        return try await queue.response(id, of: requestId)
    }

    public static let shared: Client = Self(config: ClientConfig())

    public static func withProxy(_ url: String) -> Client {
        return Self(config: ClientConfig(requestProxy: url))
    }
}
