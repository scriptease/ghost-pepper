#!/bin/bash
set -euo pipefail

APP_NAME="GhostPepper"
DMG_NAME="GhostPepper"
BUILD_DIR="build"
DMG_DIR="$BUILD_DIR/dmg"

# Get version from Info.plist
VERSION=$(defaults read "$(pwd)/GhostPepper/Info.plist" CFBundleShortVersionString)
BUILD_NUMBER=$(defaults read "$(pwd)/GhostPepper/Info.plist" CFBundleVersion)

echo "==> Building $APP_NAME v$VERSION (build $BUILD_NUMBER)..."

echo "==> Cleaning..."
rm -rf "$BUILD_DIR"
mkdir -p "$DMG_DIR"

echo "==> Building release..."
xcodebuild -project "$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/derived" \
  -skipMacroValidation \
  build 2>&1 | tail -5

APP_PATH="$BUILD_DIR/derived/Build/Products/Release/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: Build failed — $APP_PATH not found"
  exit 1
fi

echo "==> Preparing DMG contents..."
cp -R "$APP_PATH" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

echo "==> Creating DMG..."
hdiutil create -volname "$APP_NAME" \
  -srcfolder "$DMG_DIR" \
  -ov -format UDZO \
  "$BUILD_DIR/$DMG_NAME.dmg"

echo "==> Generating Sparkle signature..."
SPARKLE_SIGN=$(find ~/Library/Developer/Xcode/DerivedData/GhostPepper-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update 2>/dev/null | head -1)
if [ -n "$SPARKLE_SIGN" ]; then
  SIGNATURE=$("$SPARKLE_SIGN" "$BUILD_DIR/$DMG_NAME.dmg" 2>&1)
  echo "$SIGNATURE"
  echo ""
  echo "Add this to the appcast.xml <enclosure> tag:"
  echo "  $SIGNATURE"
else
  echo "WARNING: sign_update not found — run a build in Xcode first to fetch Sparkle"
fi

echo "==> Cleaning up..."
rm -rf "$DMG_DIR" "$BUILD_DIR/derived"

DMG_SIZE=$(stat -f%z "$BUILD_DIR/$DMG_NAME.dmg")

echo ""
echo "Done! DMG is at: $BUILD_DIR/$DMG_NAME.dmg ($DMG_SIZE bytes)"
echo ""
echo "Next steps:"
echo "  1. Update appcast.xml with version $VERSION, size $DMG_SIZE, and signature above"
echo "  2. Commit and push appcast.xml"
echo "  3. Create a GitHub release: gh release create v$VERSION $BUILD_DIR/$DMG_NAME.dmg --title \"Ghost Pepper v$VERSION\""
