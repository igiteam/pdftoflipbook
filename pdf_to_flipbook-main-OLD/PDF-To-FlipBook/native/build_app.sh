#!/bin/bash

APPNAME=$(cat .appname 2>/dev/null || echo "PDF-To-FlipBook")

echo "🔨 Building $APPNAME..."
echo ""

rm -rf build dist 2>/dev/null || true
mkdir -p build dist

echo "📦 Compiling Swift code..."
swiftc Sources/main.swift \
    -framework Cocoa \
    -framework PDFKit \
    -o build/app_binary 2>&1

if [ $? -ne 0 ]; then
    echo "❌ Compilation failed"
    exit 1
fi

echo "✅ Compilation successful!"
echo ""
echo "📦 Creating app bundle: $APPNAME.app"
APP_BUNDLE="dist/$APPNAME.app"
rm -rf "$APP_BUNDLE" 2>/dev/null || true
mkdir -p "$APP_BUNDLE/Contents/"{MacOS,Resources}

cp build/app_binary "$APP_BUNDLE/Contents/MacOS/$APPNAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APPNAME"
echo "✅ Copied binary"

if [ -f "../public/app_icon.icns" ] && [ -s "../public/app_icon.icns" ]; then
    cp "../public/app_icon.icns" "$APP_BUNDLE/Contents/Resources/app_icon.icns"
    echo "✅ Copied .icns icon"
elif [ -f "../public/app_icon.png" ] && [ -s "../public/app_icon.png" ]; then
    cp "../public/app_icon.png" "$APP_BUNDLE/Contents/Resources/app_icon.icns"
    echo "✅ Copied .png as icon"
else
    echo "⚠ No icon found, app will use default"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" << INFO_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APPNAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.flipbook.${APPNAME//-/_}</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>$APPNAME</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>LSUIElement</key>
    <false/>
    <key>CFBundleIconFile</key>
    <string>app_icon.icns</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
INFO_EOF
echo "✅ Created Info.plist"

echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

if [ -d "$APP_BUNDLE" ]; then
    echo ""
    echo "🎉 BUILD SUCCESSFUL!"
    echo "📁 App bundle: $APP_BUNDLE"
else
    echo "❌ App bundle creation failed!"
    exit 1
fi

echo "✅ Build complete!"
