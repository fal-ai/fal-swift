import Dispatch
import Foundation

func buildUrl(fromId id: String, path: String? = nil) -> String {
    "https://\(id).gateway.alpha.fal.ai" + (path ?? "")
}

/// The main client class that provides access to simple API model usage,
/// as well as access to the `queue` and `storage` APIs.
///
/// Example:
///
/// ```swift
/// import FalClient
///
/// let fal = FalClient.withCredentials("fal_key_id:fal_key_secret");
///
/// void main() async {
///   // check https://fal.ai/models for the available models
///   final result = await fal.subscribe(to: 'text-to-image', input: {
///     'prompt': 'a cute shih-tzu puppy',
///     'model_name': 'stabilityai/stable-diffusion-xl-base-1.0',
///   });
///   print(result);
/// }
/// ```
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
        pollInterval: DispatchTimeInterval,
        timeout: DispatchTimeInterval,
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
}

public extension FalClient {
    static func withProxy(_ url: String) -> FalClient {
        return FalClient(config: ClientConfig(requestProxy: url))
    }
}
