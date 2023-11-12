

public struct QueueSubmitResult: Decodable {
    let requestId: String

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
    }
}

public extension Queue {
    func submit(_ id: String, input: (some Encodable) = EmptyInput.empty, webhookUrl _: String? = nil) async throws -> String {
        let result: QueueSubmitResult = try await client.run(id, input: input, options: .route("/fal/queue/submit"))
        return result.requestId
    }

    func response<Output: Decodable>(_ id: String, of requestId: String) async throws -> Output {
        return try await client.run(
            id,
            input: EmptyInput.empty,
            options: .route("/fal/queue/requests/\(requestId)/response", withMethod: .get)
        )
    }
}
