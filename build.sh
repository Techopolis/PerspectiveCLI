#!/bin/bash
# build.sh — Build PerspectiveCLI
#
# Usage:
#   ./build.sh           Build debug (default)
#   ./build.sh release   Build release (optimized)
#   ./build.sh clean     Clean build artifacts and rebuild debug
#   ./build.sh dist      Build release + create distributable .tar.gz
#
# This script handles both Swift compilation and Metal shader compilation,
# which swift build cannot do on its own.

set -euo pipefail

CONFIG="debug"
CLEAN=false
DIST=false

case "${1:-}" in
    release) CONFIG="release" ;;
    clean)   CLEAN=true ;;
    dist)    CONFIG="release"; DIST=true ;;
esac

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

# ── Clean ──────────────────────────────────────────────────────────────
if $CLEAN; then
    echo "Cleaning build artifacts..."
    swift package clean
    echo ""
fi

# ── Swift Build ────────────────────────────────────────────────────────
echo "Building PerspectiveCLI ($CONFIG)..."
if [ "$CONFIG" = "release" ]; then
    swift build -c release
else
    swift build
fi

BIN_DIR=$(swift build ${CONFIG:+-c $CONFIG} --show-bin-path 2>/dev/null)
echo "Binary: $BIN_DIR/PerspectiveCLI"
echo ""

# ── Metal Shaders ──────────────────────────────────────────────────────
# SwiftPM doesn't compile .metal files in C/C++ targets.
# We compile them manually and place mlx.metallib next to the binary.

METAL_DIR=".build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal"

if [ ! -d "$METAL_DIR" ]; then
    echo "Warning: Metal shader directory not found, skipping metallib build."
    echo "MLX backend will not work without it."
    exit 0
fi

# Skip if metallib is already newer than all .metal sources
METALLIB="$BIN_DIR/mlx.metallib"
if [ -f "$METALLIB" ]; then
    NEEDS_REBUILD=false
    while IFS= read -r f; do
        if [ "$f" -nt "$METALLIB" ]; then
            NEEDS_REBUILD=true
            break
        fi
    done < <(find "$METAL_DIR" -name "*.metal")

    if ! $NEEDS_REBUILD; then
        echo "mlx.metallib is up to date, skipping."
        SKIP_METAL=true
    fi
fi

if [ "${SKIP_METAL:-false}" = false ]; then
    WORK=$(mktemp -d)
    trap 'rm -rf "$WORK"' EXIT

    echo "Compiling Metal shaders..."
    for f in $(find "$METAL_DIR" -name "*.metal"); do
        name=$(basename "$f" .metal)
        echo "  $name"
        xcrun metal -c \
            -I "$METAL_DIR" \
            -I "$METAL_DIR/steel" \
            -I "$METAL_DIR/steel/gemm" \
            -I "$METAL_DIR/steel/conv" \
            -I "$METAL_DIR/steel/attn" \
            -I "$METAL_DIR/steel/attn/kernels" \
            -o "$WORK/$name.air" "$f"
    done

    echo "Linking mlx.metallib..."
    xcrun metallib -o "$WORK/mlx.metallib" "$WORK"/*.air
    cp "$WORK/mlx.metallib" "$METALLIB"
fi

echo ""

# ── Dist ──────────────────────────────────────────────────────────────
if $DIST; then
    VERSION=$(git describe --tags 2>/dev/null || echo "dev")
    DIST_DIR="$PROJECT_DIR/dist"
    STAGE="$DIST_DIR/perspective-cli-${VERSION}"
    ARCHIVE="$DIST_DIR/perspective-cli-${VERSION}-macos-arm64.tar.gz"

    rm -rf "$STAGE"
    mkdir -p "$STAGE"

    cp "$BIN_DIR/PerspectiveCLI" "$STAGE/perspective"
    cp "$METALLIB" "$STAGE/mlx.metallib"
    cp "$PROJECT_DIR/LICENSE" "$STAGE/" 2>/dev/null || true
    cp "$PROJECT_DIR/README.md" "$STAGE/"

    tar -czf "$ARCHIVE" -C "$DIST_DIR" "perspective-cli-${VERSION}"
    rm -rf "$STAGE"

    SHA=$(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)

    echo "Distribution archive created:"
    echo "  $ARCHIVE"
    echo "  SHA-256: $SHA"
    echo ""
    echo "To install manually:"
    echo "  tar xzf $(basename "$ARCHIVE")"
    echo "  cp perspective-cli-${VERSION}/perspective /usr/local/bin/"
    echo "  cp perspective-cli-${VERSION}/mlx.metallib /usr/local/bin/"
fi

echo "Build complete."
