import Foundation

enum PostureDisplayState: Equatable {
    case starting
    case calibrating(collected: Int, required: Int)
    case good
    case slouching
    case noPose
    case pausedForCall
    case pausedManually
    case pausedUntil(Date)
    case cameraPermissionDenied
    case cameraUnavailable
    case error(String)

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    var title: String {
        switch self {
        case .starting:
            return "Starting posture monitor…"
        case let .calibrating(collected, required):
            return "Sit upright — calibrating \(collected)/\(required)"
        case .good:
            return "Posture looks good"
        case .slouching:
            return "You’re slouching"
        case .noPose:
            return "Move into the camera’s view"
        case .pausedForCall:
            return "Paused — microphone or camera in use"
        case .pausedManually:
            return "Monitoring paused"
        case let .pausedUntil(date):
            return "Paused until \(Self.timeFormatter.string(from: date))"
        case .cameraPermissionDenied:
            return "Camera permission required"
        case .cameraUnavailable:
            return "No camera available"
        case let .error(message):
            return "Camera error: \(message)"
        }
    }
}
