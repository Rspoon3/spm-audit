//
//  PackageUpdateResult.swift
//  spm-audit
//
//  Created by Ricky Witherspoon on 1/31/26.
//

import Foundation

struct PackageUpdateResult {
    let package: PackageInfo
    let status: UpdateStatus
    let readmeStatus: ReadmeStatus
    let licenseType: LicenseType
    let claudeFileStatus: FileStatus
    let agentsFileStatus: FileStatus

    enum UpdateStatus {
        case upToDate(String)
        case updateAvailable(current: String, latest: String)
        case noReleases
        case error(String)
    }

    enum ReadmeStatus {
        case present
        case missing
        case unknown
    }

    enum FileStatus {
        case present
        case missing
        case unknown
    }

    enum LicenseType {
        case gpl
        case agpl
        case lgpl
        case mit
        case apache
        case bsd
        case mpl
        case unlicense
        case isc
        case cc0
        case epl
        case eupl
        case artistic
        case boost
        case wtfpl
        case zlib
        case other(String)
        case missing
        case unknown

        var displayName: String {
            switch self {
            case .gpl: return "GPL"
            case .agpl: return "AGPL"
            case .lgpl: return "LGPL"
            case .mit: return "MIT"
            case .apache: return "Apache"
            case .bsd: return "BSD"
            case .mpl: return "MPL"
            case .unlicense: return "Unlicense"
            case .isc: return "ISC"
            case .cc0: return "CC0"
            case .epl: return "EPL"
            case .eupl: return "EUPL"
            case .artistic: return "Artistic"
            case .boost: return "Boost"
            case .wtfpl: return "WTFPL"
            case .zlib: return "Zlib"
            case .other(let name): return name
            case .missing: return "Missing"
            case .unknown: return "Unknown"
            }
        }
    }
}
