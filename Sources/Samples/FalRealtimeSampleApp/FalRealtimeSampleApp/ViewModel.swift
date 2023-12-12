import FalClient
import SwiftUI

// See https://www.fal.ai/models/latent-consistency-sd/api for API documentation

let OptimizedLatentConsistency = "110602490-lcm-sd15-i2i"

struct LcmInput: Encodable {
    let prompt: String
    let imageUrl: String
    let seed: Int
    let syncMode: Bool

    enum CodingKeys: String, CodingKey {
        case prompt
        case imageUrl = "image_url"
        case seed
        case syncMode = "sync_mode"
    }
}

struct LcmImage: Decodable {
    let url: String
    let width: Int
    let height: Int
}

struct LcmResponse: Decodable {
    let images: [LcmImage]
}

class LiveImage: ObservableObject {
    @Published var currentImage: Data?

    // This example demonstrates the support to Codable types, but
    // RealtimeConnection can also be used for untyped input / output
    // using dictionary-like ObjectValue
    private var connection: TypedRealtimeConnection<LcmInput>?

    init() {
        connection = try? fal.realtime.connect(
            to: OptimizedLatentConsistency,
            connectionKey: "PencilKitDemo",
            throttleInterval: .milliseconds(128)
        ) { (result: Result<LcmResponse, Error>) in
            if case let .success(data) = result,
               let image = data.images.first
            {
                let data = try? Data(contentsOf: URL(string: image.url)!)
                DispatchQueue.main.async {
                    self.currentImage = data
                }
            }
        }
    }

    func generate(prompt: String, drawing: Data) throws {
        if let connection {
            try connection.send(LcmInput(
                prompt: prompt,
                imageUrl: "data:image/jpeg;base64,\(drawing.base64EncodedString())",
                seed: 6_252_023,
                syncMode: true
            ))
        }
    }
}
