# spm-audit

A Swift command-line tool to audit and update Swift Package Manager dependencies.

## Features

- 🔍 **Audit** - Check for available package updates across Package.swift files and Xcode projects
- 📦 **Update** - Automatically update Package.swift dependencies to latest or specific versions
- ⚡️ **Fast** - Parallel GitHub API requests for quick results
- 📊 **Clear Output** - Formatted tables showing current vs. latest versions
- 🔐 **Authenticated** - Optional GitHub token support for higher rate limits and private repos

## Installation

### Build from source

```bash
git clone https://github.com/Rspoon3/spm-audit.git
cd spm-audit
swift build -c release
cp .build/release/spm-audit /usr/local/bin/
```

### Run without installing

```bash
swift run spm-audit
```

### Using [Mint](https://github.com/yonaskolb/Mint)

```bash
mint run Rspoon3/spm-audit
```

## Usage

### Audit Packages

Check for available updates (read-only, doesn't modify files):

```bash
# Check current directory
spm-audit

# Check specific directory
spm-audit audit /path/to/project

# Include transitive dependencies
spm-audit audit --all
```

**Example output:**
```
📦 Found 2 package(s) with exact versions
⚡️ Checking for updates in parallel...

📋 TestDriveKit (Package.swift)
────────────────────────────────────────────────────────────────
+------------------+----------+---------+--------+--------------------+
| Package          | Type     | Current | Latest | Status             |
+------------------+----------+---------+--------+--------------------+
| swift-algorithms | Exact    | 1.0.0   | 1.2.1  | ⚠️  Update available |
| SFSafeSymbols    | Exact    | 6.2.0   | 7.0.0  | ⚠️  Update available |
+------------------+----------+---------+--------+--------------------+

📊 Summary: 2 update(s) available
```

### Update Packages

**⚠️ Currently only supports Package.swift files. Xcode projects must be updated manually.**

Update all packages to latest versions:

```bash
spm-audit update all
```

Update a specific package to latest:

```bash
spm-audit update package swift-algorithms
```

Update a specific package to a specific version:

```bash
spm-audit update package swift-algorithms --version 1.2.0
```

## Commands

### `audit` (default)
Check for available updates without modifying files. Shows which packages have updates available.

**Options:**
- `[directory]` - Directory to scan (defaults to current directory)
- `--all` / `-a` - Include transitive dependencies

### `update all`
Update all packages in Package.swift files to their latest stable versions.

### `update package <name>`
Update a specific package to latest or specified version.

**Options:**
- `<name>` - Package name (e.g., "swift-algorithms")
- `--version <version>` / `-v <version>` - Update to specific version
- `[directory]` - Directory to scan (defaults to current directory)

## Authentication

For higher GitHub API rate limits (5000/hour vs 60/hour) and access to private repositories:

**Option 1: Environment variable**
```bash
export GITHUB_TOKEN=your_token_here
spm-audit
```

**Option 2: GitHub CLI**
```bash
gh auth login
spm-audit
```

## Requirements

- macOS 10.15+ / Linux
- Swift 5.9+
- GitHub-hosted packages only

## How It Works

1. **Scans** for Package.swift files and Xcode projects with SPM dependencies
2. **Extracts** package information including current versions
3. **Queries** GitHub API for latest stable releases
4. **Compares** versions using semantic versioning
5. **Updates** (optional) Package.swift files with new versions

## Limitations

- Only supports GitHub-hosted packages
- Only checks GitHub Releases (not git tags without releases)
- Pre-release versions are excluded
- Xcode project updates not currently supported (must be done manually to prevent crashes)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see LICENSE file for details

## Author

Created by [Ricky Witherspoon](https://github.com/Rspoon3)

Built with assistance from Claude Sonnet 4.5
