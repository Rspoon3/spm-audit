//
//  LicenseDefinition.swift
//  spm-audit
//
//  Created by Ricky Witherspoon on 1/31/26.
//

import Foundation

struct LicenseDefinition {
    let type: PackageUpdateResult.LicenseType
    let keywords: [String]
    let isPermissive: Bool
    let matchStrategy: MatchStrategy
    let exclusions: [String]
    let additionalRequirements: [String]

    enum MatchStrategy {
        case allKeywords  // All keywords must be present
        case anyKeyword   // At least one keyword must be present
    }

    init(type: PackageUpdateResult.LicenseType,
         keywords: [String],
         isPermissive: Bool,
         matchStrategy: MatchStrategy = .allKeywords,
         exclusions: [String] = [],
         additionalRequirements: [String] = []) {
        self.type = type
        self.keywords = keywords
        self.isPermissive = isPermissive
        self.matchStrategy = matchStrategy
        self.exclusions = exclusions
        self.additionalRequirements = additionalRequirements
    }

    static let all: [LicenseDefinition] = [
        // GNU licenses (check most specific first)
        LicenseDefinition(
            type: .agpl,
            keywords: ["GNU AFFERO GENERAL PUBLIC LICENSE", "AGPL"],
            isPermissive: false,
            matchStrategy: .anyKeyword
        ),
        LicenseDefinition(
            type: .lgpl,
            keywords: ["GNU LESSER GENERAL PUBLIC LICENSE", "GNU LIBRARY GENERAL PUBLIC LICENSE", "LGPL"],
            isPermissive: false,
            matchStrategy: .anyKeyword
        ),
        LicenseDefinition(
            type: .gpl,
            keywords: ["GNU GENERAL PUBLIC LICENSE", "GPL"],
            isPermissive: false,
            matchStrategy: .anyKeyword,
            exclusions: ["LGPL", "AGPL", "LESSER", "AFFERO"],
            additionalRequirements: ["VERSION"]
        ),

        // Permissive licenses
        LicenseDefinition(
            type: .mit,
            keywords: ["MIT LICENSE", "MIT", "PERMISSION IS HEREBY GRANTED"],
            isPermissive: true,
            matchStrategy: .anyKeyword
        ),
        LicenseDefinition(
            type: .apache,
            keywords: ["APACHE LICENSE", "APACHE", "VERSION 2.0"],
            isPermissive: true,
            matchStrategy: .anyKeyword
        ),
        LicenseDefinition(
            type: .bsd,
            keywords: ["BSD", "REDISTRIBUTION", "BSD-2-CLAUSE", "BSD-3-CLAUSE"],
            isPermissive: true,
            matchStrategy: .anyKeyword
        ),
        LicenseDefinition(
            type: .isc,
            keywords: ["ISC LICENSE", "ISC", "PERMISSION TO USE"],
            isPermissive: true,
            matchStrategy: .anyKeyword
        ),

        // Copyleft licenses
        LicenseDefinition(
            type: .mpl,
            keywords: ["MOZILLA PUBLIC LICENSE", "MPL"],
            isPermissive: false,
            matchStrategy: .anyKeyword
        ),
        LicenseDefinition(
            type: .epl,
            keywords: ["ECLIPSE PUBLIC LICENSE", "EPL"],
            isPermissive: false,
            matchStrategy: .anyKeyword
        ),
        LicenseDefinition(
            type: .eupl,
            keywords: ["EUROPEAN UNION PUBLIC LICENCE", "EUPL"],
            isPermissive: false,
            matchStrategy: .anyKeyword
        ),

        // Public domain and permissive
        LicenseDefinition(
            type: .unlicense,
            keywords: ["UNLICENSE", "THIS IS FREE AND UNENCUMBERED SOFTWARE RELEASED INTO THE PUBLIC DOMAIN"],
            isPermissive: true,
            matchStrategy: .anyKeyword
        ),
        LicenseDefinition(
            type: .cc0,
            keywords: ["CC0", "CREATIVE COMMONS ZERO"],
            isPermissive: true,
            matchStrategy: .anyKeyword
        ),

        // Other licenses
        LicenseDefinition(
            type: .artistic,
            keywords: ["ARTISTIC LICENSE"],
            isPermissive: true,
            matchStrategy: .anyKeyword
        ),
        LicenseDefinition(
            type: .boost,
            keywords: ["BOOST SOFTWARE LICENSE"],
            isPermissive: true,
            matchStrategy: .anyKeyword
        ),
        LicenseDefinition(
            type: .wtfpl,
            keywords: ["WTFPL", "DO WHAT THE FUCK YOU WANT"],
            isPermissive: true,
            matchStrategy: .anyKeyword
        ),
        LicenseDefinition(
            type: .zlib,
            keywords: ["ZLIB LICENSE"],
            isPermissive: true,
            matchStrategy: .anyKeyword
        )
    ]

    func matches(_ content: String) -> Bool {
        let uppercased = content.uppercased()

        // Check exclusions - if any are present, this license doesn't match
        if exclusions.contains(where: { uppercased.contains($0) }) {
            return false
        }

        // Check keywords based on match strategy
        let keywordsMatch: Bool
        switch matchStrategy {
        case .allKeywords:
            keywordsMatch = keywords.allSatisfy { uppercased.contains($0) }
        case .anyKeyword:
            keywordsMatch = keywords.contains { uppercased.contains($0) }
        }

        // If keywords don't match, no need to check requirements
        guard keywordsMatch else {
            return false
        }

        // Check additional requirements - all must be present
        let requirementsMet = additionalRequirements.allSatisfy { uppercased.contains($0) }

        return requirementsMet
    }
}
