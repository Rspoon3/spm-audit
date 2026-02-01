//
//  PbxprojParser.swift
//  spm-audit
//
//  Created by Ricky Witherspoon on 1/31/26.
//

import Foundation

enum PbxprojParser {
    /// Extract requirement types from Xcode project.pbxproj file
    static func extractRequirementTypes(from pbxprojPath: String) -> [String: PackageInfo.RequirementType] {
        guard let content = try? String(contentsOfFile: pbxprojPath, encoding: .utf8) else {
            return [:]
        }

        var requirements: [String: PackageInfo.RequirementType] = [:]

        // Pattern to match XCRemoteSwiftPackageReference sections
        // Need to match content including nested braces
        let pattern = #"XCRemoteSwiftPackageReference[\s\S]*?repositoryURL = "([^"]+)";[\s\S]*?requirement = \{[\s\S]*?kind = (\w+);"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return [:]
        }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))

        for match in matches {
            if match.numberOfRanges == 3 {
                let urlRange = match.range(at: 1)
                let kindRange = match.range(at: 2)

                let url = nsContent.substring(with: urlRange).replacingOccurrences(of: ".git", with: "")
                let kind = nsContent.substring(with: kindRange)

                if let requirementType = PackageInfo.RequirementType(rawValue: kind) {
                    requirements[url] = requirementType
                }
            }
        }

        return requirements
    }
}
