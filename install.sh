#!/bin/bash
# install.sh — Install PerspectiveCLI
#
# Usage:
#   ./install.sh              Install to /usr/local/bin (default)
#   ./install.sh /custom/path Install to a custom directory
#   ./install.sh --uninstall  Remove installed files

set -euo pipefail

INSTALL_DIR="${1:-/usr/local/bin}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Uninstall ─────────────────────────────────────────────────────────
if [ "${1:-}" = "--uninstall" ]; then
    INSTALL_DIR="/usr/local/bin"
    echo "Uninstalling Perspective CLI from $INSTALL_DIR..."
    rm -f "$INSTALL_DIR/perspective"
    rm -f "$INSTALL_DIR/mlx.metallib"
    echo "Done."
    exit 0
fi

# ── Install ───────────────────────────────────────────────────────────
echo "Installing Perspective CLI to $INSTALL_DIR..."

# Check that the binary exists in the same directory as this script
if [ ! -f "$SCRIPT_DIR/perspective" ]; then
    echo "Error: 'perspective' binary not found in $SCRIPT_DIR"
    echo "Run this script from inside the extracted archive."
    exit 1
fi

# Create install directory if needed
mkdir -p "$INSTALL_DIR"

# Copy files
cp "$SCRIPT_DIR/perspective" "$INSTALL_DIR/perspective"
chmod +x "$INSTALL_DIR/perspective"

if [ -f "$SCRIPT_DIR/mlx.metallib" ]; then
    cp "$SCRIPT_DIR/mlx.metallib" "$INSTALL_DIR/mlx.metallib"
fi

echo "Done."
echo ""
echo "  perspective  → $INSTALL_DIR/perspective"
if [ -f "$SCRIPT_DIR/mlx.metallib" ]; then
    echo "  mlx.metallib → $INSTALL_DIR/mlx.metallib"
fi
echo ""

# Check if install dir is on PATH
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
    echo "Note: $INSTALL_DIR is not on your PATH."
    echo "Add it with: export PATH=\"$INSTALL_DIR:\$PATH\""
fi
