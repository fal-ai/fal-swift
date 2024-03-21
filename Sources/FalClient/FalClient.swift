import Dispatch
import Foundation

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

    public var realtime: Realtime { RealtimeClient(client: self) }

    public var storage: Storage { StorageClient(client: self) }

    public func run(_ app: String, input: Payload?, options: RunOptions) async throws -> Payload {
        var requestInput = input
        if let storage = storage as? StorageClient,
           let input,
           options.httpMethod != .get,
           input.hasBinaryData
        {
            requestInput = try await storage.autoUpload(input: input)
        }
        let queryParams = options.httpMethod == .get ? input : nil
        let url = buildUrl(fromId: app, path: options.path)
        let data = try await sendRequest(to: url, input: requestInput?.json(), queryParams: queryParams?.asDictionary, options: options)
        return try .create(fromJSON: data)
    }

    public func subscribe(
        to app: String,
        input: Payload?,
        pollInterval: DispatchTimeInterval,
        timeout: DispatchTimeInterval,
        includeLogs: Bool,
        onQueueUpdate: OnQueueUpdate?
    ) async throws -> Payload {
        let requestId = try await queue.submit(app, input: input)
        let start = Int64(Date().timeIntervalSince1970 * 1000)
        var elapsed: Int64 = 0
        var isCompleted = false
        while elapsed < timeout.milliseconds {
            let update = try await queue.status(app, of: requestId, includeLogs: includeLogs)
            if let onQueueUpdateCallback = onQueueUpdate {
                onQueueUpdateCallback(update)
            }
            isCompleted = update.isCompleted
            if isCompleted {
                break
            }
            try await Task.sleep(nanoseconds: UInt64(Int(pollInterval.milliseconds * 1_000_000)))
            elapsed = Int64(Date().timeIntervalSince1970 * 1000) - start
        }
        if !isCompleted {
            throw FalError.queueTimeout
        }
        return try await queue.response(app, of: requestId)
    }
}

public extension FalClient {
    static func withProxy(_ url: String, headers: [String: String]? = nil) -> Client {
        FalClient(config: ClientConfig(requestProxy: url, customHeaders: headers))
    }

    static func withCredentials(_ credentials: ClientCredentials) -> Client {
        FalClient(config: ClientConfig(credentials: credentials))
    }
}
