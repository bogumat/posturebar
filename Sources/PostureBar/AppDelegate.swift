import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var postureController: PostureController?
    private var pendingControlURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        postureController = PostureController()
        postureController?.start()

        let pendingURLs = pendingControlURLs
        pendingControlURLs.removeAll()
        handleControlURLs(pendingURLs)
    }

    func applicationWillTerminate(_ notification: Notification) {
        postureController?.stop()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard postureController != nil else {
            pendingControlURLs.append(contentsOf: urls)
            return
        }
        handleControlURLs(urls)
    }

    private func handleControlURLs(_ urls: [URL]) {
        for url in urls where url.scheme?.lowercased() == "posturebar" {
            switch url.host?.lowercased() {
            case "start", "resume":
                postureController?.resumeMonitoring()
            case "quit", "stop":
                NSApplication.shared.terminate(nil)
            default:
                continue
            }
        }
    }
}
