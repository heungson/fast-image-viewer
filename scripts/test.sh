#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
mkdir -p "$PROJECT_DIR/build"
PORT_FILE=$(mktemp -t fast-image-viewer-port)
rm "$PORT_FILE"
python3 "$PROJECT_DIR/scripts/test_server.py" --port-file "$PORT_FILE" --fixture "$PROJECT_DIR/build/Test image.png" &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true; rm -f "$PORT_FILE"' EXIT
for attempt in {1..100}; do
  [[ -s "$PORT_FILE" ]] && break
  sleep 0.05
done
export TEST_SERVER_URL="http://127.0.0.1:$(cat "$PORT_FILE")"
xcrun swiftc -swift-version 5 -framework AppKit -framework ImageIO \
  "$PROJECT_DIR/Sources/ImageSource.swift" "$PROJECT_DIR/Sources/ImageLoader.swift" \
  "$PROJECT_DIR/Tests/main.swift" -o "$PROJECT_DIR/build/viewer-tests"
"$PROJECT_DIR/build/viewer-tests"
