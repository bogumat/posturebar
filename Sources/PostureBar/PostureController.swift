import AppKit
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
    private var retryTimer: Timer?
    private var pauseTimer: Timer?
    private var systemNotificationTokens: [NSObjectProtocol] = []
    private var displayedCameraName: String?
    private var recordedHistoryState: PostureHistoryState?
    private var lastHistoryRecordAt: Date?

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
            self?.refreshExternalState()
        }
        statusBar.setHistoryProvider { [weak self] in
            self?.historyStore.binnedStates(count: 120) ?? []
        }
        updateSoundAlertMenu()

        refreshCameras()
        observeSystemChanges()
        microphoneMonitor.start()
        reevaluateCapture()
    }

    func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        pauseTimer?.invalidate()
        pauseTimer = nil
        let center = NotificationCenter.default
        systemNotificationTokens.forEach(center.removeObserver)
        systemNotificationTokens.removeAll()
        historyStore.finish()
        soundAlert.reset()
        microphoneMonitor.stop()
        cameraService.shutdown()
    }

    func resumeMonitoring() {
        monitoringMode = .active
        pauseTimer?.invalidate()
        pauseTimer = nil
        if case .retrying = captureLifecycle {
            retryTimer?.invalidate()
            retryTimer = nil
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
        scheduleRetry(after: 0.5)
        missingPoseCount = 0
        statusBar.updateCameras(cameras, selectedCameraID: selectedCameraID)
        updateDisplay(.starting)
    }

    private func toggleMonitoring() {
        switch monitoringMode {
        case .active:
            monitoringMode = .pausedManually
            pauseTimer?.invalidate()
            pauseTimer = nil
        case .pausedManually, .pausedUntil:
            monitoringMode = .active
            pauseTimer?.invalidate()
            pauseTimer = nil
            if case .retrying = captureLifecycle {
                retryTimer?.invalidate()
                retryTimer = nil
                captureLifecycle = .idle
            }
        }
        reevaluateCapture()
    }

    private func pauseForThirtyMinutes() {
        let date = Date().addingTimeInterval(30 * 60)
        monitoringMode = .pausedUntil(date)
        schedulePauseExpiration(at: date)
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

    private func observeSystemChanges() {
        let center = NotificationCenter.default
        let cameraNotifications: [Notification.Name] = [
            AVCaptureDevice.wasConnectedNotification,
            AVCaptureDevice.wasDisconnectedNotification
        ]

        for name in cameraNotifications {
            systemNotificationTokens.append(center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refreshExternalState()
            })
        }

        systemNotificationTokens.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshExternalState()
        })
    }

    private func refreshExternalState() {
        if case .permissionDenied = captureLifecycle,
           AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
            captureLifecycle = .idle
        }
        refreshCameras()
        reevaluateCapture()
    }

    private func schedulePauseExpiration(at date: Date) {
        pauseTimer?.invalidate()
        let timer = Timer(fireAt: date, interval: 0, target: self,
                          selector: #selector(finishTimedPause), userInfo: nil, repeats: false)
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        pauseTimer = timer
    }

    @objc private func finishTimedPause() {
        pauseTimer = nil
        guard case let .pausedUntil(date) = monitoringMode,
              date <= Date() else {
            return
        }
        monitoringMode = .active
        reevaluateCapture()
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
            pauseTimer?.invalidate()
            pauseTimer = nil
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
            retryTimer?.invalidate()
            retryTimer = nil
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
            retryTimer?.invalidate()
            retryTimer = nil
            captureLifecycle = .idle
        case .idle, .permissionDenied:
            break
        }
    }

    private func invalidateCapture() {
        cameraService.stop()
        retryTimer?.invalidate()
        retryTimer = nil
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
        retryTimer?.invalidate()
        let date = Date().addingTimeInterval(delay)
        captureLifecycle = .retrying(until: date)

        let timer = Timer(fireAt: date, interval: 0, target: self,
                          selector: #selector(finishRetryDelay), userInfo: nil, repeats: false)
        timer.tolerance = min(0.25, delay * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
    }

    @objc private func finishRetryDelay() {
        retryTimer = nil
        guard case let .retrying(until) = captureLifecycle,
              until <= Date() else {
            return
        }
        captureLifecycle = .idle
        reevaluateCapture()
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
            let date = Date()
            soundAlert.update(isBadPosture: isSlouching, at: date)
            if didCalibrate,
               let selectedCameraID,
               let baseline = classifier.baseline {
                baselineStore.save(baseline, for: selectedCameraID)
            }
            updateDisplay(isSlouching ? .slouching : .good, at: date)
        }
    }

    private func updateDisplay(_ state: PostureDisplayState, at date: Date = Date()) {
        let historyState = state.historyState
        recordHistoryIfNeeded(historyState, at: date)

        let stateChanged = state != displayState
        let cameraChanged = selectedCameraName != displayedCameraName
        guard stateChanged || cameraChanged else { return }

        if stateChanged, historyState == .noRecording {
            soundAlert.update(isBadPosture: false, at: date)
        }

        displayState = state
        displayedCameraName = selectedCameraName
        statusBar.update(state: state, cameraName: selectedCameraName)
    }

    private func recordHistoryIfNeeded(
        _ state: PostureHistoryState,
        at date: Date
    ) {
        let stateChanged = state != recordedHistoryState
        let heartbeatDue = lastHistoryRecordAt.map {
            date.timeIntervalSince($0) >= PostureHistoryStore.heartbeatInterval
        } ?? true
        guard stateChanged || heartbeatDue else { return }

        if historyStore.record(state, at: date) {
            statusBar.refreshHistory()
        }
        recordedHistoryState = state
        lastHistoryRecordAt = date
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
