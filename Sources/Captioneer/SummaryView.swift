import SwiftUI

struct SummaryView: View {
    let summary: ProcessSummary
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.success)
                    .padding(.bottom, 4)

                Text("Extraction Complete")
                    .font(Theme.titleFont)
                    .foregroundStyle(Theme.ink)

                Text("\(summary.extractedCount) items extracted to \(summary.outputName)")
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.muted)
            }
            .padding(.top, 40)
            .padding(.bottom, 24)

            // List with Pinned Header
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section(header: tableHeader) {
                        ForEach(summary.files) { file in
                            HStack(spacing: 12) {
                                Text(file.filename)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(width: 180, alignment: .leading)
                                    .foregroundStyle(Theme.ink)

                                if let cap = file.caption, !cap.isEmpty {
                                    Text(cap)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .foregroundStyle(Theme.inkSoft)
                                } else {
                                    Text("—")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .foregroundStyle(Theme.muted)
                                }

                                Group {
                                    if let cap = file.caption, !cap.isEmpty {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Theme.success)
                                            .font(.system(size: 14))
                                    } else {
                                        Text("—")
                                            .foregroundStyle(Theme.muted)
                                    }
                                }
                                .frame(width: 60, alignment: .center)
                            }
                            .font(.system(size: 13))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            
                            Divider()
                                .background(Theme.paperDeep.opacity(0.5))
                        }
                    }
                }
                .padding(.bottom, 24)
            }

            // Footer
            VStack {
                Button("Done") {
                    onReset()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(24)
            .background(Theme.paper)
            // Border top
            .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.paperDeep), alignment: .top)
        }
    }
    
    private var tableHeader: some View {
        HStack(spacing: 12) {
            Text("FILE").frame(width: 180, alignment: .leading)
            Text("DESCRIPTION").frame(maxWidth: .infinity, alignment: .leading)
            Text("STATUS").frame(width: 60, alignment: .center)
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(Theme.paperDeep)
    }
}
