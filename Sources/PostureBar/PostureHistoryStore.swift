import Foundation

enum PostureHistoryState: String, Codable, Equatable {
    case good
    case bad
    case noRecording
}

struct PostureHistoryEntry: Codable, Equatable {
    let timestamp: TimeInterval
    let state: PostureHistoryState
}

/// Stores state transitions plus a sparse heartbeat instead of one entry per
/// frame. This keeps an hour of history tiny while allowing unrecorded gaps to
/// be represented accurately after pauses, quits, or crashes.
final class PostureHistoryStore {
    static let historyDuration: TimeInterval = 60 * 60
    static let heartbeatInterval: TimeInterval = 30
    static let activeStateTimeout: TimeInterval = 36

    private let defaults: UserDefaults
    private let storageKey = "postureHistoryV1"
    private var entries: [PostureHistoryEntry]

    init(defaults: UserDefaults = .standard, now: Date = Date()) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let storedEntries = try? JSONDecoder().decode(
               [PostureHistoryEntry].self,
               from: data
           ) {
            entries = storedEntries.sorted { $0.timestamp < $1.timestamp }
        } else {
            entries = []
        }
        prune(at: now.timeIntervalSinceReferenceDate)
    }

    @discardableResult
    func record(
        _ state: PostureHistoryState,
        at date: Date = Date(),
        force: Bool = false
    ) -> Bool {
        let timestamp = date.timeIntervalSinceReferenceDate
        prune(at: timestamp)

        if !force,
           let latest = entries.last,
           latest.state == state,
           timestamp - latest.timestamp < Self.heartbeatInterval {
            return false
        }

        entries.append(PostureHistoryEntry(timestamp: timestamp, state: state))
        save()
        return true
    }

    func finish(at date: Date = Date()) {
        _ = record(.noRecording, at: date, force: true)
    }

    func state(at date: Date) -> PostureHistoryState {
        let timestamp = date.timeIntervalSinceReferenceDate
        guard let entry = entries.last(where: { $0.timestamp <= timestamp }) else {
            return .noRecording
        }

        if entry.state != .noRecording,
           timestamp - entry.timestamp > Self.activeStateTimeout {
            return .noRecording
        }
        return entry.state
    }

    func binnedStates(
        count: Int,
        endingAt endDate: Date = Date()
    ) -> [PostureHistoryState] {
        guard count > 0 else { return [] }

        let binDuration = Self.historyDuration / Double(count)
        let start = endDate.addingTimeInterval(-Self.historyDuration)
        let samplesPerBin = 5

        return (0..<count).map { binIndex in
            let binStart = start.addingTimeInterval(Double(binIndex) * binDuration)
            var goodCount = 0
            var badCount = 0
            var noRecordingCount = 0

            for sampleIndex in 0..<samplesPerBin {
                let offset = (Double(sampleIndex) + 0.5)
                    * binDuration / Double(samplesPerBin)
                switch state(at: binStart.addingTimeInterval(offset)) {
                case .good:
                    goodCount += 1
                case .bad:
                    badCount += 1
                case .noRecording:
                    noRecordingCount += 1
                }
            }

            if badCount >= goodCount, badCount >= noRecordingCount, badCount > 0 {
                return .bad
            }
            if goodCount >= noRecordingCount, goodCount > 0 {
                return .good
            }
            return .noRecording
        }
    }

    private func prune(at timestamp: TimeInterval) {
        let cutoff = timestamp - Self.historyDuration - Self.activeStateTimeout

        guard let firstRetainedIndex = entries.firstIndex(where: {
            $0.timestamp >= cutoff
        }) else {
            if let last = entries.last {
                entries = [last]
            }
            return
        }

        // Preserve one preceding transition so the state at the graph's left
        // edge can still be determined.
        let removalEnd = max(0, firstRetainedIndex - 1)
        if removalEnd > 0 {
            entries.removeFirst(removalEnd)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
