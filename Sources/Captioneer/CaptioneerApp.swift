import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    /// URLs received via Services before the UI was ready
    static var pendingServiceURLs: [URL]?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
    }

    /// Force the app's window in front of whoever launched us (Finder).
    /// `activate(ignoringOtherApps:)` alone is unreliable on macOS 14+, so we
    /// also `orderFrontRegardless()` every window and retry a few times to ride
    /// out the cold-start window where no window exists yet.
    static func bringToFront() {
        func raise() {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
        raise()
        for delay in [0.1, 0.3, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { raise() }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // Stash as well: on cold start this can arrive before ContentView's
        // .onReceive is listening, so onAppear consumes pendingServiceURLs instead.
        AppDelegate.pendingServiceURLs = urls
        NotificationCenter.default.post(name: Notification.Name("OpenFilesNotification"), object: urls)
        AppDelegate.bringToFront()
    }

    @objc func handleServices(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            // Store for pickup by ContentView, and also post notification in case the view is already listening
            AppDelegate.pendingServiceURLs = urls
            NotificationCenter.default.post(name: Notification.Name("OpenFilesNotification"), object: urls)
            AppDelegate.bringToFront()
        }
    }
}

@main
struct CaptioneerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var updaterController = UpdaterController()

    var body: some Scene {
        Window("Captioneer", id: "Captioneer-main") {
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
                Link("Captioneer Help", destination: URL(string: "https://github.com/jerefrer/captioneer")!)
            }
        }
    }
}
