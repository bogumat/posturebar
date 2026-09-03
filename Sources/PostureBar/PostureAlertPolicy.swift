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

enum PostureAlertPolicy {
    static let maximumVolumeTime: TimeInterval = 120
    static let beepInterval: TimeInterval = 5

    static func volume(
        afterBadPosture duration: TimeInterval,
        initialDelay: TimeInterval = PostureAlertDelay.defaultValue.duration
    ) -> Float? {
        guard duration >= initialDelay else { return nil }

        let rampDuration = maximumVolumeTime - initialDelay
        let progress = min(1, max(0, (duration - initialDelay) / rampDuration))
        let easedProgress = pow(progress, 1.35)
        return Float(0.05 + (0.85 * easedProgress))
    }
}
