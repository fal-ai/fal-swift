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

    func run(_ id: String, input: [String: Any]?, options: RunOptions) async throws -> [String: Any]

    func subscribe(
        to app: String,
        input: [String: Any]?,
        pollInterval: DispatchTimeInterval,
        timeout: DispatchTimeInterval,
        includeLogs: Bool,
        onQueueUpdate: OnQueueUpdate?
    ) async throws -> [String: Any]
}

public extension Client {
    func run(_ app: String, input: [String: Any]? = nil, options: RunOptions = DefaultRunOptions) async throws -> [String: Any] {
        return try await run(app, input: input, options: options)
    }

    func subscribe(
        to app: String,
        input: [String: Any]? = nil,
        pollInterval: DispatchTimeInterval = .seconds(1),
        timeout: DispatchTimeInterval = .minutes(3),
        includeLogs: Bool = false,
        onQueueUpdate: OnQueueUpdate? = nil
    ) async throws -> [String: Any] {
        return try await subscribe(to: app,
                                   input: input,
                                   pollInterval: pollInterval,
                                   timeout: timeout,
                                   includeLogs: includeLogs,
                                   onQueueUpdate: onQueueUpdate)
    }
}
