//
//  GitHubClient.swift
//  spm-audit
//
//  Created by Ricky Witherspoon on 1/31/26.
//

import Foundation

final class GitHubClient: Sendable {
    private let githubToken: String?

    init(githubToken: String? = nil) {
        self.githubToken = githubToken ?? Self.getGitHubToken()
    }

    static func getGitHubToken() -> String? {
        // First check environment variable
        if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"] {
            return token
        }

        // Fall back to gh CLI token
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "auth", "token"]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !token.isEmpty {
                    return token
                }
            }
        } catch {
            return nil
        }

        return nil
    }

    func fetchLatestRelease(owner: String, repo: String, package: PackageInfo) async -> PackageUpdateResult {
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/releases"

        guard let url = URL(string: urlString) else {
            return PackageUpdateResult(package: package, status: .error("Invalid API URL"), readmeStatus: .unknown, licenseType: .unknown)
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        // Add GitHub token if available (for private repos)
        if let token = githubToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return PackageUpdateResult(package: package, status: .error("Invalid response"), readmeStatus: .unknown, licenseType: .unknown)
            }

            // If releases endpoint returns 404, fall back to tags
            if httpResponse.statusCode == 404 {
                return await fetchLatestTag(owner: owner, repo: repo, package: package)
            }

            guard httpResponse.statusCode == 200 else {
                return PackageUpdateResult(
                    package: package,
                    status: .error("API error (status \(httpResponse.statusCode))"),
                    readmeStatus: .unknown,
                    licenseType: .unknown
                )
            }

            let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)

            // Filter out prereleases and find the latest
            let stableReleases = releases.filter { !$0.prerelease }

            // If no releases found, fall back to checking tags
            guard let latestRelease = stableReleases.first else {
                return await fetchLatestTag(owner: owner, repo: repo, package: package)
            }

            let latestVersion = VersionHelpers.normalize(latestRelease.tagName)

            if VersionHelpers.compare(latestVersion, package.currentVersion) {
                return PackageUpdateResult(
                    package: package,
                    status: .updateAvailable(current: package.currentVersion, latest: latestVersion),
                    readmeStatus: .unknown,
                    licenseType: .unknown
                )
            } else {
                return PackageUpdateResult(
                    package: package,
                    status: .upToDate(latestVersion),
                    readmeStatus: .unknown,
                    licenseType: .unknown
                )
            }

        } catch {
            return PackageUpdateResult(
                package: package,
                status: .error(error.localizedDescription),
                readmeStatus: .unknown,
                licenseType: .unknown
            )
        }
    }

    func fetchLatestTag(owner: String, repo: String, package: PackageInfo) async -> PackageUpdateResult {
        // Request more tags per page (GitHub allows up to 100)
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/tags?per_page=100"

        guard let url = URL(string: urlString) else {
            return PackageUpdateResult(package: package, status: .error("Invalid API URL"), readmeStatus: .unknown, licenseType: .unknown)
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        if let token = githubToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return PackageUpdateResult(package: package, status: .error("Invalid response"), readmeStatus: .unknown, licenseType: .unknown)
            }

            if httpResponse.statusCode == 404 {
                return PackageUpdateResult(package: package, status: .noReleases, readmeStatus: .unknown, licenseType: .unknown)
            }

            guard httpResponse.statusCode == 200 else {
                return PackageUpdateResult(
                    package: package,
                    status: .error("API error (status \(httpResponse.statusCode))"),
                    readmeStatus: .unknown,
                    licenseType: .unknown
                )
            }

            let tags = try JSONDecoder().decode([GitHubTag].self, from: data)

            // Filter tags to find valid semver tags that are not prereleases
            let validTags = tags
                .map { $0.name }
                .filter { !TagHelpers.isPrerelease($0) }
                .filter { TagHelpers.isValidSemver($0) }
                .map { (original: $0, normalized: TagHelpers.normalize($0)) }
                .sorted { tag1, tag2 in
                    // Sort by semantic version (descending)
                    let v1 = VersionHelpers.normalize(tag1.normalized)
                    let v2 = VersionHelpers.normalize(tag2.normalized)
                    return VersionHelpers.compare(v1, v2)
                }

            guard let latestTag = validTags.first else {
                return PackageUpdateResult(package: package, status: .noReleases, readmeStatus: .unknown, licenseType: .unknown)
            }

            let latestVersion = VersionHelpers.normalize(latestTag.normalized)

            if VersionHelpers.compare(latestVersion, package.currentVersion) {
                return PackageUpdateResult(
                    package: package,
                    status: .updateAvailable(current: package.currentVersion, latest: latestVersion),
                    readmeStatus: .unknown,
                    licenseType: .unknown
                )
            } else {
                return PackageUpdateResult(
                    package: package,
                    status: .upToDate(latestVersion),
                    readmeStatus: .unknown,
                    licenseType: .unknown
                )
            }

        } catch {
            return PackageUpdateResult(
                package: package,
                status: .error(error.localizedDescription),
                readmeStatus: .unknown,
                licenseType: .unknown
            )
        }
    }

    func fetchAllReleases(package: PackageInfo) async throws -> [GitHubRelease] {
        // Extract owner and repo from GitHub URL
        let components = package.url.components(separatedBy: "/")
        guard components.count >= 5,
              let ownerIndex = components.firstIndex(of: "github.com"),
              ownerIndex + 2 < components.count else {
            throw UpdateError.parseError("Could not parse GitHub URL: \(package.url)")
        }

        let owner = components[ownerIndex + 1]
        let repo = components[ownerIndex + 2]

        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/releases"

        guard let url = URL(string: urlString) else {
            throw UpdateError.parseError("Invalid API URL")
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        if let token = githubToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.parseError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            throw UpdateError.parseError("API error (status \(httpResponse.statusCode))")
        }

        return try JSONDecoder().decode([GitHubRelease].self, from: data)
    }

    func checkReadmeExists(owner: String, repo: String) async -> PackageUpdateResult.ReadmeStatus {
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/readme"

        guard let url = URL(string: urlString) else {
            return .unknown
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        if let token = githubToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .unknown
            }

            switch httpResponse.statusCode {
            case 200:
                return .present
            case 404:
                return .missing
            default:
                return .unknown
            }
        } catch {
            return .unknown
        }
    }
}
