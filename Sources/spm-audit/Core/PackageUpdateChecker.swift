//
//  PackageUpdateChecker.swift
//  spm-audit
//
//  Created by Ricky Witherspoon on 1/31/26.
//

import Foundation

final class PackageUpdateChecker: Sendable {
    private nonisolated(unsafe) let fileManager = FileManager.default
    private let workingDirectory: String
    private let githubClient: GitHubClient
    private let includeTransitive: Bool

    init(workingDirectory: String? = nil, includeTransitive: Bool = false) {
        self.workingDirectory = workingDirectory ?? FileManager.default.currentDirectoryPath
        self.githubClient = GitHubClient()
        self.includeTransitive = includeTransitive
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
            let readmeStatus = checkLocalReadme(for: filePath)
            OutputFormatter.printTable(sortedResults, source: filePath, readmeStatus: readmeStatus)
        }
    }

    // MARK: - Private Helpers

    private func findPackages() -> [PackageInfo] {
        var packages: [PackageInfo] = []

        guard let enumerator = fileManager.enumerator(atPath: workingDirectory) else {
            return packages
        }

        for case let path as String in enumerator {
            // Skip .build directories and test fixtures
            if path.contains("/.build/") || path.hasPrefix(".build/") ||
               path.contains("/Fixtures/") || path.contains("-tests/") {
                continue
            }

            if path.hasSuffix("Package.swift") {
                let fullPath = (workingDirectory as NSString).appendingPathComponent(path)
                packages.append(contentsOf: PackageSwiftParser.extractPackages(from: fullPath))
            } else if path.hasSuffix("Package.resolved") {
                let fullPath = (workingDirectory as NSString).appendingPathComponent(path)
                packages.append(contentsOf: PackageResolvedParser.extractPackages(from: fullPath, includeTransitive: includeTransitive))
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

    private func checkForUpdatesAsync(package: PackageInfo) async -> PackageUpdateResult {
        // Extract owner and repo from GitHub URL
        let components = package.url.components(separatedBy: "/")
        guard components.count >= 5,
              let ownerIndex = components.firstIndex(of: "github.com"),
              ownerIndex + 2 < components.count else {
            return PackageUpdateResult(
                package: package,
                status: .error("Could not parse GitHub URL"),
                readmeStatus: .unknown
            )
        }

        let owner = components[ownerIndex + 1]
        let repoWithGit = components[ownerIndex + 2]
        // Strip .git suffix if present (GitHub API requires URLs without .git)
        let repo = repoWithGit.replacingOccurrences(of: ".git", with: "")

        let result = await githubClient.fetchLatestRelease(owner: owner, repo: repo, package: package)

        // Return result with unknown README status (will be checked at project level)
        return PackageUpdateResult(
            package: result.package,
            status: result.status,
            readmeStatus: .unknown
        )
    }

    private func checkLocalReadme(for filePath: String) -> PackageUpdateResult.ReadmeStatus {
        // Determine the directory to check based on the file path
        let directory: String
        if filePath.hasSuffix("Package.swift") {
            // For Package.swift, check in the same directory
            directory = (filePath as NSString).deletingLastPathComponent
        } else if filePath.contains("Package.resolved") {
            // For Package.resolved, check in the project root
            // Navigate up from Package.resolved location to find the project root
            if filePath.contains(".xcodeproj") {
                // Xcode project: go up to the .xcodeproj's parent directory
                let components = filePath.components(separatedBy: "/")
                if let xcodeIndex = components.firstIndex(where: { $0.hasSuffix(".xcodeproj") }) {
                    let projectComponents = components.prefix(xcodeIndex)
                    directory = projectComponents.joined(separator: "/")
                } else {
                    directory = workingDirectory
                }
            } else {
                // SPM package: Package.resolved is usually in the root
                directory = (filePath as NSString).deletingLastPathComponent
            }
        } else {
            directory = workingDirectory
        }

        let readmePath = (directory as NSString).appendingPathComponent("README.md")
        return fileManager.fileExists(atPath: readmePath) ? .present : .missing
    }

    // MARK: - Public Test Helpers

    public func extractRequirementTypesPublic(from pbxprojPath: String) -> [String: PackageInfo.RequirementType] {
        return PbxprojParser.extractRequirementTypes(from: pbxprojPath)
    }

    public func extractPackagesFromResolvedPublic(from filePath: String, includeTransitive: Bool) -> [PackageInfo] {
        return PackageResolvedParser.extractPackages(from: filePath, includeTransitive: includeTransitive)
    }

    public func extractPackagesFromSwiftPackagePublic(from filePath: String) -> [PackageInfo] {
        return PackageSwiftParser.extractPackages(from: filePath)
    }

    public func compareVersionsPublic(_ latest: String, _ current: String) -> Bool {
        return VersionHelpers.compare(latest, current)
    }

    public func normalizeVersionPublic(_ version: String) -> String {
        return VersionHelpers.normalize(version)
    }

    public func extractSourceNamePublic(from path: String) -> String {
        return OutputFormatter.extractSourceNamePublic(from: path)
    }

    public func normalizeTagNamePublic(_ tag: String) -> String {
        return TagHelpers.normalize(tag)
    }

    public func isValidSemverTagPublic(_ tag: String) -> Bool {
        return TagHelpers.isValidSemver(tag)
    }

    public func isPrereleasePublic(_ tag: String) -> Bool {
        return TagHelpers.isPrerelease(tag)
    }

    func findPackagesPublic() -> [PackageInfo] {
        return findPackages()
    }

    public func checkLocalReadmePublic(for filePath: String) -> PackageUpdateResult.ReadmeStatus {
        return checkLocalReadme(for: filePath)
    }
}
