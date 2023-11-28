import PencilKit
import SwiftUI
import UIKit

class CanvasView: PKCanvasView {
    // keep a list of functions that will be called when the touchMoves event is fired
    var touchMoveListeners: [(Set<UITouch>) -> Void] = []

    func addTouchMoveListener(_ listener: @escaping (Set<UITouch>) -> Void) {
        touchMoveListeners.append(listener)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with _: UIEvent?) {
        // call all the touchMove listeners
        touchMoveListeners.forEach { listener in
            listener(touches)
        }
    }
}

struct DrawingCanvasView: UIViewRepresentable {
    @Binding var canvasView: CanvasView
    @Binding var drawingData: Data?
    @State var toolPicker = PKToolPicker()
    @State var isDrawing = false

    func makeUIView(context: Context) -> CanvasView {
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 10)
        canvasView.delegate = context.coordinator
        canvasView.addTouchMoveListener { _ in
            if self.isDrawing {
//                self.triggerDrawingChange()
            }
        }
        return canvasView
    }

//    @MainActor
    func triggerDrawingChange() {
        if let image = drawingToImage(canvasView: canvasView),
           let imageData = image.jpegData(compressionQuality: 0.6)
        {
            drawingData = imageData
        }
    }

    func updateUIView(_: CanvasView, context _: Context) {
        showToolPicker()
        if let data = drawingData,
           let drawing = try? PKDrawing(data: data)
        {
            canvasView.drawing = drawing
        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: DrawingCanvasView

        init(_ parent: DrawingCanvasView) {
            self.parent = parent
        }

        @MainActor
        func canvasViewDrawingDidChange(_: PKCanvasView) {
            parent.triggerDrawingChange()
        }

        @MainActor
        func canvasViewDidBeginUsingTool(_: PKCanvasView) {
            parent.isDrawing = true
        }

        @MainActor
        func canvasViewDidEndUsingTool(_: PKCanvasView) {
            parent.isDrawing = false
        }
    }
}

extension DrawingCanvasView {
    func showToolPicker() {
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)
        canvasView.becomeFirstResponder()
    }

//    @MainActor
    func drawingToImage(canvasView: PKCanvasView) -> UIImage? {
        // TODO: improve this, so the drawable area is clear to the user and also cropped
        // correctly when the image is submitted
        let drawingArea = CGRect(x: 0, y: 0, width: 512, height: 512)
        return canvasView.drawing.image(from: drawingArea, scale: 1.0)
//        let renderer = ImageRenderer(content: self)
//        guard let image = renderer.cgImage?.cropping(to: drawingArea) else {
//            return nil
//        }
//        return UIImage(cgImage: image)
    }
}
