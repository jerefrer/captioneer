import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct DropZoneView: View {
    let onItems: ([URL]) -> Void
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 18) {
                Image(systemName: isHovering ? "arrow.down.doc.fill" : "arrow.down.doc")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Theme.ink.opacity(isHovering ? 0.9 : 0.55))
                    .animation(.easeOut(duration: 0.15), value: isHovering)

                VStack(spacing: 6) {
                    Text("Drop images or a folder here")
                        .font(Theme.titleFont)
                        .foregroundStyle(Theme.ink)
                    Text("or click to choose them")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.inkSoft)
                }

                Text("Extracts captions/legends from photos\nand creates an Excel spreadsheet.")
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.top, 8)
            }
            .padding(48)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isHovering ? Theme.paperDeep.opacity(0.6) : Theme.paper.opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        Theme.ink.opacity(isHovering ? 0.65 : 0.3),
                        style: StrokeStyle(lineWidth: 2, dash: [10, 6])
                    )
                    .animation(.easeOut(duration: 0.15), value: isHovering)
            )
            .onTapGesture { pickItems() }
            .onDrop(of: [.fileURL], isTargeted: $isHovering) { providers in
                handleDrop(providers)
            }
        }
        .padding(28)
    }

    private func pickItems() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Choose"
        panel.title = "Choose images or a folder"
        if panel.runModal() == .OK {
            onItems(panel.urls)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        Task {
            var urls: [URL] = []
            for provider in providers {
                if let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? URL {
                    urls.append(url)
                } else if let data = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
            if !urls.isEmpty {
                await MainActor.run { onItems(urls) }
            }
        }
        return true
    }
}
