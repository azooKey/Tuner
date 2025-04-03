#!/bin/bash

# エラー時に即座に終了
set -e

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

# パッケージの分析
pkgbuild --analyze --root "$TEMP_DIR" pkg.plist

# 一時パッケージの作成
pkgbuild --root "$TEMP_DIR" \
         --component-plist pkg.plist \
         --identifier "$BUNDLE_ID" \
         --version "$VERSION" \
         --install-location "/Applications" \
         "$PKG_DIR/$APP_NAME-tmp.pkg"

# 最終パッケージの作成
productbuild --distribution Distribution.xml \
             --package-path "$PKG_DIR" \
             --version "$VERSION" \
             "$BUILD_DIR/$APP_NAME-$VERSION.pkg"

# 署名
productsign --sign "Developer ID Installer" \
            "$BUILD_DIR/$APP_NAME-$VERSION.pkg" \
            "$BUILD_DIR/$APP_NAME-$VERSION-signed.pkg"

# 署名済みパッケージを元の名前に移動
mv "$BUILD_DIR/$APP_NAME-$VERSION-signed.pkg" "$BUILD_DIR/$APP_NAME-$VERSION.pkg"

# クリーンアップ
rm -rf "$TEMP_DIR" "$PKG_DIR" pkg.plist

echo "PKGファイルの作成が完了しました: $BUILD_DIR/$APP_NAME-$VERSION.pkg" 