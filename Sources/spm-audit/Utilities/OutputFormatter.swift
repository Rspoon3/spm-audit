//
//  OutputFormatter.swift
//  spm-audit
//
//  Created by Ricky Witherspoon on 1/31/26.
//

import Foundation
import ASCIITable

enum OutputFormatter {
    /// Print a formatted table of package update results
    static func printTable(_ results: [PackageUpdateResult], source: String) {
        // Print source header
        let sourceName = extractSourceName(from: source)
        print("\n📋 \(sourceName)")
        print(String(repeating: "─", count: 80))

        // Check if there are results to display
        guard !results.isEmpty else {
            print("\n📊 Summary: 0 update(s) available")
            return
        }

        // Create table with columns
        let table = ASCIITable(columns: ["Package", "Type", "Current", "Swift", "Latest", "Status",
                                          "README", "License", "CLAUDE.md", "AGENTS.md", "Last Commit"])
            .sort(.by(column: "Package", transform: { $0.lowercased() }))

        // Add rows for each result
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
            let lastCommit = formatLastCommitDate(result.lastCommitDate)

            table.addRow([name, type, current, swift, latest, status,
                          readme, license, claude, agents, lastCommit])
        }

        // Print the table
        print(table.render())

        // Print summary
        let updateCount = results.filter {
            if case .updateAvailable = $0.status { return true }
            return false
        }.count

        print("\n📊 Summary: \(updateCount) update(s) available")
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
            return (latest, "✅ Up to date")
        case .updateAvailable(_, let latest):
            return (latest, "⚠️  Update available")
        case .noReleases:
            return ("N/A", "⚠️  No releases")
        case .error:
            return ("N/A", "❌ Error")
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

    private static func formatLastCommitDate(_ date: Date?) -> String {
        guard let date = date else {
            return "N/A"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let dateString = formatter.string(from: date)

        // Calculate age
        let ageInDays = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        let sixMonthsInDays = 182 // Approximately 6 months
        let oneYearInDays = 365

        // Apply color codes based on age
        if ageInDays > oneYearInDays {
            // Red for older than a year
            return "\u{001B}[31m\(dateString)\u{001B}[0m"
        } else if ageInDays > sixMonthsInDays {
            // Yellow for 6 months to a year
            return "\u{001B}[33m\(dateString)\u{001B}[0m"
        } else {
            // Green for newer than 6 months
            return "\u{001B}[32m\(dateString)\u{001B}[0m"
        }
    }

    // MARK: - Public Test Helpers

    public static func extractSourceNamePublic(from path: String) -> String {
        return extractSourceName(from: path)
    }
}
