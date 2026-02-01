//
//  PackageResolvedParser.swift
//  spm-audit
//
//  Created by Ricky Witherspoon on 1/31/26.
//

import Foundation

enum PackageResolvedParser {
    /// Extract packages from Package.resolved file
    static func extractPackages(from filePath: String, includeTransitive: Bool) -> [PackageInfo] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              let resolved = try? JSONDecoder().decode(PackageResolved.self, from: data) else {
            return []
        }

        // Find the project.pbxproj file to extract requirement types
        let projectPath = (filePath as NSString).deletingLastPathComponent
            .replacingOccurrences(of: "/project.xcworkspace/xcshareddata/swiftpm", with: "")
        let pbxprojPath = "\(projectPath)/project.pbxproj"
        let requirementTypes = PbxprojParser.extractRequirementTypes(from: pbxprojPath)

        var packages: [PackageInfo] = []

        for pin in resolved.pins {
            // Only include packages with versions (not branch/revision only)
            guard let version = pin.state.version else {
                continue
            }

            // Only include GitHub packages
            guard pin.location.contains("github.com") else {
                continue
            }

            // Clean up URL by removing .git suffix
            let cleanURL = pin.location.replacingOccurrences(of: ".git", with: "")

            // Get requirement type for this package
            let requirementType = requirementTypes[cleanURL] ?? requirementTypes[pin.location]

            // Skip transitive dependencies (packages not directly referenced in project.pbxproj)
            // unless includeTransitive flag is set
            if !includeTransitive && requirementType == nil {
                continue
            }

            // Extract package name from location
            let name = cleanURL.components(separatedBy: "/").last ?? pin.identity

            packages.append(PackageInfo(
                name: name,
                url: cleanURL,
                currentVersion: version,
                filePath: filePath,
                requirementType: requirementType
            ))
        }

        return packages
    }
}
