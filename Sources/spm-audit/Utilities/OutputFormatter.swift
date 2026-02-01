//
//  OutputFormatter.swift
//  spm-audit
//
//  Created by Ricky Witherspoon on 1/31/26.
//

import Foundation

enum OutputFormatter {
    /// Error types for formatting operations
    enum FormattingError: Error {
        case columnFailed(String)
        case encodingFailed
    }

    /// Print a formatted table of package update results
    static func printTable(_ results: [PackageUpdateResult], source: String) {
        // Print source header
        let sourceName = extractSourceName(from: source)
        print("\n📋 \(sourceName)")
        print(String(repeating: "─", count: 80))

        // Generate pipe-delimited content
        let pipeDelimited = generatePipeDelimited(results)

        // Try to format with column command, fall back if needed
        let alignedLines: [String]
        do {
            let formatted = try formatWithColumn(pipeDelimited)
            alignedLines = formatted.split(separator: "\n").map(String.init)
        } catch {
            let formatted = formatFallback(pipeDelimited)
            alignedLines = formatted.split(separator: "\n").map(String.init)
        }

        // Add borders and print
        guard !alignedLines.isEmpty else {
            print("\n📊 Summary: 0 update(s) available")
            return
        }

        // Generate separator from first line (header)
        let separator = generateSeparator(from: alignedLines[0])

        // Print with borders
        print(separator)
        for (index, line) in alignedLines.enumerated() {
            print(line)
            if index == 0 {
                // Separator after header
                print(separator)
            }
        }
        print(separator)

        // Print summary
        let updateCount = results.filter {
            if case .updateAvailable = $0.status { return true }
            return false
        }.count

        print("\n📊 Summary: \(updateCount) update(s) available")
    }

    /// Generate pipe-delimited content from results
    private static func generatePipeDelimited(_ results: [PackageUpdateResult]) -> String {
        var lines: [String] = []

        // Header row
        let headers = ["Package", "Type", "Current", "Swift", "Latest", "Status",
                       "README", "License", "CLAUDE.md", "AGENTS.md"]
        lines.append("| " + headers.joined(separator: " | ") + " |")

        // Data rows
        for result in results {
            let name = result.package.name
            let type = result.package.requirementType?.displayName ?? "Unknown"
            let current = result.package.currentVersion
            let swift = result.package.swiftVersion ?? "N/A"
            let readme = getReadmeIndicator(result.readmeStatus)
            let license = result.licenseType.displayName
            let claude = getFileIndicator(result.claudeFileStatus)
            let agents = getFileIndicator(result.agentsFileStatus)
            let (latest, status) = getLatestAndStatus(result.status)

            let fields = [name, type, current, swift, latest, status,
                          readme, license, claude, agents]
            lines.append("| " + fields.joined(separator: " | ") + " |")
        }

        return lines.joined(separator: "\n")
    }

    /// Format pipe-delimited content using the column command
    private static func formatWithColumn(_ pipeDelimited: String) throws -> String {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        // Configure process
        process.executableURL = URL(fileURLWithPath: "/usr/bin/column")
        process.arguments = ["-t", "-s", "|"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Write pipe-delimited to stdin
        let inputHandle = inputPipe.fileHandleForWriting
        if let data = pipeDelimited.data(using: .utf8) {
            inputHandle.write(data)
        }
        try inputHandle.close()

        // Execute
        try process.run()
        process.waitUntilExit()

        // Check exit status
        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw FormattingError.columnFailed(errorMsg)
        }

        // Read output
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: outputData, encoding: .utf8) else {
            throw FormattingError.encodingFailed
        }

        return output
    }

    /// Generate separator line based on aligned output
    private static func generateSeparator(from alignedLine: String) -> String {
        var separator = ""
        for char in alignedLine {
            if char == "|" {
                separator.append("+")
            } else {
                separator.append("-")
            }
        }
        return separator
    }

    /// Fallback formatting if column command fails
    private static func formatFallback(_ pipeDelimited: String) -> String {
        let lines = pipeDelimited.split(separator: "\n").map(String.init)
        guard !lines.isEmpty else { return pipeDelimited }

        // Parse pipe-delimited lines and calculate max width per column
        var columnWidths: [Int] = []
        var parsedLines: [[String]] = []

        for line in lines {
            // Split by | and trim spaces, skip empty first/last elements
            let fields = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            parsedLines.append(fields)

            for (index, field) in fields.enumerated() {
                if index >= columnWidths.count {
                    columnWidths.append(field.count)
                } else {
                    columnWidths[index] = max(columnWidths[index], field.count)
                }
            }
        }

        // Format with padding and pipes
        var formatted: [String] = []
        for fields in parsedLines {
            var formattedLine = "|"
            for (index, field) in fields.enumerated() {
                let width = columnWidths[index]
                let padded = field.padding(toLength: width, withPad: " ", startingAt: 0)
                formattedLine += " \(padded) |"
            }
            formatted.append(formattedLine)
        }

        return formatted.joined(separator: "\n")
    }

    private static func extractSourceName(from path: String) -> String {
        // Extract a readable name from the file path
        if path.contains("Package.swift") {
            // For Package.swift files, get the package name from the directory
            let components = path.components(separatedBy: "/")
            if let packageIndex = components.lastIndex(where: { $0 == "Package.swift" }),
               packageIndex > 0 {
                return "\(components[packageIndex - 1]) (Package.swift)"
            }
            return "Package.swift"
        } else if path.contains("Package.resolved") {
            // For Package.resolved, try to get the project/package name
            let components = path.components(separatedBy: "/")
            if components.contains("Package.resolved") {
                // Look for .xcodeproj in the path
                if let xcodeIndex = components.firstIndex(where: { $0.hasSuffix(".xcodeproj") }) {
                    let projectName = components[xcodeIndex].replacingOccurrences(of: ".xcodeproj", with: "")
                    return "\(projectName) (Xcode Project)"
                }
            }
            return "Package.resolved"
        }
        return path
    }

    private static func getLatestAndStatus(_ status: PackageUpdateResult.UpdateStatus) -> (String, String) {
        switch status {
        case .upToDate(let latest):
            return (latest, "✅ Up to date ")
        case .updateAvailable(_, let latest):
            return (latest, "⚠️  Update available ")
        case .noReleases:
            return ("N/A", "⚠️  No releases ")
        case .error:
            return ("N/A", "❌ Error ")
        }
    }

    private static func getReadmeIndicator(_ readmeStatus: PackageUpdateResult.ReadmeStatus) -> String {
        switch readmeStatus {
        case .present:
            return "✅"
        case .missing:
            return "❌"
        case .unknown:
            return "❓"
        }
    }

    private static func getReadmeText(_ readmeStatus: PackageUpdateResult.ReadmeStatus) -> String {
        switch readmeStatus {
        case .present:
            return "Has README"
        case .missing:
            return "Missing README"
        case .unknown:
            return "README status unknown"
        }
    }

    private static func getFileIndicator(_ fileStatus: PackageUpdateResult.FileStatus) -> String {
        switch fileStatus {
        case .present:
            return "✅"
        case .missing:
            return "❌"
        case .unknown:
            return "❓"
        }
    }

    private static func getLicenseIndicator(_ licenseType: PackageUpdateResult.LicenseType) -> String {
        switch licenseType {
        case .gpl, .agpl, .lgpl, .mpl, .epl, .eupl:
            // Copyleft licenses - require derivative works to use same license
            return "⚠️ "
        case .mit, .apache, .bsd, .isc, .unlicense, .cc0, .boost, .wtfpl, .zlib, .artistic:
            // Permissive licenses - minimal restrictions
            return "✅"
        case .other:
            return "ℹ️ "
        case .missing:
            return "❌"
        case .unknown:
            return "❓"
        }
    }

    // MARK: - Public Test Helpers

    public static func extractSourceNamePublic(from path: String) -> String {
        return extractSourceName(from: path)
    }

    public static func generatePipeDelimitedPublic(_ results: [PackageUpdateResult]) -> String {
        return generatePipeDelimited(results)
    }

    public static func formatWithColumnPublic(_ pipeDelimited: String) throws -> String {
        return try formatWithColumn(pipeDelimited)
    }

    public static func generateSeparatorPublic(from alignedLine: String) -> String {
        return generateSeparator(from: alignedLine)
    }

    public static func formatFallbackPublic(_ pipeDelimited: String) -> String {
        return formatFallback(pipeDelimited)
    }
}
