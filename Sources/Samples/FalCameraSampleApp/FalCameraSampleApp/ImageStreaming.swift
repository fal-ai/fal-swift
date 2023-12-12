import UIKit

protocol ImageStreamingDelegate: AnyObject {
    func didReceive(image: UIImage)

    func didUpdate(fps: Double)

    func willProcess(image: UIImage)
}

struct ImageFrame {
    let image: UIImage
    let timestamp: DispatchTime

    static func from(image: UIImage) -> Self {
        ImageFrame(image: image, timestamp: .now())
    }
}

enum TargetSize {
    case square

    var dimensions: CGSize {
        switch self {
        case .square:
            return CGSize(width: 512, height: 512)
        }
    }
}

extension UIImage {
    func resize(to targetSize: TargetSize) -> UIImage? {
        guard let image = cgImage else {
            return nil
        }
        let dimensions = targetSize.dimensions
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: image.bitmapInfo.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .default
        context.draw(image, in: CGRect(origin: .zero, size: size))
        context.scaleBy(x: dimensions.width / size.width, y: dimensions.height / size.height)

        guard let scaledImage = context.makeImage() else { return nil }

        // https://developer.apple.com/documentation/coregraphics/cgcontext/1456228-rotate#discussion
        return UIImage(cgImage: scaledImage, scale: 1.0, orientation: imageOrientation).correctImageOrientation()
    }

    func correctImageOrientation() -> UIImage? {
        guard let cgImage else { return nil }

        switch imageOrientation {
        case .up:
            return self
        default:
            UIGraphicsBeginImageContextWithOptions(size, false, scale)
            draw(in: CGRect(origin: .zero, size: size))
            let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return normalizedImage
        }
    }
}

class ImageStreaming {
    private let incomingQueue = DispatchQueue(label: "ai.fal.imagestreaming.incoming", attributes: .concurrent)
    private let processingQueue = DispatchQueue(label: "ai.fal.imagestreaming.processing", attributes: .concurrent)
    private var incomingBuffer: [ImageFrame] = []

    private var lastIncomingTime = DispatchTime.now()
    private var lastProcessedTime = DispatchTime.now()
    private var processedFrameCount = 0
    private var targetFPS: Double
    private var frameDropThreshold: Double
    private var lastSubmittedFrame: ImageFrame?

    weak var delegate: ImageStreamingDelegate?

    init(targetFPS: Double = 40, frameDropThreshold: Double = 0.1) {
        self.targetFPS = targetFPS
        self.frameDropThreshold = frameDropThreshold
    }

    func process(image: UIImage) {
        lastIncomingTime = .now()
        let frame = ImageFrame.from(image: image)
        lastSubmittedFrame = frame

        incomingQueue.async {
            self.incomingBuffer.append(frame)
            self.processNextImage()
        }
    }

    private func processNextImage() {
        processingQueue.async(flags: .barrier) {
            guard !self.incomingBuffer.isEmpty else { return }

            let currentTime = DispatchTime.now()
            let nextFrame = self.incomingBuffer.removeFirst()

            let timeElapsed = Double(currentTime.uptimeNanoseconds - nextFrame.timestamp.uptimeNanoseconds) / 1_000_000_000
            if timeElapsed <= self.frameDropThreshold {
                DispatchQueue.main.async {
                    self.delegate?.willProcess(image: nextFrame.image)
                }
            }

            // Check if additional frame needs to be sent
            self.checkAndSendAdditionalFrame()
        }
    }

    func doneProcessing(image: UIImage) {
        processedFrameCount += 1
        notifyCurrentFPS()
        DispatchQueue.main.async {
            self.delegate?.didReceive(image: image)
        }
    }

    private func notifyCurrentFPS() {
        let currentTime = DispatchTime.now()
        let timeInterval = Double(currentTime.uptimeNanoseconds - lastProcessedTime.uptimeNanoseconds) / 1_000_000_000
        lastProcessedTime = currentTime

        if timeInterval > 0 {
            let currentFPS = 1.0 / timeInterval
            DispatchQueue.main.async {
                self.delegate?.didUpdate(fps: currentFPS)
            }
        }
    }

    private func checkAndSendAdditionalFrame() {
        // The input FPS is 30% higher than target FPS so we send more frames than what we want to achieve as output
        let desiredFPS = targetFPS * 1.3
        let currentTime = DispatchTime.now()
        let fps = 1.0 / (Double(currentTime.uptimeNanoseconds - lastIncomingTime.uptimeNanoseconds) / 1_000_000_000)

        if fps < desiredFPS, let lastFrame = lastSubmittedFrame {
            // Resend the last submitted frame
            DispatchQueue.main.async {
                self.delegate?.willProcess(image: lastFrame.image)
            }
        }
    }
}
