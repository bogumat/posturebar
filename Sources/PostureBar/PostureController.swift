import AVFoundation
import Foundation

final class PostureController {
    private struct CaptureAttempt: Equatable {
        let cameraID: String
        let generation: UInt64
    }

    private enum CaptureLifecycle {
        case idle
        case starting(CaptureAttempt)
        case running(CaptureAttempt)
        case retrying(until: Date)
        case permissionDenied
    }

    private enum MonitoringMode {
        case active
        case pausedManually
        case pausedUntil(Date)
    }

    private enum CallBlocker: Hashable {
        case microphone
        case camera
    }

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
    private var monitoringMode: MonitoringMode = .active
    private var captureLifecycle: CaptureLifecycle = .idle
    private var callBlockers: Set<CallBlocker> = []
    private var captureGeneration: UInt64 = 0
    private var missingPoseCount = 0
    private var maintenanceTimer: Timer?
    private var maintenanceTickCount = 0

    func start() {
        cameraService.onEvent = { [weak self] event in
            self?.handleCameraEvent(event)
        }
        cameraService.onPose = { [weak self] generation, features in
            self?.handlePose(features, generation: generation)
        }
        microphoneMonitor.onChange = { [weak self] isActive in
            guard let self else { return }
            self.setCallBlocker(.microphone, isActive: isActive)
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
        monitoringMode = .active
        if case .retrying = captureLifecycle {
            captureLifecycle = .idle
        }
        reevaluateCapture()
    }

    private func refreshCameras() {
        let previousCameraID = selectedCameraID
        cameras = CameraCaptureService.availableCameras()

        if let selectedCameraID,
           !cameras.contains(where: { $0.id == selectedCameraID }) {
            invalidateCapture()
            self.selectedCameraID = nil
            selectedCameraName = nil
            callBlockers.remove(.camera)
        }

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

        invalidateCapture()
        selectedCameraID = descriptor.id
        selectedCameraName = descriptor.name
        baselineStore.selectedCameraID = descriptor.id
        classifier.setBaseline(baselineStore.baseline(for: descriptor.id))
        callBlockers.remove(.camera)
        captureLifecycle = .retrying(until: Date().addingTimeInterval(0.5))
        missingPoseCount = 0
        statusBar.updateCameras(cameras, selectedCameraID: selectedCameraID)
        updateDisplay(.starting)
    }

    private func toggleMonitoring() {
        switch monitoringMode {
        case .active:
            monitoringMode = .pausedManually
        case .pausedManually, .pausedUntil:
            monitoringMode = .active
            if case .retrying = captureLifecycle {
                captureLifecycle = .idle
            }
        }
        reevaluateCapture()
    }

    private func pauseForThirtyMinutes() {
        monitoringMode = .pausedUntil(Date().addingTimeInterval(30 * 60))
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

        if case let .pausedUntil(date) = monitoringMode, date <= Date() {
            monitoringMode = .active
            if case .retrying = captureLifecycle {
                captureLifecycle = .idle
            }
        }

        if maintenanceTickCount.isMultiple(of: 10) {
            refreshCamerasIfSelectionDisappeared()
        }

        if case .permissionDenied = captureLifecycle,
           AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
            captureLifecycle = .idle
        }

        reevaluateCapture()
    }

    private func refreshCamerasIfSelectionDisappeared() {
        guard selectedCameraID == nil
                || !CameraCaptureService.availableCameras().contains(where: { $0.id == selectedCameraID }) else {
            return
        }
        refreshCameras()
    }

    private var captureIsAllowed: Bool {
        guard case .active = monitoringMode,
              callBlockers.isEmpty,
              selectedCameraID != nil,
              case .running = captureLifecycle else {
            return false
        }
        return true
    }

    private func reevaluateCapture() {
        switch monitoringMode {
        case .pausedManually:
            stopCaptureIfNeeded()
            updateDisplay(.pausedManually)
            return
        case let .pausedUntil(date) where date > Date():
            stopCaptureIfNeeded()
            updateDisplay(.pausedUntil(date))
            return
        case .pausedUntil:
            monitoringMode = .active
        case .active:
            break
        }

        if !callBlockers.isEmpty {
            stopCaptureIfNeeded()
            updateDisplay(.pausedForCall)
            return
        }

        if case .permissionDenied = captureLifecycle {
            updateDisplay(.cameraPermissionDenied)
            return
        }

        guard let selectedCameraID else {
            stopCaptureIfNeeded()
            updateDisplay(.cameraUnavailable)
            return
        }

        if case let .retrying(until) = captureLifecycle {
            guard until <= Date() else { return }
            captureLifecycle = .idle
        }

        switch captureLifecycle {
        case let .starting(attempt), let .running(attempt):
            guard attempt.cameraID != selectedCameraID else { return }
            invalidateCapture()
        case .idle, .retrying:
            break
        case .permissionDenied:
            return
        }

        captureGeneration &+= 1
        let attempt = CaptureAttempt(
            cameraID: selectedCameraID,
            generation: captureGeneration
        )
        captureLifecycle = .starting(attempt)
        updateDisplay(.starting)
        cameraService.start(
            cameraID: selectedCameraID,
            generation: attempt.generation
        )
    }

    private func stopCaptureIfNeeded() {
        switch captureLifecycle {
        case .starting, .running:
            cameraService.stop()
            captureLifecycle = .idle
        case .retrying:
            captureLifecycle = .idle
        case .idle, .permissionDenied:
            break
        }
    }

    private func invalidateCapture() {
        cameraService.stop()
        captureGeneration &+= 1
        captureLifecycle = .idle
    }

    private func setCallBlocker(_ blocker: CallBlocker, isActive: Bool) {
        if isActive {
            callBlockers.insert(blocker)
        } else {
            callBlockers.remove(blocker)
        }
    }

    private func scheduleRetry(after delay: TimeInterval) {
        captureLifecycle = .retrying(until: Date().addingTimeInterval(delay))
    }

    private func handleCameraEvent(_ event: CameraEvent) {
        guard event.generation == captureGeneration else { return }

        switch event.kind {
        case .authorizationDenied:
            guard case .starting = captureLifecycle else { return }
            captureLifecycle = .permissionDenied
            updateDisplay(.cameraPermissionDenied)
        case .unavailable:
            guard case .starting = captureLifecycle else { return }
            scheduleRetry(after: 5)
            updateDisplay(.cameraUnavailable)
        case let .started(camera):
            guard case let .starting(attempt) = captureLifecycle,
                  attempt.cameraID == camera.id else {
                return
            }
            captureLifecycle = .running(attempt)
            selectedCameraName = camera.name
            callBlockers.remove(.camera)
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
            if case .starting = captureLifecycle {
                captureLifecycle = .idle
            } else if case .running = captureLifecycle {
                captureLifecycle = .idle
            }
        case .interrupted:
            guard isCaptureActive else { return }
            setCallBlocker(.camera, isActive: true)
            stopCaptureIfNeeded()
            updateDisplay(.pausedForCall)
        case .interruptionEnded:
            setCallBlocker(.camera, isActive: false)
            scheduleRetry(after: 1)
        case let .externalUseChanged(isUsedElsewhere):
            let wasBlocked = callBlockers.contains(.camera)
            setCallBlocker(.camera, isActive: isUsedElsewhere)
            if isUsedElsewhere {
                stopCaptureIfNeeded()
            } else if wasBlocked {
                scheduleRetry(after: 1)
            }
            reevaluateCapture()
        case let .failed(message):
            guard isCaptureActive else { return }
            cameraService.stop()
            scheduleRetry(after: 5)
            updateDisplay(.error(message))
        }
    }

    private var isCaptureActive: Bool {
        switch captureLifecycle {
        case .starting, .running:
            return true
        case .idle, .retrying, .permissionDenied:
            return false
        }
    }

    private func handlePose(_ features: PostureFeatures?, generation: UInt64) {
        guard generation == captureGeneration,
              captureIsAllowed else {
            return
        }

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
