//
//  UpdateAllCommand.swift
//  spm-audit
//
//  Created by Ricky Witherspoon on 1/31/26.
//

import Foundation
import ArgumentParser

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
        await VersionChecker.checkForUpdates()

        let updater = PackageUpdater(workingDirectory: directory)
        try await updater.updateAllPackages()
    }
}
