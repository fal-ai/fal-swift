import Foundation

public enum ClientCredentials: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .keyPair(value):
            return value
        case let .key(id: id, secret: secret):
            return "\(id):\(secret)"
        case .fromEnv:
            if let keyPair = ProcessInfo.processInfo.environment["FAL_KEY"] {
                return keyPair
            }

            if let keyId = ProcessInfo.processInfo.environment["FAL_KEY_ID"],
               let keySecret = ProcessInfo.processInfo.environment["FAL_KEY_SECRET"]
            {
                return "\(keyId):\(keySecret)"
            }
            return ""
        case let .custom(resolver):
            return resolver()
        }
    }

    case keyPair(_ pair: String)
    case key(id: String, secret: String)
    case fromEnv
    case custom(_ resolver: () -> String)
}

public struct ClientConfig {
    public let credentials: ClientCredentials
    public let requestProxy: String?
    public let customHeaders: [String: String]?

    init(credentials: ClientCredentials = .fromEnv, requestProxy: String? = nil, customHeaders: [String: String]? = nil) {
        self.credentials = credentials
        self.requestProxy = requestProxy
        self.customHeaders = customHeaders
    }
}
