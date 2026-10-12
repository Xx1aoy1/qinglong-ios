#!/usr/bin/env bash
#
# 本地（macOS）一键构建未签名 IPA，产物：./dist/QingLong-<version>.ipa
#
# 用法：
#   ./Scripts/build_ipa.sh              # 构建
#   VERSION=1.2.0 ./Scripts/build_ipa.sh
#
# 前置依赖：Xcode 命令行工具、xcodegen
#   brew install xcodegen ldid
#
set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="QingLong"
PROJECT="QingLong.xcodeproj"
BUILD_DIR="build"
DIST_DIR="dist"

VERSION="${VERSION:-$(grep -m1 'MARKETING_VERSION:' project.yml \
  | sed -E 's/.*MARKETING_VERSION:[[:space:]]*"?([^"]*)"?.*/\1/' | tr -d '[:space:]')}"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
REPO_URL="${REPO_URL:-https://github.com/Xx1aoy1/qinglong-ios}"

echo "==> 版本：${VERSION} (build ${BUILD_NUMBER})"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "::error::未找到 xcodegen，请先执行： brew install xcodegen"
  exit 1
fi

echo "==> 生成 Xcode 工程"
xcodegen generate --spec project.yml

echo "==> 编译（未签名 / arm64）"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$BUILD_DIR" \
  ONLY_ACTIVE_ARCH=NO \
  ARCHS=arm64 \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  QL_REPOSITORY_URL="$REPO_URL" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  DEVELOPMENT_TEAM="" \
  clean build

APP="${BUILD_DIR}/Build/Products/Release-iphoneos/${SCHEME}.app"
[ -d "$APP" ] || { echo "::error::未找到 .app：$APP"; exit 1; }

echo "==> 打包 IPA"
rm -rf "$DIST_DIR/Payload" "${DIST_DIR}/${SCHEME}-${VERSION}.ipa"
mkdir -p "$DIST_DIR/Payload"
cp -R "$APP" "$DIST_DIR/Payload/"

if command -v ldid >/dev/null 2>&1; then
  ldid -S "$DIST_DIR/Payload/${SCHEME}.app/${SCHEME}" && echo "    ldid 伪签名完成"
fi

rm -rf "$DIST_DIR/Payload/${SCHEME}.app/_CodeSignature" \
       "$DIST_DIR/Payload/${SCHEME}.app/embedded.mobileprovision" || true

( cd "$DIST_DIR" && zip -qry "${SCHEME}-${VERSION}.ipa" Payload )
rm -rf "$DIST_DIR/Payload"

echo
echo "==> 完成：$(pwd)/${DIST_DIR}/${SCHEME}-${VERSION}.ipa"
echo "    用 AirDrop / 爱思助手 / Filza 传到设备，再用 TrollStore 安装。"
