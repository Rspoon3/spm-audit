//
//  main.swift
//  spm-audit
//
//  Created by Ricky Witherspoon on 1/31/26.
//

import Foundation
import ArgumentParser

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
        subcommands: [Audit.self, Update.self],
        defaultSubcommand: Audit.self
    )

    @Flag(name: [.short, .long], help: "Show version information")
    var version: Bool = false

    func validate() throws {
        if version {
            print("spm-audit version \(Version.current)")
            throw ExitCode.success
        }
    }
}
