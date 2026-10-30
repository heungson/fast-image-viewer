#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
APP="$PROJECT_DIR/build/Fast Image Viewer.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos13.0" -O -framework AppKit -framework Carbon -framework ImageIO \
  "$PROJECT_DIR/Sources/ImageSource.swift" "$PROJECT_DIR/Sources/ImageLoader.swift" \
  "$PROJECT_DIR/Sources/main.swift" -o "$APP/Contents/MacOS/FastImageViewer"
cp "$PROJECT_DIR/Info.plist" "$APP/Contents/Info.plist"
if [[ ! -f "$APP/Contents/Resources/AppIcon.icns" ]]; then
  xcrun swift "$PROJECT_DIR/scripts/MakeIcon.swift" "$PROJECT_DIR/build"
  iconutil -c icns "$PROJECT_DIR/build/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
fi
codesign --force --deep --sign - "$APP"
print -r -- "$APP"
