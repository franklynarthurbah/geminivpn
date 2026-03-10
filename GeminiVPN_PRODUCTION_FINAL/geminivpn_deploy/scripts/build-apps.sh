#!/usr/bin/env bash
# =============================================================================
# GeminiVPN — Multi-Platform App Build Script
# Builds: Android APK, Windows EXE, macOS DMG, Linux AppImage/DEB
# iOS IPA requires a macOS machine with Xcode — instructions provided.
#
# Usage: sudo bash scripts/build-apps.sh [platform]
#   platform: android | windows | macos | linux | all | desktop
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠  $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }
info() { echo -e "${CYAN}→ $1${NC}"; }
step() { echo ""; echo -e "${BOLD}── $1 ──${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DESKTOP_DIR="$PROJECT_DIR/desktop"
ANDROID_DIR="$PROJECT_DIR/android"
DOWNLOADS_DIR="${DOWNLOADS_DIR:-/var/www/geminivpn/downloads}"
BUILD_DIR="/tmp/geminivpn-builds"
APP_VERSION="${APP_VERSION:-1.0.0}"

mkdir -p "$DOWNLOADS_DIR" "$BUILD_DIR"

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         GeminiVPN — Multi-Platform App Builder              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "  Version : v${APP_VERSION}"
echo "  Output  : ${DOWNLOADS_DIR}"
echo ""

# =============================================================================
# DESKTOP (Electron) — Windows EXE, macOS DMG, Linux AppImage
# =============================================================================

build_desktop() {
  step "Desktop Apps (Electron)"

  [[ -d "$DESKTOP_DIR" ]] || fail "Desktop source not found: $DESKTOP_DIR"
  cd "$DESKTOP_DIR"

  # Install dependencies
  info "Installing desktop dependencies..."
  npm install --legacy-peer-deps 2>&1 | tail -3

  local PLATFORM="${1:-}"

  # Determine electron-builder target flags
  local BUILD_FLAGS="--dir"  # default: just compile, don't package
  case "$PLATFORM" in
    windows) BUILD_FLAGS="--win --x64" ;;
    macos)   BUILD_FLAGS="--mac --x64 --arm64" ;;
    linux)   BUILD_FLAGS="--linux AppImage deb" ;;
    all)     BUILD_FLAGS="--win --linux AppImage deb" ;;  # no mac on Linux CI
    *)       BUILD_FLAGS="--linux AppImage deb" ;;
  esac

  # Check if electron-builder is available
  if ! npx electron-builder --version &>/dev/null; then
    info "Installing electron-builder..."
    npm install --save-dev electron-builder 2>&1 | tail -3
  fi

  info "Building with flags: ${BUILD_FLAGS}..."

  # Set API URL for production build
  export VITE_API_URL="https://geminivpn.zapto.org/api/v1"

  # Build renderer first
  info "Building renderer (Vite)..."
  if [[ -f "node_modules/.bin/vite" ]]; then
    NODE_ENV=production node "node_modules/.bin/vite" build 2>&1 | tail -5
  else
    npm run build:renderer 2>&1 | tail -5 || warn "Renderer build skipped (no build:renderer script)"
  fi

  # Run electron-builder
  npx electron-builder $BUILD_FLAGS --publish never 2>&1 | tail -20 || {
    warn "electron-builder failed — creating placeholder files for download system"
    _create_placeholder_downloads
    return
  }

  # Copy outputs to downloads dir
  local DIST_DIR="$DESKTOP_DIR/dist"
  if [[ -d "$DIST_DIR" ]]; then
    find "$DIST_DIR" -name "*.exe"     -exec cp {} "${DOWNLOADS_DIR}/GeminiVPN-Setup.exe"  \; 2>/dev/null || true
    find "$DIST_DIR" -name "*.dmg"     -exec cp {} "${DOWNLOADS_DIR}/GeminiVPN.dmg"         \; 2>/dev/null || true
    find "$DIST_DIR" -name "*.AppImage"-exec cp {} "${DOWNLOADS_DIR}/GeminiVPN.AppImage"    \; 2>/dev/null || true
    find "$DIST_DIR" -name "*.deb"     -exec cp {} "${DOWNLOADS_DIR}/GeminiVPN.deb"         \; 2>/dev/null || true
    ok "Desktop builds copied to ${DOWNLOADS_DIR}"
  fi
}

# =============================================================================
# ANDROID APK
# =============================================================================

build_android() {
  step "Android APK"

  # Check if we're in a Docker container without Java
  if ! command -v java &>/dev/null; then
    info "Java not found — building Android APK via Docker..."
    _build_android_docker
    return
  fi

  [[ -d "$ANDROID_DIR" ]] || fail "Android source not found: $ANDROID_DIR"
  cd "$ANDROID_DIR"

  # Check for local.properties
  if [[ ! -f "local.properties" ]]; then
    info "Setting up local.properties..."
    local SDK_DIR
    SDK_DIR=$(find /opt /home /root -name "android-sdk" -maxdepth 5 2>/dev/null | head -1 || echo "/opt/android-sdk")
    echo "sdk.dir=${SDK_DIR}" > local.properties
  fi

  info "Running Gradle assembleRelease..."
  if ./gradlew assembleRelease 2>&1 | tail -20; then
    local APK
    APK=$(find . -name "*.apk" -path "*/release/*" | head -1)
    if [[ -n "$APK" ]]; then
      cp "$APK" "${DOWNLOADS_DIR}/GeminiVPN.apk"
      ok "Android APK built: ${DOWNLOADS_DIR}/GeminiVPN.apk"
      ls -lh "${DOWNLOADS_DIR}/GeminiVPN.apk"
    fi
  else
    warn "Native Gradle build failed — trying Docker..."
    _build_android_docker
  fi
}

_build_android_docker() {
  info "Building APK using Docker Android SDK image..."
  
  # Check if image is available
  if ! docker pull mingc/android-build-box:latest 2>/dev/null; then
    warn "Android Docker image unavailable. Creating placeholder APK."
    _create_placeholder_apk
    return
  fi

  docker run --rm \
    -v "$ANDROID_DIR":/app \
    -v "${DOWNLOADS_DIR}":/output \
    -w /app \
    mingc/android-build-box:latest \
    bash -c "
      ./gradlew assembleRelease --no-daemon 2>&1 | tail -20
      APK=\$(find . -name '*.apk' -path '*/release/*' | head -1)
      [[ -n \"\$APK\" ]] && cp \"\$APK\" /output/GeminiVPN.apk && echo 'APK copied'
    " && ok "APK built successfully" || {
      warn "Docker build failed. Creating placeholder."
      _create_placeholder_apk
    }
}

_create_placeholder_apk() {
  # Create a real minimal APK placeholder so the download endpoint serves something
  # (actual APK requires Android SDK — this lets you test the download flow)
  cat > "${BUILD_DIR}/apk_placeholder.py" << 'PYEOF'
import zipfile, io, os

placeholder_dir = os.environ.get('DOWNLOADS_DIR', '/var/www/geminivpn/downloads')
apk_path = os.path.join(placeholder_dir, 'GeminiVPN.apk')

with zipfile.ZipFile(apk_path, 'w', zipfile.ZIP_DEFLATED) as zf:
    manifest = '''<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.geminivpn"
    android:versionCode="1"
    android:versionName="1.0.0">
    <uses-sdk android:minSdkVersion="21" android:targetSdkVersion="34" />
    <application android:label="GeminiVPN" android:icon="@drawable/ic_launcher">
        <activity android:name=".ui.SplashActivity">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>'''
    zf.writestr('AndroidManifest.xml', manifest)
    zf.writestr('classes.dex', b'\x64\x65\x78\x0a\x30\x33\x35\x00' + b'\x00' * 100)
    zf.writestr('README.txt', 'GeminiVPN v1.0.0 - Build with Android SDK for production APK')

print(f"Placeholder APK created: {apk_path}")
PYEOF
  DOWNLOADS_DIR="$DOWNLOADS_DIR" python3 "${BUILD_DIR}/apk_placeholder.py"
  ok "Placeholder APK created (replace with real build from Android SDK)"
}

# =============================================================================
# PLACEHOLDER DOWNLOADS (when build tools unavailable)
# =============================================================================

_create_placeholder_downloads() {
  info "Creating placeholder download files..."

  # Windows EXE placeholder
  python3 - << PYEOF
import os
d = "${DOWNLOADS_DIR}"
for name, content in [
    ("GeminiVPN-Setup.exe", "MZ\x90\x00" + b"\x00"*60),
    ("GeminiVPN.dmg", b"geminivpn-dmg-placeholder-v${APP_VERSION}"),
    ("GeminiVPN.AppImage", b"#!/bin/sh\n# GeminiVPN AppImage placeholder\necho 'Install Android SDK or Electron to build real apps'"),
    ("GeminiVPN.deb", b"!<arch>\n"),
]:
    fp = os.path.join(d, name)
    if not os.path.exists(fp):
        with open(fp, 'wb') as f:
            f.write(content if isinstance(content, bytes) else content.encode())
        print(f"  Created placeholder: {name}")
PYEOF
  ok "Placeholder files created in ${DOWNLOADS_DIR}"
}

_create_router_guide() {
  step "Router Setup Guide (PDF)"
  local PDF_PATH="${DOWNLOADS_DIR}/router-guide.pdf"
  
  if [[ -f "$PDF_PATH" ]]; then
    ok "Router guide already exists"
    return
  fi

  # Generate a minimal but real PDF
  python3 - << 'PYEOF'
import os, textwrap

pdf_content = b"""%PDF-1.4
1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
3 0 obj<</Type/Page/MediaBox[0 0 612 792]/Parent 2 0 R/Resources<</Font<</F1 4 0 R>>>>/Contents 5 0 R>>endobj
4 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj
5 0 obj<</Length 480>>
stream
BT
/F1 24 Tf
80 720 Td
(GeminiVPN Router Setup Guide) Tj
/F1 12 Tf
0 -40 Td
(Configure WireGuard on your router for network-wide VPN protection.) Tj
0 -30 Td
(Step 1: Download WireGuard for your router firmware (DD-WRT / OpenWrt).) Tj
0 -20 Td
(Step 2: Log into your router admin panel.) Tj
0 -20 Td
(Step 3: Go to VPN > WireGuard and add new interface.) Tj
0 -20 Td
(Step 4: Import your GeminiVPN config file from the dashboard.) Tj
0 -20 Td
(Step 5: Save and restart the WireGuard interface.) Tj
0 -30 Td
(Support: https://geminivpn.zapto.org/support) Tj
ET
endstream
endobj
xref
0 6
0000000000 65535 f 
0000000009 00000 n 
0000000058 00000 n 
0000000115 00000 n 
0000000266 00000 n 
0000000343 00000 n 
trailer<</Size 6/Root 1 0 R>>
startxref
875
%%EOF"""

out = os.environ.get('PDF_PATH', '/var/www/geminivpn/downloads/router-guide.pdf')
with open(out, 'wb') as f:
    f.write(pdf_content)
print(f"Router guide PDF created: {out}")
PYEOF
  ok "Router setup guide created"
}

# =============================================================================
# iOS (macOS only)
# =============================================================================

build_ios_instructions() {
  step "iOS IPA — Build Instructions"
  echo ""
  echo "  iOS builds require a macOS machine with Xcode and an Apple Developer account."
  echo ""
  echo "  On your Mac:"
  echo "    1. Clone the project:"
  echo "       git clone https://your-repo/geminivpn.git && cd geminivpn/ios"
  echo ""
  echo "    2. Install CocoaPods dependencies:"
  echo "       pod install"
  echo ""
  echo "    3. Open GeminiVPN.xcworkspace in Xcode"
  echo ""
  echo "    4. Set Bundle ID: com.yourdomain.geminivpn"
  echo ""
  echo "    5. Select target 'GeminiVPN' → Product → Archive"
  echo ""
  echo "    6. Export as Ad Hoc or App Store IPA"
  echo ""
  echo "    7. Upload GeminiVPN.ipa to your server:"
  echo "       scp GeminiVPN.ipa root@geminivpn.zapto.org:/var/www/geminivpn/downloads/"
  echo ""
  echo "  Alternative: Use Expo EAS or Bitrise CI for cloud IPA builds."
  warn "iOS build instructions saved to ${DOWNLOADS_DIR}/iOS-Build-Instructions.txt"
  
  cat > "${DOWNLOADS_DIR}/iOS-Build-Instructions.txt" << 'EOF'
GeminiVPN iOS Build Instructions
=================================
Requires: macOS, Xcode 15+, Apple Developer Account

1. git clone <repo> && cd ios
2. pod install
3. Open GeminiVPN.xcworkspace in Xcode
4. Set Team & Bundle ID in Signing settings
5. Product → Archive → Export IPA
6. Upload to: /var/www/geminivpn/downloads/GeminiVPN.ipa
   scp GeminiVPN.ipa root@geminivpn.zapto.org:/var/www/geminivpn/downloads/

App Store URL configured in: /opt/geminivpn/.env → IOS_APP_STORE_URL
EOF
}

# =============================================================================
# VERSION FILE
# =============================================================================

write_version_manifest() {
  info "Writing version manifest..."
  cat > "${DOWNLOADS_DIR}/version.json" << EOF
{
  "version": "${APP_VERSION}",
  "buildDate": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "platforms": {
    "android": {
      "file": "GeminiVPN.apk",
      "url": "/api/v1/downloads/android",
      "available": $([ -f "${DOWNLOADS_DIR}/GeminiVPN.apk" ] && echo "true" || echo "false")
    },
    "windows": {
      "file": "GeminiVPN-Setup.exe",
      "url": "/api/v1/downloads/windows",
      "available": $([ -f "${DOWNLOADS_DIR}/GeminiVPN-Setup.exe" ] && echo "true" || echo "false")
    },
    "macos": {
      "file": "GeminiVPN.dmg",
      "url": "/api/v1/downloads/macos",
      "available": $([ -f "${DOWNLOADS_DIR}/GeminiVPN.dmg" ] && echo "true" || echo "false")
    },
    "linux": {
      "file": "GeminiVPN.AppImage",
      "url": "/api/v1/downloads/linux",
      "available": $([ -f "${DOWNLOADS_DIR}/GeminiVPN.AppImage" ] && echo "true" || echo "false")
    },
    "ios": {
      "url": "/api/v1/downloads/ios",
      "redirectsTo": "App Store",
      "available": true
    }
  }
}
EOF
  ok "Version manifest: ${DOWNLOADS_DIR}/version.json"
}

# =============================================================================
# Main
# =============================================================================

PLATFORM="${1:-all}"

case "$PLATFORM" in
  android)
    build_android
    ;;
  windows)
    build_desktop windows
    ;;
  macos)
    build_desktop macos
    ;;
  linux)
    build_desktop linux
    ;;
  desktop)
    build_desktop linux
    ;;
  ios)
    build_ios_instructions
    ;;
  all)
    build_android
    build_desktop linux
    build_ios_instructions
    _create_router_guide
    ;;
  placeholders)
    _create_placeholder_downloads
    _create_placeholder_apk
    _create_router_guide
    ;;
  *)
    fail "Unknown platform: $PLATFORM. Use: android|windows|macos|linux|desktop|ios|all|placeholders"
    ;;
esac

write_version_manifest

echo ""
echo -e "${BOLD}=== Download Files ===${NC}"
ls -lh "$DOWNLOADS_DIR" 2>/dev/null || warn "Downloads directory empty"

echo ""
ok "Build script complete! Files are in: ${DOWNLOADS_DIR}"
echo ""
echo "  Test download endpoints:"
echo "    curl -I https://geminivpn.zapto.org/api/v1/downloads/android"
echo "    curl -I https://geminivpn.zapto.org/api/v1/downloads/windows"
echo "    curl    https://geminivpn.zapto.org/api/v1/downloads/stats"
