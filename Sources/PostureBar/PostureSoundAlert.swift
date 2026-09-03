import AppKit

final class PostureSoundAlert {
    private let defaults: UserDefaults
    private let enabledKey = "soundAlertsEnabled"
    private let delayKey = "soundAlertDelaySeconds"
    private let volumeModeKey = "soundAlertVolumeMode"
    private var tracker = PostureAlertTracker()
    private var alertTimer: Timer?
    private var isTrackingBadPosture = false

    private var alertSound: NSSound?

    private(set) var isEnabled: Bool
    private(set) var delay: PostureAlertDelay
    private(set) var volumeMode: PostureAlertVolumeMode

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: enabledKey) == nil {
            isEnabled = true
        } else {
            isEnabled = defaults.bool(forKey: enabledKey)
        }
        delay = PostureAlertDelay(
            rawValue: defaults.integer(forKey: delayKey)
        ) ?? .defaultValue
        volumeMode = defaults.string(forKey: volumeModeKey)
            .flatMap(PostureAlertVolumeMode.init(rawValue:))
            ?? .defaultValue
    }

    func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
        defaults.set(isEnabled, forKey: enabledKey)
        if !isEnabled {
            reset()
        }
    }

    func setDelay(_ delay: PostureAlertDelay) {
        self.delay = delay
        defaults.set(delay.rawValue, forKey: delayKey)
        tracker.resetAlertCadence()
        alertTimer?.invalidate()
        alertTimer = nil
        scheduleNextAlert()
    }

    func setVolumeMode(_ volumeMode: PostureAlertVolumeMode) {
        self.volumeMode = volumeMode
        defaults.set(volumeMode.rawValue, forKey: volumeModeKey)
    }

    func update(isBadPosture: Bool, at date: Date = Date()) {
        guard isEnabled else {
            reset()
            return
        }

        if isBadPosture {
            isTrackingBadPosture = true
            tracker.observeBadPosture(at: date)
            scheduleNextAlert()
        } else if isTrackingBadPosture {
            reset()
        }
    }

    func reset() {
        guard isTrackingBadPosture || alertTimer != nil || alertSound?.isPlaying == true else {
            return
        }
        isTrackingBadPosture = false
        tracker.reset()
        alertTimer?.invalidate()
        alertTimer = nil
        alertSound?.stop()
    }

    private func scheduleNextAlert() {
        guard isEnabled,
              alertTimer == nil,
              let nextDate = tracker.nextAlertDate(delay: delay) else {
            return
        }

        let timer = Timer(fireAt: nextDate, interval: 0, target: self,
                          selector: #selector(fireAlert), userInfo: nil, repeats: false)
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        alertTimer = timer
    }

    @objc private func fireAlert() {
        alertTimer = nil
        guard isEnabled,
              let volume = tracker.nextVolume(
                  at: Date(),
                  delay: delay,
                  mode: volumeMode
              ) else {
            return
        }

        if alertSound == nil {
            alertSound = BuzzerSoundFactory.makeSound()
                ?? NSSound(named: NSSound.Name("Tink"))
                ?? NSSound(named: NSSound.Name("Ping"))
        }
        alertSound?.stop()
        alertSound?.volume = volume
        alertSound?.play()
        scheduleNextAlert()
    }
}
