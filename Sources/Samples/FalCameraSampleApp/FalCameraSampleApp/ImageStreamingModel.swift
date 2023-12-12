import FalClient
import SwiftUI

let TurboApp = "110602490-sd-turbo-real-time-high-fps-msgpack"
// let TurboApp = "110602490-sdxl-turbo-realtime-high-fps"
// let TurboApp = "110602490-sd-turbo-realtime-high-fps"

class ImageStreamingModel: ObservableObject, ImageStreamingDelegate {
    @Published var currentCapturedFrame: UIImage? {
        didSet {
            if let frame = currentCapturedFrame {
                process(image: frame)
            }
        }
    }

    @Published var prompt: String = "photo of george clooney, sharp focus, intricate, elegant, realistic, 8k ultra hd" {
        didSet {
            if let frame = currentCapturedFrame {
                process(image: frame)
            }
        }
    }

    @Published var currentProcessedFrame: UIImage?
    @Published var currentFPS: Double = 0.0
    @Published var active: Bool = false

    private var imageStreaming: ImageStreaming

    private var connection: RealtimeConnection?

    init(imageStreaming: ImageStreaming = ImageStreaming()) {
        // simplified error handling for demo purposes
        connection = try? fal.realtime.connect(
            to: TurboApp,
            connectionKey: "swift-realtime-camera-demo",
            throttleInterval: .never
        ) { result in
            if case let .success(data) = result,
               case let .data(image) = data["image"],
               let processedImage = UIImage(data: image)
            {
                imageStreaming.doneProcessing(image: processedImage)
            }
            if case let .failure(error) = result {
                print(error)
            }
        }
        self.imageStreaming = imageStreaming
        imageStreaming.delegate = self
    }

    func process(image: UIImage) {
        imageStreaming.process(image: image)
    }

    // MARK: ImageStreamingDelegate methods

    func didReceive(image: UIImage) {
        currentProcessedFrame = image
    }

    func didUpdate(fps: Double) {
        currentFPS = fps
    }

    func willProcess(image: UIImage) {
        guard active else {
            return
        }
        if let connection, let data = image.resize(to: .square)?.jpegData(compressionQuality: 0.5) {
            do {
                try connection.send([
                    "prompt": .string(prompt),
                    "image": .data(data),
                    "num_inference_steps": 3,
                    "strength": 0.44,
                    "guidance_scale": 1,
                    "seed": 224,
                ])
            } catch {
                print(error)
            }
        }
    }
}
