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

    public var realtime: Realtime { RealtimeClient(client: self) }

    public func run(_ app: String, input: ObjectValue?, options: RunOptions) async throws -> ObjectValue {
        let inputData = input != nil ? try JSONEncoder().encode(input) : nil
        let queryParams = options.httpMethod == .get ? input : nil
        let url = buildUrl(fromId: app, path: options.path)
        let data = try await sendRequest(url, input: inputData, queryParams: queryParams?.asDictionary, options: options)
//        guard let result = try? JSON(data: data) else {
//            throw FalError.invalidResultFormat
//        }
//        return result
        let decoder = JSONDecoder()
        return try decoder.decode(ObjectValue.self, from: data)
    }

    public func subscribe(
        to app: String,
        input: ObjectValue?,
        pollInterval: DispatchTimeInterval,
        timeout: DispatchTimeInterval,
        includeLogs: Bool,
        onQueueUpdate: OnQueueUpdate?
    ) async throws -> ObjectValue {
        let requestId = try await queue.submit(app, input: input)
        let start = Int(Date().timeIntervalSince1970 * 1000)
        var elapsed = 0
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
            elapsed += Int(Date().timeIntervalSince1970 * 1000) - start
        }
        if !isCompleted {
            throw FalError.queueTimeout
        }
        return try await queue.response(app, of: requestId)
    }
}

public extension FalClient {
    static func withProxy(_ url: String) -> Client {
        FalClient(config: ClientConfig(requestProxy: url))
    }

    static func withCredentials(_ credentials: ClientCredentials) -> Client {
        FalClient(config: ClientConfig(credentials: credentials))
    }
}
