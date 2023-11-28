import Kingfisher
import SwiftUI

struct ContentView: View {
    @State var canvasView = CanvasView()
    @State var drawingData: Data?
    @ObservedObject var liveImage = LiveImage()

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width > geometry.size.height {
                // Landscape
                HStack {
                    DrawingCanvasView(canvasView: $canvasView, drawingData: $drawingData)
                        .onChange(of: drawingData) { onDrawingChange() }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    ImageViewContainer(imageData: liveImage.currentImage)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                // Portrait
                VStack {
                    ImageViewContainer(imageData: liveImage.currentImage)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    DrawingCanvasView(canvasView: $canvasView, drawingData: $drawingData)
                        .onChange(of: drawingData) { onDrawingChange() }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding()
    }

    func onDrawingChange() {
        guard let data = drawingData else {
            return
        }
        do {
            try liveImage.generate(prompt: "a moon in a starry night sky", drawing: data)
        } catch {
            print(error)
        }
    }
}

struct ImageViewContainer: View {
    var imageData: Data?

    var body: some View {
        VStack {
            if let image = imageData {
                KFImage.data(image, cacheKey: UUID().uuidString)
                    .transition(.opacity)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.4))
            }
        }
    }
}
