import XCTest
@testable import PostureBar

final class PostureAlertPolicyTests: XCTestCase {
    func testProgressiveModeRampsFromQuietToConfiguredMaximum() {
        let initial = PostureAlertPolicy.volume(afterBadPosture: 10)
        let middle = PostureAlertPolicy.volume(afterBadPosture: 65)
        let maximum = PostureAlertPolicy.volume(afterBadPosture: 120)

        XCTAssertEqual(initial, PostureAlertPolicy.progressiveInitialVolume)
        XCTAssertGreaterThan(middle ?? 0, initial ?? 0)
        XCTAssertEqual(maximum, PostureAlertPolicy.progressiveMaximumVolume)
    }

    func testConstantModeUsesMaximumVolumeAfterDelay() {
        XCTAssertNil(PostureAlertPolicy.volume(
            afterBadPosture: 9.99,
            mode: .constantMaximum
        ))
        XCTAssertEqual(
            PostureAlertPolicy.volume(
                afterBadPosture: 10,
                mode: .constantMaximum
            ),
            PostureAlertPolicy.constantMaximumVolume
        )
        XCTAssertEqual(
            PostureAlertPolicy.volume(
                afterBadPosture: 300,
                mode: .constantMaximum
            ),
            PostureAlertPolicy.constantMaximumVolume
        )
    }

    func testVolumeModePersists() {
        let suiteName = "PostureAlertPolicyTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let alert = PostureSoundAlert(defaults: defaults)
        XCTAssertEqual(alert.volumeMode, .progressive)

        alert.setVolumeMode(.constantMaximum)
        XCTAssertEqual(
            PostureSoundAlert(defaults: defaults).volumeMode,
            .constantMaximum
        )
    }
}
