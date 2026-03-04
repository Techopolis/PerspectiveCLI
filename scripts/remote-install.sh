#!/bin/bash
# remote-install.sh — Download and install the latest PerspectiveCLI release
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/techopolis/PerspectiveCLI/main/scripts/remote-install.sh | bash

set -euo pipefail

REPO="techopolis/PerspectiveCLI"

# ── Check architecture ────────────────────────────────────────────────
ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
    echo "Error: PerspectiveCLI requires Apple Silicon (arm64)."
    echo "Detected architecture: $ARCH"
    exit 1
fi

# ── Fetch latest release tag ─────────────────────────────────────────
echo "Fetching latest release..."
RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest") || {
    echo "Error: Could not fetch release info from GitHub."
    echo "Check your internet connection or visit https://github.com/${REPO}/releases"
    exit 1
}

TAG=$(echo "$RELEASE_JSON" | grep '"tag_name"' | head -1 | sed 's/.*: *"//;s/".*//')
if [ -z "$TAG" ]; then
    echo "Error: No releases found for ${REPO}."
    echo "Visit https://github.com/${REPO}/releases to check for available releases."
    exit 1
fi

echo "Latest release: $TAG"

# ── Download asset ────────────────────────────────────────────────────
ASSET_NAME="perspective-cli-${TAG}-macos-arm64.tar.gz"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET_NAME}"

TMPDIR_INSTALL=$(mktemp -d)
trap 'rm -rf "$TMPDIR_INSTALL"' EXIT

echo "Downloading ${ASSET_NAME}..."
curl -fSL -o "${TMPDIR_INSTALL}/${ASSET_NAME}" "$DOWNLOAD_URL" || {
    echo "Error: Failed to download ${DOWNLOAD_URL}"
    echo "The release may not include a macOS arm64 archive."
    exit 1
}

# ── Extract ───────────────────────────────────────────────────────────
echo "Extracting..."
tar xzf "${TMPDIR_INSTALL}/${ASSET_NAME}" -C "$TMPDIR_INSTALL" || {
    echo "Error: Failed to extract archive."
    exit 1
}

# Find the extracted directory (perspective-cli-*)
EXTRACTED=$(find "$TMPDIR_INSTALL" -mindepth 1 -maxdepth 1 -type d | head -1)
if [ -z "$EXTRACTED" ] || [ ! -f "$EXTRACTED/install.sh" ]; then
    echo "Error: Archive does not contain expected install.sh."
    exit 1
fi

if [ ! -f "$EXTRACTED/perspective" ]; then
    echo "Error: Archive does not contain the perspective binary."
    exit 1
fi

# ── Install ───────────────────────────────────────────────────────────
echo ""
echo "Installing to /usr/local/bin (requires sudo)..."
sudo bash "$EXTRACTED/install.sh"
