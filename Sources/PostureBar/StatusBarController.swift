import AppKit

final class StatusBarController: NSObject, NSMenuDelegate {
    var onToggleMonitoring: (() -> Void)?
    var onPauseForThirtyMinutes: (() -> Void)?
    var onRecalibrate: (() -> Void)?
    var onToggleSoundAlerts: (() -> Void)?
    var onSelectSoundAlertDelay: ((PostureAlertDelay) -> Void)?
    var onSelectSoundAlertVolumeMode: ((PostureAlertVolumeMode) -> Void)?
    var onSelectCamera: ((String) -> Void)?
    var onMenuWillOpen: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let cameraMenuItem = NSMenuItem(title: "Camera", action: nil, keyEquivalent: "")
    private let historyView = PostureHistoryView(
        frame: NSRect(x: 0, y: 0, width: 300, height: 82)
    )
    private let toggleMenuItem = NSMenuItem(title: "Pause", action: #selector(toggleMonitoring), keyEquivalent: "p")
    private let pauseThirtyMenuItem = NSMenuItem(title: "Pause for 30 Minutes", action: #selector(pauseThirtyMinutes), keyEquivalent: "")
    private let recalibrateMenuItem = NSMenuItem(title: "Recalibrate Upright Posture…", action: #selector(recalibrate), keyEquivalent: "")
    private let soundAlertsMenuItem = NSMenuItem(title: "Sound Alerts", action: #selector(toggleSoundAlerts), keyEquivalent: "")
    private let soundAlertDelayMenuItem = NSMenuItem(title: "Buzz After", action: nil, keyEquivalent: "")
    private let soundAlertVolumeMenuItem = NSMenuItem(title: "Buzz Volume", action: nil, keyEquivalent: "")
    private let privacySettingsMenuItem = NSMenuItem(title: "Open Camera Privacy Settings…", action: #selector(openCameraPrivacySettings), keyEquivalent: "")

    override init() {
        super.init()

        statusMenuItem.isEnabled = false
        menu.delegate = self

        toggleMenuItem.target = self
        pauseThirtyMenuItem.target = self
        recalibrateMenuItem.target = self
        soundAlertsMenuItem.target = self
        privacySettingsMenuItem.target = self

        let soundAlertDelayMenu = NSMenu(title: "Buzz After")
        for delay in PostureAlertDelay.allCases {
            let item = NSMenuItem(
                title: delay.title,
                action: #selector(selectSoundAlertDelay(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = delay.rawValue
            soundAlertDelayMenu.addItem(item)
        }
        soundAlertDelayMenuItem.submenu = soundAlertDelayMenu

        let soundAlertVolumeMenu = NSMenu(title: "Buzz Volume")
        for mode in PostureAlertVolumeMode.allCases {
            let item = NSMenuItem(
                title: mode.title,
                action: #selector(selectSoundAlertVolumeMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            soundAlertVolumeMenu.addItem(item)
        }
        soundAlertVolumeMenuItem.submenu = soundAlertVolumeMenu

        menu.addItem(statusMenuItem)
        menu.addItem(cameraMenuItem)
        menu.addItem(.separator())

        let historyMenuItem = NSMenuItem()
        historyMenuItem.view = historyView
        menu.addItem(historyMenuItem)
        menu.addItem(.separator())

        menu.addItem(toggleMenuItem)
        menu.addItem(pauseThirtyMenuItem)
        menu.addItem(recalibrateMenuItem)
        menu.addItem(soundAlertsMenuItem)
        menu.addItem(soundAlertDelayMenuItem)
        menu.addItem(soundAlertVolumeMenuItem)
        menu.addItem(privacySettingsMenuItem)
        menu.addItem(.separator())

        let privacyItem = NSMenuItem(
            title: "Frames are processed locally and never saved",
            action: nil,
            keyEquivalent: ""
        )
        privacyItem.isEnabled = false
        menu.addItem(privacyItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit PostureBar", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        update(state: .starting, cameraName: nil)
    }

    func update(state: PostureDisplayState, cameraName: String?) {
        let title = state.title
        statusMenuItem.title = title
        cameraMenuItem.title = "Camera: \(cameraName ?? "None")"
        statusItem.button?.image = StatusIconFactory.image(for: state)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = title

        switch state {
        case .pausedManually, .pausedUntil:
            toggleMenuItem.title = "Resume Monitoring"
            pauseThirtyMenuItem.isEnabled = false
        default:
            toggleMenuItem.title = "Pause Monitoring"
            pauseThirtyMenuItem.isEnabled = true
        }

        privacySettingsMenuItem.isHidden = {
            if case .cameraPermissionDenied = state { return false }
            return true
        }()
    }

    func updateCameras(_ cameras: [CameraDescriptor], selectedCameraID: String?) {
        let submenu = NSMenu(title: "Camera")

        if cameras.isEmpty {
            let unavailable = NSMenuItem(title: "No Cameras Found", action: nil, keyEquivalent: "")
            unavailable.isEnabled = false
            submenu.addItem(unavailable)
        } else {
            for camera in cameras {
                let item = NSMenuItem(
                    title: camera.name,
                    action: #selector(selectCamera(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = camera.id
                item.state = camera.id == selectedCameraID ? .on : .off
                submenu.addItem(item)
            }
        }

        cameraMenuItem.submenu = submenu
    }

    func setHistoryProvider(_ provider: @escaping () -> [PostureHistoryState]) {
        historyView.statesProvider = provider
        refreshHistory()
    }

    func refreshHistory() {
        historyView.needsDisplay = true
    }

    func updateSoundAlerts(
        isEnabled: Bool,
        delay: PostureAlertDelay,
        volumeMode: PostureAlertVolumeMode
    ) {
        soundAlertsMenuItem.state = isEnabled ? .on : .off
        soundAlertDelayMenuItem.isEnabled = isEnabled
        soundAlertDelayMenuItem.title = "Buzz After: \(delay.title)"
        soundAlertVolumeMenuItem.isEnabled = isEnabled
        soundAlertVolumeMenuItem.title = "Buzz Volume: \(volumeMode.title)"

        for item in soundAlertDelayMenuItem.submenu?.items ?? [] {
            item.state = item.representedObject as? Int == delay.rawValue ? .on : .off
        }
        for item in soundAlertVolumeMenuItem.submenu?.items ?? [] {
            item.state = item.representedObject as? String == volumeMode.rawValue ? .on : .off
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshHistory()
        onMenuWillOpen?()
    }

    @objc private func toggleMonitoring() {
        onToggleMonitoring?()
    }

    @objc private func pauseThirtyMinutes() {
        onPauseForThirtyMinutes?()
    }

    @objc private func recalibrate() {
        onRecalibrate?()
    }

    @objc private func toggleSoundAlerts() {
        onToggleSoundAlerts?()
    }

    @objc private func selectSoundAlertDelay(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? Int,
              let delay = PostureAlertDelay(rawValue: rawValue) else {
            return
        }
        onSelectSoundAlertDelay?(delay)
    }

    @objc private func selectSoundAlertVolumeMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = PostureAlertVolumeMode(rawValue: rawValue) else {
            return
        }
        onSelectSoundAlertVolumeMode?(mode)
    }

    @objc private func selectCamera(_ sender: NSMenuItem) {
        guard let cameraID = sender.representedObject as? String else { return }
        onSelectCamera?(cameraID)
    }

    @objc private func openCameraPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
