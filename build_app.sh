#!/usr/bin/env bash
# build_app.sh — builds Panels and packages it as a proper macOS .app bundle
# Usage: ./build_app.sh
# Output: Panels.app  and  Panels-macOS.zip  in the project root

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="Panels"
APP_BUNDLE="${APP_NAME}.app"
BUILD_DIR=".build/release"
RESOURCES_BUNDLE="${BUILD_DIR}/${APP_NAME}_${APP_NAME}.bundle"

echo "==> Building release binary..."
swift build -c release

echo ""
echo "==> Packaging ${APP_BUNDLE}..."

# Remove any previous .app
rm -rf "${APP_BUNDLE}"

# Create the .app directory structure
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy the executable
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Copy Info.plist
cp "Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# Copy the SPM resource bundle (contains Panels.png, SampleComics, etc.)
if [ -d "${RESOURCES_BUNDLE}" ]; then
    cp -R "${RESOURCES_BUNDLE}" "${APP_BUNDLE}/Contents/Resources/"
    echo "    Bundled resources: ${RESOURCES_BUNDLE}"
else
    echo "    Warning: resource bundle not found at ${RESOURCES_BUNDLE}"
fi

# Generate a simple .icns from Panels.png so macOS shows the icon in Finder
PNG_SOURCE="Sources/Resources/Panels.png"
ICONSET_DIR="${APP_BUNDLE}/Contents/Resources/AppIcon.iconset"

if command -v sips &>/dev/null && [ -f "${PNG_SOURCE}" ]; then
    mkdir -p "${ICONSET_DIR}"
    for size in 16 32 64 128 256 512; do
        sips -z ${size} ${size} "${PNG_SOURCE}" --out "${ICONSET_DIR}/icon_${size}x${size}.png"    &>/dev/null
        sips -z $((size*2)) $((size*2)) "${PNG_SOURCE}" --out "${ICONSET_DIR}/icon_${size}x${size}@2x.png" &>/dev/null
    done
    iconutil -c icns "${ICONSET_DIR}" -o "${APP_BUNDLE}/Contents/Resources/AppIcon.icns" 2>/dev/null && \
        echo "    Generated AppIcon.icns"
    rm -rf "${ICONSET_DIR}"
fi

echo ""
echo "==> Clearing quarantine attribute..."
xattr -cr "${APP_BUNDLE}" 2>/dev/null || true

echo ""
echo "==> Creating Panels-macOS.zip..."
rm -f Panels-macOS.zip
zip -r --quiet Panels-macOS.zip "${APP_BUNDLE}"

echo ""
echo "Done."
echo ""
echo "  ${APP_BUNDLE}         — drag into /Applications to install"
echo "  Panels-macOS.zip    — upload this to a GitHub Release"
echo ""
echo "Architecture: $(uname -m)"
echo "macOS:        $(sw_vers -productVersion)"
