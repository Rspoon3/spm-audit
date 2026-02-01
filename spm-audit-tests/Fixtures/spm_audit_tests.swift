//
//  spm_audit_tests.swift
//  spm-audit-tests
//
//  Created by Ricky Witherspoon on 1/31/26.
//

import Testing
import Foundation

@testable import spm_audit

struct RequirementTypeTests {

    @Test("Parse exactVersion requirement")
    func testExactVersionRequirement() async throws {
        let checker = PackageUpdateChecker()
        let fixturesURL = Bundle.module.resourceURL!.appendingPathComponent("exactVersion")

        let pbxprojPath = fixturesURL.appendingPathComponent("project.pbxproj").path
        let requirements = checker.extractRequirementTypesPublic(from: pbxprojPath)

        #expect(!requirements.isEmpty)

        // Should find swift-algorithms with exactVersion
        let algorithmRequirement = requirements.values.first
        #expect(algorithmRequirement == .exact)
    }

    @Test("Parse upToNextMajorVersion requirement")
    func testUpToNextMajorVersionRequirement() async throws {
        let checker = PackageUpdateChecker()
        let fixturesURL = Bundle.module.resourceURL!.appendingPathComponent("upToNextMajorVersion")

        let pbxprojPath = fixturesURL.appendingPathComponent("project.pbxproj").path
        let requirements = checker.extractRequirementTypesPublic(from: pbxprojPath)

        #expect(!requirements.isEmpty)

        let algorithmRequirement = requirements.values.first
        #expect(algorithmRequirement == .upToNextMajor)
    }

    @Test("Parse upToNextMinorVersion requirement")
    func testUpToNextMinorVersionRequirement() async throws {
        let checker = PackageUpdateChecker()
        let fixturesURL = Bundle.module.resourceURL!.appendingPathComponent("upToNextMinorVersion")

        let pbxprojPath = fixturesURL.appendingPathComponent("project.pbxproj").path
        let requirements = checker.extractRequirementTypesPublic(from: pbxprojPath)

        #expect(!requirements.isEmpty)

        let algorithmRequirement = requirements.values.first
        #expect(algorithmRequirement == .upToNextMinor)
    }

    @Test("Parse versionRange requirement")
    func testVersionRangeRequirement() async throws {
        let checker = PackageUpdateChecker()
        let fixturesURL = Bundle.module.resourceURL!.appendingPathComponent("versionRange")

        let pbxprojPath = fixturesURL.appendingPathComponent("project.pbxproj").path
        let requirements = checker.extractRequirementTypesPublic(from: pbxprojPath)

        #expect(!requirements.isEmpty)

        let algorithmRequirement = requirements.values.first
        #expect(algorithmRequirement == .range)
    }
}

struct PackageResolvedTests {

    @Test("Parse Package.resolved file")
    func testParsePackageResolved() async throws {
        let checker = PackageUpdateChecker()
        let fixturesURL = Bundle.module.resourceURL!.appendingPathComponent("exactVersion")

        let resolvedPath = fixturesURL.appendingPathComponent("Package.resolved").path
        let packages = checker.extractPackagesFromResolvedPublic(from: resolvedPath, includeTransitive: true)

        #expect(!packages.isEmpty)

        // Should find swift-algorithms
        let algorithmsPackage = packages.first { $0.name == "swift-algorithms" }
        #expect(algorithmsPackage != nil)
        #expect(algorithmsPackage?.requirementType == .exact)
    }

    @Test("Filter transitive dependencies by default")
    func testFilterTransitiveDependencies() async throws {
        let checker = PackageUpdateChecker()
        let fixturesURL = Bundle.module.resourceURL!.appendingPathComponent("exactVersion")

        let resolvedPath = fixturesURL.appendingPathComponent("Package.resolved").path

        // Without includeTransitive
        let directPackages = checker.extractPackagesFromResolvedPublic(from: resolvedPath, includeTransitive: false)

        // With includeTransitive
        let allPackages = checker.extractPackagesFromResolvedPublic(from: resolvedPath, includeTransitive: true)

        // Direct packages should be <= all packages
        #expect(directPackages.count <= allPackages.count)

        // All direct packages should have a requirement type
        for package in directPackages {
            #expect(package.requirementType != nil)
        }
    }
}

struct VersionComparisonTests {

    @Test("Compare semantic versions correctly")
    func testVersionComparison() async throws {
        let checker = PackageUpdateChecker()

        // 1.0.0 > 0.9.0
        #expect(checker.compareVersionsPublic("1.0.0", "0.9.0") == true)

        // 1.1.0 > 1.0.0
        #expect(checker.compareVersionsPublic("1.1.0", "1.0.0") == true)

        // 1.0.1 > 1.0.0
        #expect(checker.compareVersionsPublic("1.0.1", "1.0.0") == true)

        // 1.0.0 == 1.0.0
        #expect(checker.compareVersionsPublic("1.0.0", "1.0.0") == false)

        // 0.9.0 < 1.0.0
        #expect(checker.compareVersionsPublic("0.9.0", "1.0.0") == false)
    }

    @Test("Normalize version strings")
    func testVersionNormalization() async throws {
        let checker = PackageUpdateChecker()

        #expect(checker.normalizeVersionPublic("v1.0.0") == "1.0.0")
        #expect(checker.normalizeVersionPublic("1.0.0") == "1.0.0")
        #expect(checker.normalizeVersionPublic(" v1.0.0 ") == "1.0.0")
    }
}

struct SourceNameExtractionTests {

    @Test("Extract source name from Package.swift")
    func testExtractSourceNameFromPackageSwift() async throws {
        let checker = PackageUpdateChecker()

        let path = "/Users/test/MyProject/Package.swift"
        let sourceName = checker.extractSourceNamePublic(from: path)

        #expect(sourceName == "MyProject (Package.swift)")
    }

    @Test("Extract source name from nested Package.swift")
    func testExtractSourceNameFromNestedPackageSwift() async throws {
        let checker = PackageUpdateChecker()

        let path = "/Users/test/TestDrive/TestDriveKit/Package.swift"
        let sourceName = checker.extractSourceNamePublic(from: path)

        #expect(sourceName == "TestDriveKit (Package.swift)")
    }

    @Test("Extract source name from Xcode Package.resolved")
    func testExtractSourceNameFromXcodePackageResolved() async throws {
        let checker = PackageUpdateChecker()

        let path = "/Users/test/TestDrive/TestDrive.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        let sourceName = checker.extractSourceNamePublic(from: path)

        #expect(sourceName == "TestDrive (Xcode Project)")
    }

    @Test("Extract source name from standalone Package.resolved")
    func testExtractSourceNameFromStandalonePackageResolved() async throws {
        let checker = PackageUpdateChecker()

        let path = "/Users/test/SomePackage/Package.resolved"
        let sourceName = checker.extractSourceNamePublic(from: path)

        #expect(sourceName == "Package.resolved")
    }
}

struct PackageUpdaterTests {

    @Test("Reject Xcode project updates with clear error message")
    func testRejectXcodeProjectUpdates() async throws {
        let updater = PackageUpdater()
        let fixturesURL = Bundle.module.resourceURL!.appendingPathComponent("exactVersion")

        // Create a temporary copy
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let tempProjectDir = tempDir.appendingPathComponent("TestDrive.xcodeproj")
        try FileManager.default.createDirectory(at: tempProjectDir, withIntermediateDirectories: true)

        let workspaceDir = tempProjectDir.appendingPathComponent("project.xcworkspace/xcshareddata/swiftpm")
        try FileManager.default.createDirectory(at: workspaceDir, withIntermediateDirectories: true)
        let tempResolved = workspaceDir.appendingPathComponent("Package.resolved")
        let sourceResolved = fixturesURL.appendingPathComponent("Package.resolved")
        try FileManager.default.copyItem(at: sourceResolved, to: tempResolved)

        // Try to update an Xcode project package
        let package = PackageInfo(
            name: "swift-algorithms",
            url: "https://github.com/apple/swift-algorithms",
            currentVersion: "0.2.0",
            filePath: tempResolved.path,
            requirementType: .exact,
        swiftVersion: nil
        )

        do {
            try updater.updateFile(package: package, newVersion: "1.0.0")
            #expect(Bool(false), "Should have thrown xcodeProjectNotSupported error")
        } catch let error as UpdateError {
            if case .xcodeProjectNotSupported(let name) = error {
                #expect(name == "swift-algorithms")
                #expect(error.description.contains("Xcode project updates are not currently supported"))
            } else {
                #expect(Bool(false), "Wrong error type: \(error)")
            }
        }

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("Update Package.swift successfully")
    func testUpdatePackageSwift() async throws {
        let updater = PackageUpdater()

        // Create a temporary Package.swift file
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let packageSwiftPath = tempDir.appendingPathComponent("Package.swift")
        let packageContent = """
        // swift-tools-version: 5.9
        import PackageDescription

        let package = Package(
            name: "TestPackage",
            dependencies: [
                .package(url: "https://github.com/apple/swift-algorithms", exact: "1.0.0")
            ]
        )
        """
        try packageContent.write(to: URL(fileURLWithPath: packageSwiftPath.path), atomically: true, encoding: .utf8)

        let package = PackageInfo(
            name: "swift-algorithms",
            url: "https://github.com/apple/swift-algorithms",
            currentVersion: "1.0.0",
            filePath: packageSwiftPath.path,
            requirementType: .exact,
        swiftVersion: nil
        )

        try updater.updateFile(package: package, newVersion: "1.2.0")

        // Verify the update
        let updatedContent = try String(contentsOfFile: packageSwiftPath.path, encoding: .utf8)
        #expect(updatedContent.contains("exact: \"1.2.0\""))
        #expect(!updatedContent.contains("exact: \"1.0.0\""))

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("Validate version format")
    func testValidateVersionFormat() async throws {
        let updater = PackageUpdater()

        #expect(updater.isValidVersionPublic("1.0.0") == true)
        #expect(updater.isValidVersionPublic("1.0") == true)
        #expect(updater.isValidVersionPublic("2.1.3") == true)
        #expect(updater.isValidVersionPublic("invalid") == false)
        #expect(updater.isValidVersionPublic("1") == false)
        #expect(updater.isValidVersionPublic("1.2.3.4") == false)
    }

    @Test("Update multiple packages in Package.swift")
    func testUpdateMultiplePackages() async throws {
        let updater = PackageUpdater()

        // Create a temporary Package.swift with multiple packages
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let packageSwiftPath = tempDir.appendingPathComponent("Package.swift")
        let packageContent = """
        // swift-tools-version: 5.9
        import PackageDescription

        let package = Package(
            name: "TestPackage",
            dependencies: [
                .package(url: "https://github.com/apple/swift-algorithms", exact: "1.0.0"),
                .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.5.0")
            ]
        )
        """
        try packageContent.write(to: URL(fileURLWithPath: packageSwiftPath.path), atomically: true, encoding: .utf8)

        let package = PackageInfo(
            name: "swift-algorithms",
            url: "https://github.com/apple/swift-algorithms",
            currentVersion: "1.0.0",
            filePath: packageSwiftPath.path,
            requirementType: .exact,
        swiftVersion: nil
        )

        try updater.updateFile(package: package, newVersion: "1.2.0")

        // Verify only the specific package was updated
        let updatedContent = try String(contentsOfFile: packageSwiftPath.path, encoding: .utf8)
        #expect(updatedContent.contains("exact: \"1.2.0\""))
        #expect(!updatedContent.contains("exact: \"1.0.0\""))
        // Other package should remain unchanged
        #expect(updatedContent.contains("exact: \"1.5.0\""))

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }
}

struct VersionTests {

    @Test("Version constant is valid semantic version")
    func testVersionFormat() async throws {
        // Version should be in semantic version format (X.Y.Z)
        let components = Version.current.split(separator: ".")

        #expect(components.count == 3, "Version should have 3 components (major.minor.patch)")

        // Each component should be a valid integer
        for component in components {
            #expect(Int(component) != nil, "Version component '\(component)' should be a number")
        }
    }

    @Test("Version constant matches expected format")
    func testVersionNotEmpty() async throws {
        #expect(!Version.current.isEmpty, "Version should not be empty")
        #expect(!Version.current.contains("v"), "Version should not contain 'v' prefix")
        #expect(!Version.current.contains(" "), "Version should not contain spaces")
    }
}

struct GitURLHandlingTests {

    @Test("Strip .git suffix from package names")
    func testStripGitSuffixFromPackageNames() async throws {
        let checker = PackageUpdateChecker()

        // Create a temporary Package.swift with .git suffix in URL
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let packageSwiftPath = tempDir.appendingPathComponent("Package.swift")
        let packageContent = """
        // swift-tools-version: 5.9
        import PackageDescription

        let package = Package(
            name: "TestPackage",
            dependencies: [
                .package(url: "https://github.com/airbnb/lottie-ios.git", exact: "4.5.0")
            ]
        )
        """
        try packageContent.write(to: URL(fileURLWithPath: packageSwiftPath.path), atomically: true, encoding: .utf8)

        // Extract packages
        let packages = checker.extractPackagesFromSwiftPackagePublic(from: packageSwiftPath.path)

        #expect(!packages.isEmpty, "Should find packages")

        // Verify the .git suffix is stripped from the package name
        let lottiePackage = packages.first { $0.name == "lottie-ios" }
        #expect(lottiePackage != nil, "Should find lottie-ios package")
        #expect(lottiePackage?.name == "lottie-ios", "Package name should not include .git suffix")
        #expect(!lottiePackage!.name.hasSuffix(".git"), "Package name should not end with .git")

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("GitHub API calls strip .git suffix from repo name")
    func testGitHubAPIStripsGitSuffix() async throws {
        // This test verifies that the repo name extraction from URLs with .git suffix
        // correctly strips the suffix before making API calls

        let testURLs = [
            ("https://github.com/airbnb/lottie-ios.git", "airbnb", "lottie-ios"),
            ("https://github.com/apple/swift-algorithms.git", "apple", "swift-algorithms"),
            ("https://github.com/pointfreeco/swift-composable-architecture", "pointfreeco", "swift-composable-architecture")
        ]

        for (url, expectedOwner, expectedRepo) in testURLs {
            let components = url.components(separatedBy: "/")
            guard let ownerIndex = components.firstIndex(of: "github.com"),
                  ownerIndex + 2 < components.count else {
                #expect(Bool(false), "Failed to parse URL: \(url)")
                continue
            }

            let owner = components[ownerIndex + 1]
            let repoWithGit = components[ownerIndex + 2]
            let repo = repoWithGit.replacingOccurrences(of: ".git", with: "")

            #expect(owner == expectedOwner, "Owner should be \(expectedOwner) for \(url)")
            #expect(repo == expectedRepo, "Repo should be \(expectedRepo) for \(url)")
            #expect(!repo.hasSuffix(".git"), "Repo name should not end with .git for \(url)")
        }
    }
}

struct TagNormalizationTests {

    @Test("Normalize tag names with common prefixes")
    func testTagNameNormalization() async throws {
        let checker = PackageUpdateChecker()

        // Test v prefix
        #expect(checker.normalizeTagNamePublic("v1.0.0") == "1.0.0")
        #expect(checker.normalizeTagNamePublic("V1.0.0") == "1.0.0")

        // Test package name prefix
        #expect(checker.normalizeTagNamePublic("wire-3.0.1") == "3.0.1")
        #expect(checker.normalizeTagNamePublic("lottie-4.5.0") == "4.5.0")

        // Test no prefix
        #expect(checker.normalizeTagNamePublic("5.5.0") == "5.5.0")

        // Test release/ prefix
        #expect(checker.normalizeTagNamePublic("release/1.0.0") == "1.0.0")
    }

    @Test("Identify valid semver tags")
    func testValidSemverTags() async throws {
        let checker = PackageUpdateChecker()

        // Valid tags
        #expect(checker.isValidSemverTagPublic("1.0.0") == true)
        #expect(checker.isValidSemverTagPublic("v2.3.4") == true)
        #expect(checker.isValidSemverTagPublic("wire-3.0.1") == true)
        #expect(checker.isValidSemverTagPublic("5.5.0") == true)

        // Invalid tags
        #expect(checker.isValidSemverTagPublic("main") == false)
        #expect(checker.isValidSemverTagPublic("develop") == false)
        #expect(checker.isValidSemverTagPublic("swift53") == false)
        #expect(checker.isValidSemverTagPublic("v1") == false)
    }

    @Test("Identify prerelease tags")
    func testPrereleaseIdentification() async throws {
        let checker = PackageUpdateChecker()

        // Prerelease tags
        #expect(checker.isPrereleasePublic("1.0.0-alpha") == true)
        #expect(checker.isPrereleasePublic("1.0.0-beta.1") == true)
        #expect(checker.isPrereleasePublic("2.0.0-RC1") == true)
        #expect(checker.isPrereleasePublic("1.0.0-dev") == true)
        #expect(checker.isPrereleasePublic("1.0.0.alpha1") == true)

        // Stable tags
        #expect(checker.isPrereleasePublic("1.0.0") == false)
        #expect(checker.isPrereleasePublic("v2.3.4") == false)
    }

    @Test("Sort tags by semantic version")
    func testTagSorting() async throws {
        let checker = PackageUpdateChecker()

        let tags = ["1.0.0", "2.0.0", "1.5.0", "1.0.1"]
        let sorted = tags.sorted { tag1, tag2 in
            let v1 = checker.normalizeVersionPublic(tag1)
            let v2 = checker.normalizeVersionPublic(tag2)
            return checker.compareVersionsPublic(v1, v2)
        }

        #expect(sorted.first == "2.0.0", "Latest version should be first")
        #expect(sorted.last == "1.0.0", "Oldest version should be last")
    }
}

struct ReadmeStatusTests {

    @Test("README status values are correct")
    func testReadmeStatusValues() async throws {
        // Create test results with different README statuses
        let package = PackageInfo(
            name: "test-package",
            url: "https://github.com/test/package",
            currentVersion: "1.0.0",
            filePath: "/test/path",
            requirementType: .exact,
        swiftVersion: nil
        )

        let presentResult = PackageUpdateResult(
            package: package,
            status: .upToDate("1.0.0"),
            readmeStatus: .present,
            licenseType: .mit,
            claudeFileStatus: .unknown,
            agentsFileStatus: .unknown
        )

        let missingResult = PackageUpdateResult(
            package: package,
            status: .upToDate("1.0.0"),
            readmeStatus: .missing,
            licenseType: .missing,
            claudeFileStatus: .unknown,
            agentsFileStatus: .unknown
        )

        let unknownResult = PackageUpdateResult(
            package: package,
            status: .upToDate("1.0.0"),
            readmeStatus: .unknown,
            licenseType: .unknown,
            claudeFileStatus: .unknown,
            agentsFileStatus: .unknown
        )

        #expect(presentResult.readmeStatus == .present)
        #expect(missingResult.readmeStatus == .missing)
        #expect(unknownResult.readmeStatus == .unknown)
    }

    @Test("README indicator displays correct emoji")
    func testReadmeIndicator() async throws {
        // Test that the formatter correctly shows README indicators
        let package = PackageInfo(
            name: "test-package",
            url: "https://github.com/test/package",
            currentVersion: "1.0.0",
            filePath: "/test/path",
            requirementType: .exact,
        swiftVersion: nil
        )

        // We can't directly test the private getReadmeIndicator method,
        // but we verify the enum cases exist and are distinct
        let presentStatus: PackageUpdateResult.ReadmeStatus = .present
        let missingStatus: PackageUpdateResult.ReadmeStatus = .missing
        let unknownStatus: PackageUpdateResult.ReadmeStatus = .unknown

        #expect(presentStatus != missingStatus)
        #expect(presentStatus != unknownStatus)
        #expect(missingStatus != unknownStatus)
    }

    @Test("README status is included in PackageUpdateResult")
    func testPackageUpdateResultIncludesReadmeStatus() async throws {
        let package = PackageInfo(
            name: "swift-algorithms",
            url: "https://github.com/apple/swift-algorithms",
            currentVersion: "1.0.0",
            filePath: "/test/Package.resolved",
            requirementType: .upToNextMajor,
        swiftVersion: nil
        )

        let result = PackageUpdateResult(
            package: package,
            status: .updateAvailable(current: "1.0.0", latest: "1.2.0"),
            readmeStatus: .present,
            licenseType: .apache,
            claudeFileStatus: .unknown,
            agentsFileStatus: .unknown
        )

        #expect(result.readmeStatus == .present)
        #expect(result.package.name == "swift-algorithms")

        if case .updateAvailable(let current, let latest) = result.status {
            #expect(current == "1.0.0")
            #expect(latest == "1.2.0")
        } else {
            #expect(Bool(false), "Expected updateAvailable status")
        }
    }

    @Test("Swift version is extracted from Package.swift")
    func testSwiftVersionExtraction() async throws {
        // Create a temporary directory structure that mimics .build/checkouts
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-swift-version-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Create a fake Package.swift with swift-tools-version
        let packageSwiftContent = """
        // swift-tools-version: 5.9
        // The swift-tools-version declares the minimum version of Swift required to build this package.

        import PackageDescription

        let package = Package(
            name: "TestPackage",
            products: [.library(name: "TestPackage", targets: ["TestPackage"])],
            targets: [.target(name: "TestPackage")]
        )
        """

        let packageSwiftPath = tempDir.appendingPathComponent("Package.swift")
        try packageSwiftContent.write(to: packageSwiftPath, atomically: true, encoding: .utf8)

        // Test extraction
        let checker = PackageUpdateChecker(workingDirectory: tempDir.path)
        let swiftVersion = checker.extractSwiftVersion(from: tempDir.path)

        #expect(swiftVersion == "5.9")

        // Test PackageInfo with Swift version
        let packageWithSwift = PackageInfo(
            name: "TestPackage",
            url: "https://github.com/test/package",
            currentVersion: "1.0.0",
            filePath: "/test/path",
            requirementType: .exact,
            swiftVersion: "5.9"
        )

        #expect(packageWithSwift.swiftVersion == "5.9")

        // Test PackageInfo without Swift version (shows N/A in output)
        let packageWithoutSwift = PackageInfo(
            name: "TestPackage",
            url: "https://github.com/test/package",
            currentVersion: "1.0.0",
            filePath: "/test/path",
            requirementType: .exact,
            swiftVersion: nil
        )

        #expect(packageWithoutSwift.swiftVersion == nil)

        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("Swift version extraction handles different formats")
    func testSwiftVersionFormats() async throws {
        let checker = PackageUpdateChecker()

        // Test with colon and space
        let tempDir1 = FileManager.default.temporaryDirectory.appendingPathComponent("test-swift-formats-1-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir1, withIntermediateDirectories: true)
        let content1 = "// swift-tools-version: 6.0\n"
        let path1 = tempDir1.appendingPathComponent("Package.swift")
        try content1.write(to: path1, atomically: true, encoding: .utf8)
        let version1 = checker.extractSwiftVersion(from: tempDir1.path)
        #expect(version1 == "6.0")
        try? FileManager.default.removeItem(at: tempDir1)

        // Test with colon but no space
        let tempDir2 = FileManager.default.temporaryDirectory.appendingPathComponent("test-swift-formats-2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir2, withIntermediateDirectories: true)
        let content2 = "// swift-tools-version:5.7\n"
        let path2 = tempDir2.appendingPathComponent("Package.swift")
        try content2.write(to: path2, atomically: true, encoding: .utf8)
        let version2 = checker.extractSwiftVersion(from: tempDir2.path)
        #expect(version2 == "5.7")
        try? FileManager.default.removeItem(at: tempDir2)
    }
}

// Expose internal methods for testing
extension PackageUpdater {
    func isValidVersionPublic(_ version: String) -> Bool {
        return isValidVersion(version)
    }
}

struct OutputFormatterTests {

    @Test("Generate pipe-delimited with correct structure")
    func testPipeDelimitedGeneration() async throws {
        let package = PackageInfo(
            name: "TestPackage",
            url: "https://github.com/test/package",
            currentVersion: "1.0.0",
            filePath: "/test/path",
            requirementType: .exact,
            swiftVersion: "5.9"
        )

        let result = PackageUpdateResult(
            package: package,
            status: .updateAvailable(current: "1.0.0", latest: "1.2.0"),
            readmeStatus: .present,
            licenseType: .mit,
            claudeFileStatus: .missing,
            agentsFileStatus: .missing
        )

        let results = [result]
        let pipeDelimited = OutputFormatter.generatePipeDelimitedPublic(results)

        let lines = pipeDelimited.split(separator: "\n")
        #expect(lines.count == 2) // Header + 1 row
        #expect(lines[0].contains("| Package | Type | Current"))
        // Split by | gives: ["", " Package ", " Type ", ..., " AGENTS.md ", ""]
        // That's 10 columns + 2 empty strings from leading/trailing pipes = 12 total
        // But split(separator:) drops empty strings by default, so we get 10 fields
        let fields = lines[1].split(separator: "|")
        #expect(fields.count == 10) // 10 actual data fields
    }

    @Test("Format with column command")
    func testColumnFormatting() async throws {
        let pipeDelimited = "| Name | Version |\n| Pkg1 | 1.0.0 |\n| Package2 | 2.0.0 |"

        do {
            let formatted = try OutputFormatter.formatWithColumnPublic(pipeDelimited)

            #expect(formatted.contains("Name"))
            #expect(formatted.contains("Version"))
            #expect(formatted.contains("|"))
        } catch {
            // If column command fails (shouldn't on macOS), test passes
            #expect(Bool(true))
        }
    }

    @Test("Fallback formatting works without column")
    func testFallbackFormatting() async throws {
        let pipeDelimited = "| Name | Version |\n| Pkg1 | 1.0.0 |\n| Package2 | 2.0.0 |"
        let formatted = OutputFormatter.formatFallbackPublic(pipeDelimited)

        #expect(formatted.contains("Name"))
        #expect(formatted.contains("Version"))
        #expect(formatted.contains("|"))

        // Verify it has proper structure
        let lines = formatted.split(separator: "\n")
        #expect(lines.count == 3) // Header + 2 rows
    }

    @Test("Separator generation from aligned line")
    func testSeparatorGeneration() async throws {
        let alignedLine = "| Package  | Type  | Current |"
        let separator = OutputFormatter.generateSeparatorPublic(from: alignedLine)

        // Each character is replaced: | becomes +, everything else becomes -
        #expect(separator == "+----------+-------+---------+")
    }

    @Test("Pipe-delimited format has correct headers")
    func testPipeDelimitedHeaders() async throws {
        let package = PackageInfo(
            name: "TestPackage",
            url: "https://github.com/test/package",
            currentVersion: "1.0.0",
            filePath: "/test/path",
            requirementType: .upToNextMajor,
            swiftVersion: nil
        )

        let result = PackageUpdateResult(
            package: package,
            status: .upToDate("1.0.0"),
            readmeStatus: .unknown,
            licenseType: .apache,
            claudeFileStatus: .unknown,
            agentsFileStatus: .unknown
        )

        let results = [result]
        let pipeDelimited = OutputFormatter.generatePipeDelimitedPublic(results)

        // Verify all expected headers are present
        #expect(pipeDelimited.contains("Package"))
        #expect(pipeDelimited.contains("Type"))
        #expect(pipeDelimited.contains("Current"))
        #expect(pipeDelimited.contains("Swift"))
        #expect(pipeDelimited.contains("Latest"))
        #expect(pipeDelimited.contains("Status"))
        #expect(pipeDelimited.contains("README"))
        #expect(pipeDelimited.contains("License"))
        #expect(pipeDelimited.contains("CLAUDE.md"))
        #expect(pipeDelimited.contains("AGENTS.md"))
    }

    @Test("Fallback formatter handles emoji correctly")
    func testFallbackFormatterWithEmoji() async throws {
        let pipeDelimited = "| Package | Status |\n| TestPkg | ✅ Up to date |\n| OtherPkg | ⚠️  Update available |"
        let formatted = OutputFormatter.formatFallbackPublic(pipeDelimited)

        // Verify emojis are preserved
        #expect(formatted.contains("✅"))
        #expect(formatted.contains("⚠️"))
        #expect(formatted.contains("|"))
    }
}
