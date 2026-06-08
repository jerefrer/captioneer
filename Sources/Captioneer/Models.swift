import Foundation

enum AppState {
    case idle
    case processing(ProcessingProgress)
    case done(Result<ProcessSummary, CaptioneerError>)
}

struct ProcessingProgress {
    var phase: Phase
    var current: Int = 0
    var total: Int = 0
    var currentFile: String? = nil

    enum Phase {
        case installingExifTool // download exiftool, 1st run
        case scanningImages     // listing the images to read
        case extracting         // reading metadata + writing the spreadsheet
    }

    var label: String {
        switch phase {
        case .installingExifTool: return "Installing ExifTool (first run)…"
        case .scanningImages:     return "Scanning images…"
        case .extracting:         return "Extracting captions…"
        }
    }

    var isDeterminate: Bool { phase == .extracting && total > 0 }
    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
}

struct ProcessSummary {
    let folder: URL
    let outputName: String
    let extractedCount: Int
    let files: [FileResult]

    var withCaptionCount: Int { files.filter { $0.status == .extracted }.count }
    var noCaptionCount: Int   { files.filter { $0.status == .noCaption }.count }
}

struct FileResult: Identifiable, Equatable {
    let id = UUID()
    let filename: String
    let caption: String?
    let status: Status

    enum Status: Equatable {
        case extracted     // caption read successfully
        case noCaption     // image had no caption metadata
    }
}

enum CaptioneerError: LocalizedError {
    case parseFailed(String)
    case noMatches
    case exifToolUnavailable(String)
    case exifToolFailed(String)

    var errorDescription: String? {
        switch self {
        case .parseFailed(let msg):
            return "Error reading metadata: " + msg
        case .noMatches:
            return "No images found to read."
        case .exifToolUnavailable(let msg):
            return "ExifTool couldn’t be installed: \(msg)\n\nCheck your internet connection."
        case .exifToolFailed(let msg):
            return "Extracting captions failed:\n\n" + msg
        }
    }
}
