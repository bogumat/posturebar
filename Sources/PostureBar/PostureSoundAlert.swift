import AppKit

final class PostureSoundAlert {
    private let defaults: UserDefaults
    private let enabledKey = "soundAlertsEnabled"
    private let delayKey = "soundAlertDelaySeconds"
    private var badPostureStartedAt: Date?
    private var lastBeepAt: Date?

    private lazy var alertSound: NSSound? = {
        BuzzerSoundFactory.makeSound()
            ?? NSSound(named: NSSound.Name("Tink"))
            ?? NSSound(named: NSSound.Name("Ping"))
    }()

    private(set) var isEnabled: Bool
    private(set) var delay: PostureAlertDelay

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
        lastBeepAt = nil
    }

    func update(isBadPosture: Bool, at date: Date = Date()) {
        guard isEnabled else {
            reset()
            return
        }

        if isBadPosture {
            if badPostureStartedAt == nil {
                badPostureStartedAt = date
                lastBeepAt = nil
            }
        } else {
            reset()
        }
    }

    func tick(at date: Date = Date()) {
        guard isEnabled,
              let badPostureStartedAt,
              let volume = PostureAlertPolicy.volume(
                  afterBadPosture: date.timeIntervalSince(badPostureStartedAt),
                  initialDelay: delay.duration
              ) else {
            return
        }

        if let lastBeepAt,
           date.timeIntervalSince(lastBeepAt) < PostureAlertPolicy.beepInterval {
            return
        }

        lastBeepAt = date
        alertSound?.stop()
        alertSound?.volume = volume
        alertSound?.play()
    }

    func reset() {
        badPostureStartedAt = nil
        lastBeepAt = nil
        alertSound?.stop()
    }
}
