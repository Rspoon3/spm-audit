//
//  UpdatePackageCommand.swift
//  spm-audit
//
//  Created by Ricky Witherspoon on 1/31/26.
//

import Foundation
import ArgumentParser

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
        await VersionChecker.checkForUpdates()

        let updater = PackageUpdater(workingDirectory: directory)
        try await updater.updatePackage(name: name, to: version)
    }
}
