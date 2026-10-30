#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
"$PROJECT_DIR/scripts/build.sh"
DESTINATION="$HOME/Applications/Fast Image Viewer.app"
if [[ -e "$DESTINATION" ]]; then
  BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DESTINATION/Contents/Info.plist")
  [[ "$BUNDLE_ID" == "com.heungson.fast-image-viewer" ]] || { print -u2 "A different application already exists at $DESTINATION"; exit 1; }
fi
mkdir -p "$HOME/Applications"
ditto "$PROJECT_DIR/build/Fast Image Viewer.app" "$DESTINATION"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DESTINATION"
print -r -- "Installed: $DESTINATION"
