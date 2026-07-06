#!/bin/bash
# Build PixelPetCafe.app into dist/ (release, ad-hoc signed, no dock icon).
set -euo pipefail
cd "$(dirname "$0")/.."

# separate scratch path: editor LSP holds .build/build.db
swift build -c release --scratch-path .build-release || true  # spurious build.db exit on this FS
test -x .build-release/release/PixelPetCafe || { echo "build failed"; exit 1; }

APP=dist/PixelPetCafe.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build-release/release/PixelPetCafe "$APP/Contents/MacOS/"
cp -R .build-release/release/PixelPetCafe_PixelPetCafe.bundle "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>PixelPetCafe</string>
    <key>CFBundleIdentifier</key><string>com.leonardcl.pixelpetcafe</string>
    <key>CFBundleName</key><string>Pixel Pet Café</string>
    <key>CFBundleDisplayName</key><string>Pixel Pet Café</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>Leonard Christopher Limanjaya</string>
</dict>
</plist>
PLIST

# Sign with a real Apple Development identity when available so macOS
# permissions (Accessibility for Work Mode) survive across rebuilds — an
# ad-hoc signature ("-") gets a new identity hash every build, which silently
# invalidates TCC grants each time. Falls back to ad-hoc if none is found.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | sed -E 's/.*"(.*)"/\1/')
if [ -n "$IDENTITY" ]; then
  echo "signing with: $IDENTITY"
  codesign --force --deep --sign "$IDENTITY" "$APP"
else
  echo "no Apple Development identity found — signing ad-hoc (Accessibility grants won't survive rebuilds)"
  codesign --force --sign - "$APP"
fi
echo "built $APP"
