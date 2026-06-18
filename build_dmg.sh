#!/bin/bash

# Zatrzymanie skryptu w razie błędu
set -e

APP_NAME="Vessel"
APP_BUNDLE="$APP_NAME.app"
DMG_NAME="$APP_NAME.dmg"
ICON_PNG="Assets/icon.png"
ICON_ICNS="Vessel.icns"

echo "🔨 1/6 Budowanie wersji Release..."
swift build -c release -Xswiftc -strict-concurrency=minimal -Xswiftc -whole-module-optimization -Xlinker -dead_strip

echo "📦 2/6 Tworzenie struktury $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Kopiowanie pliku binarnego
cp .build/release/$APP_NAME "$APP_BUNDLE/Contents/MacOS/"

echo "🔨 Budowanie narzędzia CLI (vcctl)..."
swift build -c release --product vcctl -Xswiftc -strict-concurrency=minimal -Xswiftc -whole-module-optimization -Xlinker -dead_strip
cp .build/release/vcctl "$APP_BUNDLE/Contents/Resources/cctl"

echo "🔨 Budowanie demona VesselHelper..."
swift build -c release --product VesselHelper
mkdir -p "$APP_BUNDLE/Contents/Library/LaunchDaemons"
cp .build/release/VesselHelper "$APP_BUNDLE/Contents/MacOS/VesselHelper"

echo "📝 Generowanie com.vessel.helper.plist..."
cat > "$APP_BUNDLE/Contents/Library/LaunchDaemons/com.vessel.helper.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.vessel.helper</string>
    <key>BundleProgram</key>
    <string>Contents/MacOS/VesselHelper</string>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF


echo "🔨 Budowanie demona (vesseld)..."
swift build -c release --product vesseld -Xswiftc -whole-module-optimization -Xlinker -dead_strip

XPCSERVICE_DIR="$APP_BUNDLE/Contents/XPCServices/com.vessel.daemon.xpc"
mkdir -p "$XPCSERVICE_DIR/Contents/MacOS"

cp .build/release/vesseld "$XPCSERVICE_DIR/Contents/MacOS/com.vessel.daemon"

cat > "$XPCSERVICE_DIR/Contents/Info.plist" <<EOF2
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>com.vessel.daemon</string>
    <key>CFBundleIdentifier</key>
    <string>com.vessel.daemon</string>
    <key>CFBundleName</key>
    <string>vesseld</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>XPCService</key>
    <dict>
        <key>ServiceType</key>
        <string>Application</string>
    </dict>
</dict>
</plist>
EOF2

echo "🖼️ 3/6 Generowanie ikony aplikacji ($ICON_ICNS)..."

mkdir -p "Assets"
if [ ! -f "$ICON_PNG" ]; then
    echo "⚠️ Nie znaleziono $ICON_PNG. Proszę dodać ikonę."
    exit 1
fi

GENERATED_ICNS="Assets/$ICON_ICNS"
if [ "$ICON_PNG" -nt "$GENERATED_ICNS" ] || [ ! -f "$GENERATED_ICNS" ]; then
    echo "⚙️ Tworzenie pliku .icns za pomocą narzędzi sips i iconutil (standard macOS)..."
    ICONSET_DIR="Vessel.iconset"
    mkdir -p "$ICONSET_DIR"
    sips -s format png -z 16 16     "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16.png" > /dev/null
    sips -s format png -z 32 32     "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null
    sips -s format png -z 32 32     "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32.png" > /dev/null
    sips -s format png -z 64 64     "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null
    sips -s format png -z 128 128   "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128.png" > /dev/null
    sips -s format png -z 256 256   "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null
    sips -s format png -z 256 256   "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256.png" > /dev/null
    sips -s format png -z 512 512   "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null
    sips -s format png -z 512 512   "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512.png" > /dev/null
    sips -s format png -z 1024 1024 "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null

    iconutil -c icns "$ICONSET_DIR" -o "$GENERATED_ICNS"
    rm -rf "$ICONSET_DIR"
else
    echo "⏭️ Pomijam generowanie ikony (brak zmian w pliku źródłowym)."
fi

cp "$GENERATED_ICNS" "$APP_BUNDLE/Contents/Resources/$ICON_ICNS"

echo "📝 4/6 Generowanie Info.plist..."
cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.vessel.app</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>$ICON_ICNS</string>
</dict>
</plist>
EOF

echo "🔐 5/6 Ad-Hoc Code Signing (inside-out)..."
codesign --force --options runtime --sign - --entitlements Vessel.entitlements "$APP_BUNDLE/Contents/Resources/cctl"
codesign --force --options runtime --sign - --entitlements Vessel.entitlements "$APP_BUNDLE/Contents/MacOS/VesselHelper"
codesign --force --options runtime --sign - --entitlements vesseld.entitlements "$APP_BUNDLE/Contents/XPCServices/com.vessel.daemon.xpc"
codesign --force --options runtime --sign - --entitlements Vessel.entitlements "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
codesign --force --options runtime --sign - --entitlements Vessel.entitlements "$APP_BUNDLE"

echo "💿 6/6 Generowanie pięknego pliku $DMG_NAME..."
rm -f "$DMG_NAME"

if command -v create-dmg &> /dev/null; then
    # create-dmg potrafi działać nieco głośniej i wymaga uprawnień lub czystego obrazu
    create-dmg \
      --volname "$APP_NAME" \
      --volicon "$APP_BUNDLE/Contents/Resources/$ICON_ICNS" \
      --window-pos 200 120 \
      --window-size 600 400 \
      --icon-size 100 \
      --icon "$APP_NAME.app" 150 190 \
      --hide-extension "$APP_NAME.app" \
      --app-drop-link 450 190 \
      --no-internet-enable \
      --skip-jenkins \
      "$DMG_NAME" \
      "$APP_BUNDLE"
else
    echo "⚠️ Narzędzie create-dmg nie zostało znalezione, używam hdiutil..."
    hdiutil create -volname "$APP_NAME" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_NAME"
fi

echo "✅ Gotowe! Twój plik $DMG_NAME czeka w folderze projektu."
