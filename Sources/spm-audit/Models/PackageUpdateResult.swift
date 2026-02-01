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
}
