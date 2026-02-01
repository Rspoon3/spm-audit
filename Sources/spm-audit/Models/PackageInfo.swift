//
//  PackageInfo.swift
//  spm-audit
//
//  Created by Ricky Witherspoon on 1/31/26.
//

import Foundation

struct PackageInfo: Codable {
    let name: String
    let url: String
    let currentVersion: String
    let filePath: String
    let requirementType: RequirementType?

    enum RequirementType: String, Codable {
        case exact = "exactVersion"
        case upToNextMajor = "upToNextMajorVersion"
        case upToNextMinor = "upToNextMinorVersion"
        case range = "versionRange"
        case branch = "branch"
        case revision = "revision"

        var displayName: String {
            switch self {
            case .exact: return "Exact"
            case .upToNextMajor: return "^Major"
            case .upToNextMinor: return "^Minor"
            case .range: return "Range"
            case .branch: return "Branch"
            case .revision: return "Revision"
            }
        }
    }
}
