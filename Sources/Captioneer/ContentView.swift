import SwiftUI

struct ContentView: View {
    @StateObject private var engine = CaptioneerEngine()

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            switch engine.state {
            case .idle:
                DropZoneView { urls in engine.start(items: urls) }
            case .processing(let progress):
                ProcessingView(progress: progress)
            case .done(.success(let summary)):
                SummaryView(summary: summary) {
                    if engine.startedAutomatically {
                        NSApplication.shared.terminate(nil)
                    } else {
                        engine.reset()
                    }
                }
            case .done(.failure(let error)):
                ErrorView(error: error) { engine.reset() }
            }
        }
        .frame(minWidth: 580, minHeight: 540)
        .onAppear {
            // Cold start via the Finder "Extract Captions" service: handleServices
            // fires (and posts its notification) before .onReceive is wired up, so the
            // notification is missed. The URLs are stashed in pendingServiceURLs — pick
            // them up here, otherwise nothing runs until the app is relaunched.
            if let pending = AppDelegate.pendingServiceURLs, !pending.isEmpty {
                AppDelegate.pendingServiceURLs = nil
                engine.startedAutomatically = true
                AppDelegate.bringToFront()
                engine.start(items: pending)
                return
            }

            let args = ProcessInfo.processInfo.arguments.dropFirst()
            if !args.isEmpty {
                let paths = args.filter { !$0.hasPrefix("-") }
                if !paths.isEmpty {
                    let urls = paths.map { URL(fileURLWithPath: String($0)) }
                    engine.startedAutomatically = true
                    engine.start(items: urls)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenFilesNotification"))) { notification in
            if let urls = notification.object as? [URL] {
                engine.startedAutomatically = true
                AppDelegate.bringToFront()
                engine.start(items: urls)
            }
        }
    }
}
