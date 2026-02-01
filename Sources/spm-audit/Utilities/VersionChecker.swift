//
//  VersionChecker.swift
//  spm-audit
//
//  Created by Ricky Witherspoon on 1/31/26.
//

import Foundation

// MARK: - Version

enum Version {
    static let current = "0.3.0"
}

// MARK: - Version Checker

enum VersionChecker {
    @Sendable
    static func checkForUpdates() async {
        let url = URL(string: "https://api.github.com/repos/Rspoon3/spm-audit/releases")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 2.0 // Quick timeout to not block startup

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return
            }

            struct Release: Codable {
                let tagName: String
                enum CodingKeys: String, CodingKey {
                    case tagName = "tag_name"
                }
            }

            let releases = try JSONDecoder().decode([Release].self, from: data)

            guard let latestRelease = releases.first else {
                return
            }

            let latestVersion = latestRelease.tagName

            if latestVersion != Version.current {
                print("⚠️  A new version of spm-audit is available: \(latestVersion)")
                print("   Update with: brew upgrade spm-audit\n")
            }
        } catch {
            // Silently fail - don't bother the user with version check errors
        }
    }
}
