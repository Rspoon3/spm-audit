//
//  VersionHelpers.swift
//  spm-audit
//
//  Created by Ricky Witherspoon on 1/31/26.
//

import Foundation

enum VersionHelpers {
    /// Normalize a version string by removing 'v' prefix and trimming whitespace
    static func normalize(_ version: String) -> String {
        version.replacingOccurrences(of: "v", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Compare two semantic versions
    /// - Returns: true if latest > current (update available)
    static func compare(_ latest: String, _ current: String) -> Bool {
        // Split versions into components
        let latestComponents = latest.split(separator: ".").compactMap { Int($0) }
        let currentComponents = current.split(separator: ".").compactMap { Int($0) }

        // Pad to same length (e.g., 2.3 becomes [2, 3, 0])
        let maxLength = max(latestComponents.count, currentComponents.count)
        var latestPadded = latestComponents
        var currentPadded = currentComponents

        while latestPadded.count < maxLength {
            latestPadded.append(0)
        }
        while currentPadded.count < maxLength {
            currentPadded.append(0)
        }

        // Compare component by component
        for (l, c) in zip(latestPadded, currentPadded) {
            if l > c {
                return true  // Update available
            } else if l < c {
                return false // Current is newer
            }
        }

        return false // Equal
    }
}
