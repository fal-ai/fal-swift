import SwiftUI

struct ContentView: View {
    @ObservedObject var imageStreaming = ImageStreamingModel()

    var body: some View {
        HStack {
            CameraView(currentFrame: $imageStreaming.currentCapturedFrame)
                .frame(minWidth: 0, maxWidth: .infinity)

            VStack {
                if let image = imageStreaming.currentProcessedFrame {
                    Image(uiImage: image)
                }
            }
            .frame(minWidth: 0, maxWidth: 512)
            .overlay(alignment: .topLeading) {
                Text(String(format: "%.2f FPS", imageStreaming.currentFPS))
                    .padding(.all)
                    .foregroundColor(.white)
                    .background(.black.opacity(0.3))
            }
        }
    }
}
