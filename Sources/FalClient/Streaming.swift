import Combine
import Foundation

public class FalStream<Input: Codable, Output: Codable>: AsyncSequence {
    public typealias Element = Output

    private let url: URL
    private let input: Input
    private let timeout: DispatchTimeInterval

    private let subject = PassthroughSubject<Element, Error>()
    private var buffer: [Output] = []
    private var currentData: Output?
    private var lastEventTimestamp: Date = .init()
    private var streamClosed = false
    private var doneFuture: Future<Output, Error>? = nil

    private var cancellables: Set<AnyCancellable> = []

    public init(url: URL, input: Input, timeout: DispatchTimeInterval) {
        self.url = url
        self.input = input
        self.timeout = timeout
    }

    public var publisher: AnyPublisher<Element, Error> {
        subject.eraseToAnyPublisher()
    }

    func start() {
        doneFuture = Future { promise in
            self.subject
                .last()
                .sink(
                    receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            if let lastValue = self.currentData {
                                promise(.success(lastValue))
                            } else {
                                promise(.failure(StreamingApiError.emptyResponse))
                            }
                        case let .failure(error):
                            promise(.failure(error))
                        }
                    },
                    receiveValue: { _ in }
                )
                .store(in: &self.cancellables)
        }

        Task {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("Keep-Alive", forHTTPHeaderField: "Connection")

            do {
                request.httpBody = try JSONEncoder().encode(input)
                let (data, _) = try await URLSession.shared.bytes(for: request)

                for try await content in data.lines {
                    // NOTE: naive approach that relies on each chunk to be a complete event
                    // revisit this in case endpoints start to handle SSE differently
                    if content.starts(with: "data:") {
                        let payloadData = content.dropFirst("data:".count)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .data(using: .utf8) ?? Data()
                        let eventData = try JSONDecoder().decode(Output.self, from: payloadData)
                        self.currentData = eventData
                        subject.send(eventData)
                    }
                }
                subject.send(completion: .finished)
            } catch {
                subject.send(completion: .failure(error))
                return
            }
        }
    }

    private func checkTimeout() {
        let currentTime = Date()
        let timeInterval = currentTime.timeIntervalSince(lastEventTimestamp)
        switch timeout {
        case let .seconds(seconds):
            if timeInterval > TimeInterval(seconds) {
                handleError(StreamingApiError.timeout)
            }
        case let .milliseconds(milliseconds):
            if timeInterval > TimeInterval(milliseconds) / 1000.0 {
                handleError(StreamingApiError.timeout)
            }
        default:
            break
        }
    }

    private func handleError(_ error: Error) {
        streamClosed = true
        subject.send(completion: .failure(error))
    }

    public func makeAsyncIterator() -> AsyncThrowingStream<Element, Error>.AsyncIterator {
        AsyncThrowingStream { continuation in
            self.subject.sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        continuation.finish()
                    case let .failure(error):
                        continuation.finish(throwing: error)
                    }
                },
                receiveValue: { value in
                    continuation.yield(value)
                }
            ).store(in: &self.cancellables)
        }.makeAsyncIterator()
    }

    public func done() async throws -> Output {
        guard let doneFuture else {
            throw StreamingApiError.invalidState
        }
        return try await doneFuture.value
    }
}

public typealias UntypedFalStream = FalStream<Payload, Payload>

enum StreamingApiError: Error {
    case invalidState
    case invalidResponse
    case httpError(statusCode: Int)
    case emptyResponse
    case timeout
}

public protocol Streaming {
    func stream<Input: Codable, Output: Codable>(
        from endpointId: String,
        input: Input,
        timeout: DispatchTimeInterval
    ) async throws -> FalStream<Input, Output>
}

public extension Streaming {
    func stream<Input: Codable, Output: Codable>(
        from endpointId: String,
        input: Input,
        timeout: DispatchTimeInterval = .seconds(60)
    ) async throws -> FalStream<Input, Output> {
        try await stream(from: endpointId, input: input, timeout: timeout)
    }
}

public struct StreamingClient: Streaming {
    public let client: Client

    public func stream<Input, Output>(
        from endpointId: String,
        input: Input,
        timeout: DispatchTimeInterval
    ) async throws -> FalStream<Input, Output> where Input: Codable, Output: Codable {
        let token = try await client.fetchTemporaryAuthToken(for: endpointId)
        let url = client.buildEndpointUrl(fromId: endpointId, path: "/stream", queryParams: [
            "fal_jwt_token": token,
        ])

        // TODO: improve auto-upload handling across different APIs
        var inputPayload = input is EmptyInput ? nil : try input.asPayload()
        if let storage = client.storage as? StorageClient,
           inputPayload != nil,
           inputPayload.hasBinaryData
        {
            inputPayload = try await storage.autoUpload(input: inputPayload)
        }

        let stream: FalStream<Input, Output> = try FalStream(url: url, input: inputPayload.asType(Input.self), timeout: timeout)
        stream.start()
        return stream
    }
}
