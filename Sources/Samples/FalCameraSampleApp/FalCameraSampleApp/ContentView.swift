import SwiftUI

struct ContentView: View {
    @ObservedObject var imageStreaming = ImageStreamingModel()
    @Environment(\.verticalSizeClass) var sizeClass

    var body: some View {
        VStack {
            TextField("Imagine yourself as", text: $imageStreaming.prompt)
                .font(.largeTitle)
                .textFieldStyle(.roundedBorder)
                .padding()
            
            if sizeClass == .regular {
                HStack(alignment: .center) {
                    cameraView
                    processedImageView
                }
            } else {
                VStack(alignment: .center) {
                    cameraView
                    processedImageView
                }
            }
        }
    }

    var cameraView: some View {
        ZStack {
            CameraView(currentFrame: $imageStreaming.currentCapturedFrame)
                .frame(minWidth: 0, maxWidth: .infinity)
            // Show button to start/stop streaming
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        imageStreaming.active.toggle()
                    }) {
                        Text(imageStreaming.active ? "Stop" : "Start")
                            .padding()
                            .foregroundColor(.white)
                            .background(.black.opacity(0.3))
                    }
                    .padding()
                }
            }
        }
    }

    var processedImageView: some View {
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
