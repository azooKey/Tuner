#!/bin/bash

# バージョン設定
VERSION="1.0.0"
APP_NAME="Tuner"
BUNDLE_ID="com.tuner.app"

# ビルドディレクトリの設定
BUILD_DIR="build"
PKG_DIR="$BUILD_DIR/pkg"
TEMP_DIR="$BUILD_DIR/temp"
APPLICATIONS_DIR="$TEMP_DIR"

# ディレクトリの作成
mkdir -p "$BUILD_DIR" "$PKG_DIR" "$TEMP_DIR"

# Xcodeビルド（自動署名を有効化）
xcodebuild -project Tuner.xcodeproj -scheme Tuner -configuration Release CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# アプリケーションバンドルをコピー
DERIVED_DATA_APP="$HOME/Library/Developer/Xcode/DerivedData/Tuner-ciqmcchfmnbfecalwkclsxhusmkq/Build/Products/Release/$APP_NAME.app"
cp -R "$DERIVED_DATA_APP" "$APPLICATIONS_DIR/"

# pkgbuildの実行
pkgbuild --root "$TEMP_DIR" \
         --identifier "$BUNDLE_ID" \
         --version "$VERSION" \
         --install-location "/Applications" \
         "$PKG_DIR/$APP_NAME.pkg"

# productbuildの実行
productbuild --distribution Distribution.xml \
             --package-path "$PKG_DIR" \
             --version "$VERSION" \
             "$BUILD_DIR/$APP_NAME-$VERSION.pkg"

# クリーンアップ
rm -rf "$TEMP_DIR" "$PKG_DIR"

echo "PKGファイルの作成が完了しました: $BUILD_DIR/$APP_NAME-$VERSION.pkg" 