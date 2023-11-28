import Dispatch

extension DispatchTimeInterval {
    public static func minutes(_ value: Int) -> DispatchTimeInterval {
        return .seconds(value * 60)
    }

    var milliseconds: Int {
        switch self {
        case let .milliseconds(value):
            return value
        case let .seconds(value):
            return value * 1000
        case let .microseconds(value):
            return value / 1000
        case let .nanoseconds(value):
            return value / 1_000_000
        case .never:
            return 0
        @unknown default:
            return 0
        }
    }
}
