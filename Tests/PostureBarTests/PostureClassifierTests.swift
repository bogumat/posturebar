import XCTest
@testable import PostureBar

final class PostureClassifierTests: XCTestCase {
    private let upright = PostureFeatures(
        headY: 0.62,
        headSize: 0.20
    )

    func testCalibrationCompletesAfterRequiredSamples() {
        let classifier = PostureClassifier()

        for sample in 1..<PostureClassifier.requiredCalibrationSamples {
            XCTAssertEqual(
                classifier.consume(upright),
                .calibrating(
                    collected: sample,
                    required: PostureClassifier.requiredCalibrationSamples
                )
            )
        }

        XCTAssertEqual(
            classifier.consume(upright),
            .classified(isSlouching: false, score: 0, didCalibrate: true)
        )
        XCTAssertNotNil(classifier.baseline)
    }

    func testMovementRestartsCalibration() {
        let classifier = PostureClassifier()

        for _ in 0..<10 {
            _ = classifier.consume(upright)
        }

        XCTAssertEqual(
            classifier.consume(PostureFeatures(headY: 0.50, headSize: 0.28)),
            .calibrating(
                collected: 1,
                required: PostureClassifier.requiredCalibrationSamples
            )
        )
        XCTAssertNil(classifier.baseline)
    }

    func testCalibrationGapRestartsCalibration() {
        let classifier = PostureClassifier()
        let start = Date(timeIntervalSinceReferenceDate: 1_000)

        for offset in 0..<10 {
            _ = classifier.consume(
                upright,
                at: start.addingTimeInterval(Double(offset) * 0.2)
            )
        }

        XCTAssertEqual(
            classifier.consume(upright, at: start.addingTimeInterval(3)),
            .calibrating(
                collected: 1,
                required: PostureClassifier.requiredCalibrationSamples
            )
        )
    }

    func testInvalidCalibrationSampleClearsProgress() {
        let classifier = PostureClassifier()
        for _ in 0..<10 {
            _ = classifier.consume(upright)
        }

        XCTAssertEqual(
            classifier.consume(PostureFeatures(headY: .nan, headSize: 0.20)),
            .calibrating(
                collected: 0,
                required: PostureClassifier.requiredCalibrationSamples
            )
        )
    }

    func testLoadedBaselineDeviationIsBounded() {
        let classifier = PostureClassifier(baseline: CalibrationBaseline(
            headY: upright.headY,
            headYDeviation: 0.5,
            headSize: upright.headSize,
            headSizeDeviation: 0.5
        ))

        XCTAssertEqual(classifier.baseline?.headYDeviation, 0.015)
        XCTAssertEqual(classifier.baseline?.headSizeDeviation, 0.0125)
    }

    func testSustainedSlouchChangesState() {
        let classifier = calibratedClassifier()
        let slouch = PostureFeatures(
            headY: 0.55,
            headSize: 0.24
        )

        var result = classifier.consume(slouch)
        for _ in 0..<8 {
            result = classifier.consume(slouch)
        }

        guard case let .classified(isSlouching, score, _) = result else {
            return XCTFail("Expected a classification")
        }
        XCTAssertTrue(isSlouching)
        XCTAssertGreaterThan(score, 1)
    }

    func testSingleBadSampleDoesNotChangeState() {
        let classifier = calibratedClassifier()
        let result = classifier.consume(PostureFeatures(
            headY: 0.55,
            headSize: 0.24
        ))

        guard case let .classified(isSlouching, _, _) = result else {
            return XCTFail("Expected a classification")
        }
        XCTAssertFalse(isSlouching)
    }

    func testUprightSamplesRecoverFromSlouch() {
        let classifier = calibratedClassifier()
        let slouch = PostureFeatures(
            headY: 0.55,
            headSize: 0.24
        )

        for _ in 0..<9 {
            _ = classifier.consume(slouch)
        }

        var result = classifier.consume(upright)
        for _ in 0..<12 {
            result = classifier.consume(upright)
        }

        guard case let .classified(isSlouching, _, _) = result else {
            return XCTFail("Expected a classification")
        }
        XCTAssertFalse(isSlouching)
    }

    private func calibratedClassifier() -> PostureClassifier {
        let classifier = PostureClassifier()
        for _ in 0..<PostureClassifier.requiredCalibrationSamples {
            _ = classifier.consume(upright)
        }
        return classifier
    }
}
