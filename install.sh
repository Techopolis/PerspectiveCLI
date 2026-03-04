#!/bin/bash
# install.sh — Install PerspectiveCLI
#
# Usage:
#   sudo ./install.sh              Install to /usr/local/bin
#   sudo ./install.sh --uninstall  Remove installed files
#
# Requires sudo because /usr/local/bin is owned by root on macOS.

set -euo pipefail

INSTALL_DIR="/usr/local/bin"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Check sudo ────────────────────────────────────────────────────────
# /usr/local/bin is owned by root on macOS, so we need elevated privileges.
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run with sudo."
    echo ""
    echo "  sudo $0 ${1:-}"
    echo ""
    echo "/usr/local/bin is owned by root, so elevated privileges are required."
    exit 1
fi

# ── Uninstall ─────────────────────────────────────────────────────────
if [ "${1:-}" = "--uninstall" ]; then
    echo "Uninstalling Perspective CLI..."
    rm -f "$INSTALL_DIR/perspective"
    rm -f "$INSTALL_DIR/mlx.metallib"
    echo "Done."
    exit 0
fi

# ── Install ───────────────────────────────────────────────────────────

# Check that the binary exists in the same directory as this script
if [ ! -f "$SCRIPT_DIR/perspective" ]; then
    echo "Error: 'perspective' binary not found in $SCRIPT_DIR"
    echo "Run this script from inside the extracted archive."
    exit 1
fi

echo "Installing Perspective CLI to $INSTALL_DIR..."

# Create install directory
mkdir -p "$INSTALL_DIR"

# Copy files
cp "$SCRIPT_DIR/perspective" "$INSTALL_DIR/perspective"
chmod +x "$INSTALL_DIR/perspective"

if [ -f "$SCRIPT_DIR/mlx.metallib" ]; then
    cp "$SCRIPT_DIR/mlx.metallib" "$INSTALL_DIR/mlx.metallib"
fi

echo "Done."
echo ""
echo "  $INSTALL_DIR/perspective"
if [ -f "$SCRIPT_DIR/mlx.metallib" ]; then
    echo "  $INSTALL_DIR/mlx.metallib"
fi
echo ""

# Check if install dir is on PATH
if echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
    echo "Run 'perspective' to start."
else
    echo "Add /usr/local/bin to your PATH by adding this to your ~/.zshrc:"
    echo ""
    echo "  export PATH=\"/usr/local/bin:\$PATH\""
    echo ""
    echo "Then restart your terminal, or run:"
    echo ""
    echo "  source ~/.zshrc"
fi
echo ""
echo "To uninstall: sudo ./install.sh --uninstall"
