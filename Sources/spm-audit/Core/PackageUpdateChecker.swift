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
        print("🔍 Auditing project...\n")

        let packages = findPackages()

        if packages.isEmpty {
            print("⚠️  No packages with exact versions found.")

            // Still check and display README and License status for root project only
            // Check in the working directory (root project)
            let readmeStatus = checkReadmeInDirectory(for: workingDirectory)
            let licenseType = checkLicenseInDirectory(for: workingDirectory)

            print("\n📄 Project README: \(getReadmeIndicator(readmeStatus)) \(getReadmeText(readmeStatus))")
            print("⚖️  Project License: \(getLicenseIndicator(licenseType)) \(licenseType.displayName)")

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
            let readmeStatus = checkReadmeInDirectory(for: filePath)
            let licenseType = checkLicenseInDirectory(for: filePath)
            OutputFormatter.printTable(sortedResults, source: filePath, readmeStatus: readmeStatus, licenseType: licenseType)
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

    private func getReadmeIndicator(_ readmeStatus: PackageUpdateResult.ReadmeStatus) -> String {
        switch readmeStatus {
        case .present:
            return "✅"
        case .missing:
            return "❌"
        case .unknown:
            return "❓"
        }
    }

    private func getReadmeText(_ readmeStatus: PackageUpdateResult.ReadmeStatus) -> String {
        switch readmeStatus {
        case .present:
            return "Has README"
        case .missing:
            return "Missing README"
        case .unknown:
            return "README status unknown"
        }
    }

    private func getLicenseIndicator(_ licenseType: PackageUpdateResult.LicenseType) -> String {
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

    private func checkReadmeInDirectory(for filePath: String) -> PackageUpdateResult.ReadmeStatus {
        let directory = getDirectoryPath(for: filePath)
        let readmePath = (directory as NSString).appendingPathComponent("README.md")
        return fileManager.fileExists(atPath: readmePath) ? .present : .missing
    }

    private func checkLicenseInDirectory(for filePath: String) -> PackageUpdateResult.LicenseType {
        let directory = getDirectoryPath(for: filePath)

        // Common license file names
        let licenseFileNames = ["LICENSE", "LICENSE.txt", "LICENSE.md", "COPYING", "COPYING.txt", "LICENSE-MIT", "LICENSE-APACHE"]

        // Find the first license file that exists
        for fileName in licenseFileNames {
            let licensePath = (directory as NSString).appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: licensePath),
               let content = try? String(contentsOfFile: licensePath, encoding: .utf8) {
                return detectLicenseType(from: content)
            }
        }

        return .missing
    }

    private func detectLicenseType(from content: String) -> PackageUpdateResult.LicenseType {
        let uppercased = content.uppercased()

        // Check for specific license types based on content (ordered by specificity)

        // GNU licenses (check most specific first)
        if uppercased.contains("GNU AFFERO GENERAL PUBLIC LICENSE") ||
           (uppercased.contains("AGPL") && uppercased.contains("VERSION")) {
            return .agpl
        } else if uppercased.contains("GNU LESSER GENERAL PUBLIC LICENSE") ||
                  uppercased.contains("GNU LIBRARY GENERAL PUBLIC LICENSE") ||
                  (uppercased.contains("LGPL") && uppercased.contains("VERSION")) {
            return .lgpl
        } else if uppercased.contains("GNU GENERAL PUBLIC LICENSE") ||
                  (uppercased.contains("GPL") && uppercased.contains("VERSION") &&
                   !uppercased.contains("LGPL") && !uppercased.contains("AGPL")) {
            return .gpl
        }

        // Permissive licenses
        else if uppercased.contains("MIT LICENSE") ||
                (uppercased.contains("MIT") && uppercased.contains("PERMISSION IS HEREBY GRANTED")) {
            return .mit
        } else if uppercased.contains("APACHE LICENSE") ||
                  (uppercased.contains("APACHE") && uppercased.contains("VERSION 2.0")) {
            return .apache
        } else if (uppercased.contains("BSD") && uppercased.contains("REDISTRIBUTION")) ||
                  uppercased.contains("BSD-2-CLAUSE") ||
                  uppercased.contains("BSD-3-CLAUSE") {
            return .bsd
        } else if uppercased.contains("ISC LICENSE") ||
                  (uppercased.contains("ISC") && uppercased.contains("PERMISSION TO USE")) {
            return .isc
        }

        // Mozilla and other copyleft
        else if uppercased.contains("MOZILLA PUBLIC LICENSE") ||
                (uppercased.contains("MPL") && uppercased.contains("VERSION")) {
            return .mpl
        } else if uppercased.contains("ECLIPSE PUBLIC LICENSE") ||
                  uppercased.contains("EPL") {
            return .epl
        } else if uppercased.contains("EUROPEAN UNION PUBLIC LICENCE") ||
                  uppercased.contains("EUPL") {
            return .eupl
        }

        // Public domain and permissive
        else if uppercased.contains("UNLICENSE") ||
                uppercased.contains("THIS IS FREE AND UNENCUMBERED SOFTWARE RELEASED INTO THE PUBLIC DOMAIN") {
            return .unlicense
        } else if uppercased.contains("CC0") ||
                  uppercased.contains("CREATIVE COMMONS ZERO") {
            return .cc0
        }

        // Other known licenses
        else if uppercased.contains("ARTISTIC LICENSE") {
            return .artistic
        } else if uppercased.contains("BOOST SOFTWARE LICENSE") {
            return .boost
        } else if uppercased.contains("WTFPL") ||
                  uppercased.contains("DO WHAT THE FUCK YOU WANT") {
            return .wtfpl
        } else if uppercased.contains("ZLIB LICENSE") {
            return .zlib
        }

        // Unknown license - try to extract first line
        else {
            let lines = content.components(separatedBy: .newlines)
            if let firstLine = lines.first?.trimmingCharacters(in: .whitespaces),
               !firstLine.isEmpty {
                return .other(firstLine.prefix(50).description)
            }
            return .unknown
        }
    }

    private func getDirectoryPath(for filePath: String) -> String {
        // Determine the directory to check based on the file path
        if filePath.hasSuffix("Package.swift") {
            // For Package.swift, check in the same directory
            return (filePath as NSString).deletingLastPathComponent
        } else if filePath.contains("Package.resolved") {
            // For Package.resolved in Xcode projects, check the project root
            if filePath.contains(".xcodeproj") {
                let components = filePath.components(separatedBy: "/")
                if let xcodeIndex = components.firstIndex(where: { $0.hasSuffix(".xcodeproj") }) {
                    let projectComponents = components.prefix(xcodeIndex)
                    return projectComponents.joined(separator: "/")
                } else {
                    return (filePath as NSString).deletingLastPathComponent
                }
            } else {
                // For standalone Package.resolved, check in the same directory
                return (filePath as NSString).deletingLastPathComponent
            }
        } else {
            return workingDirectory
        }
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

    public func checkReadmeInDirectoryPublic(for filePath: String) -> PackageUpdateResult.ReadmeStatus {
        return checkReadmeInDirectory(for: filePath)
    }
}
