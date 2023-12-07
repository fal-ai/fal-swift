import FalClient
import SwiftUI

class ImageStreamingModel: ObservableObject, ImageStreamingDelegate {
    @Published var currentCapturedFrame: UIImage? {
        didSet {
            if let frame = currentCapturedFrame {
                process(image: frame)
            }
        }
    }

    @Published var currentProcessedFrame: UIImage?
    @Published var currentFPS: Double = 0.0

    private var imageStreaming: ImageStreaming

    private var connection: RealtimeConnection<Data>?

    init(imageStreaming: ImageStreaming = ImageStreaming()) {
        // simplified error handling for demo purposes
        connection = try? fal.realtime.connect(
            to: "110602490-sdxl-turbo-realtime-high-fps",
            input: [
                "prompt": "photo of george clooney, sharp focus, intricate, elegant, realistic, 8k ultra hd",
                "num_inference_steps": 3,
                "strength": 0.4,
                "guidance_scale": 1,
                "seed": 224,
            ],
            connectionKey: "swift-realtime-camera-demo",
            throttleInterval: .never
        ) { result in
            print("====> ImageStreamingModel.onResult")
            if case let .success(data) = result, let processedImage = UIImage(data: data) {
                imageStreaming.doneProcessing(image: processedImage)
            }
        }
        self.imageStreaming = imageStreaming
        imageStreaming.delegate = self
    }

    func process(image: UIImage) {
        print("---------------")
        print(image)
        print("---------------")
        imageStreaming.process(image: image)
    }

    // MARK: ImageStreamingDelegate methods

    func didReceive(image: UIImage) {
        currentProcessedFrame = image
    }

    func didUpdate(fps: Double) {
        print("\(fps) FPS")
        currentFPS = fps
    }

    func willProcess(image: UIImage) {
        guard let connection, let data = image.jpegData(compressionQuality: 0.7) else {
            return
        }
        do {
            print("=> ImageStreamingModel.willProcess")
            try connection.send(data)
        } catch {
            print(error)
        }
    }
}
