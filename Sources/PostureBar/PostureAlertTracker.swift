import Foundation

/// Tracks only continuously observed bad posture. A stalled camera or a
/// sleep/wake gap invalidates the alert instead of allowing an old state to
/// produce a delayed, loud buzzer.
struct PostureAlertTracker {
    static let maximumObservationAge: TimeInterval = 1.5

    private var badPostureStartedAt: Date?
    private var latestBadObservationAt: Date?
    private var lastAlertAt: Date?

    mutating func observeBadPosture(at date: Date) {
        if let latestBadObservationAt {
            let gap = date.timeIntervalSince(latestBadObservationAt)
            if gap < 0 || gap > Self.maximumObservationAge {
                reset()
            }
        }

        if badPostureStartedAt == nil {
            badPostureStartedAt = date
        }
        latestBadObservationAt = date
    }

    mutating func nextVolume(
        at date: Date,
        delay: PostureAlertDelay,
        mode: PostureAlertVolumeMode = .defaultValue
    ) -> Float? {
        guard let badPostureStartedAt,
              let latestBadObservationAt else {
            return nil
        }

        let observationAge = date.timeIntervalSince(latestBadObservationAt)
        guard observationAge >= 0,
              observationAge <= Self.maximumObservationAge else {
            reset()
            return nil
        }

        guard let volume = PostureAlertPolicy.volume(
            afterBadPosture: date.timeIntervalSince(badPostureStartedAt),
            initialDelay: delay.duration,
            mode: mode
        ) else {
            return nil
        }

        if let lastAlertAt,
           date.timeIntervalSince(lastAlertAt) < PostureAlertPolicy.beepInterval {
            return nil
        }

        self.lastAlertAt = date
        return volume
    }

    mutating func resetAlertCadence() {
        lastAlertAt = nil
    }

    func nextAlertDate(delay: PostureAlertDelay) -> Date? {
        if let lastAlertAt {
            return lastAlertAt.addingTimeInterval(PostureAlertPolicy.beepInterval)
        }
        return badPostureStartedAt?.addingTimeInterval(delay.duration)
    }

    mutating func reset() {
        badPostureStartedAt = nil
        latestBadObservationAt = nil
        lastAlertAt = nil
    }
}
