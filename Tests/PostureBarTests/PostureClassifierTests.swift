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
