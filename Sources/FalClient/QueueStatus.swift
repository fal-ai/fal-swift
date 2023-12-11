/// Enum that represents the status of a request in the queue.
/// This is the base class for the different statuses: [inProgress], [inQueue] and [completed].
public enum QueueStatus: Codable {
    case inProgress(logs: [RequestLog])
    case inQueue(position: Int, responseUrl: String)
    case completed(logs: [RequestLog], responseUrl: String)

    enum CodingKeys: String, CodingKey {
        case status
        case logs
        case queue_position
        case response_url
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(String.self, forKey: .status)

        switch status {
        case "IN_PROGRESS":
            let logs = try container.decode([RequestLog]?.self, forKey: .logs)
            self = .inProgress(logs: logs ?? [])

        case "IN_QUEUE":
            let position = try container.decode(Int.self, forKey: .queue_position)
            let responseUrl = try container.decode(String.self, forKey: .response_url)
            self = .inQueue(position: position, responseUrl: responseUrl)

        case "COMPLETED":
            let logs = try container.decode([RequestLog]?.self, forKey: .logs)
            let responseUrl = try container.decode(String.self, forKey: .response_url)
            self = .completed(logs: logs ?? [], responseUrl: responseUrl)

        default:
            throw DecodingError.dataCorruptedError(
                forKey: .status,
                in: container,
                debugDescription: "Invalid status value: \(status)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .inProgress(logs):
            try container.encode("IN_PROGRESS", forKey: .status)
            try container.encode(logs, forKey: .logs)

        case let .inQueue(position, responseUrl):
            try container.encode("IN_QUEUE", forKey: .status)
            try container.encode(position, forKey: .queue_position)
            try container.encode(responseUrl, forKey: .response_url)

        case let .completed(logs, responseUrl):
            try container.encode("COMPLETED", forKey: .status)
            try container.encode(logs, forKey: .logs)
            try container.encode(responseUrl, forKey: .response_url)
        }
    }

    /// Whether the request is completed or not.
    public var isCompleted: Bool {
        switch self {
        case .completed:
            return true
        default:
            return false
        }
    }

    /// Logs related to the request, if any.
    public var logs: [RequestLog] {
        switch self {
        case let .inProgress(logs), let .completed(logs, _):
            return logs
        default:
            return []
        }
    }
}

public struct RequestLog: Codable {
    public let message: String
    public let timestamp: String
    public let labels: Labels
    public var level: LogLevel { labels.level }

    public struct Labels: Codable {
        public let level: LogLevel
    }

    public enum LogLevel: String, Codable {
        case stderr = "STDERR"
        case stdout = "STDOUT"
        case error = "ERROR"
        case info = "INFO"
        case warn = "WARN"
        case debug = "DEBUG"
    }
}
