import Dispatch
import Foundation

public enum HttpMethod: String {
    case get
    case post
    case put
    case delete
}

public protocol RequestOptions {
    var httpMethod: HttpMethod { get }
    var path: String { get }
}

public struct RunOptions: RequestOptions {
    public let path: String
    public let httpMethod: HttpMethod

    static func withMethod(_ method: HttpMethod) -> RunOptions {
        RunOptions(path: "", httpMethod: method)
    }

    static func route(_ path: String, withMethod method: HttpMethod = .post) -> RunOptions {
        RunOptions(path: path, httpMethod: method)
    }
}

public let DefaultRunOptions: RunOptions = .withMethod(.post)

public typealias OnQueueUpdate = (QueueStatus) -> Void

public protocol Client {
    var config: ClientConfig { get }

    var queue: Queue { get }

    var realtime: Realtime { get }

    func run(_ id: String, input: Payload?, options: RunOptions) async throws -> Payload

    func subscribe(
        to app: String,
        input: Payload?,
        pollInterval: DispatchTimeInterval,
        timeout: DispatchTimeInterval,
        includeLogs: Bool,
        onQueueUpdate: OnQueueUpdate?
    ) async throws -> Payload
}

public extension Client {
    /// Sends a request to the given [id], an optional [path]. This method
    /// is a direct request to the model API and it waits for the processing
    /// to complete before returning the result.
    ///
    /// This is useful for short running requests, but it's not recommended for
    /// long running requests, for those see [submit].
    ///
    /// - Parameters:
    ///   - app: The id of the model app.
    ///   - input: The input to the model.
    ///   - options: The request options.
    func run(_ app: String, input: Payload? = nil, options: RunOptions = DefaultRunOptions) async throws -> Payload {
        try await run(app, input: input, options: options)
    }

    /// Submits a request to the given [app], an optional [path]. This method
    /// uses the [queue] API to submit the request and poll for the result.
    ///
    /// This is useful for long running requests, and it's the preffered way
    /// to interact with the model APIs.
    ///
    /// - Parameters:
    ///   - app: The id of the model app.
    ///   - input: The input to the model.
    ///   - pollInterval: The interval to poll for the result. Defaults to 1 second.
    ///   - timeout: The timeout to wait for the result. Defaults to 3 minutes.
    ///   - includeLogs: Whether to include logs in the result. Defaults to false.
    ///   - onQueueUpdate: A callback to be called when the queue status is updated.
    func subscribe(
        to app: String,
        input: Payload? = nil,
        pollInterval: DispatchTimeInterval = .seconds(1),
        timeout: DispatchTimeInterval = .minutes(3),
        includeLogs: Bool = false,
        onQueueUpdate: OnQueueUpdate? = nil
    ) async throws -> Payload {
        try await subscribe(to: app,
                            input: input,
                            pollInterval: pollInterval,
                            timeout: timeout,
                            includeLogs: includeLogs,
                            onQueueUpdate: onQueueUpdate)
    }
}
