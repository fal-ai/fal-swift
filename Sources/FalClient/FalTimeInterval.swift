public enum FalTimeInterval {
    case milliseconds(Int)
    case seconds(Int)
    case minutes(Int)
    case hours(Int)

    var milliseconds: Int {
        switch self {
        case let .milliseconds(value):
            return value
        case let .seconds(value):
            return value * 1000
        case let .minutes(value):
            return value * 60 * 1000
        case let .hours(value):
            return value * 60 * 60 * 1000
        }
    }
}
