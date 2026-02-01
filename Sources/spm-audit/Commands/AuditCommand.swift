//
//  AuditCommand.swift
//  spm-audit
//
//  Created by Ricky Witherspoon on 1/31/26.
//

import Foundation
import ArgumentParser

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
        await VersionChecker.checkForUpdates()

        let checker = PackageUpdateChecker(workingDirectory: directory, includeTransitive: all)
        await checker.run()
    }
}
