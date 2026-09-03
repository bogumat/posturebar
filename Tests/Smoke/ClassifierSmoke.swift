import Foundation

@main
struct ClassifierSmoke {
    static func main() {
        let upright = PostureFeatures(
            headY: 0.62,
            headSize: 0.20
        )
        let slouch = PostureFeatures(
            headY: 0.55,
            headSize: 0.24
        )
        let classifier = PostureClassifier()

        for _ in 0..<PostureClassifier.requiredCalibrationSamples {
            _ = classifier.consume(upright)
        }
        precondition(classifier.baseline != nil, "Calibration should produce a baseline")

        var slouchResult = classifier.consume(slouch)
        for _ in 0..<8 {
            slouchResult = classifier.consume(slouch)
        }
        guard case let .classified(isSlouching, score, _) = slouchResult else {
            preconditionFailure("Expected a slouch classification")
        }
        precondition(isSlouching && score > 1, "Sustained slouch should trigger")

        var uprightResult = classifier.consume(upright)
        for _ in 0..<12 {
            uprightResult = classifier.consume(upright)
        }
        guard case let .classified(hasRecovered, _, _) = uprightResult else {
            preconditionFailure("Expected an upright classification")
        }
        precondition(!hasRecovered, "Sustained upright posture should recover")

        testAlertVolumeRamp()
        testStalePostureStopsAlerts()
        testPostureHistory()
        testCameraPreference()

        print("PostureBar smoke tests passed")
    }

    private static func testCameraPreference() {
        let builtIn = CameraDescriptor(
            id: "built-in",
            name: "UGREEN Camera",
            isExternal: false
        )
        let external = CameraDescriptor(
            id: "usb",
            name: "Any USB Webcam",
            isExternal: true
        )

        precondition(
            CameraSelectionPolicy.preferredCamera(from: [builtIn, external]) == external,
            "An external webcam should be preferred regardless of its brand"
        )
        precondition(
            CameraSelectionPolicy.preferredCamera(from: [builtIn]) == builtIn,
            "The first available camera should be used as a fallback"
        )
        precondition(CameraSelectionPolicy.preferredCamera(from: []) == nil)
    }

    private static func testAlertVolumeRamp() {
        precondition(
            PostureAlertPolicy.volume(afterBadPosture: 9.99) == nil,
            "Alerts should remain silent for the first ten seconds"
        )

        let initialVolume = PostureAlertPolicy.volume(afterBadPosture: 10)!
        let middleVolume = PostureAlertPolicy.volume(afterBadPosture: 65)!
        let maximumVolume = PostureAlertPolicy.volume(afterBadPosture: 120)!
        let laterVolume = PostureAlertPolicy.volume(afterBadPosture: 300)!

        precondition(abs(initialVolume - 0.05) < 0.001)
        precondition(middleVolume > initialVolume)
        precondition(maximumVolume > middleVolume)
        precondition(abs(maximumVolume - 0.90) < 0.001)
        precondition(abs(laterVolume - maximumVolume) < 0.001)

        for delay in PostureAlertDelay.allCases {
            precondition(
                PostureAlertPolicy.volume(
                    afterBadPosture: delay.duration - 0.01,
                    initialDelay: delay.duration
                ) == nil
            )
            precondition(
                PostureAlertPolicy.volume(
                    afterBadPosture: delay.duration,
                    initialDelay: delay.duration
                ) != nil
            )
        }
    }

    private static func testStalePostureStopsAlerts() {
        let start = Date(timeIntervalSinceReferenceDate: 20_000)
        var tracker = PostureAlertTracker()

        tracker.observeBadPosture(at: start)
        tracker.observeBadPosture(at: start.addingTimeInterval(0.8))
        precondition(
            tracker.nextVolume(
                at: start.addingTimeInterval(1),
                delay: .oneSecond
            ) != nil,
            "Fresh bad-posture observations should allow an alert"
        )

        precondition(
            tracker.nextVolume(
                at: start.addingTimeInterval(2.31),
                delay: .oneSecond
            ) == nil,
            "A stale posture observation must stop alerts"
        )

        tracker.observeBadPosture(at: start.addingTimeInterval(2.4))
        precondition(
            tracker.nextVolume(
                at: start.addingTimeInterval(3.39),
                delay: .oneSecond
            ) == nil,
            "Fresh observations after a gap must start a new delay"
        )
    }

    private static func testPostureHistory() {
        let suiteName = "PostureBarSmoke-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Could not create isolated defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let start = Date(timeIntervalSinceReferenceDate: 10_000)
        let history = PostureHistoryStore(defaults: defaults, now: start)

        precondition(history.state(at: start) == .noRecording)
        history.record(.good, at: start)
        precondition(history.state(at: start.addingTimeInterval(10)) == .good)
        precondition(history.state(at: start.addingTimeInterval(37)) == .noRecording)

        history.record(.bad, at: start.addingTimeInterval(20))
        precondition(history.state(at: start.addingTimeInterval(25)) == .bad)
        history.record(.good, at: start.addingTimeInterval(40))
        history.finish(at: start.addingTimeInterval(50))
        precondition(history.state(at: start.addingTimeInterval(55)) == .noRecording)

        let bins = history.binnedStates(
            count: 120,
            endingAt: start.addingTimeInterval(60)
        )
        precondition(bins.count == 120)
        precondition(bins.suffix(2).elementsEqual([.good, .bad]))
    }
}
