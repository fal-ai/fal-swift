import AVFoundation
import FalClient
import SwiftUI

class FrameProcessor: ObservableObject {
    @Published var currentFrame: UIImage? {
        didSet {
            if let frame = currentFrame {
                process(frame: frame)
            }
        }
    }

    @Published var processedFrame: UIImage?

    @Published var currentFPS = 0.0

    var lastFrameTime = Date()
    var connection: RealtimeConnection<Data>?

    init() {
        connection = try? fal.realtime.connect(
            to: "110602490-sdxl-turbo-realtime-high-fps",
            input: [
                "prompt": "photo of brad pitt, sharp focus, intricate, elegant, realistic, 8k ultra hd",
                "num_inference_steps": 2,
                "strength": 0.66,
                "guidance_scale": 1,
                "seed": 6_252_023,
            ],
            connectionKey: "swift-realtime-camera-demo",
            throttleInterval: .milliseconds(16)
        ) { result in
            print("======> result!!!")
//            print(result)
            print("----------------------")
            if case let .success(data) = result {
                print("%%%%% about to render processed frame")

                // Calculate the current FPS
                let now = Date()
                let fps = 1 / now.timeIntervalSince(self.lastFrameTime)
                self.lastFrameTime = now

                DispatchQueue.main.async {
                    self.currentFPS = fps
                    self.processedFrame = UIImage(data: data)
                }
            }
            if case let .failure(error) = result {
                print("!!!!! error")
                print(type(of: error))
            }
        }
    }

    func process(frame: UIImage) {
//        self.processedFrame = frame

        print("-----------------------------")
//        print(croppedImage)
//        print("-----------------------------")

        if let connection,
           //    let image = preprocess(frame: frame),
           let imageData = frame.jpegData(compressionQuality: 0.5)
        {
            // print(frame)
            // print("preprocess done!")
            // let base64DataUri = "data:image/jpeg;base64,\(imageData.base64EncodedString())"
            // print(base64DataUri)
            print("-----------------------------")
            // self.processedFrame = frame
            do {
                print("!!process!!")
                try connection.send(imageData)
            } catch {
                print(error)
            }
        }
    }
}
