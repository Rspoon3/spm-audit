//
//  UpdateError.swift
//  spm-audit
//
//  Created by Ricky Witherspoon on 1/31/26.
//

import Foundation

enum UpdateError: Error, CustomStringConvertible {
    case packageNotFound(String)
    case versionNotFound(package: String, version: String)
    case invalidVersion(String)
    case unsupportedRequirementType(PackageInfo.RequirementType)
    case multipleSourcesFound(package: String, sources: [String])
    case fileNotWritable(String)
    case fileNotFound(String)
    case parseError(String)
    case xcodeProjectNotSupported(String)

    var description: String {
        switch self {
        case .packageNotFound(let name):
            return "Package '\(name)' not found in project"
        case .versionNotFound(let package, let version):
            return "Version '\(version)' not found for package '\(package)' on GitHub"
        case .invalidVersion(let version):
            return "Invalid version format: '\(version)'"
        case .unsupportedRequirementType(let type):
            return "Cannot update packages with requirement type '\(type.displayName)'. Only Exact, ^Major, ^Minor, and Range are supported."
        case .multipleSourcesFound(let package, let sources):
            return "Package '\(package)' found in multiple files: \(sources.joined(separator: ", "))"
        case .fileNotWritable(let path):
            return "File is not writable: \(path)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .parseError(let message):
            return "Parse error: \(message)"
        case .xcodeProjectNotSupported(let packageName):
            return "⚠️  Xcode project updates are not currently supported. Package '\(packageName)' is in an Xcode project. Please update it manually."
        }
    }
}
