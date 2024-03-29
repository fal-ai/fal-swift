import FalClient
import SwiftUI

struct LcmInput: Encodable {
    let prompt: String
    let image: FalImageContent
    let seed: Int
    let syncMode: Bool

    enum CodingKeys: String, CodingKey {
        case prompt
        case image = "image_url"
        case seed
        case syncMode = "sync_mode"
    }
}

struct LcmResponse: Decodable {
    let images: [FalImage]
}

class LiveImage: ObservableObject {
    @Published var currentImage: Data?

    // This example demonstrates the support to Codable types, but
    // RealtimeConnection can also be used for untyped input / output
    // using dictionary-like Payload
    private var connection: TypedRealtimeConnection<LcmInput>?

    init() {
        connection = try? fal.realtime.connect(
            // See https://fal.ai/models/latent-consistency-sd/api
            to: "fal-ai/lcm-sd15-i2i",
            connectionKey: "PencilKitDemo",
            throttleInterval: .milliseconds(128)
        ) { (result: Result<LcmResponse, Error>) in
            if case let .success(data) = result,
               let image = data.images.first
            {
                DispatchQueue.main.async {
                    self.currentImage = image.content.data
                }
            }
            if case let .failure(error) = result {
                print(error)
            }
        }
    }

    func generate(prompt: String, drawing: Data) throws {
        if let connection {
            try connection.send(LcmInput(
                prompt: prompt,
                image: "data:image/jpeg;base64,\(drawing.base64EncodedString())",
                seed: 6_252_023,
                syncMode: true
            ))
        }
    }
}
