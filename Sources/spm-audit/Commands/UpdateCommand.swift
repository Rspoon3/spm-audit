//
//  UpdateCommand.swift
//  spm-audit
//
//  Created by Ricky Witherspoon on 1/31/26.
//

import Foundation
import ArgumentParser

struct Update: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update package dependencies to newer versions",
        discussion: """
            Update package dependencies to their latest versions or to a specific version.
            This command MODIFIES your Package.swift files.

            ⚠️  IMPORTANT: Currently only supports Package.swift files.
            Xcode projects must be updated manually to prevent Xcode crashes.

            SUPPORTED REQUIREMENT TYPES:
              • Exact version (exact: "1.0.0")

            EXAMPLES:
              # Update all packages to latest
              spm-audit update all

              # Update one package to latest
              spm-audit update package swift-algorithms

              # Update one package to specific version
              spm-audit update package swift-algorithms --version 1.2.0

              # Update packages in specific directory
              spm-audit update all /path/to/project

            Run 'spm-audit audit' first to see which packages have updates available.
            """,
        subcommands: [UpdateAll.self, UpdatePackage.self]
    )
}
