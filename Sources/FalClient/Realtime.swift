
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
}

public class RealtimeConnection<Input> {
    var sendReference: SendFunction
    var closeReference: CloseFunction

    init(_ send: @escaping SendFunction, _ close: @escaping CloseFunction) {
        sendReference = send
        closeReference = close
    }

    public func close() {
        closeReference()
    }

    public func send(_: Input) throws {
        preconditionFailure("This method must be overridden to handle \(Input.self)")
    }
}

typealias SendFunction = (Data) throws -> Void
typealias CloseFunction = () -> Void

class UntypedRealtimeConnection: RealtimeConnection<[String: Any]> {
    override public func send(_ data: [String: Any]) throws {
        let json = try JSONSerialization.data(withJSONObject: data)
        try sendReference(json)
    }
}

func buildRealtimeUrl(forApp app: String, host: String, token: String? = nil) -> URL {
    var components = URLComponents()
    components.scheme = "wss"
    components.host = "\(app).\(host)"
    components.path = "/ws"

    if let token = token {
        components.queryItems = [URLQueryItem(name: "fal_jwt_token", value: token)]
    }
    // swiftlint:disable:next force_unwrapping
    return components.url!
}

typealias RefreshTokenFunction = (String, (Result<String, Error>) -> Void) -> Void

private let TokenExpirationInterval: DispatchTimeInterval = .minutes(1)

class WebSocketConnection: NSObject, URLSessionWebSocketDelegate {
    let app: String
    let client: Client
    let onMessage: (Data) -> Void
    let onError: (Error) -> Void

    private let queue = DispatchQueue(label: "ai.fal.WebSocketConnection.\(UUID().uuidString)")
    private let session = URLSession(configuration: .default)
    private var enqueuedMessages: [Data] = []
    private var task: URLSessionWebSocketTask?
    private var token: String?

    private var isConnecting = false
    private var isRefreshingToken = false

    init(
        app: String,
        client: Client,
        onMessage: @escaping (Data) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.app = app
        self.client = client
        self.onMessage = onMessage
        self.onError = onError
    }

    func connect() {
        if task == nil && !isConnecting && !isRefreshingToken {
            isConnecting = true
            if token == nil && !isRefreshingToken {
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
            let url = buildRealtimeUrl(forApp: app, host: "gateway.alpha.fal.ai", token: token)
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
                    let data = try message.data()
                    guard let parsedMessage = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        self?.onError(FalRealtimeError.invalidResult)
                        return
                    }
                    if isSuccessResult(parsedMessage) {
                        self?.onMessage(data)
                    }
//                    if (parsedMessage["status"] as? String != "error") {
//                        self?.task?.cancel()
//                    }

                } catch {
                    self?.onError(error)
                }
            case let .failure(error):
                self?.onError(error)
            }
            self?.receiveMessage()
        }
    }

    func send(_ data: Data) throws {
        if let task = task {
            guard let message = String(data: data, encoding: .utf8) else {
                return
            }
            task.send(.string(message)) { [weak self] error in
                if let error = error {
                    self?.onError(error)
                }
            }
        } else {
            enqueuedMessages.append(data)
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
        if let lastMessage = enqueuedMessages.last {
            do {
                try send(lastMessage)
            } catch {
                onError(error)
            }
        }
        enqueuedMessages.removeAll()
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
    return message["status"] as? String != "error" && message["type"] as? String != "x-fal-message"
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

public struct RealtimeClient: Realtime {
    
    // TODO in the future make this non-public
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
        return handleConnection(
            to: app,
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
    internal func handleConnection<InputType, ResultType>(
        to app: String,
        connectionKey: String,
        throttleInterval: DispatchTimeInterval,
        resultConverter convertToResultType: @escaping (Data) throws -> ResultType,
        connectionFactory createRealtimeConnection: @escaping (@escaping SendFunction, @escaping CloseFunction) -> RealtimeConnection<InputType>,
        onResult completion: @escaping (Result<ResultType, Error>) -> Void
    ) -> RealtimeConnection<InputType> {
        let key = "\(app):\(connectionKey)"
        let ws = connectionPool[key] ?? WebSocketConnection(
            app: app,
            client: self.client,
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

        let sendData = { (data: Data) in
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
    func connect(
        to app: String,
        connectionKey: String = UUID().uuidString,
        throttleInterval: DispatchTimeInterval = .milliseconds(64),
        onResult completion: @escaping (Result<[String: Any], Error>) -> Void
    ) throws -> RealtimeConnection<[String: Any]> {
        return try connect(
            to: app,
            connectionKey: connectionKey,
            throttleInterval: throttleInterval,
            onResult: completion
        )
    }
}
