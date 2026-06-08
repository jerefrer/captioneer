import Foundation

enum AppState {
    case idle
    case processing(ProcessingProgress)
    case done(Result<ProcessSummary, CaptionExtractorError>)
}

struct ProcessingProgress {
    var phase: Phase
    var current: Int = 0
    var total: Int = 0
    var currentFile: String? = nil

    enum Phase {
        case scanning           // listing files
        case installingExifTool // download exiftool, 1st run
        case readingSheet       // Not used really, but kept for compat
        case stamping           // extracting metadata
    }

    var label: String {
        switch phase {
        case .scanning:           return "Scanning items…"
        case .installingExifTool: return "Installing ExifTool (first run)…"
        case .readingSheet:       return "Scanning images…"
        case .stamping:           return "Extracting metadata…"
        }
    }

    var isDeterminate: Bool { phase == .stamping && total > 0 }
    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
}

struct ProcessSummary {
    let folder: URL
    let sheetName: String
    let updatedCount: Int
    let files: [FileResult]

    var stampedCount: Int    { files.filter { $0.status == .stamped }.count }
    var noCaptionCount: Int  { files.filter { $0.status == .noCaption }.count }
    var missingFileCount: Int { files.filter { $0.status == .missingFile }.count }
}

struct FileResult: Identifiable, Equatable {
    let id = UUID()
    let filename: String
    let caption: String?
    let status: Status

    enum Status: Equatable {
        case stamped       // extracted successfully
        case noCaption     // no caption found
        case missingFile   // not an image
    }
}

enum CaptionExtractorError: LocalizedError {
    case noSheetFound
    case multipleSheets([String])
    case parseFailed(String)
    case noMatches
    case exifToolUnavailable(String)
    case exifToolFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSheetFound:
            return "No supported files found."
        case .multipleSheets(let names):
            return "Multiple files found: " + names.joined(separator: ", ")
        case .parseFailed(let msg):
            return "Error reading metadata: " + msg
        case .noMatches:
            return "No metadata or images found."
        case .exifToolUnavailable(let msg):
            return "ExifTool couldn’t be installed: \(msg)\n\nCheck your internet connection."
        case .exifToolFailed(let msg):
            return "Extracting captions failed:\n\n" + msg
        }
    }
}
