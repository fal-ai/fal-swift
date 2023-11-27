import Dispatch
import Foundation

enum HttpMethod: String {
    case get
    case post
    case put
    case delete
}

protocol RequestOptions {
    var httpMethod: HttpMethod { get }
    var path: String { get }
}

public struct RunOptions: RequestOptions {
    let path: String
    let httpMethod: HttpMethod

    static func withMethod(_ method: HttpMethod) -> Self {
        RunOptions(path: "", httpMethod: method)
    }

    static func route(_ path: String, withMethod method: HttpMethod = .post) -> Self {
        RunOptions(path: path, httpMethod: method)
    }
}

public let DefaultRunOptions: RunOptions = .withMethod(.post)

public typealias OnQueueUpdate = (QueueStatus) -> Void

public protocol Client {
    var config: ClientConfig { get }

    var queue: Queue { get }

    func run(_ id: String, input: [String: Any]?, options: RunOptions) async throws -> [String: Any]

    func subscribe(
        _ id: String,
        input: [String: Any]?,
        pollInterval: DispatchTimeInterval,
        timeout: DispatchTimeInterval,
        includeLogs: Bool,
        options: RunOptions,
        onQueueUpdate: OnQueueUpdate?
    ) async throws -> [String: Any]
}

public extension Client {
    func run(_ id: String, input: [String: Any]? = nil, options: RunOptions = DefaultRunOptions) async throws -> [String: Any] {
        return try await run(id, input: input, options: options)
    }

    func subscribe(
        _ id: String,
        input: [String: Any]? = nil,
        pollInterval: DispatchTimeInterval = .seconds(1),
        timeout: DispatchTimeInterval = .minutes(3),
        includeLogs: Bool = false,
        options: RunOptions = DefaultRunOptions,
        onQueueUpdate: OnQueueUpdate? = nil
    ) async throws -> [String: Any] {
        return try await subscribe(id,
                                   input: input,
                                   pollInterval: pollInterval,
                                   timeout: timeout,
                                   includeLogs: includeLogs,
                                   options: options,
                                   onQueueUpdate: onQueueUpdate)
    }
}
