//
//  OutputFormatter.swift
//  spm-audit
//
//  Created by Ricky Witherspoon on 1/31/26.
//

import Foundation

enum OutputFormatter {
    /// Print a formatted table of package update results
    static func printTable(_ results: [PackageUpdateResult], source: String) {
        // Print source header
        let sourceName = extractSourceName(from: source)
        print("\n📋 \(sourceName)")
        print(String(repeating: "─", count: 80))

        // Calculate column widths
        let nameWidth = max(
            results.map { $0.package.name.count }.max() ?? 0,
            "Package".count
        ) + 2

        let typeWidth = 10 // "Exact", "Range", etc.

        let currentWidth = max(
            results.map { $0.package.currentVersion.count }.max() ?? 0,
            "Current".count
        ) + 2

        let swiftWidth = max(
            results.compactMap { $0.package.swiftVersion?.count }.max() ?? 0,
            "Swift".count
        ) + 2

        let latestWidth = max(
            results.compactMap { result -> Int? in
                switch result.status {
                case .upToDate(let v), .updateAvailable(_, let v):
                    return v.count
                default:
                    return nil
                }
            }.max() ?? 0,
            "Latest".count
        ) + 2

        let statusWidth = max(
            "⚠️  Update available ".count,
            "Status".count
        ) + 2

        let readmeWidth = 8 // "README" or icons

        let licenseWidth = max(
            results.map { $0.licenseType.displayName.count }.max() ?? 0,
            "License".count
        ) + 2

        // Print header
        let separator = "+" + String(repeating: "-", count: nameWidth) +
                       "+" + String(repeating: "-", count: typeWidth) +
                       "+" + String(repeating: "-", count: currentWidth) +
                       "+" + String(repeating: "-", count: swiftWidth) +
                       "+" + String(repeating: "-", count: latestWidth) +
                       "+" + String(repeating: "-", count: statusWidth) +
                       "+" + String(repeating: "-", count: readmeWidth) +
                       "+" + String(repeating: "-", count: licenseWidth) + "+"

        print(separator)
        print("| \(pad("Package", width: nameWidth - 2))" +
              " | \(pad("Type", width: typeWidth - 2))" +
              " | \(pad("Current", width: currentWidth - 2))" +
              " | \(pad("Swift", width: swiftWidth - 2))" +
              " | \(pad("Latest", width: latestWidth - 2))" +
              " | \(pad("Status", width: statusWidth - 2))" +
              " | \(pad("README", width: readmeWidth - 2))" +
              " | \(pad("License", width: licenseWidth - 2)) |")
        print(separator)

        // Print rows
        for result in results {
            let name = result.package.name
            let type = result.package.requirementType?.displayName ?? "Unknown"
            let current = result.package.currentVersion
            let swift = result.package.swiftVersion ?? "N/A"
            let readme = getReadmeIndicator(result.readmeStatus)
            let license = result.licenseType.displayName

            let (latest, status) = getLatestAndStatus(result.status)

            print("| \(pad(name, width: nameWidth - 2))" +
                  " | \(pad(type, width: typeWidth - 2))" +
                  " | \(pad(current, width: currentWidth - 2))" +
                  " | \(pad(swift, width: swiftWidth - 2))" +
                  " | \(pad(latest, width: latestWidth - 2))" +
                  " | \(pad(status, width: statusWidth - 2))" +
                  " | \(pad(readme, width: readmeWidth - 2))" +
                  " | \(pad(license, width: licenseWidth - 2)) |")
        }

        print(separator)

        // Print summary
        let updateCount = results.filter {
            if case .updateAvailable = $0.status { return true }
            return false
        }.count

        print("\n📊 Summary: \(updateCount) update(s) available")
    }

    private static func pad(_ text: String, width: Int) -> String {
        let padding = width - text.count
        if padding <= 0 {
            return text
        }
        return text + String(repeating: " ", count: padding)
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
}
