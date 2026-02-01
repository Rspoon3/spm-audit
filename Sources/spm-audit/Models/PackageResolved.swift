//
//  PackageResolved.swift
//  spm-audit
//
//  Created by Ricky Witherspoon on 1/31/26.
//

import Foundation

struct PackageResolved: Codable {
    let pins: [Pin]
    let version: Int

    struct Pin: Codable {
        let identity: String
        let location: String
        let state: State

        struct State: Codable {
            let version: String?
        }
    }
}
