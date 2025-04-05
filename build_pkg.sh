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

# 証明書の確認
echo "証明書の確認を開始します..."
if ! security find-identity -v | grep -q "Developer ID Application"; then
    echo "エラー: Developer ID Application証明書が見つかりません"
    exit 1
fi

if ! security find-identity -v | grep -q "Developer ID Installer"; then
    echo "エラー: Developer ID Installer証明書が見つかりません"
    exit 1
fi

# ディレクトリの作成
mkdir -p "$BUILD_DIR" "$PKG_DIR" "$TEMP_DIR"

# Xcodeビルド（開発用署名）
echo "Xcodeビルドを開始します..."
xcodebuild -project Tuner.xcodeproj -scheme Tuner -configuration Release \
    CODE_SIGN_STYLE="Automatic" \
    DEVELOPMENT_TEAM="CW97U5J24N" \
    CODE_SIGN_IDENTITY="Apple Development" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES || {
    echo "エラー: Xcodeビルドに失敗しました"
    exit 1
}

# アプリケーションバンドルをコピー
echo "アプリケーションバンドルをコピーしています..."
DERIVED_DATA_APP=$(find "$HOME/Library/Developer/Xcode/DerivedData" -name "$APP_NAME.app" -type d | grep "Release" | head -n 1)

if [ -z "$DERIVED_DATA_APP" ]; then
    echo "エラー: ビルドされたアプリケーションが見つかりません"
    exit 1
fi

cp -R "$DERIVED_DATA_APP" "$APPLICATIONS_DIR/" || {
    echo "エラー: アプリケーションバンドルのコピーに失敗しました"
    exit 1
}

# アプリケーションの再署名
echo "アプリケーションを再署名しています..."
codesign --force --sign "Developer ID Application: Naoki Takahashi (CW97U5J24N)" \
         --options runtime \
         --timestamp \
         "$APPLICATIONS_DIR/$APP_NAME.app" || {
    echo "エラー: アプリケーションの再署名に失敗しました"
    exit 1
}

# パッケージの分析
echo "パッケージの分析を開始します..."
pkgbuild --analyze --root "$TEMP_DIR" pkg.plist || {
    echo "エラー: パッケージの分析に失敗しました"
    exit 1
}

# パッケージの作成と署名
echo "パッケージを作成しています..."
pkgbuild --root "$TEMP_DIR" \
         --component-plist pkg.plist \
         --identifier "$BUNDLE_ID" \
         --version "$VERSION" \
         --install-location "/Applications" \
         --sign "Developer ID Installer: Naoki Takahashi (CW97U5J24N)" \
         --timestamp \
         "$BUILD_DIR/$APP_NAME-$VERSION.pkg" || {
    echo "エラー: パッケージの作成に失敗しました"
    exit 1
}

# クリーンアップ
rm -rf "$TEMP_DIR" "$PKG_DIR" pkg.plist

echo "PKGファイルの作成が完了しました: $BUILD_DIR/$APP_NAME-$VERSION.pkg" 