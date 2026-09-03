import AVFoundation
import CoreVideo
import Foundation

enum CameraEvent {
    case authorizationDenied
    case unavailable
    case started(CameraDescriptor)
    case stopped
    case interrupted
    case interruptionEnded
    case externalUseChanged(Bool)
    case failed(String)
}

final class CameraCaptureService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private static let captureFramesPerSecond: Int32 = 10
    private static let analysisInterval: TimeInterval = 0.20

    var onEvent: ((CameraEvent) -> Void)?
    var onPose: ((PostureFeatures?) -> Void)?

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
    private var requestedCameraID: String?
    private var wantsToRun = false
    private var lastAnalysisTime: TimeInterval = 0

    static func availableCameras() -> [CameraDescriptor] {
        discoverySession().devices.map(makeDescriptor)
    }

    func start(cameraID: String) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.wantsToRun = true
            self.requestedCameraID = cameraID
            self.startAfterAuthorization()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.wantsToRun || self.session?.isRunning == true else { return }
            self.wantsToRun = false
            if self.session?.isRunning == true {
                self.session?.stopRunning()
            }
            self.emit(.stopped)
        }
    }

    func shutdown() {
        sessionQueue.sync {
            wantsToRun = false
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

    private func startAfterAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startConfiguredSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                self?.sessionQueue.async {
                    guard let self, self.wantsToRun else { return }
                    if granted {
                        self.startConfiguredSession()
                    } else {
                        self.wantsToRun = false
                        self.emit(.authorizationDenied)
                    }
                }
            }
        case .denied, .restricted:
            wantsToRun = false
            emit(.authorizationDenied)
        @unknown default:
            wantsToRun = false
            emit(.authorizationDenied)
        }
    }

    private func startConfiguredSession() {
        guard wantsToRun, let requestedCameraID else { return }

        if selectedDevice?.uniqueID != requestedCameraID || session == nil {
            guard configureSession(cameraID: requestedCameraID) else { return }
        }

        guard let device = selectedDevice,
              let session,
              let descriptor = selectedDescriptor else {
            wantsToRun = false
            emit(.unavailable)
            return
        }

        guard !device.isInUseByAnotherApplication else {
            wantsToRun = false
            emit(.externalUseChanged(true))
            return
        }

        guard !session.isRunning else { return }
        lastAnalysisTime = 0
        session.startRunning()

        if session.isRunning {
            emit(.started(descriptor))
        } else {
            wantsToRun = false
            emit(.failed("The camera did not start"))
        }
    }

    private func configureSession(cameraID: String) -> Bool {
        if session?.isRunning == true {
            session?.stopRunning()
        }
        removeSessionObservers()
        deviceUseObservation = nil

        guard let device = Self.discoverySession().devices.first(where: { $0.uniqueID == cameraID }) else {
            wantsToRun = false
            emit(.unavailable)
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
                wantsToRun = false
                emit(.failed("The selected camera does not support video capture"))
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
            observeDeviceUse(device)
            observeSession(newSession)
            return true
        } catch {
            wantsToRun = false
            emit(.failed(error.localizedDescription))
            return false
        }
    }

    private func observeDeviceUse(_ device: AVCaptureDevice) {
        deviceUseObservation = device.observe(
            \.isInUseByAnotherApplication,
            options: [.initial, .new]
        ) { [weak self] _, change in
            guard let isUsedElsewhere = change.newValue else { return }
            self?.emit(.externalUseChanged(isUsedElsewhere))
        }
    }

    private func observeSession(_ session: AVCaptureSession) {
        let center = NotificationCenter.default

        notificationTokens.append(center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            self?.emit(.interrupted)
        })

        notificationTokens.append(center.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            self?.emit(.interruptionEnded)
        })

        notificationTokens.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
            self?.emit(.failed(error?.localizedDescription ?? "Camera runtime error"))
        })
    }

    private func removeSessionObservers() {
        let center = NotificationCenter.default
        notificationTokens.forEach(center.removeObserver)
        notificationTokens.removeAll(keepingCapacity: true)
    }

    private func emit(_ event: CameraEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
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
        let features = poseDetector.detect(in: pixelBuffer)
        DispatchQueue.main.async { [weak self] in
            self?.onPose?(features)
        }
    }
}
