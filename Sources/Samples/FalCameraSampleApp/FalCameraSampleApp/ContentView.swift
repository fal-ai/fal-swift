import SwiftUI

struct ContentView: View {
    @ObservedObject var imageStreaming = ImageStreamingModel()
//    @ObservedObject var frameProcessor = FrameProcessor()

    var body: some View {
        HStack {
            CameraView(currentFrame: $imageStreaming.currentCapturedFrame) // UIImage
//            CameraView(currentFrame: $frameProcessor.currentFrame)
                .frame(minWidth: 0, maxWidth: .infinity)

            VStack {
                if let image = imageStreaming.currentProcessedFrame {
//                if let image = frameProcessor.processedFrame {
                    Image(uiImage: image)
//                        .frame(maxWidth: 512)
                }
            }
            .frame(minWidth: 0, maxWidth: 512)
            .overlay(alignment: .topLeading) {
                Text("\(imageStreaming.currentFPS) FPS")
//                Text("\(frameProcessor.currentFPS) FPS")
                    .padding(.all)
                    .foregroundColor(.white)
                    .background(.black.opacity(0.3))
            }
        }
    }
}
