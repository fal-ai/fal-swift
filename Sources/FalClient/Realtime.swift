
import Dispatch
import Foundation
import SwiftMsgpack

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
    case connectionError(code: Int? = nil)
    case unauthorized
    case invalidInput
    case invalidResult(requestId: String? = nil, causedBy: Error? = nil)
    case serviceError(type: String, reason: String)
}

extension FalRealtimeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .connectionError(code):
            return NSLocalizedString("Connection error (code: \(String(describing: code)))", comment: "FalRealtimeError.connectionError")
        case .unauthorized:
            return NSLocalizedString("Unauthorized", comment: "FalRealtimeError.unauthorized")
        case .invalidInput:
            return NSLocalizedString("Invalid input format", comment: "FalRealtimeError.invalidInput")
        case .invalidResult:
            return NSLocalizedString("Invalid result", comment: "FalRealtimeError.invalidResult")
        case let .serviceError(type, reason):
            return NSLocalizedString("\(type): \(reason)", comment: "FalRealtimeError.serviceError")
        }
    }
}

typealias SendFunction = (URLSessionWebSocketTask.Message) throws -> Void
typealias CloseFunction = () -> Void

func hasBinaryField(_ type: Encodable) -> Bool {
    if let object = type as? Payload,
       case let .dict(dict) = object
    {
        return dict.values.contains {
            if case .data = $0 {
                return true
            }
            return false
        }
    }
    let mirror = Mirror(reflecting: type)
    for child in mirror.children {
        if child.value is Data {
            return true
        }
        if case FalImageContent.raw = child.value {
            return true
        }
    }
    return false
}

/// The real-time connection. This is used to send messages to the app, which will send
/// responses back to the `connect` result completion callback.
public class BaseRealtimeConnection<Input: Encodable> {
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
    public func send(_ input: Input) throws {
        if hasBinaryField(input) {
            try sendBinary(input)
        } else {
            try sendJSON(input)
        }
    }

    func sendJSON(_ data: Input) throws {
        let jsonData = try JSONEncoder().encode(data)
        guard let json = String(data: jsonData, encoding: .utf8) else {
            throw FalRealtimeError.invalidInput
        }
        try sendReference(.string(json))
    }

    func sendBinary(_ data: Input) throws {
        let payload = try MsgPackEncoder().encode(data)
        try sendReference(.data(payload))
    }
}

/// Connection implementation that can be used to send messages using the `Payload` type.
public class RealtimeConnection: BaseRealtimeConnection<Payload> {}

/// Connection implementation that can be used to send messages using a custom `Encodable` type.
public class TypedRealtimeConnection<Input: Encodable>: BaseRealtimeConnection<Input> {}

/// This is a list of apps deployed before formal realtime support. Their URLs follow
/// a different pattern and will be kept here until we fully sunset them.
let LegacyApps = [
    "lcm-sd15-i2i",
    "lcm",
    "sdxl-turbo-realtime",
    "sd-turbo-real-time-high-fps-msgpack-a10g",
    "lcm-plexed-sd15-i2i",
    "sd-turbo-real-time-high-fps-msgpack",
]

typealias RefreshTokenFunction = (String, (Result<String, Error>) -> Void) -> Void

private let TokenExpirationInterval: DispatchTimeInterval = .minutes(1)

typealias WebSocketMessage = URLSessionWebSocketTask.Message

class WebSocketConnection: NSObject, URLSessionWebSocketDelegate {
    let app: String
    let client: Client
    let onMessage: (WebSocketMessage) -> Void
    let onError: (Error) -> Void

    private let queue = DispatchQueue(label: "ai.fal.WebSocketConnection.\(UUID().uuidString)")
    private let session = URLSession(configuration: .default)
    private var enqueuedMessage: WebSocketMessage? = nil
    private var task: URLSessionWebSocketTask?
    private var token: String?

    private var isConnecting = false
    private var isRefreshingToken = false

    init(
        app: String,
        client: Client,
        onMessage: @escaping (WebSocketMessage) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.app = app
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

            let url = buildRealtimeUrl(token: token)
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
            do {
                let token = try await self.client.fetchTemporaryAuthToken(for: app)
                completion(.success(token.replacingOccurrences(of: "\"", with: "")))
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

                    let object = try message.decode(to: Payload.self)
                    if isSuccessResult(object) {
                        self?.onMessage(message)
                        return
                    }
                    if let error = getError(object) {
                        self?.onError(error)
                        return
                    }
                } catch {
                    self?.onError(error)
                }
            case let .failure(error):
                self?.task = nil
                if let posixError = error as? POSIXError, posixError.code == .ENOTCONN {
                    // Ignore this error as it's thrown by Foundation's WebSocket implementation
                    // when messages were requested but the connection was closed already.
                    // This is safe to ignore, as the client is not expecting any other messages
                    // and will reconnect when new messages are sent.
                    return
                }
                self?.onError(error)
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
        task = nil
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
        didCloseWith code: URLSessionWebSocketTask.CloseCode,
        reason _: Data?
    ) {
        if code != .normalClosure {
            onError(FalRealtimeError.connectionError(code: code.rawValue))
        }
        task = nil
    }

    private func buildRealtimeUrl(token: String? = nil) -> URL {
        // Some basic support for old ids, this should be removed during 1.0.0 release
        // For full-support of old ids, users can point to version 0.4.x
        let appAlias = (try? appAlias(fromId: app)) ?? app
        let path = LegacyApps.contains(appAlias) || !app.contains("/") ? "/ws" : "/realtime"
        var queryParams: [String: String] = [:]
        if let token {
            queryParams["fal_jwt_token"] = token
        }
        return client.buildEndpointUrl(fromId: app, path: path, scheme: "wss", queryParams: queryParams)
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
        onResult completion: @escaping (Result<Payload, Error>) -> Void
    ) throws -> RealtimeConnection
}

func isSuccessResult(_ message: Payload) -> Bool {
    message["status"].stringValue != "error"
        && message["type"].stringValue != "x-fal-message"
        && message["type"].stringValue != "x-fal-error"
}

func getError(_ message: Payload) -> FalRealtimeError? {
    if message["type"].stringValue == "x-fal-error",
       let error = message["error"].stringValue,
       let reason = message["reason"].stringValue,
       // The timeout error is expected as the websocket endpoint returns that
       // when no input has ben sent for a while. It's safe to ignore and should
       // not trigger the onError callback of the client
       error != "TIMEOUT"
    {
        return FalRealtimeError.serviceError(type: error, reason: reason)
    }
    return nil
}

extension WebSocketMessage {
    func data() throws -> Data {
        switch self {
        case let .data(data):
            return data
        case let .string(string):
            guard let data = string.data(using: .utf8) else {
                throw FalRealtimeError.invalidResult()
            }
            return data
        @unknown default:
            preconditionFailure("Unknown URLSessionWebSocketTask.Message case")
        }
    }

    func decode<Type: Decodable>(to type: Type.Type) throws -> Type {
        switch self {
        case let .data(data):
            return try MsgPackDecoder().decode(type, from: data)
        case .string:
            return try JSONDecoder().decode(type, from: data())
        @unknown default:
            return try JSONDecoder().decode(type, from: data())
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
        onResult completion: @escaping (Result<Payload, Error>) -> Void
    ) throws -> RealtimeConnection {
        handleConnection(
            to: app,
            connectionKey: connectionKey,
            throttleInterval: throttleInterval,
            connectionFactory: { send, close in
                RealtimeConnection(send, close)
            },
            onResult: completion
        ) as! RealtimeConnection
    }
}

extension Realtime {
    func handleConnection<InputType: Encodable, ResultType: Decodable>(
        to app: String,
        connectionKey: String = UUID().uuidString,
        throttleInterval: DispatchTimeInterval = .milliseconds(128),
        connectionFactory createRealtimeConnection: @escaping (@escaping SendFunction, @escaping CloseFunction) -> BaseRealtimeConnection<InputType>,
        onResult completion: @escaping (Result<ResultType, Error>) -> Void
    ) -> BaseRealtimeConnection<InputType> {
        let key = "\(app):\(connectionKey)"
        let ws = connectionPool[key] ?? WebSocketConnection(
            app: app,
            client: client,
            onMessage: { message in
                do {
                    let result = try message.decode(to: ResultType.self)
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

        let sendData = { (data: WebSocketMessage) in
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
        onResult completion: @escaping (Result<Payload, Error>) -> Void
    ) throws -> RealtimeConnection {
        try connect(
            to: app,
            connectionKey: connectionKey,
            throttleInterval: throttleInterval,
            onResult: completion
        )
    }
}
