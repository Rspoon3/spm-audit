//
//  PackageUpdater.swift
//  spm-audit
//
//  Created by Ricky Witherspoon on 1/31/26.
//

import Foundation

final class PackageUpdater: Sendable {
    private nonisolated(unsafe) let fileManager = FileManager.default
    private let workingDirectory: String
    private let githubClient: GitHubClient

    init(workingDirectory: String? = nil) {
        self.workingDirectory = workingDirectory ?? FileManager.default.currentDirectoryPath
        self.githubClient = GitHubClient()
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
        let releases = try await githubClient.fetchAllReleases(package: package)
        let normalizedVersion = VersionHelpers.normalize(version)

        let exists = releases.contains { release in
            let releaseVersion = VersionHelpers.normalize(release.tagName)
            return releaseVersion == normalizedVersion
        }

        guard exists else {
            throw UpdateError.versionNotFound(package: package.name, version: version)
        }
    }

    private func fetchLatestVersion(package: PackageInfo) async throws -> String {
        let releases = try await githubClient.fetchAllReleases(package: package)

        let stableReleases = releases.filter { !$0.prerelease }

        guard let latestRelease = stableReleases.first else {
            throw UpdateError.versionNotFound(package: package.name, version: "latest")
        }

        return VersionHelpers.normalize(latestRelease.tagName)
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
