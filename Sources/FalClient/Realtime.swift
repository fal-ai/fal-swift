
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

public class RealtimeConnectionUntyped: RealtimeConnection<[String: Any]> {
    override public func send(_ data: [String: Any]) throws {
        let json = try JSONSerialization.data(withJSONObject: data)
        try sendReference(json)
    }
}

// public protocol RealtimeConnectionTyped: RealtimeConnection where Input: Encodable {
//     func send(_ data: Input) throws
// }

func buildRealtimeUrl(forApp app: String, host: String, token: String? = nil) -> URL {
    var components = URLComponents()
    components.scheme = "wss"
    components.host = "\(app).\(host)"
    components.path = "/ws"

    if let token = token {
        let queryItem = URLQueryItem(name: "fal_jwt_token", value: token)
        components.queryItems = [queryItem]
    }

    // swiftlint:disable:next force_unwrapping
    return components.url!
}

class ConnectionManager {
    private let session = URLSession(configuration: .default)
    private var connections: [String: URLSessionWebSocketTask] = [:]
    private var currentToken: String?

    // Singleton pattern for global access
    static let shared = ConnectionManager()

    init() {}

    func token() -> String? {
        return currentToken
    }

    func refreshToken(for app: String, completion: @escaping (String?) -> Void) {
        // Assuming getToken is a function that fetches the token for the app
        getToken(for: app) { [weak self] newToken in
            self?.currentToken = newToken
            print("Refreshed token: \(String(describing: newToken))")
            completion(newToken)
        }
    }

    func hasConnection(for app: String) -> Bool {
        return connections[app] != nil
    }

    func getConnection(for app: String) -> URLSessionWebSocketTask {
        if let connection = connections[app] {
            return connection
        }

        // TODO: get host from config
        return session.webSocketTask(with: buildRealtimeUrl(forApp: app, host: "gateway.alpha.fal.ai", token: currentToken))
    }

    func setConnection(for app: String, connection: URLSessionWebSocketTask) {
        connections[app] = connection
    }

    func removeConnection(for app: String) {
        connections[app]?.cancel(with: .normalClosure, reason: nil)
        connections.removeValue(forKey: app)
    }

    // Implement the getToken function or integrate your existing token fetching logic
    private func getToken(for app: String, onComplete completion: @escaping (String?) -> Void) {
        completion("token" + app)
    }
}

public protocol Realtime {
    func connect(
        to app: String,
        connectionKey: String,
        throttleInterval: DispatchTimeInterval,
        onResult completion: @escaping (Result<[String: Any], Error>) -> Void
    ) throws -> RealtimeConnection<[String: Any]>
}

// public extension Realtime {
//     func connect(
//         to app: String,
//         throttleInterval: DispatchTimeInterval = .milliseconds(64),
//         onResult: @escaping (Result<[String: Any], Error>) -> Void
//     ) throws -> any RealtimeConnectionUntyped {
//         return try connect(to: app, throttleInterval: throttleInterval, onResult: onResult)
//     }
// }

// func establishConnection(
//     to _: String,
//     onConnect _: @escaping (URLSessionWebSocketTask) -> Void
// ) {
//     preconditionFailure()
// }

extension URLSessionWebSocketTask.Message {
    func data() throws -> Data {
        switch self {
        case let .data(data):
            return data
        case let .string(string):
            guard let data = string.data(using: .utf8) else {
                // TODO: improve exception type
                preconditionFailure()
            }
            return data
        @unknown default:
            preconditionFailure("Unknown URLSessionWebSocketTask.Message case")
        }
    }
}

struct RealtimeClient: Realtime {
    private let client: Client

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
            to: app, connectionKey: connectionKey, throttleInterval: throttleInterval,
            resultConverter: { data in
                guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    // TODO: throw exception
                    preconditionFailure()
                }
                return result
            },
            connectionFactory: { send, close in
                RealtimeConnectionUntyped(send, close)
            },
            onResult: completion
        )
    }

    func handleConnection<InputType, ResultType>(
        to app: String,
        connectionKey _: String,
        throttleInterval: DispatchTimeInterval,
        resultConverter convertToResultType: @escaping (Data) throws -> ResultType,
        connectionFactory createRealtimeConnection: @escaping (@escaping SendFunction, @escaping CloseFunction) -> RealtimeConnection<InputType>,
        onResult completion: @escaping (Result<ResultType, Error>) -> Void
    ) -> RealtimeConnection<InputType> {
        var enqueuedMessages: [Data] = []
        var ws: URLSessionWebSocketTask? = nil

        let reconnect = {
            let connection = ConnectionManager.shared.getConnection(for: app)
            connection.receive { incomingMessage in
                switch incomingMessage {
                case let .success(message):
                    do {
                        let data = try message.data()
                        let result = try convertToResultType(data)
                        completion(.success(result))
                    } catch {
                        completion(.failure(error))
                    }
                case let .failure(error):
                    // TODO: only drop the connection if the error is fatal
                    ws = nil
                    ConnectionManager.shared.removeConnection(for: app)
                    // TODO: only send certain errors to the completion callback
                    completion(.failure(error))
                }
            }
            connection.resume()
            ws = connection
        }

        let sendData = { (data: Data) in
            if let task = ws, task.state == .running {
                guard let message = String(data: data, encoding: .utf8) else {
                    // TODO: throw exception
                    return
                }
                task.send(.string(message)) { error in
                    if let error = error {
                        completion(.failure(error))
                    }
                }
            } else {
                enqueuedMessages.append(data)
                reconnect()
            }
        }

        let send: SendFunction = throttleInterval.milliseconds > 0 ? throttle(sendData, throttleInterval: throttleInterval) : sendData
        let close: CloseFunction = {
            ws?.cancel(with: .normalClosure, reason: nil)
        }

        return createRealtimeConnection(send, close)
    }
}
