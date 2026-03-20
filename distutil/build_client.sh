#!/bin/bash -x
set -e

SRCROOT=`git rev-parse --show-toplevel`
NOCSERVER_SRC=$SRCROOT

GIT_TAG=`git rev-parse --short HEAD`

# append '-dirty' when there are uncommitted changes
if [[ -n `git status --porcelain` ]]; then
    GIT_TAG="$GIT_TAG-dirty"
fi

PRODUCT_NAME="Noctiluca Navigator"
VERSION=$(grep 'MARKETING_VERSION = ' 'NoctilucaClient/NoctilucaClient.xcodeproj/project.pbxproj' | tail -n 1 | perl -nE '/= ([\d\.]+);/;print $1')
IDENTIFIER="app.noctiluca.client.unleashed"

# [중요] Notarytool 프로필 이름 (터미널에서 'xcrun notarytool store-credentials'로 생성 필요)
NOTARY_KEYCHAIN_PROFILE="tu-noctiluca-notarycred"

# 인증서 이름
APP_CERT_ID="Developer ID Application: team unstablers Inc. (XHA76UVA95)"

# 빌드 출력 및 임시 경로
DIST_DIR="$SRCROOT/dist_client"
INTERMEDIATE_DIR="$DIST_DIR/intermediate"
UPDATES_DIR="$SRCROOT/dist_client_updates"
# DerivedData를 빌드 디렉토리 내에 고정 (SPM 아티팩트 경로 예측 가능)
DERIVED_DATA_PATH="$DIST_DIR/DerivedData"
FINAL_DMG="$UPDATES_DIR/noctiluca-navigator-unleashed-signed-$VERSION-$GIT_TAG-RELEASE.dmg"

# 초기화
rm -rf "$DIST_DIR"
mkdir -p "$INTERMEDIATE_DIR"
mkdir -p "$UPDATES_DIR"

# ==============================================================================
# 1. 빌드 (Archive + Export)
# ==============================================================================
function build_client() {
    ARCHIVE_PATH="$INTERMEDIATE_DIR/NoctilucaClient.xcarchive"
    EXPORT_PATH="$INTERMEDIATE_DIR/export"

    mkdir -p "$EXPORT_PATH"

    echo "🔨 Archiving NoctilucaClient..."
    xcodebuild -workspace "$NOCSERVER_SRC/NoctilucaServer.xcworkspace" \
               -scheme "Noctiluca Navigator UE" \
               -configuration Release \
               -destination 'generic/platform=macOS' \
               -derivedDataPath "$DERIVED_DATA_PATH" \
               -archivePath "$ARCHIVE_PATH" \
               archive

    # ExportOptions.plist 동적 생성
    cat <<EOF > "${INTERMEDIATE_DIR}/NoctilucaClient-ExportOptions.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>XHA76UVA95</string>
    <key>signingCertificate</key>
    <string>Developer ID Application: team unstablers Inc. (XHA76UVA95)</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>app.noctiluca.client.unleashed</key>
        <string>Noctiluca Navigator (Unleashed)</string>
    </dict>
</dict>
</plist>
EOF

    echo "📤 Exporting archive..."
    xcodebuild -exportArchive \
               -archivePath "$ARCHIVE_PATH" \
               -exportOptionsPlist "${INTERMEDIATE_DIR}/NoctilucaClient-ExportOptions.plist" \
               -exportPath "$EXPORT_PATH" \
               -allowProvisioningUpdates

    APP_PATH="${EXPORT_PATH}/Noctiluca Navigator.app"
}

# ==============================================================================
# 2. DMG 생성
# ==============================================================================
function create_dmg() {
    echo "💿 Creating DMG..."

    DMG_STAGING="$INTERMEDIATE_DIR/dmg-staging"
    DMG_TEMPLATE_DIR="$SRCROOT/distutil/navigator-dmg-templates"

    mkdir -p "$DMG_STAGING"
    cp -a "$APP_PATH" "$DMG_STAGING/"

    # create-dmg는 배경 설정 실패 등 비치명적 오류 시 exit code 2를 반환함
    set +e
    create-dmg \
        --volname "$PRODUCT_NAME" \
        --background "$DMG_TEMPLATE_DIR/background.png" \
        --window-pos 200 120 \
        --window-size 660 432 \
        --icon-size 128 \
        --icon "$PRODUCT_NAME.app" 180 200 \
        --hide-extension "$PRODUCT_NAME.app" \
        --app-drop-link 480 200 \
        "$FINAL_DMG" \
        "$DMG_STAGING"
    CREATE_DMG_EXIT=$?
    set -e

    if [[ $CREATE_DMG_EXIT -ne 0 && $CREATE_DMG_EXIT -ne 2 ]]; then
        echo "❌ create-dmg failed with exit code $CREATE_DMG_EXIT"
        exit 1
    fi

    codesign --force --sign "$APP_CERT_ID" \
        --timestamp \
        "$FINAL_DMG"
}

# --- 실행 ---
echo "📦 Building NoctilucaClient..."
build_client
create_dmg

# ==============================================================================
# 3. 공증 (Notarization)
# ==============================================================================
echo "🛡️  Submitting to Apple Notary Service..."

xcrun notarytool submit "$FINAL_DMG" \
                 --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
                 --wait

# ==============================================================================
# 4. 스테이플링 (Stapling)
# ==============================================================================
echo "📎 Stapling Ticket..."

xcrun stapler staple "$FINAL_DMG"

# DMG 검증
echo "🔍 Verifying DMG..."
spctl --assess --type open --context context:primary-signature -v "$FINAL_DMG"

echo "✅ 배포 준비 완료"
echo "   DMG: $FINAL_DMG"
