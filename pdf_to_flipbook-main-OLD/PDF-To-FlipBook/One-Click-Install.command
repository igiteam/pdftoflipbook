#!/bin/bash

echo "⚡ PDF to FlipBook Installer"
echo "================================================"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

APPNAME=$(cat native/.appname 2>/dev/null || echo "PDF-To-FlipBook")
echo "Installing: $APPNAME"
echo ""

echo "🔨 Step 1: Building app..."
cd native || exit 1

if ./build_app.sh; then
    echo ""
    echo "✅ Build successful!"
else
    echo "❌ Build failed"
    exit 1
fi

echo ""
echo "📦 Step 2: Installing to Applications..."
APP_BUNDLE="dist/$APPNAME.app"
USER_APPS="$HOME/Applications"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "❌ App bundle not found at: $APP_BUNDLE"
    exit 1
fi

mkdir -p "$USER_APPS"
if [ -d "$USER_APPS/$APPNAME.app" ]; then
    echo "⚠ Removing existing app..."
    rm -rf "$USER_APPS/$APPNAME.app"
fi

if cp -R "$APP_BUNDLE" "$USER_APPS/"; then
    INSTALL_PATH="$USER_APPS/$APPNAME.app"
    echo "✅ Installed to: $INSTALL_PATH"
else
    echo "❌ Installation failed!"
    exit 1
fi

echo -e "🔍 Verifying app bundle structure..."

if [ -f "$APP_BUNDLE/Contents/MacOS/$APPNAME" ]; then
    echo -e "   ✅ Bundle structure is CORRECT"
else
    echo -e "   ❌ Bundle structure is INCORRECT!"
    exit 1
fi

echo -e "📋 Installing to Applications..."

mkdir -p "$HOME/Applications"
APP_PATH="$HOME/Applications/$APPNAME.app"
rm -rf "$APP_PATH"
cp -R "$APP_BUNDLE" "$APP_PATH"

if [ -d "$APP_PATH" ]; then
    echo -e "   ✅ Installed to: $APP_PATH"
else
    echo -e "   ❌ Failed to install to Applications"
    APP_PATH="$(pwd)/$APP_BUNDLE"
fi

DESKTOP_APP="$HOME/Desktop/$APPNAME.app"
rm -rf "$DESKTOP_APP"
cp -R "$APP_BUNDLE" "$DESKTOP_APP"
echo -e "   ✅ Copied to Desktop: $DESKTOP_APP"

cat > "$HOME/Desktop/Launch $APPNAME.command" << LAUNCHER_EOF
#!/bin/bash
echo "🚀 Launching $APPNAME..."
open "$APP_PATH"
LAUNCHER_EOF
chmod +x "$HOME/Desktop/Launch $APPNAME.command"
echo -e "   ✅ Launcher created"

echo -e "📌 Adding to Dock..."

DOCK_APPS=$(defaults read com.apple.dock persistent-apps 2>/dev/null || echo "[]")
if ! echo "$DOCK_APPS" | grep -q "$APPNAME"; then
    defaults write com.apple.dock persistent-apps -array-add "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$APP_PATH</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
    killall Dock 2>/dev/null &
    echo -e "   ✅ Added to Dock"
else
    echo -e "   ⚠ App already in Dock"
fi

echo ""
echo "🚀 Step 4: Launching $APPNAME..."

sleep 2

if open "$INSTALL_PATH" 2>/dev/null; then
    echo "✅ App launched successfully!"
else
    echo "⚠ Could not launch automatically"
    echo "   Open manually from: $INSTALL_PATH"
    echo "   Or use: Desktop/Launch $APPNAME.command"
fi

echo ""
echo "🎉 INSTALLATION COMPLETE!"
echo "================================================"
echo "📋 HOW TO USE:"
echo "   1. Drag & drop a PDF onto the app window"
echo "   2. Click 'Convert PDF to FlipBook'"
echo "   3. PNG images + HTML saved to Downloads folder"
echo ""
echo "📁 OUTPUT: Downloads/[PDFName]_FlipBook/"
echo "   - [name]_page_1.png, page_2.png, etc."
echo "   - [name]_flipbook.html (open in browser)"
echo "================================================"
echo ""
echo "📌 App installed to: $INSTALL_PATH"
echo "📌 Desktop copy: $HOME/Desktop/$APPNAME.app"
echo "📌 Launcher: $HOME/Desktop/Launch $APPNAME.command"
