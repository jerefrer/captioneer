import Foundation
import SwiftUI

@MainActor
final class CaptionExtractorEngine: ObservableObject {
    @Published var state: AppState = .idle

    private var supportDir: URL {
        let lib = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return lib.appendingPathComponent("CaptionExtractor", isDirectory: true)
    }

    // MARK: - Public API

    func start(items: [URL]) {
        Task { await runPipeline(items: items) }
    }

    func reset() {
        state = .idle
    }

    var startedAutomatically = false

    // MARK: - Pipeline

    private func updateProgress(_ progress: ProcessingProgress) {
        state = .processing(progress)
    }

    private func runPipeline(items: [URL]) async {
        do {
            guard !items.isEmpty else {
                state = .done(.failure(.noMatches))
                return
            }
            
            updateProgress(.init(phase: .installingExifTool))
            let exiftool = try await ensureExifTool()

            updateProgress(.init(phase: .readingSheet)) // we reuse this phase for "scanning"
            
            // Where to save the output file?
            let firstItem = items[0]
            var outFolder = firstItem
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: firstItem.path, isDirectory: &isDir), !isDir.boolValue {
                outFolder = firstItem.deletingLastPathComponent()
            }
            let outPath = outFolder.appendingPathComponent("Extraction.xlsx")

            updateProgress(.init(phase: .stamping, total: 0)) // indeterminate progress

            let extraction = try await extractMetadata(exiftool: exiftool, items: items)
            
            guard !extraction.isEmpty else {
                state = .done(.failure(.noMatches))
                return
            }
            
            try writeXLSX(data: extraction, to: outPath)
            
            let files = extraction.map { FileResult(filename: $0.filename, caption: $0.caption, status: .stamped) }

            let summary = ProcessSummary(
                folder: outFolder,
                sheetName: "Extraction.xlsx",
                updatedCount: files.count,
                files: files
            )
            state = .done(.success(summary))
            
        } catch let error as CaptionExtractorError {
            state = .done(.failure(error))
        } catch {
            state = .done(.failure(.parseFailed(error.localizedDescription)))
        }
    }
    
    private func escapeXML(_ string: String) -> String {
        var escaped = string.replacingOccurrences(of: "&", with: "&amp;")
        escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
        escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
        escaped = escaped.replacingOccurrences(of: "\"", with: "&quot;")
        escaped = escaped.replacingOccurrences(of: "'", with: "&apos;")
        escaped = escaped.filter {
            let scalar = $0.unicodeScalars.first!.value
            return scalar == 0x9 || scalar == 0xA || scalar == 0xD ||
                (scalar >= 0x20 && scalar <= 0xD7FF) ||
                (scalar >= 0xE000 && scalar <= 0xFFFD) ||
                (scalar >= 0x10000 && scalar <= 0x10FFFF)
        }
        return escaped
    }

    private func writeXLSX(data: [(filename: String, caption: String)], to url: URL) throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }
        
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        </Types>
        """
        try contentTypes.write(to: tempDir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
        
        let relsDir = tempDir.appendingPathComponent("_rels")
        try fm.createDirectory(at: relsDir, withIntermediateDirectories: true)
        let dotRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
        try dotRels.write(to: relsDir.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)
        
        let xlDir = tempDir.appendingPathComponent("xl")
        try fm.createDirectory(at: xlDir, withIntermediateDirectories: true)
        let workbook = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets>
        </workbook>
        """
        try workbook.write(to: xlDir.appendingPathComponent("workbook.xml"), atomically: true, encoding: .utf8)
        
        let xlRelsDir = xlDir.appendingPathComponent("_rels")
        try fm.createDirectory(at: xlRelsDir, withIntermediateDirectories: true)
        let xlRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        </Relationships>
        """
        try xlRels.write(to: xlRelsDir.appendingPathComponent("workbook.xml.rels"), atomically: true, encoding: .utf8)
        
        let wsDir = xlDir.appendingPathComponent("worksheets")
        try fm.createDirectory(at: wsDir, withIntermediateDirectories: true)
        
        var sheetData = "<row r=\"1\"><c r=\"A1\" t=\"inlineStr\"><is><t>Filename</t></is></c><c r=\"B1\" t=\"inlineStr\"><is><t>Description</t></is></c></row>\n"
        for (i, row) in data.enumerated() {
            let r = i + 2
            let c1 = escapeXML(row.filename)
            let c2 = escapeXML(row.caption)
            sheetData += "<row r=\"\(r)\"><c r=\"A\(r)\" t=\"inlineStr\"><is><t>\(c1)</t></is></c><c r=\"B\(r)\" t=\"inlineStr\"><is><t>\(c2)</t></is></c></row>\n"
        }
        
        let sheet1 = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetData>\(sheetData)</sheetData>
        </worksheet>
        """
        try sheet1.write(to: wsDir.appendingPathComponent("sheet1.xml"), atomically: true, encoding: .utf8)
        
        let zipProcess = Process()
        zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipProcess.arguments = ["-r", "-X", url.path, "."]
        zipProcess.currentDirectoryURL = tempDir
        
        let pipe = Pipe()
        zipProcess.standardOutput = pipe
        zipProcess.standardError = pipe
        try zipProcess.run()
        zipProcess.waitUntilExit()
    }

    private func extractMetadata(exiftool: URL, items: [URL]) async throws -> [(filename: String, caption: String)] {
        return try await Task.detached {
            let process = Process()
            process.executableURL = exiftool
            
            var args = ["-T", "-FileName", "-Title", "-Description", "-Caption-Abstract", "-ImageDescription", "-ext", "tif", "-ext", "tiff", "-ext", "jpg", "-ext", "jpeg", "-ext", "png"]
            for item in items {
                args.append(item.path)
            }
            process.arguments = args
            
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            
            do {
                try process.run()
                
                // Read data before waitUntilExit to avoid pipe buffer deadlocks (64KB limit)
                let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                _ = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                
                process.waitUntilExit()
                
                guard let output = String(data: stdout, encoding: .utf8) else {
                    return []
                }
                
                var results: [(String, String)] = []
                let lines = output.components(separatedBy: .newlines)
                for line in lines {
                    if line.isEmpty { continue }
                    let parts = line.components(separatedBy: "\t")
                    if parts.isEmpty { continue }
                    
                    let filename = parts[0]
                    // We look for the first non-empty caption field
                    var caption = ""
                    for i in 1..<parts.count {
                        if parts[i] != "-" && !parts[i].isEmpty {
                            caption = parts[i]
                            break
                        }
                    }
                    results.append((filename, caption))
                }
                
                return results
            } catch {
                throw CaptionExtractorError.exifToolFailed(error.localizedDescription)
            }
        }.value
    }

    // MARK: - ExifTool installation

    private func ensureExifTool() async throws -> URL {
        for candidate in ["/usr/local/bin/exiftool", "/opt/homebrew/bin/exiftool"] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                let candidate = "\(dir)/exiftool"
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return URL(fileURLWithPath: candidate)
                }
            }
        }

        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let existing = (try? FileManager.default.contentsOfDirectory(at: supportDir, includingPropertiesForKeys: nil)) ?? []
        let existingTool = existing
            .filter { $0.lastPathComponent.hasPrefix("Image-ExifTool-") }
            .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }
            .first
            .map { $0.appendingPathComponent("exiftool") }
        if let url = existingTool, FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }

        return try await downloadExifTool()
    }

    private func downloadExifTool() async throws -> URL {
        let session = URLSession.shared
        let versionURL = URL(string: "https://exiftool.org/ver.txt")!
        let (verData, _) = try await session.data(from: versionURL)
        let version = String(data: verData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !version.isEmpty else {
            throw CaptionExtractorError.exifToolUnavailable("Version not found on exiftool.org")
        }

        let tgzURL = URL(string: "https://exiftool.org/Image-ExifTool-\(version).tar.gz")!
        let (tgzLocalURL, _) = try await session.download(from: tgzURL)
        let targetTgz = supportDir.appendingPathComponent("Image-ExifTool-\(version).tar.gz")
        try? FileManager.default.removeItem(at: targetTgz)
        try FileManager.default.moveItem(at: tgzLocalURL, to: targetTgz)

        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xzf", targetTgz.path, "-C", supportDir.path]
        try tar.run()
        tar.waitUntilExit()
        if tar.terminationStatus != 0 {
            throw CaptionExtractorError.exifToolUnavailable("Extraction failed (tar)")
        }

        let exiftoolURL = supportDir.appendingPathComponent("Image-ExifTool-\(version)").appendingPathComponent("exiftool")
        try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: exiftoolURL.path)
        guard FileManager.default.isExecutableFile(atPath: exiftoolURL.path) else {
            throw CaptionExtractorError.exifToolUnavailable("Binary not found after extraction")
        }
        return exiftoolURL
    }
}
