#!/bin/bash
set -euo pipefail

APP_NAME="CalSync"
BUILD_DIR=".build/release"
BUNDLE_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "Building ${APP_NAME} in release mode..."
swift build -c release

echo "Creating app bundle at ${BUNDLE_DIR}..."
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

cp "${BUILD_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
cp "Sources/CalSync/Info.plist" "${CONTENTS_DIR}/Info.plist"
cp "icons/v2_without_border.icns" "${RESOURCES_DIR}/AppIcon.icns"

echo "Done! App bundle created at: ${BUNDLE_DIR}"
echo ""
echo "To run:  open ${BUNDLE_DIR}"
echo "To install: cp -r ${BUNDLE_DIR} /Applications/"
