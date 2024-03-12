import Foundation

public struct QueueSubmitResult: Decodable {
    let requestId: String

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
    }
}

public extension Queue {
    func submit(_ id: String, input: (some Encodable) = EmptyInput.empty, webhookUrl: String? = nil) async throws -> String {
        // Convert some Encodable to Payload, so the underlying call can inspect the input more freely
        var inputPayload: Payload? = nil
        if !(input is EmptyInput) {
            let encoder = JSONEncoder()
            let data = try encoder.encode(input)
            inputPayload = try Payload.create(fromJSON: data)
        }
        return try await submit(id, input: inputPayload, webhookUrl: webhookUrl)
    }

    func response<Output: Decodable>(_ id: String, of requestId: String) async throws -> Output {
        let appId = try AppId.parse(id: id)
        return try await runOnQueue(
            "\(appId.ownerId)/\(appId.appAlias)",
            input: nil as Payload?,
            options: .route("/requests/\(requestId)", withMethod: .get)
        )
    }
}
