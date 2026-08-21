#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build/Awake.app/Contents/MacOS
swiftc -O -o build/Awake.app/Contents/MacOS/Awake main.swift \
    -framework AppKit -framework IOKit -framework ServiceManagement -framework UserNotifications
cp Info.plist build/Awake.app/Contents/Info.plist
mkdir -p build/Awake.app/Contents/Resources
cp AppIcon.icns build/Awake.app/Contents/Resources/AppIcon.icns
xattr -cr build/Awake.app
codesign --force --sign - build/Awake.app

echo "Built: $(pwd)/build/Awake.app"
