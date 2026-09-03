import Foundation

enum PostureAlertDelay: Int, CaseIterable {
    case oneSecond = 1
    case twoSeconds = 2
    case fiveSeconds = 5
    case tenSeconds = 10
    case twentySeconds = 20
    case thirtySeconds = 30
    case oneMinute = 60

    static let defaultValue: PostureAlertDelay = .tenSeconds

    var duration: TimeInterval {
        TimeInterval(rawValue)
    }

    var title: String {
        switch self {
        case .oneSecond:
            return "1 Second"
        case .twoSeconds:
            return "2 Seconds"
        case .fiveSeconds:
            return "5 Seconds"
        case .tenSeconds:
            return "10 Seconds"
        case .twentySeconds:
            return "20 Seconds"
        case .thirtySeconds:
            return "30 Seconds"
        case .oneMinute:
            return "1 Minute"
        }
    }
}

enum PostureAlertVolumeMode: String, CaseIterable {
    case progressive
    case constantMaximum

    static let defaultValue: PostureAlertVolumeMode = .progressive

    var title: String {
        switch self {
        case .progressive:
            return "Progressive"
        case .constantMaximum:
            return "Constant (Maximum)"
        }
    }
}

enum PostureAlertPolicy {
    static let maximumVolumeTime: TimeInterval = 120
    static let beepInterval: TimeInterval = 5
    static let progressiveInitialVolume: Float = 0.05
    static let progressiveMaximumVolume: Float = 0.90
    static let constantMaximumVolume: Float = 1.0

    static func volume(
        afterBadPosture duration: TimeInterval,
        initialDelay: TimeInterval = PostureAlertDelay.defaultValue.duration,
        mode: PostureAlertVolumeMode = .defaultValue
    ) -> Float? {
        guard duration >= initialDelay else { return nil }

        if mode == .constantMaximum {
            return constantMaximumVolume
        }

        let rampDuration = maximumVolumeTime - initialDelay
        let progress = min(1, max(0, (duration - initialDelay) / rampDuration))
        let easedProgress = pow(progress, 1.35)
        return progressiveInitialVolume
            + ((progressiveMaximumVolume - progressiveInitialVolume)
                * Float(easedProgress))
    }
}
