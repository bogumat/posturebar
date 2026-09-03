import Foundation

final class BaselineStore {
    private let defaults: UserDefaults
    private let baselinesKey = "calibrationBaselines"
    private let selectedCameraKey = "selectedCameraID"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedCameraID: String? {
        get { defaults.string(forKey: selectedCameraKey) }
        set { defaults.set(newValue, forKey: selectedCameraKey) }
    }

    func baseline(for cameraID: String) -> CalibrationBaseline? {
        loadBaselines()[cameraID]
    }

    func save(_ baseline: CalibrationBaseline, for cameraID: String) {
        var baselines = loadBaselines()
        baselines[cameraID] = baseline
        if let data = try? JSONEncoder().encode(baselines) {
            defaults.set(data, forKey: baselinesKey)
        }
    }

    func removeBaseline(for cameraID: String) {
        var baselines = loadBaselines()
        baselines.removeValue(forKey: cameraID)
        if let data = try? JSONEncoder().encode(baselines) {
            defaults.set(data, forKey: baselinesKey)
        }
    }

    private func loadBaselines() -> [String: CalibrationBaseline] {
        guard let data = defaults.data(forKey: baselinesKey),
              let baselines = try? JSONDecoder().decode(
                  [String: CalibrationBaseline].self,
                  from: data
              ) else {
            return [:]
        }
        return baselines
    }
}
