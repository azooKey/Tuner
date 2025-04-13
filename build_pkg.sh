#!/bin/bash
set -e

# Paths
APP_PATH="/Users/takahashinaoki/Downloads/Tuner.app"
BUILD_DIR="./build"
PKG_TMP="Tuner-tmp.pkg"
PKG_FINAL="Tuner-release.pkg"
PKG_SIGNED="Tuner-release-signed.pkg"
BUNDLE_ID="dev.ensan.tuner-debug.azooKeyMac"
VERSION="1.0"
INSTALL_LOCATION="/Applications"

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Copy app to build dir
cp -R "$APP_PATH" "$BUILD_DIR/"

# Create component plist (only needed once, or if app structure changes)
pkgbuild --analyze --root "$BUILD_DIR" pkg.plist

# Create temporary package
pkgbuild --root "$BUILD_DIR" \
         --component-plist pkg.plist \
         --identifier "$BUNDLE_ID" \
         --version "$VERSION" \
         --install-location "$INSTALL_LOCATION" \
         "$PKG_TMP"

# Create distribution XML
productbuild --synthesize --package "$PKG_TMP" distribution.xml

# Build final pkg from distribution file
productbuild --distribution distribution.xml \
             --package-path . \
             "$PKG_FINAL"

# Clean temporary pkg
rm "$PKG_TMP"

# Sign the final pkg
productsign --sign "Developer ID Installer" "$PKG_FINAL" "$PKG_SIGNED"
rm "$PKG_FINAL"

# Notarize (requires "Notarytool" keychain profile setup in advance)
xcrun notarytool submit "$PKG_SIGNED" --keychain-profile "Notarytool" --wait

# Staple notarization ticket
xcrun stapler staple "$PKG_SIGNED"