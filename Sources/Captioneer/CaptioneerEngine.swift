import Foundation
import SwiftUI

@MainActor
final class CaptioneerEngine: ObservableObject {
    @Published var state: AppState = .idle

    private var supportDir: URL {
        let lib = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return lib.appendingPathComponent("Captioneer", isDirectory: true)
    }

    // MARK: - Public API

    func start(items: [URL]) {
        // Ignore re-entrant starts: the cold-start service path and the
        // notification path can both fire for the same launch.
        guard case .idle = state else { return }
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

            updateProgress(.init(phase: .scanningImages))

            // Where to save the output file?
            let firstItem = items[0]
            var outFolder = firstItem
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: firstItem.path, isDirectory: &isDir), !isDir.boolValue {
                outFolder = firstItem.deletingLastPathComponent()
            }
            let outPath = outFolder.appendingPathComponent("Captions.xlsx")

            updateProgress(.init(phase: .extracting, total: 0)) // indeterminate progress

            let extraction = try await extractMetadata(exiftool: exiftool, items: items)
                .sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }

            guard !extraction.isEmpty else {
                state = .done(.failure(.noMatches))
                return
            }
            
            try writeXLSX(data: extraction, to: outPath)
            
            let files = extraction.map { row -> FileResult in
                let hasCaption = !row.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                return FileResult(
                    filename: row.filename,
                    caption: hasCaption ? row.caption : nil,
                    status: hasCaption ? .extracted : .noCaption
                )
            }

            let summary = ProcessSummary(
                folder: outFolder,
                outputName: "Captions.xlsx",
                extractedCount: files.count,
                files: files
            )
            state = .done(.success(summary))

        } catch let error as CaptioneerError {
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
          <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
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
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
        """
        try xlRels.write(to: xlRelsDir.appendingPathComponent("workbook.xml.rels"), atomically: true, encoding: .utf8)

        // Styles: bold white header on a sepia fill (style 1), wrapped top-aligned
        // body for the description (style 2), top-aligned filename (style 3).
        let styles = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <fonts count="2">
            <font><sz val="18"/><name val="Calibri"/></font>
            <font><b/><sz val="18"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>
          </fonts>
          <fills count="3">
            <fill><patternFill patternType="none"/></fill>
            <fill><patternFill patternType="gray125"/></fill>
            <fill><patternFill patternType="solid"><fgColor rgb="FF6B5B4D"/><bgColor indexed="64"/></patternFill></fill>
          </fills>
          <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
          <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
          <cellXfs count="4">
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
            <xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment horizontal="left" vertical="center"/></xf>
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top"/></xf>
          </cellXfs>
          <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
        </styleSheet>
        """
        try styles.write(to: xlDir.appendingPathComponent("styles.xml"), atomically: true, encoding: .utf8)

        let wsDir = xlDir.appendingPathComponent("worksheets")
        try fm.createDirectory(at: wsDir, withIntermediateDirectories: true)
        
        // Header row: style 1 (bold). r="1" height bumped for readability.
        var sheetData = "<row r=\"1\" ht=\"30\" customHeight=\"1\"><c r=\"A1\" t=\"inlineStr\" s=\"1\"><is><t>Filename</t></is></c><c r=\"B1\" t=\"inlineStr\" s=\"1\"><is><t>Description</t></is></c></row>\n"
        for (i, row) in data.enumerated() {
            let r = i + 2
            let c1 = escapeXML(row.filename)
            let c2 = escapeXML(row.caption)
            // s="3": filename top-aligned. s="2": description wrapped. xml:space preserves newlines.
            sheetData += "<row r=\"\(r)\"><c r=\"A\(r)\" t=\"inlineStr\" s=\"3\"><is><t xml:space=\"preserve\">\(c1)</t></is></c><c r=\"B\(r)\" t=\"inlineStr\" s=\"2\"><is><t xml:space=\"preserve\">\(c2)</t></is></c></row>\n"
        }

        let sheet1 = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetViews>
            <sheetView workbookViewId="0">
              <pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>
            </sheetView>
          </sheetViews>
          <cols>
            <col min="1" max="1" width="26" customWidth="1"/>
            <col min="2" max="2" width="123.5" customWidth="1"/>
          </cols>
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

            // -j (JSON) instead of -T (tab): captions are multi-paragraph EN/FR text.
            // Tab output collapses newlines to "." and, for separators it doesn't
            // collapse (U+2028/U+000B from the source .docx), a single record spilled
            // onto several lines — splitting on newlines then pushed caption text into
            // the filename column. JSON keeps the full multi-line value in one field.
            var args = ["-j", "-charset", "utf8", "-FileName", "-Title", "-Description", "-Caption-Abstract", "-ImageDescription", "-ext", "tif", "-ext", "tiff", "-ext", "jpg", "-ext", "jpeg", "-ext", "png"]
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

                guard let objects = try? JSONSerialization.jsonObject(with: stdout) as? [[String: Any]] else {
                    return []
                }

                // First non-empty caption field wins, in this preference order.
                let captionKeys = ["Description", "Caption-Abstract", "ImageDescription", "Title"]
                var results: [(String, String)] = []
                for obj in objects {
                    let filename = (obj["FileName"] as? String) ?? ""
                    if filename.isEmpty { continue }

                    var caption = ""
                    for key in captionKeys {
                        let value: String?
                        if let s = obj[key] as? String {
                            value = s
                        } else if let n = obj[key] as? NSNumber {
                            value = n.stringValue
                        } else {
                            value = nil
                        }
                        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            caption = value
                            break
                        }
                    }
                    results.append((filename, caption))
                }

                return results
            } catch {
                throw CaptioneerError.exifToolFailed(error.localizedDescription)
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
            throw CaptioneerError.exifToolUnavailable("Version not found on exiftool.org")
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
            throw CaptioneerError.exifToolUnavailable("Extraction failed (tar)")
        }

        let exiftoolURL = supportDir.appendingPathComponent("Image-ExifTool-\(version)").appendingPathComponent("exiftool")
        try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: exiftoolURL.path)
        guard FileManager.default.isExecutableFile(atPath: exiftoolURL.path) else {
            throw CaptioneerError.exifToolUnavailable("Binary not found after extraction")
        }
        return exiftoolURL
    }
}
