//
//  PackageSwiftParser.swift
//  spm-audit
//
//  Created by Ricky Witherspoon on 1/31/26.
//

import Foundation

enum PackageSwiftParser {
    /// Extract packages with exact version constraints from Package.swift file
    static func extractPackages(from filePath: String) -> [PackageInfo] {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return []
        }

        var packages: [PackageInfo] = []

        // Pattern to match: url: "https://github.com/...", exact: "1.0.0"
        let pattern = #"url:\s*"(https://github\.com/[^"]+)",\s*exact:\s*"([^"]+)""#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))

        for match in matches {
            if match.numberOfRanges == 3 {
                let urlRange = match.range(at: 1)
                let versionRange = match.range(at: 2)

                let url = nsContent.substring(with: urlRange)
                let version = nsContent.substring(with: versionRange)

                // Extract package name from URL and strip .git suffix
                let nameWithGit = url.components(separatedBy: "/").last ?? "Unknown"
                let name = nameWithGit.replacingOccurrences(of: ".git", with: "")

                packages.append(PackageInfo(
                    name: name,
                    url: url,
                    currentVersion: version,
                    filePath: filePath,
                    requirementType: .exact
                ))
            }
        }

        return packages
    }
}
