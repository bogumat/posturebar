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

    private static let maximumCalibrationGap: TimeInterval = 0.75
    private static let maximumCalibrationHeadYRange = 0.035
    private static let maximumCalibrationHeadSizeRange = 0.025
    private static let maximumHeadYDeviation = 0.015
    private static let maximumHeadSizeDeviation = 0.0125

    private(set) var baseline: CalibrationBaseline?

    private var calibrationSamples: [PostureFeatures] = []
    private var lastCalibrationSampleAt: Date?
    private var smoothedScore: Double?
    private var slouchingSampleCount = 0
    private var uprightSampleCount = 0
    private var isSlouching = false

    init(baseline: CalibrationBaseline? = nil) {
        self.baseline = Self.sanitizedBaseline(baseline)
        calibrationSamples.reserveCapacity(Self.requiredCalibrationSamples)
    }

    func setBaseline(_ baseline: CalibrationBaseline?) {
        self.baseline = Self.sanitizedBaseline(baseline)
        resetTransientState()
        resetCalibrationProgress()
    }

    func recalibrate() {
        baseline = nil
        resetCalibrationProgress()
        resetTransientState()
    }

    func consume(_ features: PostureFeatures) -> ClassifierOutput {
        consume(features, calibrationTime: nil)
    }

    func consume(_ features: PostureFeatures, at date: Date) -> ClassifierOutput {
        consume(features, calibrationTime: date)
    }

    private func consume(
        _ features: PostureFeatures,
        calibrationTime: Date?
    ) -> ClassifierOutput {
        guard let baseline else {
            return consumeCalibrationSample(
                features,
                at: calibrationTime ?? Date()
            )
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

    private func consumeCalibrationSample(
        _ features: PostureFeatures,
        at date: Date
    ) -> ClassifierOutput {
        guard Self.isPlausible(features) else {
            resetCalibrationProgress()
            return calibrationProgress
        }

        if let lastCalibrationSampleAt {
            let gap = date.timeIntervalSince(lastCalibrationSampleAt)
            if gap < 0 || gap > Self.maximumCalibrationGap {
                resetCalibrationProgress()
            }
        }
        lastCalibrationSampleAt = date

        calibrationSamples.append(features)
        if !Self.isStable(calibrationSamples) {
            // The newest observation becomes the start of a fresh window. This
            // avoids mixing two different seated positions into one baseline.
            calibrationSamples = [features]
        }

        guard calibrationSamples.count >= Self.requiredCalibrationSamples else {
            return calibrationProgress
        }

        self.baseline = Self.makeBaseline(from: calibrationSamples)
        resetCalibrationProgress()
        resetTransientState()
        return .classified(isSlouching: false, score: 0, didCalibrate: true)
    }

    private var calibrationProgress: ClassifierOutput {
        .calibrating(
            collected: calibrationSamples.count,
            required: Self.requiredCalibrationSamples
        )
    }

    private func resetCalibrationProgress() {
        calibrationSamples.removeAll(keepingCapacity: true)
        lastCalibrationSampleAt = nil
    }

    private static func isPlausible(_ features: PostureFeatures) -> Bool {
        features.headY.isFinite
            && (0...1).contains(features.headY)
            && features.headSize.isFinite
            && (0.04...1).contains(features.headSize)
    }

    private static func isStable(_ samples: [PostureFeatures]) -> Bool {
        guard let first = samples.first else { return true }

        var minimumHeadY = first.headY
        var maximumHeadY = first.headY
        var minimumHeadSize = first.headSize
        var maximumHeadSize = first.headSize

        for sample in samples.dropFirst() {
            minimumHeadY = min(minimumHeadY, sample.headY)
            maximumHeadY = max(maximumHeadY, sample.headY)
            minimumHeadSize = min(minimumHeadSize, sample.headSize)
            maximumHeadSize = max(maximumHeadSize, sample.headSize)
        }

        return maximumHeadY - minimumHeadY <= maximumCalibrationHeadYRange
            && maximumHeadSize - minimumHeadSize <= maximumCalibrationHeadSizeRange
    }

    private static func makeBaseline(from samples: [PostureFeatures]) -> CalibrationBaseline {
        let headPositions = samples.map(\.headY)
        let headSizes = samples.map(\.headSize)

        return CalibrationBaseline(
            headY: headPositions.median,
            headYDeviation: min(
                headPositions.medianAbsoluteDeviation * 1.4826,
                maximumHeadYDeviation
            ),
            headSize: headSizes.median,
            headSizeDeviation: min(
                headSizes.medianAbsoluteDeviation * 1.4826,
                maximumHeadSizeDeviation
            )
        )
    }

    private static func sanitizedBaseline(
        _ baseline: CalibrationBaseline?
    ) -> CalibrationBaseline? {
        guard let baseline,
              baseline.headY.isFinite,
              (0...1).contains(baseline.headY),
              baseline.headSize.isFinite,
              (0.04...1).contains(baseline.headSize),
              baseline.headYDeviation.isFinite,
              baseline.headYDeviation >= 0,
              baseline.headSizeDeviation.isFinite,
              baseline.headSizeDeviation >= 0 else {
            return nil
        }

        return CalibrationBaseline(
            headY: baseline.headY,
            headYDeviation: min(baseline.headYDeviation, maximumHeadYDeviation),
            headSize: baseline.headSize,
            headSizeDeviation: min(baseline.headSizeDeviation, maximumHeadSizeDeviation)
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
    var median: Double {
        guard !isEmpty else { return 0 }
        let values = sorted()
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }
        return values[middle]
    }

    var medianAbsoluteDeviation: Double {
        let center = median
        return map { abs($0 - center) }.median
    }
}
