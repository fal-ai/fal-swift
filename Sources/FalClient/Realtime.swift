
import Dispatch
import Foundation

func throttle<T>(_ function: @escaping (T) -> Void, throttleInterval: DispatchTimeInterval) -> ((T) -> Void) {
    var lastExecution = DispatchTime.now()

    let throttledFunction: ((T) -> Void) = { input in
        if DispatchTime.now() > lastExecution + throttleInterval {
            lastExecution = DispatchTime.now()
            function(input)
        }
    }

    return throttledFunction
}

public enum FalRealtimeError: Error {
    case connectionError
    case unauthorized
    case invalidResult
    case serviceError(type: String, reason: String)
}

extension FalRealtimeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .connectionError:
            return NSLocalizedString("Connection error", comment: "FalRealtimeError.connectionError")
        case .unauthorized:
            return NSLocalizedString("Unauthorized", comment: "FalRealtimeError.unauthorized")
        case .invalidResult:
            return NSLocalizedString("Invalid result", comment: "FalRealtimeError.invalidResult")
        case let .serviceError(type, reason):
            return NSLocalizedString("\(type): \(reason)", comment: "FalRealtimeError.serviceError")
        }
    }
}

typealias SendFunction = (URLSessionWebSocketTask.Message) throws -> Void
typealias CloseFunction = () -> Void

/// The real-time connection. This is used to send messages to the app, which will send
/// responses back to the `connect` result completion callback.
public class RealtimeConnection<Input> {
    var sendReference: SendFunction
    var closeReference: CloseFunction

    init(_ send: @escaping SendFunction, _ close: @escaping CloseFunction) {
        sendReference = send
        closeReference = close
    }

    /// Closes the connection. You can use this to manuallt close the connection.
    /// In most cases you don't need to call this method, as connections are closed
    /// automatically by the server when they are idle. The idle period is determined
    /// by the app and it may vary.
    public func close() {
        closeReference()
    }

    /// Sends a message to the app.
    public func send(_: Input) throws {
        preconditionFailure("This method must be overridden to handle \(Input.self)")
    }
}

class UntypedRealtimeConnection: RealtimeConnection<[String: Any]> {
    override public func send(_ data: [String: Any]) throws {
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        guard let json = String(data: jsonData, encoding: .utf8) else {
            throw FalRealtimeError.invalidResult
        }
        try sendReference(.string(json))
    }
}

class BinaryRealtimeConnection: RealtimeConnection<Data> {
    override public func send(_ data: Data) throws {
        try sendReference(.data(data))
    }
}

func buildRealtimeUrl(forApp app: String, host: String, params: [String: Any] = [:], token: String? = nil) -> URL {
    var components = URLComponents()
    components.scheme = "wss"
    components.host = "\(app).\(host)"
    components.path = "/ws"

    if let token {
        components.queryItems = [URLQueryItem(name: "fal_jwt_token", value: token)]
    }

    components.queryItems?.append(contentsOf: params.map { URLQueryItem(name: $0.key, value: "\($0.value)") })

    // swiftlint:disable:next force_unwrapping
    return components.url!
}

typealias RefreshTokenFunction = (String, (Result<String, Error>) -> Void) -> Void

private let TokenExpirationInterval: DispatchTimeInterval = .minutes(1)

class WebSocketConnection: NSObject, URLSessionWebSocketDelegate {
    let app: String
    let connectionParams: [String: Any]
    let client: Client
    let onMessage: (Data) -> Void
    let onError: (Error) -> Void

    private let queue = DispatchQueue(label: "ai.fal.WebSocketConnection.\(UUID().uuidString)")
    private let session = URLSession(configuration: .default)
    private var enqueuedMessage: URLSessionWebSocketTask.Message? = nil
    private var task: URLSessionWebSocketTask?
    private var token: String?

    private var isConnecting = false
    private var isRefreshingToken = false

    init(
        app: String,
        connectionParams: [String: Any],
        client: Client,
        onMessage: @escaping (Data) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.app = app
        self.connectionParams = connectionParams
        self.client = client
        self.onMessage = onMessage
        self.onError = onError
    }

    func connect() {
        if task == nil, !isConnecting, !isRefreshingToken {
            isConnecting = true
            if token == nil, !isRefreshingToken {
                isRefreshingToken = true
                refreshToken(app) { result in
                    switch result {
                    case let .success(token):
                        self.token = token
                        self.isRefreshingToken = false
                        self.isConnecting = false

                        // Very simple token expiration handling for now
                        // Create the deadline 90% of the way through the token's lifetime
                        let tokenExpirationDeadline: DispatchTime = .now() + TokenExpirationInterval - .seconds(20)
                        DispatchQueue.main.asyncAfter(deadline: tokenExpirationDeadline) {
                            self.token = nil
                        }

                        self.connect()
                    case let .failure(error):
                        self.isConnecting = false
                        self.isRefreshingToken = false
                        self.onError(error)
                    }
                }
                return
            }

            // TODO: get host from config
            let url = buildRealtimeUrl(
                forApp: app,
                host: "gateway.alpha.fal.ai",
                params: connectionParams,
                token: token
            )
            let webSocketTask = session.webSocketTask(with: url)
            webSocketTask.delegate = self
            task = webSocketTask
            // connect and keep the task reference
            task?.resume()
            isConnecting = false
            receiveMessage()
        }
    }

    func refreshToken(_ app: String, completion: @escaping (Result<String, Error>) -> Void) {
        Task {
            // TODO: improve app alias resolution
            let appAlias = app.split(separator: "-").dropFirst().joined(separator: "-")
            let url = "https://rest.alpha.fal.ai/tokens/"
            let body = try? JSONSerialization.data(withJSONObject: [
                "allowed_apps": [appAlias],
                "token_expiration": 300,
            ])
            do {
                let response = try await self.client.sendRequest(
                    url,
                    input: body,
                    options: .withMethod(.post)
                )
                if let token = String(data: response, encoding: .utf8) {
                    completion(.success(token.replacingOccurrences(of: "\"", with: "")))
                } else {
                    completion(.failure(FalRealtimeError.unauthorized))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    func receiveMessage() {
        task?.receive { [weak self] incomingMessage in
            switch incomingMessage {
            case let .success(message):
                do {
                    self?.receiveMessage()

                    if case let .data(data) = message {
                        self?.onMessage(data)
                        return
                    }

                    let data = try message.data()
                    guard let parsedMessage = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        self?.onError(FalRealtimeError.invalidResult)
                        return
                    }
                    if isSuccessResult(parsedMessage) {
                        self?.onMessage(data)
                        return
                    }
                    if let error = getError(parsedMessage) {
                        self?.onError(error)
                        return
                    }
                } catch {
                    self?.onError(error)
                }
            case let .failure(error):
                self?.onError(error)
                self?.task = nil
            }
        }
    }

    func send(_ message: URLSessionWebSocketTask.Message) throws {
        if let task {
            task.send(message) { [weak self] error in
                if let error {
                    self?.onError(error)
                }
            }
        } else {
            enqueuedMessage = message
            queue.sync {
                if !isConnecting {
                    connect()
                }
            }
        }
    }

    func close() {
        task?.cancel(with: .normalClosure, reason: "Programmatically closed".data(using: .utf8))
    }

    func urlSession(
        _: URLSession,
        webSocketTask _: URLSessionWebSocketTask,
        didOpenWithProtocol _: String?
    ) {
        if let lastMessage = enqueuedMessage {
            do {
                try send(lastMessage)
            } catch {
                onError(error)
            }
        }
        enqueuedMessage = nil
    }

    func urlSession(
        _: URLSession,
        webSocketTask _: URLSessionWebSocketTask,
        didCloseWith _: URLSessionWebSocketTask.CloseCode,
        reason _: Data?
    ) {
        task = nil
    }
}

var connectionPool: [String: WebSocketConnection] = [:]

/// The real-time client contract.
public protocol Realtime {
    var client: Client { get }

    func connect(
        to app: String,
        connectionKey: String,
        throttleInterval: DispatchTimeInterval,
        onResult completion: @escaping (Result<[String: Any], Error>) -> Void
    ) throws -> RealtimeConnection<[String: Any]>
}

func isSuccessResult(_ message: [String: Any]) -> Bool {
    message["status"] as? String != "error"
        && message["type"] as? String != "x-fal-message"
        && message["type"] as? String != "x-fal-error"
}

func getError(_ message: [String: Any]) -> FalRealtimeError? {
    if message["type"] as? String != "x-fal-error",
       let error = message["error"] as? String,
       let reason = message["reason"] as? String
    {
        return FalRealtimeError.serviceError(type: error, reason: reason)
    }
    return nil
}

extension URLSessionWebSocketTask.Message {
    func data() throws -> Data {
        switch self {
        case let .data(data):
            return data
        case let .string(string):
            guard let data = string.data(using: .utf8) else {
                throw FalRealtimeError.invalidResult
            }
            return data
        @unknown default:
            preconditionFailure("Unknown URLSessionWebSocketTask.Message case")
        }
    }
}

/// The real-time client implementation.
public struct RealtimeClient: Realtime {
    // TODO: in the future make this non-public
    // External APIs should not use it
    public let client: Client

    init(client: Client) {
        self.client = client
    }

    public func connect(
        to app: String,
        connectionKey: String,
        throttleInterval: DispatchTimeInterval,
        onResult completion: @escaping (Result<[String: Any], Error>) -> Void
    ) throws -> RealtimeConnection<[String: Any]> {
        handleConnection(
            to: app,
            connectionParams: [:],
            connectionKey: connectionKey,
            throttleInterval: throttleInterval,
            resultConverter: { data in
                guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw FalRealtimeError.invalidResult
                }
                return result
            },
            connectionFactory: { send, close in
                UntypedRealtimeConnection(send, close)
            },
            onResult: completion
        )
    }
}

extension Realtime {
    func handleConnection<InputType, ResultType>(
        to app: String,
        connectionParams: [String: Any] = [:],
        connectionKey: String = UUID().uuidString,
        throttleInterval: DispatchTimeInterval = .milliseconds(128),
        resultConverter convertToResultType: @escaping (Data) throws -> ResultType,
        connectionFactory createRealtimeConnection: @escaping (@escaping SendFunction, @escaping CloseFunction) -> RealtimeConnection<InputType>,
        onResult completion: @escaping (Result<ResultType, Error>) -> Void
    ) -> RealtimeConnection<InputType> {
        let key = "\(app):\(connectionKey)"
        let ws = connectionPool[key] ?? WebSocketConnection(
            app: app,
            connectionParams: connectionParams,
            client: client,
            onMessage: { data in
                do {
                    let result = try convertToResultType(data)
                    completion(.success(result))
                } catch {
                    completion(.failure(error))
                }
            },
            onError: { error in
                completion(.failure(error))
            }
        )
        if connectionPool[key] == nil {
            connectionPool[key] = ws
        }

        let sendData = { (data: URLSessionWebSocketTask.Message) in
            do {
                try ws.send(data)
            } catch {
                completion(.failure(error))
            }
        }
        let send: SendFunction = throttleInterval.milliseconds > 0 ? throttle(sendData, throttleInterval: throttleInterval) : sendData
        let close: CloseFunction = {
            ws.close()
        }
        return createRealtimeConnection(send, close)
    }
}

public extension Realtime {
    /// Connects to the given `app` and returns a `RealtimeConnection` that can be used to send messages to the app.
    /// The `connectionKey` is used to identify the connection and it's used to reuse the same connection
    /// and it's useful in scenarios where the `connect` function is called multiple times.
    /// The `throttleInterval` is used to throttle the messages sent to the app, it defaults to 64 milliseconds.
    ///
    /// - Parameters:
    ///   - app: The id of the model app.
    ///   - connectionKey: The connection key.
    ///   - throttleInterval: The throttle interval.
    ///   - completion: The completion callback.
    ///
    /// - Returns: A `RealtimeConnection` that can be used to send messages to the app.
    func connect(
        to app: String,
        connectionKey: String = UUID().uuidString,
        throttleInterval: DispatchTimeInterval = .milliseconds(64),
        onResult completion: @escaping (Result<[String: Any], Error>) -> Void
    ) throws -> RealtimeConnection<[String: Any]> {
        try connect(
            to: app,
            connectionKey: connectionKey,
            throttleInterval: throttleInterval,
            onResult: completion
        )
    }

    func connect(
        to app: String,
        input: [String: Any] = [:],
        connectionKey: String = UUID().uuidString,
        throttleInterval: DispatchTimeInterval = .milliseconds(64),
        onResult completion: @escaping (Result<Data, Error>) -> Void
    ) throws -> RealtimeConnection<Data> {
        handleConnection(
            to: app,
            connectionParams: input,
            connectionKey: connectionKey,
            throttleInterval: throttleInterval,
            resultConverter: { $0 },
            connectionFactory: { send, close in
                BinaryRealtimeConnection(send, close)
            },
            onResult: completion
        )
    }
}
