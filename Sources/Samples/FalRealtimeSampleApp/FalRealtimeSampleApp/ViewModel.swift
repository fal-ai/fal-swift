import FalClient
import SwiftUI

struct TurboInput: Encodable {
    let prompt: String
    let image: Data
    let seed: Int
    let syncMode: Bool
    let strength: Float

    enum CodingKeys: String, CodingKey {
        case prompt
        case image = "image_bytes"
        case seed
        case syncMode = "sync_mode"
        case strength
    }
}

struct TurboResponse: Decodable {
    let images: [FalImage]
}

class LiveImage: ObservableObject {
    @Published var currentImage: Data?

    private var connection: TypedRealtimeConnection<TurboInput>?

    init() {
        connection = try? fal.realtime.connect(
            to: "fal-ai/fast-turbo-diffusion/image-to-image",
            connectionKey: "PencilKitDemo",
            throttleInterval: .never
        ) { (result: Result<TurboResponse, Error>) in
            if case let .success(data) = result,
               case let imageData = data.images[0].content.data
            {
                DispatchQueue.main.async {
                    self.currentImage = imageData
                }
            }
            if case let .failure(error) = result {
                print("-------------- Error")
                print(error)
            }
        }
    }

    func generate(prompt: String, drawing: Data) throws {
        if let connection {
            try connection.send(TurboInput(
                prompt: prompt,
                image: drawing,
                seed: 6_252_023,
                syncMode: true,
                strength: 0.6
            ))
        }
    }
}
