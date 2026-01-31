//
//  main.swift
//  spm-audit
//
//  Created by Ricky Witherspoon on 1/31/26.
//

import Foundation
import ArgumentParser

// MARK: - Version

let currentVersion = "0.1.1"

// MARK: - Version Checker

@Sendable
func checkForUpdates() async {
    let url = URL(string: "https://api.github.com/repos/Rspoon3/spm-audit/releases")!
    var request = URLRequest(url: url)
    request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
    request.timeoutInterval = 2.0 // Quick timeout to not block startup

    do {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return
        }

        struct Release: Codable {
            let tagName: String
            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
            }
        }

        let releases = try JSONDecoder().decode([Release].self, from: data)

        guard let latestRelease = releases.first else {
            return
        }

        let latestVersion = latestRelease.tagName

        if latestVersion != currentVersion {
            print("⚠️  A new version of spm-audit is available: \(latestVersion)")
            print("   Update with: brew upgrade spm-audit\n")
        }
    } catch {
        // Silently fail - don't bother the user with version check errors
    }
}

// MARK: - Models

enum UpdateError: Error, CustomStringConvertible {
    case packageNotFound(String)
    case versionNotFound(package: String, version: String)
    case invalidVersion(String)
    case unsupportedRequirementType(PackageInfo.RequirementType)
    case multipleSourcesFound(package: String, sources: [String])
    case fileNotWritable(String)
    case fileNotFound(String)
    case parseError(String)
    case xcodeProjectNotSupported(String)

    var description: String {
        switch self {
        case .packageNotFound(let name):
            return "Package '\(name)' not found in project"
        case .versionNotFound(let package, let version):
            return "Version '\(version)' not found for package '\(package)' on GitHub"
        case .invalidVersion(let version):
            return "Invalid version format: '\(version)'"
        case .unsupportedRequirementType(let type):
            return "Cannot update packages with requirement type '\(type.displayName)'. Only Exact, ^Major, ^Minor, and Range are supported."
        case .multipleSourcesFound(let package, let sources):
            return "Package '\(package)' found in multiple files: \(sources.joined(separator: ", "))"
        case .fileNotWritable(let path):
            return "File is not writable: \(path)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .parseError(let message):
            return "Parse error: \(message)"
        case .xcodeProjectNotSupported(let packageName):
            return "⚠️  Xcode project updates are not currently supported. Package '\(packageName)' is in an Xcode project. Please update it manually."
        }
    }
}

struct PackageInfo: Codable {
    let name: String
    let url: String
    let currentVersion: String
    let filePath: String
    let requirementType: RequirementType?

    enum RequirementType: String, Codable {
        case exact = "exactVersion"
        case upToNextMajor = "upToNextMajorVersion"
        case upToNextMinor = "upToNextMinorVersion"
        case range = "versionRange"
        case branch = "branch"
        case revision = "revision"

        var displayName: String {
            switch self {
            case .exact: return "Exact"
            case .upToNextMajor: return "^Major"
            case .upToNextMinor: return "^Minor"
            case .range: return "Range"
            case .branch: return "Branch"
            case .revision: return "Revision"
            }
        }
    }
}

struct GitHubRelease: Codable {
    let tagName: String
    let name: String?
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case prerelease
    }
}

struct PackageUpdateResult {
    let package: PackageInfo
    let status: UpdateStatus

    enum UpdateStatus {
        case upToDate(String)
        case updateAvailable(current: String, latest: String)
        case noReleases
        case error(String)
    }
}

struct PackageResolved: Codable {
    let pins: [Pin]
    let version: Int

    struct Pin: Codable {
        let identity: String
        let location: String
        let state: State

        struct State: Codable {
            let version: String?
        }
    }
}

// MARK: - Main

final class PackageUpdateChecker: Sendable {
    private nonisolated(unsafe) let fileManager = FileManager.default
    private let workingDirectory: String
    private let githubToken: String?
    private let includeTransitive: Bool

    init(workingDirectory: String? = nil, includeTransitive: Bool = false) {
        self.workingDirectory = workingDirectory ?? fileManager.currentDirectoryPath
        self.githubToken = Self.getGitHubToken()
        self.includeTransitive = includeTransitive
    }

    static func getGitHubToken() -> String? {
        // First check environment variable
        if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"] {
            return token
        }

        // Fall back to gh CLI token
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "auth", "token"]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !token.isEmpty {
                    return token
                }
            }
        } catch {
            return nil
        }

        return nil
    }

    func run() async {
        print("🔍 Scanning for Package.swift and Xcode project files...\n")

        let packages = findPackages()

        if packages.isEmpty {
            print("❌ No packages with exact versions found.")
            return
        }

        print("📦 Found \(packages.count) package(s) with exact versions")
        print("⚡️ Checking for updates in parallel...\n")

        // Check all packages in parallel and collect results
        var results: [PackageUpdateResult] = []
        await withTaskGroup(of: PackageUpdateResult.self) { group in
            for package in packages {
                group.addTask {
                    await self.checkForUpdatesAsync(package: package)
                }
            }

            for await result in group {
                results.append(result)
            }
        }

        // Group results by source file path
        let groupedResults = Dictionary(grouping: results) { result in
            result.package.filePath
        }

        // Print results grouped by source
        for (filePath, packageResults) in groupedResults.sorted(by: { $0.key < $1.key }) {
            let sortedResults = packageResults.sorted { $0.package.name < $1.package.name }
            printTable(sortedResults, source: filePath)
        }
    }

    // MARK: - Private Helpers

    private func findPackages() -> [PackageInfo] {
        var packages: [PackageInfo] = []

        guard let enumerator = fileManager.enumerator(atPath: workingDirectory) else {
            return packages
        }

        for case let path as String in enumerator {
            // Skip .build directories
            if path.contains("/.build/") {
                continue
            }

            if path.hasSuffix("Package.swift") {
                let fullPath = (workingDirectory as NSString).appendingPathComponent(path)
                packages.append(contentsOf: extractPackagesFromSwiftPackage(from: fullPath))
            } else if path.hasSuffix("Package.resolved") {
                let fullPath = (workingDirectory as NSString).appendingPathComponent(path)
                packages.append(contentsOf: extractPackagesFromResolved(from: fullPath, includeTransitive: includeTransitive))
            }
        }

        // Remove duplicates based on URL
        var seen: Set<String> = []
        return packages.filter { package in
            if seen.contains(package.url) {
                return false
            }
            seen.insert(package.url)
            return true
        }
    }

    private func extractPackagesFromSwiftPackage(from filePath: String) -> [PackageInfo] {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return []
        }

        var packages: [PackageInfo] = []

        // Pattern to match: url: "https://github.com/...", exact: "1.0.0"
        let pattern = #"url:\s*"(https://github\.com/[^"]+)",\s*exact:\s*"([^"]+)""#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))

        for match in matches {
            if match.numberOfRanges == 3 {
                let urlRange = match.range(at: 1)
                let versionRange = match.range(at: 2)

                let url = nsContent.substring(with: urlRange)
                let version = nsContent.substring(with: versionRange)

                // Extract package name from URL
                let name = url.components(separatedBy: "/").last ?? "Unknown"

                packages.append(PackageInfo(
                    name: name,
                    url: url,
                    currentVersion: version,
                    filePath: filePath,
                    requirementType: .exact
                ))
            }
        }

        return packages
    }

    private func extractPackagesFromResolved(from filePath: String, includeTransitive: Bool) -> [PackageInfo] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              let resolved = try? JSONDecoder().decode(PackageResolved.self, from: data) else {
            return []
        }

        // Find the project.pbxproj file to extract requirement types
        let projectPath = (filePath as NSString).deletingLastPathComponent
            .replacingOccurrences(of: "/project.xcworkspace/xcshareddata/swiftpm", with: "")
        let pbxprojPath = "\(projectPath)/project.pbxproj"
        let requirementTypes = extractRequirementTypes(from: pbxprojPath)

        var packages: [PackageInfo] = []

        for pin in resolved.pins {
            // Only include packages with versions (not branch/revision only)
            guard let version = pin.state.version else {
                continue
            }

            // Only include GitHub packages
            guard pin.location.contains("github.com") else {
                continue
            }

            // Clean up URL by removing .git suffix
            let cleanURL = pin.location.replacingOccurrences(of: ".git", with: "")

            // Get requirement type for this package
            let requirementType = requirementTypes[cleanURL] ?? requirementTypes[pin.location]

            // Skip transitive dependencies (packages not directly referenced in project.pbxproj)
            // unless includeTransitive flag is set
            if !includeTransitive && requirementType == nil {
                continue
            }

            // Extract package name from location
            let name = cleanURL.components(separatedBy: "/").last ?? pin.identity

            packages.append(PackageInfo(
                name: name,
                url: cleanURL,
                currentVersion: version,
                filePath: filePath,
                requirementType: requirementType
            ))
        }

        return packages
    }

    private func extractRequirementTypes(from pbxprojPath: String) -> [String: PackageInfo.RequirementType] {
        guard let content = try? String(contentsOfFile: pbxprojPath, encoding: .utf8) else {
            return [:]
        }

        var requirements: [String: PackageInfo.RequirementType] = [:]

        // Pattern to match XCRemoteSwiftPackageReference sections
        // Need to match content including nested braces
        let pattern = #"XCRemoteSwiftPackageReference[\s\S]*?repositoryURL = "([^"]+)";[\s\S]*?requirement = \{[\s\S]*?kind = (\w+);"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return [:]
        }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))

        for match in matches {
            if match.numberOfRanges == 3 {
                let urlRange = match.range(at: 1)
                let kindRange = match.range(at: 2)

                let url = nsContent.substring(with: urlRange).replacingOccurrences(of: ".git", with: "")
                let kind = nsContent.substring(with: kindRange)

                if let requirementType = PackageInfo.RequirementType(rawValue: kind) {
                    requirements[url] = requirementType
                }
            }
        }

        return requirements
    }

    private func checkForUpdatesAsync(package: PackageInfo) async -> PackageUpdateResult {
        // Extract owner and repo from GitHub URL
        let components = package.url.components(separatedBy: "/")
        guard components.count >= 5,
              let ownerIndex = components.firstIndex(of: "github.com"),
              ownerIndex + 2 < components.count else {
            return PackageUpdateResult(
                package: package,
                status: .error("Could not parse GitHub URL")
            )
        }

        let owner = components[ownerIndex + 1]
        let repo = components[ownerIndex + 2]

        return await fetchLatestRelease(owner: owner, repo: repo, package: package)
    }

    private func printTable(_ results: [PackageUpdateResult], source: String) {
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

        let statusWidth = 20

        // Print header
        let separator = "+" + String(repeating: "-", count: nameWidth) +
                       "+" + String(repeating: "-", count: typeWidth) +
                       "+" + String(repeating: "-", count: currentWidth) +
                       "+" + String(repeating: "-", count: latestWidth) +
                       "+" + String(repeating: "-", count: statusWidth) + "+"

        print(separator)
        print("| \(pad("Package", width: nameWidth - 2))" +
              " | \(pad("Type", width: typeWidth - 2))" +
              " | \(pad("Current", width: currentWidth - 2))" +
              " | \(pad("Latest", width: latestWidth - 2))" +
              " | \(pad("Status", width: statusWidth - 2)) |")
        print(separator)

        // Print rows
        for result in results {
            let name = result.package.name
            let type = result.package.requirementType?.displayName ?? "Unknown"
            let current = result.package.currentVersion

            let (latest, status) = getLatestAndStatus(result.status)

            print("| \(pad(name, width: nameWidth - 2))" +
                  " | \(pad(type, width: typeWidth - 2))" +
                  " | \(pad(current, width: currentWidth - 2))" +
                  " | \(pad(latest, width: latestWidth - 2))" +
                  " | \(pad(status, width: statusWidth - 2)) |")
        }

        print(separator)

        // Print summary
        let updateCount = results.filter {
            if case .updateAvailable = $0.status { return true }
            return false
        }.count

        print("\n📊 Summary: \(updateCount) update(s) available")
    }

    private func pad(_ text: String, width: Int) -> String {
        let padding = width - text.count
        if padding <= 0 {
            return text
        }
        return text + String(repeating: " ", count: padding)
    }

    private func extractSourceName(from path: String) -> String {
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

    private func getLatestAndStatus(_ status: PackageUpdateResult.UpdateStatus) -> (String, String) {
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

    private func fetchLatestRelease(owner: String, repo: String, package: PackageInfo) async -> PackageUpdateResult {
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/releases"

        guard let url = URL(string: urlString) else {
            return PackageUpdateResult(package: package, status: .error("Invalid API URL"))
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        // Add GitHub token if available (for private repos)
        if let token = githubToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return PackageUpdateResult(package: package, status: .error("Invalid response"))
            }

            if httpResponse.statusCode == 404 {
                return PackageUpdateResult(package: package, status: .noReleases)
            }

            guard httpResponse.statusCode == 200 else {
                return PackageUpdateResult(
                    package: package,
                    status: .error("API error (status \(httpResponse.statusCode))")
                )
            }

            let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)

            // Filter out prereleases and find the latest
            let stableReleases = releases.filter { !$0.prerelease }

            guard let latestRelease = stableReleases.first else {
                return PackageUpdateResult(package: package, status: .noReleases)
            }

            let latestVersion = normalizeVersion(latestRelease.tagName)

            if compareVersions(latestVersion, package.currentVersion) {
                return PackageUpdateResult(
                    package: package,
                    status: .updateAvailable(current: package.currentVersion, latest: latestVersion)
                )
            } else {
                return PackageUpdateResult(
                    package: package,
                    status: .upToDate(latestVersion)
                )
            }

        } catch {
            return PackageUpdateResult(
                package: package,
                status: .error(error.localizedDescription)
            )
        }
    }

    private func normalizeVersion(_ version: String) -> String {
        // Remove 'v' prefix and normalize
        version.replacingOccurrences(of: "v", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func compareVersions(_ latest: String, _ current: String) -> Bool {
        // Split versions into components
        let latestComponents = latest.split(separator: ".").compactMap { Int($0) }
        let currentComponents = current.split(separator: ".").compactMap { Int($0) }

        // Pad to same length (e.g., 2.3 becomes [2, 3, 0])
        let maxLength = max(latestComponents.count, currentComponents.count)
        var latestPadded = latestComponents
        var currentPadded = currentComponents

        while latestPadded.count < maxLength {
            latestPadded.append(0)
        }
        while currentPadded.count < maxLength {
            currentPadded.append(0)
        }

        // Compare component by component
        for (l, c) in zip(latestPadded, currentPadded) {
            if l > c {
                return true  // Update available
            } else if l < c {
                return false // Current is newer
            }
        }

        return false // Equal
    }

    // MARK: - Public Test Helpers

    public func extractRequirementTypesPublic(from pbxprojPath: String) -> [String: PackageInfo.RequirementType] {
        return extractRequirementTypes(from: pbxprojPath)
    }

    public func extractPackagesFromResolvedPublic(from filePath: String, includeTransitive: Bool) -> [PackageInfo] {
        return extractPackagesFromResolved(from: filePath, includeTransitive: includeTransitive)
    }

    public func compareVersionsPublic(_ latest: String, _ current: String) -> Bool {
        return compareVersions(latest, current)
    }

    public func normalizeVersionPublic(_ version: String) -> String {
        return normalizeVersion(version)
    }

    public func extractSourceNamePublic(from path: String) -> String {
        return extractSourceName(from: path)
    }
}

// MARK: - Package Updater

final class PackageUpdater: Sendable {
    private nonisolated(unsafe) let fileManager = FileManager.default
    private let workingDirectory: String
    private let githubToken: String?

    init(workingDirectory: String? = nil) {
        self.workingDirectory = workingDirectory ?? fileManager.currentDirectoryPath
        self.githubToken = PackageUpdateChecker.getGitHubToken()
    }

    func updatePackage(name: String, to version: String?) async throws {
        // Find the package
        let packages = findPackagesByName(name)

        guard !packages.isEmpty else {
            throw UpdateError.packageNotFound(name)
        }

        // Check for multiple sources
        let uniqueSources = Set(packages.map { $0.filePath })
        if uniqueSources.count > 1 {
            throw UpdateError.multipleSourcesFound(package: name, sources: Array(uniqueSources))
        }

        let package = packages[0]

        // Determine target version
        let targetVersion: String
        if let version = version {
            // Validate version format
            guard isValidVersion(version) else {
                throw UpdateError.invalidVersion(version)
            }
            // Verify version exists on GitHub
            try await verifyVersionExists(package: package, version: version)
            targetVersion = version
        } else {
            // Fetch latest version
            targetVersion = try await fetchLatestVersion(package: package)
        }

        // Check for downgrade
        if compareVersionsForDowngrade(targetVersion, package.currentVersion) {
            print("⚠️  Warning: Downgrading \(package.name) from \(package.currentVersion) to \(targetVersion)")
        }

        // Update the file
        try updateFile(package: package, newVersion: targetVersion)

        print("✅ Updated \(package.name) from \(package.currentVersion) to \(targetVersion)")
    }

    func updateAllPackages() async throws {
        let checker = PackageUpdateChecker(workingDirectory: workingDirectory, includeTransitive: false)
        let packages = checker.findPackagesPublic()

        guard !packages.isEmpty else {
            print("❌ No packages found")
            return
        }

        print("📦 Found \(packages.count) package(s)")
        print("⚡️ Checking for updates...\n")

        var updatedCount = 0
        var errorCount = 0

        for package in packages {
            do {
                let latestVersion = try await fetchLatestVersion(package: package)

                if latestVersion != package.currentVersion {
                    try updateFile(package: package, newVersion: latestVersion)
                    print("✅ Updated \(package.name): \(package.currentVersion) → \(latestVersion)")
                    updatedCount += 1
                } else {
                    print("ℹ️  \(package.name) is already up to date (\(package.currentVersion))")
                }
            } catch {
                print("❌ Failed to update \(package.name): \(error)")
                errorCount += 1
            }
        }

        print("\n📊 Summary: Updated \(updatedCount) package(s), \(errorCount) error(s)")
    }

    // MARK: - Private Helpers

    func findPackagesByName(_ name: String) -> [PackageInfo] {
        let checker = PackageUpdateChecker(workingDirectory: workingDirectory, includeTransitive: false)
        let allPackages = checker.findPackagesPublic()
        return allPackages.filter { $0.name == name || $0.name.lowercased() == name.lowercased() }
    }

    func isValidVersion(_ version: String) -> Bool {
        let components = version.split(separator: ".")
        guard components.count >= 2 && components.count <= 3 else {
            return false
        }
        return components.allSatisfy { Int($0) != nil }
    }

    private func verifyVersionExists(package: PackageInfo, version: String) async throws {
        let releases = try await fetchAllReleases(package: package)
        let normalizedVersion = normalizeVersion(version)

        let exists = releases.contains { release in
            let releaseVersion = normalizeVersion(release.tagName)
            return releaseVersion == normalizedVersion
        }

        guard exists else {
            throw UpdateError.versionNotFound(package: package.name, version: version)
        }
    }

    private func fetchLatestVersion(package: PackageInfo) async throws -> String {
        let releases = try await fetchAllReleases(package: package)

        let stableReleases = releases.filter { !$0.prerelease }

        guard let latestRelease = stableReleases.first else {
            throw UpdateError.versionNotFound(package: package.name, version: "latest")
        }

        return normalizeVersion(latestRelease.tagName)
    }

    private func fetchAllReleases(package: PackageInfo) async throws -> [GitHubRelease] {
        // Extract owner and repo from GitHub URL
        let components = package.url.components(separatedBy: "/")
        guard components.count >= 5,
              let ownerIndex = components.firstIndex(of: "github.com"),
              ownerIndex + 2 < components.count else {
            throw UpdateError.parseError("Could not parse GitHub URL: \(package.url)")
        }

        let owner = components[ownerIndex + 1]
        let repo = components[ownerIndex + 2]

        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/releases"

        guard let url = URL(string: urlString) else {
            throw UpdateError.parseError("Invalid API URL")
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        if let token = githubToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.parseError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            throw UpdateError.parseError("API error (status \(httpResponse.statusCode))")
        }

        return try JSONDecoder().decode([GitHubRelease].self, from: data)
    }

    private func compareVersionsForDowngrade(_ new: String, _ current: String) -> Bool {
        let newComponents = new.split(separator: ".").compactMap { Int($0) }
        let currentComponents = current.split(separator: ".").compactMap { Int($0) }

        let maxLength = max(newComponents.count, currentComponents.count)
        var newPadded = newComponents
        var currentPadded = currentComponents

        while newPadded.count < maxLength {
            newPadded.append(0)
        }
        while currentPadded.count < maxLength {
            currentPadded.append(0)
        }

        for (n, c) in zip(newPadded, currentPadded) {
            if n < c {
                return true  // Downgrade
            } else if n > c {
                return false // Upgrade
            }
        }

        return false // Equal
    }

    private func normalizeVersion(_ version: String) -> String {
        version.replacingOccurrences(of: "v", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func updateFile(package: PackageInfo, newVersion: String) throws {
        // Check if this is an Xcode project (Package.resolved file)
        if package.filePath.hasSuffix("Package.resolved") {
            throw UpdateError.xcodeProjectNotSupported(package.name)
        }

        // Only support Package.swift files
        guard package.filePath.hasSuffix("Package.swift") else {
            throw UpdateError.parseError("Unknown file type: \(package.filePath)")
        }

        guard fileManager.isWritableFile(atPath: package.filePath) else {
            throw UpdateError.fileNotWritable(package.filePath)
        }

        try updatePackageSwift(package: package, newVersion: newVersion)
    }

    private func updatePackageSwift(package: PackageInfo, newVersion: String) throws {
        guard var content = try? String(contentsOfFile: package.filePath, encoding: .utf8) else {
            throw UpdateError.fileNotFound(package.filePath)
        }

        // Pattern to match: url: "URL", exact: "VERSION"
        let escapedURL = NSRegularExpression.escapedPattern(for: package.url)
        let pattern = #"(url:\s*"\#(escapedURL)",\s*exact:\s*")([^"]+)(")"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            throw UpdateError.parseError("Could not create regex pattern")
        }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))

        guard matches.count == 1 else {
            throw UpdateError.parseError("Expected exactly one match for package URL in Package.swift")
        }

        let match = matches[0]
        let versionRange = match.range(at: 2)

        let before = nsContent.substring(to: versionRange.location)
        let after = nsContent.substring(from: versionRange.location + versionRange.length)

        content = before + newVersion + after

        try content.write(toFile: package.filePath, atomically: true, encoding: .utf8)
    }

    private func updatePbxproj(package: PackageInfo, newVersion: String) throws {
        // Get the project.pbxproj path from Package.resolved
        let projectPath = (package.filePath as NSString).deletingLastPathComponent
            .replacingOccurrences(of: "/project.xcworkspace/xcshareddata/swiftpm", with: "")
        let pbxprojPath = "\(projectPath)/project.pbxproj"

        guard fileManager.fileExists(atPath: pbxprojPath) else {
            throw UpdateError.fileNotFound(pbxprojPath)
        }

        guard fileManager.isWritableFile(atPath: pbxprojPath) else {
            throw UpdateError.fileNotWritable(pbxprojPath)
        }

        guard var content = try? String(contentsOfFile: pbxprojPath, encoding: .utf8) else {
            throw UpdateError.fileNotFound(pbxprojPath)
        }

        guard let requirementType = package.requirementType else {
            throw UpdateError.parseError("No requirement type found for package \(package.name)")
        }

        // Check for unsupported types
        if requirementType == .branch || requirementType == .revision {
            throw UpdateError.unsupportedRequirementType(requirementType)
        }

        // Create regex pattern based on requirement type
        let escapedURL = NSRegularExpression.escapedPattern(for: package.url)
        let pattern: String

        switch requirementType {
        case .exact:
            // Match: version = X.Y.Z;
            pattern = #"(XCRemoteSwiftPackageReference[\s\S]*?repositoryURL = "\#(escapedURL)(?:\.git)?";[\s\S]*?kind = exactVersion;\s*version = )([^;]+)(;)"#

        case .upToNextMajor, .upToNextMinor:
            // Match: minimumVersion = X.Y.Z;
            pattern = #"(XCRemoteSwiftPackageReference[\s\S]*?repositoryURL = "\#(escapedURL)(?:\.git)?";[\s\S]*?kind = \#(requirementType.rawValue);\s*minimumVersion = )([^;]+)(;)"#

        case .range:
            // Match: minimumVersion = X.Y.Z; (keep maximumVersion)
            pattern = #"(XCRemoteSwiftPackageReference[\s\S]*?repositoryURL = "\#(escapedURL)(?:\.git)?";[\s\S]*?kind = versionRange;(?:\s*maximumVersion = [^;]+;)?\s*minimumVersion = )([^;]+)(;)"#

        case .branch, .revision:
            throw UpdateError.unsupportedRequirementType(requirementType)
        }

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            throw UpdateError.parseError("Could not create regex pattern")
        }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))

        guard matches.count == 1 else {
            throw UpdateError.parseError("Expected exactly one match for package URL in project.pbxproj (found \(matches.count))")
        }

        let match = matches[0]
        let versionRange = match.range(at: 2)

        let before = nsContent.substring(to: versionRange.location)
        let after = nsContent.substring(from: versionRange.location + versionRange.length)

        content = before + newVersion + after

        try content.write(toFile: pbxprojPath, atomically: true, encoding: .utf8)
    }
}

// Expose PackageUpdateChecker methods for PackageUpdater
extension PackageUpdateChecker {
    func findPackagesPublic() -> [PackageInfo] {
        return findPackages()
    }
}

// MARK: - Commands

struct Audit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "audit",
        abstract: "Check for available package updates without modifying files",
        discussion: """
            Scans for Package.swift files and Xcode projects with SPM dependencies,
            then checks GitHub for the latest available releases. This is a read-only
            operation that reports which packages have updates available.

            EXAMPLES:
              # Check current directory
              spm-audit audit

              # Check specific directory
              spm-audit audit /path/to/project

              # Include transitive dependencies
              spm-audit audit --all

            The output shows a table with current versions, latest versions, and
            whether updates are available. Use 'spm-audit update' to apply updates.
            """
    )

    @Argument(
        help: "The directory to scan for Package.swift files (defaults to current directory)",
        completion: .directory
    )
    var directory: String?

    @Flag(name: .shortAndLong, help: "Include transitive dependencies (dependencies of dependencies)")
    var all: Bool = false

    func run() async throws {
        // Check for updates (quick, with timeout)
        await checkForUpdates()

        let checker = PackageUpdateChecker(workingDirectory: directory, includeTransitive: all)
        await checker.run()
    }
}

struct Update: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update package dependencies to newer versions",
        discussion: """
            Update package dependencies to their latest versions or to a specific version.
            This command MODIFIES your Package.swift files.

            ⚠️  IMPORTANT: Currently only supports Package.swift files.
            Xcode projects must be updated manually to prevent Xcode crashes.

            SUPPORTED REQUIREMENT TYPES:
              • Exact version (exact: "1.0.0")

            EXAMPLES:
              # Update all packages to latest
              spm-audit update all

              # Update one package to latest
              spm-audit update package swift-algorithms

              # Update one package to specific version
              spm-audit update package swift-algorithms --version 1.2.0

              # Update packages in specific directory
              spm-audit update all /path/to/project

            Run 'spm-audit audit' first to see which packages have updates available.
            """,
        subcommands: [UpdateAll.self, UpdatePackage.self]
    )
}

struct UpdateAll: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "all",
        abstract: "Update all packages to their latest stable versions",
        discussion: """
            Updates all packages in Package.swift files to their latest stable versions
            available on GitHub. Pre-release versions are skipped.

            ⚠️  Note: Only updates Package.swift files. Xcode projects must be updated manually.

            This command will:
              1. Scan for all packages in Package.swift files
              2. Fetch the latest stable version for each from GitHub
              3. Update the Package.swift files
              4. Show a summary of what was updated

            EXAMPLES:
              # Update all packages in current directory
              spm-audit update all

              # Update all packages in specific directory
              spm-audit update all /path/to/project

            TIP: Run 'spm-audit audit' first to preview what will be updated.
            """
    )

    @Argument(
        help: "The directory to scan for packages (defaults to current directory)",
        completion: .directory
    )
    var directory: String?

    func run() async throws {
        // Check for updates (quick, with timeout)
        await checkForUpdates()

        let updater = PackageUpdater(workingDirectory: directory)
        try await updater.updateAllPackages()
    }
}

struct UpdatePackage: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "package",
        abstract: "Update a specific package to latest or specific version",
        discussion: """
            Updates a specific package to the latest stable version or to a specified version.
            The package name should match the repository name (e.g., "swift-algorithms").

            ⚠️  Note: Only updates packages in Package.swift files. Xcode projects must be
            updated manually through Xcode to prevent crashes.

            This command will:
              1. Find the package in your Package.swift files
              2. Validate the target version exists on GitHub (if specified)
              3. Update the Package.swift file
              4. Warn if downgrading to an older version

            EXAMPLES:
              # Update to latest stable version
              spm-audit update package swift-algorithms

              # Update to specific version
              spm-audit update package swift-algorithms --version 1.2.0
              spm-audit update package swift-algorithms -v 1.2.0

              # Update package in specific directory
              spm-audit update package swift-algorithms /path/to/project

            NOTE: The version will be validated against GitHub releases before updating.
            """
    )

    @Argument(help: "The name of the package to update")
    var name: String

    @Option(name: .shortAndLong, help: "Update to a specific version (defaults to latest)")
    var version: String?

    @Argument(
        help: "The directory to scan for packages (defaults to current directory)",
        completion: .directory
    )
    var directory: String?

    func run() async throws {
        // Check for updates (quick, with timeout)
        await checkForUpdates()

        let updater = PackageUpdater(workingDirectory: directory)
        try await updater.updatePackage(name: name, to: version)
    }
}

// MARK: - Entry Point

@main
struct SPMAudit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "spm-audit",
        abstract: "Audit and update Swift Package Manager dependencies",
        discussion: """
            A tool to check for available updates and update Swift Package Manager dependencies.
            Works with both Package.swift files and Xcode projects using SPM.

            COMMANDS:
              audit      Check for available updates (default)
              update     Update packages to newer versions

            EXAMPLES:
              # Check for updates (default command)
              spm-audit
              spm-audit audit

              # Update all packages to latest versions
              spm-audit update all

              # Update a specific package to latest
              spm-audit update package swift-algorithms

              # Update a specific package to a specific version
              spm-audit update package swift-algorithms --version 1.2.0

            AUTHENTICATION:
              Set GITHUB_TOKEN environment variable or use 'gh auth login' for
              higher API rate limits and access to private repositories.
            """,
        version: "1.0.0",
        subcommands: [Audit.self, Update.self],
        defaultSubcommand: Audit.self
    )
}
