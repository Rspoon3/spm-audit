#!/bin/bash
set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if version argument is provided
if [ -z "$1" ]; then
    echo -e "${RED}Error: Version number required${NC}"
    echo "Usage: ./release.sh <version> [release-notes]"
    echo "Example: ./release.sh 0.1.2 'Add new feature'"
    exit 1
fi

VERSION=$1
RELEASE_NOTES=${2:-"Release $VERSION"}

echo -e "${GREEN}🚀 Starting release process for version $VERSION${NC}\n"

# Step 1: Update version in main.swift
echo -e "${YELLOW}📝 Step 1: Updating version in main.swift${NC}"
sed -i '' "s/let currentVersion = \".*\"/let currentVersion = \"$VERSION\"/" Sources/spm-audit/main.swift

if ! git diff --quiet Sources/spm-audit/main.swift; then
    git add Sources/spm-audit/main.swift
    git commit -m "Bump version to $VERSION"
    git push origin main
    echo -e "${GREEN}✓ Version updated and pushed${NC}\n"
else
    echo -e "${YELLOW}⚠ Version already set to $VERSION${NC}\n"
fi

# Step 2: Create and push git tag
echo -e "${YELLOW}🏷  Step 2: Creating git tag${NC}"
if git rev-parse "$VERSION" >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠ Tag $VERSION already exists, deleting...${NC}"
    git tag -d "$VERSION"
    git push origin ":refs/tags/$VERSION" 2>/dev/null || true
fi

git tag -a "$VERSION" -m "Release $VERSION"
git push origin "$VERSION"
echo -e "${GREEN}✓ Tag created and pushed${NC}\n"

# Step 3: Create GitHub release
echo -e "${YELLOW}📦 Step 3: Creating GitHub release${NC}"
gh release delete "$VERSION" -y 2>/dev/null || true

gh release create "$VERSION" \
    --title "$VERSION" \
    --notes "$RELEASE_NOTES" \
    --repo Rspoon3/spm-audit

echo -e "${GREEN}✓ GitHub release created${NC}\n"

# Step 4: Calculate SHA256 for Homebrew formula
echo -e "${YELLOW}🔐 Step 4: Calculating SHA256${NC}"
SHA256=$(curl -sL "https://github.com/Rspoon3/spm-audit/archive/refs/tags/$VERSION.tar.gz" | shasum -a 256 | awk '{print $1}')
echo -e "SHA256: ${GREEN}$SHA256${NC}\n"

# Step 5: Update Homebrew formula
echo -e "${YELLOW}🍺 Step 5: Updating Homebrew formula${NC}"
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

git clone https://github.com/Rspoon3/homebrew-tap.git
cd homebrew-tap

# Update the formula
sed -i '' "s|url \"https://github.com/Rspoon3/spm-audit/archive/refs/tags/.*\.tar\.gz\"|url \"https://github.com/Rspoon3/spm-audit/archive/refs/tags/$VERSION.tar.gz\"|" Formula/spm-audit.rb
sed -i '' "s/sha256 \".*\"/sha256 \"$SHA256\"/" Formula/spm-audit.rb

git add Formula/spm-audit.rb
git commit -m "Update spm-audit to $VERSION"
git push origin main

cd -
rm -rf "$TEMP_DIR"

echo -e "${GREEN}✓ Homebrew formula updated${NC}\n"

# Summary
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✨ Release $VERSION completed successfully!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

echo "📍 Release URL: https://github.com/Rspoon3/spm-audit/releases/tag/$VERSION"
echo "📍 Homebrew: brew upgrade rspoon3/tap/spm-audit"
echo ""
