import Dispatch
import Foundation

public struct EmptyInput: Encodable {
    public static let empty = EmptyInput()
}

public extension Client {
    var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func run<Output: Decodable>(
        _ app: String,
        input: (some Encodable) = EmptyInput.empty,
        options: RunOptions = DefaultRunOptions
    ) async throws -> Output {
        let inputData = input is EmptyInput ? nil : try encoder.encode(input)
        let queryParams = inputData != nil && options.httpMethod == .get
            ? try Payload.create(fromJSON: inputData!)
            : Payload.dict([:])

        let url = buildUrl(fromId: app, path: options.path)
        let data = try await sendRequest(to: url, input: inputData, queryParams: queryParams.asDictionary, options: options)
        return try decoder.decode(Output.self, from: data)
    }

    func subscribe<Output: Decodable>(
        to app: String,
        input: (some Encodable) = EmptyInput.empty,
        pollInterval: DispatchTimeInterval = .seconds(1),
        timeout: DispatchTimeInterval = .minutes(3),
        includeLogs: Bool = false,
        onQueueUpdate: OnQueueUpdate? = nil
    ) async throws -> Output {
        let requestId = try await queue.submit(app, input: input)
        let start = Int(Date().timeIntervalSince1970 * 1000)
        var elapsed = 0
        var isCompleted = false
        while elapsed < timeout.milliseconds {
            let update = try await queue.status(app, of: requestId, includeLogs: includeLogs)
            if let onQueueUpdateCallback = onQueueUpdate {
                onQueueUpdateCallback(update)
            }
            isCompleted = update.isCompleted
            if isCompleted {
                break
            }
            try await Task.sleep(nanoseconds: UInt64(Int(pollInterval.milliseconds * 1_000_000)))
            elapsed += Int(Date().timeIntervalSince1970 * 1000) - start
        }
        if !isCompleted {
            throw FalError.queueTimeout
        }
        return try await queue.response(app, of: requestId)
    }
}
