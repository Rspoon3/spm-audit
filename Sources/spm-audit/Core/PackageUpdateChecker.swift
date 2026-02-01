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

        // Check and display project README and License status ONCE at the start
        let projectReadmeStatus = checkReadmeInDirectory(for: workingDirectory)
        let projectLicenseType = checkLicenseInDirectory(for: workingDirectory)
        let projectClaudeFileStatus = checkClaudeFileInDirectory(for: workingDirectory)
        let projectAgentsFileStatus = checkAgentsFileInDirectory(for: workingDirectory)
        print("📄 Project README: \(getReadmeIndicator(projectReadmeStatus)) \(getReadmeText(projectReadmeStatus))")
        print("⚖️  Project License: \(getLicenseIndicator(projectLicenseType)) \(projectLicenseType.displayName)")
        print("🤖 Project CLAUDE.md: \(getFileIndicator(projectClaudeFileStatus)) \(getFileText(projectClaudeFileStatus, fileName: "CLAUDE.md"))")
        print("🤖 Project AGENTS.md: \(getFileIndicator(projectAgentsFileStatus)) \(getFileText(projectAgentsFileStatus, fileName: "AGENTS.md"))\n")

        let packages = findPackages()

        if packages.isEmpty {
            print("⚠️  No packages with exact versions found.")
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
        let sortedGroups = groupedResults.sorted(by: { $0.key < $1.key })
        for (index, (filePath, packageResults)) in sortedGroups.enumerated() {
            let sortedResults = packageResults.sorted { $0.package.name < $1.package.name }
            OutputFormatter.printTable(sortedResults, source: filePath)

            // Add spacing after summary if not last
            if index < sortedGroups.count - 1 {
                print("\n\n")
            }
        }

        // Show local packages when using --all flag
        if includeTransitive {
            printLocalPackages()
        }
    }

    // MARK: - Private Helpers

    private struct LocalPackage {
        let name: String
        let path: String
        let swiftVersion: String?
    }

    private func findLocalPackages() -> [LocalPackage] {
        var localPackages: [LocalPackage] = []

        guard let enumerator = fileManager.enumerator(atPath: workingDirectory) else {
            return localPackages
        }

        for case let path as String in enumerator {
            // Skip .build directories, test fixtures, and DerivedData
            if path.contains("/.build/") || path.hasPrefix(".build/") ||
               path.contains("/Fixtures/") || path.contains("-tests/") ||
               path.contains("DerivedData/") {
                continue
            }

            if path.hasSuffix("Package.swift") {
                let fullPath = (workingDirectory as NSString).appendingPathComponent(path)
                let packageDir = (fullPath as NSString).deletingLastPathComponent
                let packageName = (packageDir as NSString).lastPathComponent

                // Extract swift-tools-version
                let swiftVersion = extractSwiftVersion(from: packageDir)

                localPackages.append(LocalPackage(
                    name: packageName,
                    path: packageDir,
                    swiftVersion: swiftVersion
                ))
            }
        }

        // Sort by name
        return localPackages.sorted { $0.name < $1.name }
    }

    private func printLocalPackages() {
        let localPackages = findLocalPackages()

        guard !localPackages.isEmpty else {
            return
        }

        // Convert local packages to PackageUpdateResult objects for table display
        var results: [PackageUpdateResult] = []
        for package in localPackages {
            let readmeStatus = checkReadmeInDirectory(for: package.path)
            let licenseType = checkLicenseInDirectory(for: package.path)
            let claudeFileStatus = checkClaudeFileInDirectory(for: package.path)
            let agentsFileStatus = checkAgentsFileInDirectory(for: package.path)

            // Create a PackageInfo for the local package
            let packageInfo = PackageInfo(
                name: package.name,
                url: "local://\(package.name)", // Local packages don't have URLs
                currentVersion: "N/A",
                filePath: package.path,
                requirementType: nil,
                swiftVersion: package.swiftVersion
            )

            // Create a result with N/A status (local packages aren't checked for updates)
            let result = PackageUpdateResult(
                package: packageInfo,
                status: .upToDate("N/A"), // No version tracking for local packages
                readmeStatus: readmeStatus,
                licenseType: licenseType,
                claudeFileStatus: claudeFileStatus,
                agentsFileStatus: agentsFileStatus,
                lastCommitDate: nil
            )

            results.append(result)
        }

        print("\n\n")
        OutputFormatter.printTable(results, source: "Local Packages")
    }

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

    private func findCheckoutPath(for packageName: String) -> String? {
        // Try local .build/checkouts first (for SPM projects)
        let localCheckoutPath = (workingDirectory as NSString).appendingPathComponent(".build/checkouts/\(packageName)")
        if fileManager.fileExists(atPath: localCheckoutPath) {
            return localCheckoutPath
        }

        // For Xcode projects, check DerivedData
        // Find all DerivedData directories and look for SourcePackages/checkouts
        let derivedDataPath = NSString(string: "~/Library/Developer/Xcode/DerivedData").expandingTildeInPath

        guard let derivedDataContents = try? fileManager.contentsOfDirectory(atPath: derivedDataPath) else {
            return nil
        }

        // Look through all DerivedData project directories
        for projectDir in derivedDataContents {
            let projectPath = (derivedDataPath as NSString).appendingPathComponent(projectDir)
            let checkoutPath = (projectPath as NSString).appendingPathComponent("SourcePackages/checkouts/\(packageName)")

            if fileManager.fileExists(atPath: checkoutPath) {
                return checkoutPath
            }
        }

        return nil
    }

    func extractSwiftVersion(from checkoutPath: String) -> String? {
        // Check if the checkout directory exists
        guard fileManager.fileExists(atPath: checkoutPath) else {
            return nil
        }

        let packageSwiftPath = (checkoutPath as NSString).appendingPathComponent("Package.swift")
        guard let content = try? String(contentsOfFile: packageSwiftPath, encoding: .utf8) else {
            return nil
        }

        // Pattern to match swift-tools-version comment at the top of Package.swift
        // Examples: // swift-tools-version:5.7
        //          // swift-tools-version: 5.9
        //          // swift-tools-version:6.0
        let pattern = #"//\s*swift-tools-version:\s*(\d+\.\d+)"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: content, options: [], range: NSRange(location: 0, length: (content as NSString).length)),
              match.numberOfRanges == 2 else {
            return nil
        }

        let versionRange = match.range(at: 1)
        return (content as NSString).substring(with: versionRange)
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
                readmeStatus: .unknown,
                licenseType: .unknown,
                claudeFileStatus: .unknown,
                agentsFileStatus: .unknown,
                lastCommitDate: nil
            )
        }

        let owner = components[ownerIndex + 1]
        let repoWithGit = components[ownerIndex + 2]
        // Strip .git suffix if present (GitHub API requires URLs without .git)
        let repo = repoWithGit.replacingOccurrences(of: ".git", with: "")

        let result = await githubClient.fetchLatestRelease(owner: owner, repo: repo, package: package)

        // Fetch last commit date
        let lastCommitDate = await githubClient.fetchLastCommitDate(owner: owner, repo: repo)

        // Check README, license, CLAUDE.md, AGENTS.md, and Swift version in the dependency's checkout directory
        // This works for both SPM projects and Xcode projects (DerivedData)
        let checkoutPath = findCheckoutPath(for: package.name)
        let readmeStatus = checkoutPath.map { checkDependencyReadme(in: $0) } ?? .unknown
        let licenseType = checkoutPath.map { checkDependencyLicense(in: $0) } ?? .unknown
        let claudeFileStatus = checkoutPath.map { checkDependencyClaudeFile(in: $0) } ?? .unknown
        let agentsFileStatus = checkoutPath.map { checkDependencyAgentsFile(in: $0) } ?? .unknown
        let swiftVersion = checkoutPath.flatMap { extractSwiftVersion(from: $0) }

        // Create updated package with Swift version
        let updatedPackage = PackageInfo(
            name: result.package.name,
            url: result.package.url,
            currentVersion: result.package.currentVersion,
            filePath: result.package.filePath,
            requirementType: result.package.requirementType,
            swiftVersion: swiftVersion
        )

        // Return result with dependency's README, license, CLAUDE.md, AGENTS.md status, and Swift version
        return PackageUpdateResult(
            package: updatedPackage,
            status: result.status,
            readmeStatus: readmeStatus,
            licenseType: licenseType,
            claudeFileStatus: claudeFileStatus,
            agentsFileStatus: agentsFileStatus,
            lastCommitDate: lastCommitDate
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

    private func getFileIndicator(_ fileStatus: PackageUpdateResult.FileStatus) -> String {
        switch fileStatus {
        case .present:
            return "✅"
        case .missing:
            return "❌"
        case .unknown:
            return "❓"
        }
    }

    private func getFileText(_ fileStatus: PackageUpdateResult.FileStatus, fileName: String) -> String {
        switch fileStatus {
        case .present:
            return "Has \(fileName)"
        case .missing:
            return "Missing \(fileName)"
        case .unknown:
            return "\(fileName) status unknown"
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

    private func checkClaudeFileInDirectory(for filePath: String) -> PackageUpdateResult.FileStatus {
        let directory = getDirectoryPath(for: filePath)
        let claudePath = (directory as NSString).appendingPathComponent("CLAUDE.md")
        return fileManager.fileExists(atPath: claudePath) ? .present : .missing
    }

    private func checkAgentsFileInDirectory(for filePath: String) -> PackageUpdateResult.FileStatus {
        let directory = getDirectoryPath(for: filePath)
        let agentsPath = (directory as NSString).appendingPathComponent("AGENTS.md")
        return fileManager.fileExists(atPath: agentsPath) ? .present : .missing
    }

    private func checkDependencyReadme(in checkoutPath: String) -> PackageUpdateResult.ReadmeStatus {
        // Check if the checkout directory exists
        guard fileManager.fileExists(atPath: checkoutPath) else {
            return .unknown
        }

        let readmePath = (checkoutPath as NSString).appendingPathComponent("README.md")
        return fileManager.fileExists(atPath: readmePath) ? .present : .missing
    }

    private func checkDependencyClaudeFile(in checkoutPath: String) -> PackageUpdateResult.FileStatus {
        // Check if the checkout directory exists
        guard fileManager.fileExists(atPath: checkoutPath) else {
            return .unknown
        }

        let claudePath = (checkoutPath as NSString).appendingPathComponent("CLAUDE.md")
        return fileManager.fileExists(atPath: claudePath) ? .present : .missing
    }

    private func checkDependencyAgentsFile(in checkoutPath: String) -> PackageUpdateResult.FileStatus {
        // Check if the checkout directory exists
        guard fileManager.fileExists(atPath: checkoutPath) else {
            return .unknown
        }

        let agentsPath = (checkoutPath as NSString).appendingPathComponent("AGENTS.md")
        return fileManager.fileExists(atPath: agentsPath) ? .present : .missing
    }

    private func checkDependencyLicense(in checkoutPath: String) -> PackageUpdateResult.LicenseType {
        // Check if the checkout directory exists
        guard fileManager.fileExists(atPath: checkoutPath) else {
            return .unknown
        }

        // Common license file names
        let licenseFileNames = ["LICENSE", "LICENSE.txt", "LICENSE.md", "COPYING", "COPYING.txt", "LICENSE-MIT", "LICENSE-APACHE"]

        // Find the first license file that exists
        for fileName in licenseFileNames {
            let licensePath = (checkoutPath as NSString).appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: licensePath),
               let content = try? String(contentsOfFile: licensePath, encoding: .utf8) {
                return detectLicenseType(from: content)
            }
        }

        return .missing
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
        // Check against all defined licenses
        for definition in LicenseDefinition.all {
            if definition.matches(content) {
                return definition.type
            }
        }

        // Unknown license - try to extract first line
        let lines = content.components(separatedBy: .newlines)
        if let firstLine = lines.first?.trimmingCharacters(in: .whitespaces),
           !firstLine.isEmpty {
            return .other(firstLine.prefix(50).description)
        }
        return .unknown
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
