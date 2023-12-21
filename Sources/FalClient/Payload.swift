import Foundation
import SwiftMsgpack

/// Represents a value that can be encoded and decoded. This data structure
/// is used to represent the input and output of the model API and closely
/// matches a JSON data structure.
///
/// It supports binary data as well, so it can be kept and transformed if needed
/// before it's encoded to JSON or any other supported format (e.g. msgpack).
public enum Payload: Codable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case double(Double)
    case date(Date)
    case data(Data)
    case array([Payload])
    case dict([String: Payload])
    case nilValue

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let date = try? container.decode(Date.self) {
            self = .date(date)
        } else if let data = try? container.decode(Data.self) {
            self = .data(data)
        } else if let array = try? container.decode([Payload].self) {
            self = .array(array)
        } else if let dict = try? container.decode([String: Payload].self) {
            self = .dict(dict)
        } else {
            self = .nilValue
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(str):
            try container.encode(str)
        case let .int(int):
            try container.encode(int)
        case let .bool(bool):
            try container.encode(bool)
        case let .double(double):
            try container.encode(double)
        case let .date(date):
            try container.encode(date)
        case let .data(data):
            if encoder is JSONEncoder {
                let base64String = data.base64EncodedString()
                try container.encode("data:application/octet-stream;base64,\(base64String)")
            } else {
                try container.encode(data)
            }
        case let .array(array):
            try container.encode(array)
        case let .dict(dict):
            try container.encode(dict)
        case .nilValue:
            try container.encodeNil()
        }
    }
}

// MARK: - Expressible

extension Payload: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        self = .string(value)
    }

    public var stringValue: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }
}

extension Payload: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: IntegerLiteralType) {
        self = .int(value)
    }
}

extension Payload: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: BooleanLiteralType) {
        self = .bool(value)
    }
}

extension Payload: ExpressibleByNilLiteral {
    public init(nilLiteral _: ()) {
        self = .nilValue
    }
}

extension Payload: ExpressibleByFloatLiteral {
    public init(floatLiteral value: FloatLiteralType) {
        self = .double(value)
    }
}

extension Payload: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Payload...) {
        self = .array(elements)
    }
}

extension Payload: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, Payload)...) {
        self = .dict(Dictionary(uniqueKeysWithValues: elements))
    }
}

// MARK: - Subscript

public extension Payload {
    subscript(key: String) -> Payload {
        get {
            if case let .dict(dict) = self, let value = dict[key] {
                return value
            }
            return .nilValue
        }
        set(newValue) {
            if case var .dict(dict) = self {
                dict[key] = newValue
                self = .dict(dict)
            }
        }
    }

    subscript(index: Int) -> Payload {
        get {
            if case let .array(arr) = self, arr.indices.contains(index) {
                return arr[index]
            }
            return .nilValue
        }
        set(newValue) {
            if case var .array(arr) = self {
                arr[index] = newValue
                self = .array(arr)
            }
        }
    }
}

// MARK: - Equatable

extension Payload: Equatable {
    public static func == (lhs: Payload, rhs: Payload) -> Bool {
        switch (lhs, rhs) {
        case let (.string(a), .string(b)):
            return a == b
        case let (.int(a), .int(b)):
            return a == b
        case let (.bool(a), .bool(b)):
            return a == b
        case let (.double(a), .double(b)):
            return a == b
        case let (.date(a), .date(b)):
            return a == b
        case let (.data(a), .data(b)):
            return a == b
        case let (.array(a), .array(b)):
            return a == b
        case let (.dict(a), .dict(b)):
            return a == b
        case (.nilValue, .nilValue):
            return true
        default:
            return false
        }
    }

    // Special handling to compare .nilValue with nil
    static func == (lhs: Payload?, rhs: Payload) -> Bool {
        if let lhs {
            return lhs == rhs
        } else {
            return rhs == .nilValue
        }
    }

    static func == (lhs: Payload, rhs: Payload?) -> Bool {
        rhs == lhs
    }
}

// MARK: - Convert to native types

extension Payload {
    var nativeValue: Any {
        switch self {
        case let .string(value):
            return value
        case let .int(value):
            return value
        case let .bool(value):
            return value
        case let .double(value):
            return value
        case let .date(value):
            return value
        case let .data(value):
            return value
        case let .array(value):
            return value.map(\.nativeValue)
        case let .dict(value):
            return value.mapValues { $0.nativeValue }
        case .nilValue:
            return NSNull()
        }
    }

    var asDictionary: [String: Any]? {
        guard case let .dict(value) = self else {
            return nil
        }
        return value.mapValues { $0.nativeValue }
    }
}

// MARK: - Codable utilities

public extension Payload {
    static func create(fromJSON data: Data) throws -> Payload {
        try JSONDecoder().decode(Payload.self, from: data)
    }

    static func create(fromBinary data: Data) throws -> Payload {
        try MsgPackDecoder().decode(Payload.self, from: data)
    }

    func json() throws -> Data {
        try JSONEncoder().encode(self)
    }

    func binary() throws -> Data {
        try MsgPackEncoder().encode(self)
    }
}

// MARK: - Utilities

extension Payload {
    var hasBinaryData: Bool {
        switch self {
        case .data:
            return true
        case let .array(array):
            return array.contains { $0.hasBinaryData }
        case let .dict(dict):
            return dict.values.contains { $0.hasBinaryData }
        default:
            return false
        }
    }
}
