//
//  TagHelpers.swift
//  spm-audit
//
//  Created by Ricky Witherspoon on 1/31/26.
//

import Foundation

enum TagHelpers {
    /// Check if a tag is a valid semantic version (after normalization)
    static func isValidSemver(_ tag: String) -> Bool {
        let normalized = normalize(tag)
        let components = normalized.split(separator: ".")

        // Must have 2-3 components (major.minor or major.minor.patch)
        guard components.count >= 2 && components.count <= 3 else {
            return false
        }

        // Each component should start with a digit
        return components.allSatisfy { component in
            guard let firstChar = component.first else { return false }
            return firstChar.isNumber
        }
    }

    /// Normalize a tag name by removing common prefixes
    static func normalize(_ tag: String) -> String {
        var normalized = tag

        // Remove common prefixes
        let prefixes = ["v", "release/", "version/"]
        for prefix in prefixes {
            if normalized.lowercased().hasPrefix(prefix) {
                normalized = String(normalized.dropFirst(prefix.count))
            }
        }

        // Remove package name prefix (e.g., "wire-3.0.1" -> "3.0.1")
        // Pattern: packagename-X.Y.Z where X, Y, Z are numbers
        if normalized.range(of: #"^[a-zA-Z]+-(\d+\.\d+\.?\d*)$"#, options: .regularExpression) != nil {
            if let dashIndex = normalized.lastIndex(of: "-") {
                normalized = String(normalized[normalized.index(after: dashIndex)...])
            }
        }

        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Check if a tag represents a prerelease version
    static func isPrerelease(_ tag: String) -> Bool {
        let lowercased = tag.lowercased()
        let prereleaseMarkers = ["-alpha", "-beta", "-rc", "-pre", "-dev", "-snapshot", ".alpha", ".beta", ".rc"]
        return prereleaseMarkers.contains { lowercased.contains($0) }
    }
}
