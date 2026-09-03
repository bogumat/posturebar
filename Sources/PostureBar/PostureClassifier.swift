import Foundation

struct PostureFeatures: Equatable {
    let headY: Double
    let headSize: Double
}

struct CalibrationBaseline: Codable, Equatable {
    let headY: Double
    let headYDeviation: Double
    let headSize: Double
    let headSizeDeviation: Double
}

enum ClassifierOutput: Equatable {
    case calibrating(collected: Int, required: Int)
    case classified(isSlouching: Bool, score: Double, didCalibrate: Bool)
}

final class PostureClassifier {
    static let requiredCalibrationSamples = 20

    private(set) var baseline: CalibrationBaseline?

    private var calibrationSamples: [PostureFeatures] = []
    private var smoothedScore: Double?
    private var slouchingSampleCount = 0
    private var uprightSampleCount = 0
    private var isSlouching = false

    init(baseline: CalibrationBaseline? = nil) {
        self.baseline = baseline
    }

    func setBaseline(_ baseline: CalibrationBaseline?) {
        self.baseline = baseline
        resetTransientState()
        calibrationSamples.removeAll(keepingCapacity: true)
    }

    func recalibrate() {
        baseline = nil
        calibrationSamples.removeAll(keepingCapacity: true)
        resetTransientState()
    }

    func consume(_ features: PostureFeatures) -> ClassifierOutput {
        guard let baseline else {
            calibrationSamples.append(features)

            guard calibrationSamples.count >= Self.requiredCalibrationSamples else {
                return .calibrating(
                    collected: calibrationSamples.count,
                    required: Self.requiredCalibrationSamples
                )
            }

            self.baseline = Self.makeBaseline(from: calibrationSamples)
            calibrationSamples.removeAll(keepingCapacity: false)
            resetTransientState()
            return .classified(isSlouching: false, score: 0, didCalibrate: true)
        }

        let rawScore = Self.slouchScore(features: features, baseline: baseline)
        let filteredScore: Double

        if let smoothedScore {
            // At five observations per second this reacts in under a second but
            // still prevents a single noisy face rectangle changing the icon.
            filteredScore = (0.55 * rawScore) + (0.45 * smoothedScore)
        } else {
            filteredScore = rawScore
        }
        smoothedScore = filteredScore

        if filteredScore >= 1.0 {
            slouchingSampleCount += 1
            uprightSampleCount = 0
            if slouchingSampleCount >= 3 {
                isSlouching = true
            }
        } else if filteredScore <= 0.55 {
            uprightSampleCount += 1
            slouchingSampleCount = 0
            if uprightSampleCount >= 3 {
                isSlouching = false
            }
        } else {
            slouchingSampleCount = 0
            uprightSampleCount = 0
        }

        return .classified(
            isSlouching: isSlouching,
            score: filteredScore,
            didCalibrate: false
        )
    }

    private func resetTransientState() {
        smoothedScore = nil
        slouchingSampleCount = 0
        uprightSampleCount = 0
        isSlouching = false
    }

    private static func makeBaseline(from samples: [PostureFeatures]) -> CalibrationBaseline {
        let headPositions = samples.map(\.headY)
        let headSizes = samples.map(\.headSize)

        return CalibrationBaseline(
            headY: headPositions.mean,
            headYDeviation: headPositions.standardDeviation,
            headSize: headSizes.mean,
            headSizeDeviation: headSizes.standardDeviation
        )
    }

    private static func slouchScore(
        features: PostureFeatures,
        baseline: CalibrationBaseline
    ) -> Double {
        // Vision coordinates are normalized to the frame. A slouch normally
        // lowers the face, brings it closer to the screen, or does both.
        let headDropThreshold = max(0.030, baseline.headYDeviation * 4.0)
        let headDrop = max(0, baseline.headY - features.headY)

        let sizeIncreaseThreshold = max(0.025, baseline.headSizeDeviation * 4.0)
        let sizeIncrease = max(0, features.headSize - baseline.headSize)

        return ((headDrop / headDropThreshold) * 0.75)
            + ((sizeIncrease / sizeIncreaseThreshold) * 0.25)
    }
}

private extension Array where Element == Double {
    var mean: Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }

    var standardDeviation: Double {
        guard count > 1 else { return 0 }
        let average = mean
        let variance = reduce(0) { partial, value in
            partial + pow(value - average, 2)
        } / Double(count)
        return sqrt(variance)
    }
}
