import AVFoundation
import Foundation

final class PostureController {
    private let cameraService = CameraCaptureService()
    private let microphoneMonitor = MicrophoneActivityMonitor()
    private let baselineStore = BaselineStore()
    private let historyStore = PostureHistoryStore()
    private let soundAlert = PostureSoundAlert()
    private let statusBar = StatusBarController()

    private var classifier = PostureClassifier()
    private var cameras: [CameraDescriptor] = []
    private var selectedCameraID: String?
    private var selectedCameraName: String?
    private var displayState: PostureDisplayState = .starting
    private var userPaused = false
    private var pauseUntil: Date?
    private var microphoneActive = false
    private var cameraUsedElsewhere = false
    private var captureRunning = false
    private var permissionDenied = false
    private var missingPoseCount = 0
    private var nextRetryDate: Date?
    private var maintenanceTimer: Timer?
    private var maintenanceTickCount = 0

    func start() {
        cameraService.onEvent = { [weak self] event in
            self?.handleCameraEvent(event)
        }
        cameraService.onPose = { [weak self] features in
            self?.handlePose(features)
        }
        microphoneMonitor.onChange = { [weak self] isActive in
            guard let self else { return }
            self.microphoneActive = isActive
            self.reevaluateCapture()
        }

        statusBar.onToggleMonitoring = { [weak self] in
            self?.toggleMonitoring()
        }
        statusBar.onPauseForThirtyMinutes = { [weak self] in
            self?.pauseForThirtyMinutes()
        }
        statusBar.onRecalibrate = { [weak self] in
            self?.recalibrate()
        }
        statusBar.onToggleSoundAlerts = { [weak self] in
            self?.toggleSoundAlerts()
        }
        statusBar.onSelectSoundAlertDelay = { [weak self] delay in
            self?.selectSoundAlertDelay(delay)
        }
        statusBar.onSelectCamera = { [weak self] cameraID in
            self?.selectCamera(cameraID)
        }
        statusBar.onMenuWillOpen = { [weak self] in
            self?.refreshCameras()
        }
        statusBar.setHistoryProvider { [weak self] in
            self?.historyStore.binnedStates(count: 120) ?? []
        }
        updateSoundAlertMenu()

        refreshCameras()
        microphoneMonitor.start()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.maintenanceTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        maintenanceTimer = timer

        reevaluateCapture()
    }

    func stop() {
        maintenanceTimer?.invalidate()
        maintenanceTimer = nil
        historyStore.finish()
        soundAlert.reset()
        microphoneMonitor.stop()
        cameraService.shutdown()
    }

    func resumeMonitoring() {
        userPaused = false
        pauseUntil = nil
        nextRetryDate = nil
        reevaluateCapture()
    }

    private func refreshCameras() {
        let previousCameraID = selectedCameraID
        cameras = CameraCaptureService.availableCameras()

        if selectedCameraID == nil {
            let savedID = baselineStore.selectedCameraID
            if let savedID, cameras.contains(where: { $0.id == savedID }) {
                selectedCameraID = savedID
            } else {
                selectedCameraID = CameraSelectionPolicy.preferredCamera(from: cameras)?.id
            }
        }

        if let selectedCameraID,
           let descriptor = cameras.first(where: { $0.id == selectedCameraID }) {
            selectedCameraName = descriptor.name
            baselineStore.selectedCameraID = descriptor.id
            if previousCameraID != descriptor.id {
                classifier.setBaseline(baselineStore.baseline(for: descriptor.id))
            }
        } else {
            selectedCameraID = nil
            selectedCameraName = nil
        }

        statusBar.updateCameras(cameras, selectedCameraID: selectedCameraID)
        updateDisplay(displayState)
    }

    private func selectCamera(_ cameraID: String) {
        guard cameraID != selectedCameraID,
              let descriptor = cameras.first(where: { $0.id == cameraID }) else {
            return
        }

        cameraService.stop()
        selectedCameraID = descriptor.id
        selectedCameraName = descriptor.name
        baselineStore.selectedCameraID = descriptor.id
        classifier.setBaseline(baselineStore.baseline(for: descriptor.id))
        captureRunning = false
        cameraUsedElsewhere = false
        permissionDenied = false
        nextRetryDate = Date().addingTimeInterval(0.5)
        missingPoseCount = 0
        statusBar.updateCameras(cameras, selectedCameraID: selectedCameraID)
        updateDisplay(.starting)
    }

    private func toggleMonitoring() {
        if userPaused || pauseUntil != nil {
            userPaused = false
            pauseUntil = nil
            nextRetryDate = nil
        } else {
            userPaused = true
        }
        reevaluateCapture()
    }

    private func pauseForThirtyMinutes() {
        userPaused = false
        pauseUntil = Date().addingTimeInterval(30 * 60)
        reevaluateCapture()
    }

    private func recalibrate() {
        guard let selectedCameraID else { return }
        baselineStore.removeBaseline(for: selectedCameraID)
        classifier.recalibrate()
        missingPoseCount = 0

        if captureIsAllowed {
            updateDisplay(.calibrating(
                collected: 0,
                required: PostureClassifier.requiredCalibrationSamples
            ))
        }
    }

    private func toggleSoundAlerts() {
        soundAlert.setEnabled(!soundAlert.isEnabled)
        updateSoundAlertMenu()
    }

    private func selectSoundAlertDelay(_ delay: PostureAlertDelay) {
        soundAlert.setDelay(delay)
        updateSoundAlertMenu()
    }

    private func updateSoundAlertMenu() {
        statusBar.updateSoundAlerts(
            isEnabled: soundAlert.isEnabled,
            delay: soundAlert.delay
        )
    }

    private func maintenanceTick() {
        maintenanceTickCount += 1
        soundAlert.tick()

        if let pauseUntil, pauseUntil <= Date() {
            self.pauseUntil = nil
            nextRetryDate = nil
        }

        if maintenanceTickCount.isMultiple(of: 10) {
            refreshCamerasIfSelectionDisappeared()
        }

        if permissionDenied,
           AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
            permissionDenied = false
            nextRetryDate = nil
        }

        reevaluateCapture()
    }

    private func refreshCamerasIfSelectionDisappeared() {
        guard selectedCameraID == nil
                || !CameraCaptureService.availableCameras().contains(where: { $0.id == selectedCameraID }) else {
            return
        }
        selectedCameraID = nil
        refreshCameras()
    }

    private var captureIsAllowed: Bool {
        guard !userPaused,
              pauseUntil == nil,
              !microphoneActive,
              !cameraUsedElsewhere,
              !permissionDenied,
              selectedCameraID != nil else {
            return false
        }
        return true
    }

    private func reevaluateCapture() {
        if userPaused {
            cameraService.stop()
            captureRunning = false
            updateDisplay(.pausedManually)
            return
        }

        if let pauseUntil, pauseUntil > Date() {
            cameraService.stop()
            captureRunning = false
            updateDisplay(.pausedUntil(pauseUntil))
            return
        }

        if microphoneActive || cameraUsedElsewhere {
            cameraService.stop()
            captureRunning = false
            updateDisplay(.pausedForCall)
            return
        }

        if permissionDenied {
            cameraService.stop()
            captureRunning = false
            updateDisplay(.cameraPermissionDenied)
            return
        }

        guard let selectedCameraID else {
            cameraService.stop()
            captureRunning = false
            updateDisplay(.cameraUnavailable)
            return
        }

        if let nextRetryDate, nextRetryDate > Date() {
            return
        }

        if !captureRunning {
            updateDisplay(.starting)
            cameraService.start(cameraID: selectedCameraID)
        }
    }

    private func handleCameraEvent(_ event: CameraEvent) {
        switch event {
        case .authorizationDenied:
            permissionDenied = true
            captureRunning = false
            updateDisplay(.cameraPermissionDenied)
        case .unavailable:
            captureRunning = false
            nextRetryDate = Date().addingTimeInterval(5)
            updateDisplay(.cameraUnavailable)
        case let .started(camera):
            captureRunning = true
            selectedCameraName = camera.name
            cameraUsedElsewhere = false
            nextRetryDate = nil
            missingPoseCount = 0
            if classifier.baseline == nil {
                updateDisplay(.calibrating(
                    collected: 0,
                    required: PostureClassifier.requiredCalibrationSamples
                ))
            } else {
                updateDisplay(.noPose)
            }
        case .stopped:
            captureRunning = false
        case .interrupted:
            captureRunning = false
            cameraUsedElsewhere = true
            cameraService.stop()
            updateDisplay(.pausedForCall)
        case .interruptionEnded:
            cameraUsedElsewhere = false
            nextRetryDate = Date().addingTimeInterval(1)
        case let .externalUseChanged(isUsedElsewhere):
            cameraUsedElsewhere = isUsedElsewhere
            if isUsedElsewhere {
                captureRunning = false
                cameraService.stop()
            } else {
                nextRetryDate = Date().addingTimeInterval(1)
            }
            reevaluateCapture()
        case let .failed(message):
            captureRunning = false
            nextRetryDate = Date().addingTimeInterval(5)
            updateDisplay(.error(message))
        }
    }

    private func handlePose(_ features: PostureFeatures?) {
        guard captureRunning, captureIsAllowed else { return }

        guard let features else {
            missingPoseCount += 1
            if missingPoseCount >= 10 {
                updateDisplay(.noPose)
            }
            return
        }

        missingPoseCount = 0
        switch classifier.consume(features) {
        case let .calibrating(collected, required):
            updateDisplay(.calibrating(collected: collected, required: required))
        case let .classified(isSlouching, _, didCalibrate):
            if didCalibrate,
               let selectedCameraID,
               let baseline = classifier.baseline {
                baselineStore.save(baseline, for: selectedCameraID)
            }
            updateDisplay(isSlouching ? .slouching : .good)
        }
    }

    private func updateDisplay(_ state: PostureDisplayState) {
        displayState = state
        let historyState = state.historyState
        if historyStore.record(historyState) {
            statusBar.refreshHistory()
        }
        soundAlert.update(isBadPosture: historyState == .bad)
        statusBar.update(state: state, cameraName: selectedCameraName)
    }
}

private extension PostureDisplayState {
    var historyState: PostureHistoryState {
        switch self {
        case .good:
            return .good
        case .slouching:
            return .bad
        default:
            return .noRecording
        }
    }
}
