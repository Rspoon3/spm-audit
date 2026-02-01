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
            OutputFormatter.printTable(sortedResults, source: filePath)
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

        // Check for updates and README in parallel
        async let updateResult = githubClient.fetchLatestRelease(owner: owner, repo: repo, package: package)
        async let readmeStatus = githubClient.checkReadmeExists(owner: owner, repo: repo)

        let result = await updateResult
        let readme = await readmeStatus

        // Return a new result with README status
        return PackageUpdateResult(
            package: result.package,
            status: result.status,
            readmeStatus: readme
        )
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
}
