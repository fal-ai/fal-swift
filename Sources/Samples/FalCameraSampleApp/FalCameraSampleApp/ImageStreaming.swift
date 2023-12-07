import UIKit

protocol ImageStreamingDelegate: AnyObject {
    func didReceive(image: UIImage)

    func didUpdate(fps: Double)

    func willProcess(image: UIImage)
}

// class ImageStreaming {
//    private var processedBuffer: [UIImage] = []
//    private let processedQueue = DispatchQueue(label: "ai.fal.realtime.processed", attributes: .concurrent)
//
//    private var lastFrameTime = DispatchTime.now()
//    private var lastProcessTime = DispatchTime.now()
//    private var targetFPS: Double
//    private var targetFrameInterval: Double {
//        1.0 / targetFPS
//    }
//
//    weak var delegate: ImageStreamingDelegate?
//
//    init(targetFPS: Double = 30.0) {
//        self.targetFPS = targetFPS
//    }
//
//    func process(image: UIImage) {
//        let currentTime = DispatchTime.now()
//        let timeSinceLastProcess = Double(currentTime.uptimeNanoseconds - lastProcessTime.uptimeNanoseconds) / 1_000_000_000
//
//        // Rate limiting based on the processing capacity
//        if timeSinceLastProcess >= targetFrameInterval {
//            lastProcessTime = currentTime
//            DispatchQueue.main.async {
//                self.delegate?.willProcess(image: image)
//            }
//            // The actual image processing should be done externally and `doneProcessing(image:)` called afterward
//        }
//    }
//
//    func doneProcessing(image: UIImage) {
//        processedQueue.async(flags: .barrier) {
//            self.processedBuffer.append(image)
//            self.sendNextProcessedFrameIfReady()
//        }
//    }
//
//    private func sendNextProcessedFrameIfReady() {
//        let currentTime = DispatchTime.now()
//        let timeSinceLastFrame = Double(currentTime.uptimeNanoseconds - lastFrameTime.uptimeNanoseconds) / 1_000_000_000
//
//        if timeSinceLastFrame >= targetFrameInterval, !processedBuffer.isEmpty {
//            let imageToSend = processedBuffer.removeFirst()
//            lastFrameTime = currentTime
//            DispatchQueue.main.async {
//                self.notifyCurrentFPS()
//                self.delegate?.didReceive(image: imageToSend)
//            }
//        }
//    }
//
//    private func notifyCurrentFPS() {
//        let currentTime = DispatchTime.now()
//        let timeInterval = Double(currentTime.uptimeNanoseconds - lastFrameTime.uptimeNanoseconds) / 1_000_000_000
//        if timeInterval > 0 {
//            let currentFPS = 1.0 / timeInterval
//            self.delegate?.didUpdate(fps: currentFPS)
//        }
//    }
// }

class ImageStreaming {
    private let maxBufferSize = 60

    private var incomingBuffer: [UIImage] = []
    private var processedBuffer: [UIImage] = []

    private let processingQueue = DispatchQueue(label: "ai.fal.realtime.processing", attributes: .concurrent)
    private let processedQueue = DispatchQueue(label: "ai.fal.realtime.processed", attributes: .concurrent)

    private var lastFrameTime = DispatchTime.now()
    private var targetFPS: Double
    private var targetFrameInterval: Double {
        1.0 / targetFPS
    }

    private var lastFrameTimestamp = DispatchTime.now()

    weak var delegate: ImageStreamingDelegate?

    init(targetFPS: Double = 30.0) {
        self.targetFPS = targetFPS
    }

    func process(image: UIImage) {
        processingQueue.async(flags: .barrier) {
            if self.incomingBuffer.count >= self.maxBufferSize {
                self.incomingBuffer.removeFirst()
            }
            self.incomingBuffer.append(image)
            self.delegate?.willProcess(image: image)
        }
    }

    func doneProcessing(image: UIImage) {
        processedQueue.async(flags: .barrier) {
            if self.processedBuffer.count >= self.maxBufferSize {
                self.processedBuffer.removeFirst()
            }
            self.processedBuffer.append(image)
            self.sendNextProcessedFrameIfReady()
        }
    }

    private func sendNextProcessedFrameIfReady() {
        let currentTime = DispatchTime.now()
        let timeSinceLastFrame = Double(currentTime.uptimeNanoseconds - lastFrameTime.uptimeNanoseconds) / 1_000_000_000

        if timeSinceLastFrame >= targetFrameInterval, !processedBuffer.isEmpty {
            let imageToSend = processedBuffer.removeFirst()
            lastFrameTime = DispatchTime.now()
            notifyCurrentFPS()
            DispatchQueue.main.async {
                self.delegate?.didReceive(image: imageToSend)
            }
        }
    }

    private func notifyCurrentFPS() {
        let currentTime = DispatchTime.now()
        let timeInterval = Double(currentTime.uptimeNanoseconds - lastFrameTimestamp.uptimeNanoseconds) / 1_000_000_000
        lastFrameTimestamp = currentTime

        if timeInterval > 0 {
            let currentFPS = 1.0 / timeInterval
            DispatchQueue.main.async {
                self.delegate?.didUpdate(fps: currentFPS)
            }
        }
    }
}
