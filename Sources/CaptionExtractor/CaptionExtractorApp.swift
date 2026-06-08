import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    /// URLs received via Services before the UI was ready
    static var pendingServiceURLs: [URL]?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        NotificationCenter.default.post(name: Notification.Name("OpenFilesNotification"), object: urls)
    }

    @objc func handleServices(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            // Store for pickup by ContentView, and also post notification in case the view is already listening
            AppDelegate.pendingServiceURLs = urls
            NotificationCenter.default.post(name: Notification.Name("OpenFilesNotification"), object: urls)
        }
    }
}

@main
struct CaptionExtractorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var updaterController = UpdaterController()

    var body: some Scene {
        Window("CaptionExtractor", id: "CaptionExtractor-main") {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                CheckForUpdatesMenuItem(controller: updaterController)
            }
            CommandGroup(replacing: .help) {
                Link("CaptionExtractor Help", destination: URL(string: "https://github.com/jerefrer/CaptionExtractor")!)
            }
        }
    }
}
