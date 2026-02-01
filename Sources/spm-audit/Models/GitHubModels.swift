//
//  GitHubModels.swift
//  spm-audit
//
//  Created by Ricky Witherspoon on 1/31/26.
//

import Foundation

struct GitHubRelease: Codable {
    let tagName: String
    let name: String?
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case prerelease
    }
}

struct GitHubTag: Codable {
    let name: String
}
