import AVFoundation
import CoreGraphics
import Foundation
import SwiftUI

let maxFrameRate = 60.0

func imageFromSampleBuffer(sampleBuffer: CMSampleBuffer) -> UIImage? {
    guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
    let ciImage = CIImage(cvImageBuffer: imageBuffer)

    // Perform cropping to a centered square
    let context = CIContext(options: nil)
    let imageSize = ciImage.extent.size
    let length = min(imageSize.width, imageSize.height)
    let originX = (imageSize.width - length) / 2
    let originY = (imageSize.height - length) / 2
    let cropRect = CGRect(x: originX, y: originY, width: length, height: length).integral

    guard let croppedCGImage = context.createCGImage(ciImage, from: cropRect) else { return nil }
    let scale = length / 512
    return UIImage(
        cgImage: croppedCGImage,
        scale: scale,
        orientation: .up
    )
}

extension UIDeviceOrientation {
    var videoOrientation: AVCaptureVideoOrientation {
        switch self {
        case .unknown, .portrait, .faceUp:
            return .portrait
        case .portraitUpsideDown, .faceDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        @unknown default:
            return .portrait
        }
    }
}

protocol CameraFrameDelegate: AnyObject {
    func didCaptureFrame(_ image: UIImage)
}

class CameraViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    weak var frameDelegate: CameraFrameDelegate?

    private var permissionGranted = false
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "sessionQueue")
    private var previewLayer = AVCaptureVideoPreviewLayer()
    var viewRect: CGRect! = nil

    // Frame rate limiting properties
    private var lastFrameTime = Date()
    private let frameProcessingInterval: TimeInterval = 1.0 / maxFrameRate
    private var frameCount = 0

    override func viewDidLoad() {
        checkPermission()

        sessionQueue.async { [unowned self] in
            guard permissionGranted else { return }
            setupCaptureSession()
            captureSession.startRunning()
        }
    }

    override func willTransition(to _: UITraitCollection, with _: UIViewControllerTransitionCoordinator) {
        viewRect = view.bounds
        previewLayer.frame = CGRect(x: 0, y: 0, width: viewRect.size.width, height: viewRect.size.height)
        previewLayer.connection?.videoOrientation = UIDevice.current.orientation.videoOrientation
    }

    func captureOutput(_: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from _: AVCaptureConnection) {
        let currentTime = Date()
        let elapsedTime = currentTime.timeIntervalSince(lastFrameTime)

        if elapsedTime >= frameProcessingInterval {
            lastFrameTime = currentTime

            // Process the frame
            if let image = imageFromSampleBuffer(sampleBuffer: sampleBuffer) {
                DispatchQueue.main.async {
                    self.frameDelegate?.didCaptureFrame(image)
                }
            }

            // Increment frame count
            frameCount += 1
        }
    }

    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        // Permission has been granted before
        case .authorized:
            permissionGranted = true

        // Permission has not been requested yet
        case .notDetermined:
            requestPermission()

        default:
            permissionGranted = false
        }
    }

    func requestPermission() {
        sessionQueue.suspend()
        AVCaptureDevice.requestAccess(for: .video) { [unowned self] granted in
            permissionGranted = granted
            sessionQueue.resume()
        }
    }

    func setupCaptureSession() {
        // Camera input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else { return }
        guard let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice) else { return }

        guard captureSession.canAddInput(videoDeviceInput) else { return }
        captureSession.addInput(videoDeviceInput)

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "outputQueue"))
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        } else {
            return
        }

        // Updates to UI must be on main queue
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            // Preview layer
            let sideLength = min(self.view.bounds.width, self.view.bounds.height)
            let offsetX = (self.view.bounds.width - sideLength) / 2
            let offsetY = (self.view.bounds.height - sideLength) / 2

            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.bounds = CGRect(x: 0, y: 0, width: sideLength, height: sideLength)
            previewLayer.position = CGPoint(x: self.view.bounds.midX, y: self.view.bounds.midY)
            previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
            previewLayer.connection?.videoOrientation = UIDevice.current.orientation.videoOrientation
            self.view.layer.addSublayer(self.previewLayer)

            // Crop the preview layer to 512x512
            previewLayer.masksToBounds = true
            let scale = 512 / sideLength
            previewLayer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
            previewLayer.frame = CGRect(x: offsetX, y: offsetY, width: 512, height: 512)
        }
    }
}

struct CameraView: UIViewControllerRepresentable {
    @Binding var currentFrame: UIImage?

    func makeUIViewController(context: Context) -> UIViewController {
        let cameraViewController = CameraViewController()
        cameraViewController.frameDelegate = context.coordinator
        return cameraViewController
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, CameraFrameDelegate {
        var parent: CameraView

        init(_ parent: CameraView) {
            self.parent = parent
        }

        func didCaptureFrame(_ image: UIImage) {
            parent.currentFrame = image
        }
    }
}
