#!/bin/bash -x 
set -e

SRCROOT=`git rev-parse --show-toplevel`
NOCSERVER_SRC=$SRCROOT

GIT_TAG=`git rev-parse --short HEAD`

# append '-dirty' when there are uncommitted changes
if [[ -n `git status --porcelain` ]]; then
    GIT_TAG="$GIT_TAG-dirty"
fi

PRODUCT_NAME="Noctiluca Server"
VERSION="0.1.0"
IDENTIFIER="pl.unstabler.noctiluca.NoctilucaServer"

# [중요] Notarytool 프로필 이름 (터미널에서 'xcrun notarytool store-credentials'로 생성 필요)
NOTARY_KEYCHAIN_PROFILE="tu-noctiluca-notarycred"

# 인증서 이름
INSTALLER_CERT_ID="Developer ID Installer: team unstablers Inc. (XHA76UVA95)"
APP_CERT_ID="Developer ID Application: team unstablers Inc. (XHA76UVA95)"

# 컴포넌트별 식별자
NOCSERVER_ID="pl.unstabler.noctiluca.NoctilucaServer"

# 빌드 출력 및 임시 경로
DIST_DIR="$SRCROOT/dist"
INTERMEDIATE_DIR="$DIST_DIR/intermediate"
PACKAGES_DIR="$DIST_DIR/packages"
# RESOURCES_DIR="$DIST_DIR/Resources" # 배경이미지, EULA 등이 위치할 폴더
FINAL_PKG="$DIST_DIR/noctiluca-server-signed-$VERSION-$GIT_TAG.pkg"

# 초기화
rm -rf "$DIST_DIR"
mkdir -p "$INTERMEDIATE_DIR"
mkdir -p "$PACKAGES_DIR"

# ==============================================================================
# 2. 빌드 및 컴포넌트 패키징 함수 (DSTROOT 방식 유지)
# ==============================================================================

# 공통 빌드 함수 (Hardened Runtime 적용을 위해 OTHER_CODE_SIGN_FLAGS 추가 권장)
function build_component() {
    local SCHEME=$1
    local DEST_PATH=$2
    
    echo "🔨 Building $SCHEME..."
    xcodebuild install \
        -workspace "$NOCSERVER_SRC/NoctilucaServer.xcworkspace" \
        -scheme "$SCHEME" \
        DSTROOT="$DEST_PATH" \
        CODE_SIGN_STYLE="Manual" \
        CODE_SIGN_IDENTITY="$APP_CERT_ID" \
        PROVISIONING_PROFILE_SPECIFIER="Automatic" \
        OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime"
}

function package_nocserver_pam_d() {
    local COMP_DIR="$INTERMEDIATE_DIR/NoctilucaServerPAMConf"
    mkdir -p "$COMP_DIR"
    
    mkdir -p "$COMP_DIR/etc/pam.d"
    cp -rv "$SRCROOT/pam.d/noctiluca" "$COMP_DIR/etc/pam.d/"

    pkgbuild \
        --identifier "app.noctiluca.server.pamconf" \
        --version "1.0.0" \
        --min-os-version "13.0" \
        --root "$COMP_DIR" \
        --install-location "/" \
        "$PACKAGES_DIR/NoctilucaServerPAMConf.pkg"
}

function package_nocserver() {
    local COMP_DIR="$INTERMEDIATE_DIR/NoctilucaServer"
    
    ARCHIVE_PATH="$INTERMEDIATE_DIR/NoctilucaServer.xcarchive"
    EXPORT_PATH="$COMP_DIR/Applications"
    
    mkdir -p "$EXPORT_PATH"

    APP_PATH="${EXPORT_PATH}/NoctilucaServer.app"

    xcodebuild -workspace "$NOCSERVER_SRC/NoctilucaServer.xcworkspace" \
               -scheme "NoctilucaServer" \
               -configuration Release \
               -destination 'generic/platform=macOS' \
               -archivePath "$ARCHIVE_PATH" \
               archive
    
    # ExportOptions.plist 동적 생성
    # (TeamID와 method는 본인 설정에 맞게 수정 필요할 수 있음. 보통 developer-id 사용)
    cat <<EOF > "${INTERMEDIATE_DIR}/NoctilucaServer-ExportOptions.plist"
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
        <key>app.noctiluca.server</key>
        <string>Noctiluca_Server</string>
    </dict>
</dict>
</plist>
EOF
    
    xcodebuild -exportArchive \
               -archivePath "$ARCHIVE_PATH" \
               -exportOptionsPlist "${INTERMEDIATE_DIR}/NoctilucaServer-ExportOptions.plist" \
               -exportPath "$EXPORT_PATH" \
               -allowProvisioningUpdates
    
    pkgbuild \
        --component "$APP_PATH" \
        --version "$VERSION" \
        --install-location "/Applications" \
        "$PACKAGES_DIR/NoctilucaServer.pkg"
}

# --- 실행: 각 컴포넌트 패키지 생성 ---
echo "📦 Start Packaging Components..."
# package_sessionbroker
# package_sessionprojector
# package_sessionprojector_launcher

package_nocserver
package_nocserver_pam_d

# ==============================================================================
# 3. Distribution XML 생성 (UI 커스터마이징)
# ==============================================================================
INSTALLER_TEMPLATE_DIR="$SRCROOT/distutil/installer-templates"
INSTALLER_DIR="$DIST_DIR/installer"

RESOURCES_DIR="$INSTALLER_DIR/Resources"

cp -rv "$INSTALLER_TEMPLATE_DIR" "$INSTALLER_DIR"

DIST_XML="$INSTALLER_DIR/distribution.xml"

 
# ==============================================================================
# 4. 최종 패키지 빌드 (Productbuild + Signing)
# ==============================================================================
echo "🎁 Building Final Product Package..."

productbuild --distribution "$DIST_XML" \
             --resources "$RESOURCES_DIR" \
             --package-path "$PACKAGES_DIR" \
             --sign "$INSTALLER_CERT_ID" \
             "$FINAL_PKG"

# ==============================================================================
# 5. 공증 (Notarization)
# ==============================================================================
echo "🛡️  Submitting to Apple Notary Service..."

xcrun notarytool submit "$FINAL_PKG" \
                 --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
                 --wait

# ==============================================================================
# 6. 스테이플링 (Stapling)
# ==============================================================================
echo "📎 Stapling Ticket..."

xcrun stapler staple "$FINAL_PKG"

if [ $? -eq 0 ]; then
    echo "✅ 배포 준비 완료: $FINAL_PKG"
    # 검증
    spctl --assess --type install --context context:primary-signature -v "$FINAL_PKG"
else
    echo "❌ Stapling Failed"
    exit 1
fi
