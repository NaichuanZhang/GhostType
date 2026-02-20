#!/bin/bash
# Build and run GhostType as a macOS .app bundle.
# The .app bundle is required for menu bar icon, accessibility permissions, etc.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."

cd "$PROJECT_DIR"

echo "Building GhostType..."
swift build 2>&1

APP_DIR="$PROJECT_DIR/.build/GhostType.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Kill existing instance and clean old bundle
killall GhostType 2>/dev/null || true
rm -rf "$APP_DIR"

# Create .app bundle structure
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Copy binary
cp .build/debug/GhostType "$MACOS_DIR/GhostType"

# Copy Info.plist
cp GhostType/Resources/Info.plist "$CONTENTS_DIR/Info.plist"

# Copy resources bundle if it exists (contains xcassets)
if [ -d ".build/debug/GhostType_GhostTypeLib.bundle" ]; then
    cp -R ".build/debug/GhostType_GhostTypeLib.bundle" "$RESOURCES_DIR/" 2>/dev/null || true
elif [ -d ".build/debug/GhostType_GhostType.bundle" ]; then
    cp -R ".build/debug/GhostType_GhostType.bundle" "$RESOURCES_DIR/" 2>/dev/null || true
fi


# Copy menu bar icon into app bundle Resources
cp GhostType/Resources/menu-icon.png "$RESOURCES_DIR/menu-icon.png"

echo ""
echo "App bundle: $APP_DIR"
echo ""
echo "Launching GhostType..."
echo "  - Look for the ghost icon in the menu bar"
echo "  - Press Ctrl+K anywhere to open the prompt panel"
echo "  - Escape or Ctrl+K again to dismiss"
echo ""

open "$APP_DIR"
