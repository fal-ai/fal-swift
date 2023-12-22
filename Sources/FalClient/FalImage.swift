import Foundation

public enum FalImageContent: Codable {
    case url(String)
    case raw(Data)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let url = try? container.decode(String.self) {
            self = .url(url)
        } else if let data = try? container.decode(Data.self) {
            self = .raw(data)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "FalImageContent must be either URL, Base64 or Binary")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .url(url):
            try container.encode(url)
        case let .raw(data):
            try container.encode(data)
        }
    }

    public var data: Data {
        switch self {
        case let .url(url):
            let url = URL(string: url)!
            return try! Data(contentsOf: url)
        case let .raw(data):
            return data
        }
    }
}

extension FalImageContent: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .url(value)
    }
}

extension FalImageContent: ExpressibleByStringInterpolation {
    public init(stringInterpolation: StringInterpolation) {
        self = .url(stringInterpolation.string)
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        var string: String = ""

        public init(literalCapacity _: Int, interpolationCount _: Int) {}

        public mutating func appendLiteral(_ literal: String) {
            string.append(literal)
        }

        public mutating func appendInterpolation(_ value: String) {
            string.append(value)
        }
    }
}

public struct FalImage: Codable {
    public let content: FalImageContent
    public let contentType: String
    public let width: Int
    public let height: Int

    // The following exist so we support payloads with both `url` and `content` keys
    // This should no longer be necessary once the Server API is consolidated
    enum UrlCodingKeys: String, CodingKey {
        case content = "url"
        case contentType = "content_type"
        case width
        case height
    }

    enum RawDataCodingKeys: String, CodingKey {
        case content
        case contentType = "content_type"
        case width
        case height
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: UrlCodingKeys.self)
        if let url = try? container.decode(String.self, forKey: .content) {
            content = .url(url)
            contentType = try container.decode(String.self, forKey: .contentType)
            width = try container.decode(Int.self, forKey: .width)
            height = try container.decode(Int.self, forKey: .height)
        } else {
            let container = try decoder.container(keyedBy: RawDataCodingKeys.self)
            content = try .raw(container.decode(Data.self, forKey: .content))
            contentType = try container.decode(String.self, forKey: .contentType)
            width = try container.decode(Int.self, forKey: .width)
            height = try container.decode(Int.self, forKey: .height)
        }
    }
}
