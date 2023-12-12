import Dispatch
import Foundation

public extension Realtime {
    func connect<Input: Encodable, Output: Decodable>(
        to app: String,
        connectionKey: String = UUID().uuidString,
        throttleInterval: DispatchTimeInterval = .milliseconds(64),
        onResult completion: @escaping (Result<Output, Error>) -> Void
    ) throws -> TypedRealtimeConnection<Input> {
        handleConnection(
            to: app,
            connectionKey: connectionKey,
            throttleInterval: throttleInterval,
            connectionFactory: { send, close in
                TypedRealtimeConnection(send, close)
            },
            onResult: completion
        ) as! TypedRealtimeConnection<Input>
    }
}
