#!/usr/bin/env bash
set -euo pipefail

# Simple DMG builder for claude-pet.
# Usage:
#   ./scripts/make-dmg.sh
#   APP_VERSION=1.0.1 ./scripts/make-dmg.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/claude-pet.xcodeproj"
SCHEME_NAME="DoggoAgent"
CONFIGURATION="Release"
APP_NAME="claude-pet"
APP_VERSION="${APP_VERSION:-1.0.0}"
DIST_DIR="${ROOT_DIR}/dist"
STAGING_DIR="${DIST_DIR}/dmg-staging"
VOLUME_NAME="${APP_NAME} ${APP_VERSION}"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${APP_VERSION}.dmg"

echo "Building ${APP_NAME}.app..."
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME_NAME}" \
  -configuration "${CONFIGURATION}" \
  clean build \
  >/tmp/stitchagent-build.log

APP_PATH="$(ls -td "${HOME}/Library/Developer/Xcode/DerivedData"/*/Build/Products/${CONFIGURATION}/${APP_NAME}.app 2>/dev/null | head -n 1)"
if [[ ! -d "${APP_PATH}" ]]; then
  echo "Build failed - app not found at ${APP_PATH}"
  echo "See /tmp/stitchagent-build.log"
  exit 1
fi

echo "Preparing DMG staging..."
rm -rf "${STAGING_DIR}" "${DMG_PATH}"
mkdir -p "${STAGING_DIR}" "${DIST_DIR}"
cp -R "${APP_PATH}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

echo "Creating DMG..."
hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}" \
  >/tmp/stitchagent-dmg.log

echo "Done: ${DMG_PATH}"
echo "Next step for public release: sign + notarize this DMG."
