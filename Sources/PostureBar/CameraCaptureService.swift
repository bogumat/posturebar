import AVFoundation
import CoreVideo
import Foundation

enum CameraEventKind {
    case authorizationDenied
    case unavailable
    case started(CameraDescriptor)
    case stopped
    case interrupted
    case interruptionEnded
    case externalUseChanged(Bool)
    case failed(String)
}

struct CameraEvent {
    let generation: UInt64
    let kind: CameraEventKind
}

final class CameraCaptureService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private struct CaptureRequest: Equatable {
        let cameraID: String
        let generation: UInt64
    }

    private static let captureFramesPerSecond: Int32 = 10
    private static let analysisInterval: TimeInterval = 0.20

    var onEvent: ((CameraEvent) -> Void)?
    var onPose: ((UInt64, PostureFeatures?) -> Void)?

    private let sessionQueue = DispatchQueue(label: "PostureBar.capture.session")
    private let sampleQueue = DispatchQueue(
        label: "PostureBar.capture.frames",
        qos: .utility,
        autoreleaseFrequency: .workItem
    )
    // Creating a Vision body-pose request can load a sizeable model. Defer that
    // work until the camera produces the first frame so paused/no-camera states
    // stay genuinely idle.
    private lazy var poseDetector = PoseDetector()

    private var session: AVCaptureSession?
    private var selectedDevice: AVCaptureDevice?
    private var selectedDescriptor: CameraDescriptor?
    private var deviceUseObservation: NSKeyValueObservation?
    private var notificationTokens: [NSObjectProtocol] = []
    private var requestedCapture: CaptureRequest?
    private var sessionGeneration: UInt64 = 0
    private var frameGeneration: UInt64 = 0
    private var lastAnalysisTime: TimeInterval = 0

    static func availableCameras() -> [CameraDescriptor] {
        discoverySession().devices.map(makeDescriptor)
    }

    func start(cameraID: String, generation: UInt64) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let request = CaptureRequest(cameraID: cameraID, generation: generation)
            guard self.requestedCapture != request || self.session?.isRunning != true else {
                return
            }
            self.requestedCapture = request
            self.startAfterAuthorization(request)
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.requestedCapture != nil || self.session?.isRunning == true else { return }
            let generation = self.requestedCapture?.generation ?? self.sessionGeneration
            self.requestedCapture = nil
            if self.session?.isRunning == true {
                self.session?.stopRunning()
            }
            self.emit(.stopped, generation: generation)
        }
    }

    func shutdown() {
        sessionQueue.sync {
            requestedCapture = nil
            if session?.isRunning == true {
                session?.stopRunning()
            }
            removeSessionObservers()
            deviceUseObservation = nil
            session = nil
            selectedDevice = nil
            selectedDescriptor = nil
        }
    }

    private func startAfterAuthorization(_ request: CaptureRequest) {
        guard requestedCapture == request else { return }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startConfiguredSession(request)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                self?.sessionQueue.async {
                    guard let self, self.requestedCapture == request else { return }
                    if granted {
                        self.startConfiguredSession(request)
                    } else {
                        self.requestedCapture = nil
                        self.emit(.authorizationDenied, generation: request.generation)
                    }
                }
            }
        case .denied, .restricted:
            requestedCapture = nil
            emit(.authorizationDenied, generation: request.generation)
        @unknown default:
            requestedCapture = nil
            emit(.authorizationDenied, generation: request.generation)
        }
    }

    private func startConfiguredSession(_ request: CaptureRequest) {
        guard requestedCapture == request else { return }

        if selectedDevice?.uniqueID != request.cameraID || session == nil {
            guard configureSession(for: request) else { return }
        } else {
            prepareFrameProcessing(generation: request.generation)
            removeSessionObservers()
            deviceUseObservation = nil
            if let device = selectedDevice, let session {
                observeDeviceUse(device, generation: request.generation)
                observeSession(session, generation: request.generation)
            }
        }

        guard let device = selectedDevice,
              let session,
              let descriptor = selectedDescriptor else {
            requestedCapture = nil
            emit(.unavailable, generation: request.generation)
            return
        }

        guard !device.isInUseByAnotherApplication else {
            requestedCapture = nil
            emit(.externalUseChanged(true), generation: request.generation)
            return
        }

        guard !session.isRunning else { return }
        session.startRunning()

        if session.isRunning {
            emit(.started(descriptor), generation: request.generation)
        } else {
            requestedCapture = nil
            emit(.failed("The camera did not start"), generation: request.generation)
        }
    }

    private func configureSession(for request: CaptureRequest) -> Bool {
        if session?.isRunning == true {
            session?.stopRunning()
        }
        removeSessionObservers()
        deviceUseObservation = nil

        guard let device = Self.discoverySession().devices.first(where: {
            $0.uniqueID == request.cameraID
        }) else {
            requestedCapture = nil
            emit(.unavailable, generation: request.generation)
            return false
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
            output.setSampleBufferDelegate(self, queue: sampleQueue)

            let newSession = AVCaptureSession()
            newSession.beginConfiguration()
            if newSession.canSetSessionPreset(.low) {
                newSession.sessionPreset = .low
            }
            guard newSession.canAddInput(input), newSession.canAddOutput(output) else {
                newSession.commitConfiguration()
                requestedCapture = nil
                emit(
                    .failed("The selected camera does not support video capture"),
                    generation: request.generation
                )
                return false
            }
            newSession.addInput(input)
            newSession.addOutput(output)
            newSession.commitConfiguration()

            // Ten low-resolution camera frames per second gives the five-Hz
            // analyzer fresh input without paying for a full 30/60 FPS stream.
            if let connection = output.connection(with: .video),
               connection.isVideoMinFrameDurationSupported {
                connection.videoMinFrameDuration = CMTime(
                    value: 1,
                    timescale: Self.captureFramesPerSecond
                )
            }

            let descriptor = Self.makeDescriptor(device)

            selectedDevice = device
            selectedDescriptor = descriptor
            session = newSession
            prepareFrameProcessing(generation: request.generation)
            observeDeviceUse(device, generation: request.generation)
            observeSession(newSession, generation: request.generation)
            return true
        } catch {
            requestedCapture = nil
            emit(.failed(error.localizedDescription), generation: request.generation)
            return false
        }
    }

    private func prepareFrameProcessing(generation: UInt64) {
        sessionGeneration = generation
        sampleQueue.sync {
            frameGeneration = generation
            lastAnalysisTime = 0
        }
    }

    private func observeDeviceUse(_ device: AVCaptureDevice, generation: UInt64) {
        deviceUseObservation = device.observe(
            \.isInUseByAnotherApplication,
            options: [.initial, .new]
        ) { [weak self] _, change in
            guard let isUsedElsewhere = change.newValue else { return }
            self?.emit(.externalUseChanged(isUsedElsewhere), generation: generation)
        }
    }

    private func observeSession(_ session: AVCaptureSession, generation: UInt64) {
        let center = NotificationCenter.default

        notificationTokens.append(center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            self?.emit(.interrupted, generation: generation)
        })

        notificationTokens.append(center.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            self?.emit(.interruptionEnded, generation: generation)
        })

        notificationTokens.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
            self?.emit(
                .failed(error?.localizedDescription ?? "Camera runtime error"),
                generation: generation
            )
        })
    }

    private func removeSessionObservers() {
        let center = NotificationCenter.default
        notificationTokens.forEach(center.removeObserver)
        notificationTokens.removeAll(keepingCapacity: true)
    }

    private func emit(_ kind: CameraEventKind, generation: UInt64) {
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(CameraEvent(generation: generation, kind: kind))
        }
    }

    private static func discoverySession() -> AVCaptureDevice.DiscoverySession {
        var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(macOS 14.0, *) {
            deviceTypes.append(.external)
        } else {
            deviceTypes.append(.externalUnknown)
        }

        return AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        )
    }

    private static func makeDescriptor(_ device: AVCaptureDevice) -> CameraDescriptor {
        let isExternal: Bool
        if #available(macOS 14.0, *) {
            isExternal = device.deviceType == .external
        } else {
            isExternal = device.deviceType == .externalUnknown
        }

        return CameraDescriptor(
            id: device.uniqueID,
            name: device.localizedName,
            isExternal: isExternal
        )
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastAnalysisTime >= Self.analysisInterval,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        lastAnalysisTime = now
        let generation = frameGeneration
        let features = poseDetector.detect(in: pixelBuffer)
        DispatchQueue.main.async { [weak self] in
            self?.onPose?(generation, features)
        }
    }
}
