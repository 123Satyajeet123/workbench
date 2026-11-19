#!/bin/zsh
# Build Workbench, install one copy in ~/Applications signed with the local identity, relaunch it in the background.
# The identity keeps the Accessibility grant across rebuilds (an ad hoc signature changes with every build).
set -euo pipefail
REPO=${0:A:h:h}
IDENTITY="Workbench Local Signing"
TARGET=~/Applications/Workbench.app

security find-identity -v -p codesigning | grep -q "\"$IDENTITY\"" \
  || { print -u2 "install: no trusted \"$IDENTITY\" identity. Run scripts/setup.sh first."; exit 1 }
mkdir -p ~/Applications

xcodebuild -project $REPO/Workbench.xcodeproj -scheme Workbench -configuration Release build -quiet
BUILT=$(xcodebuild -project $REPO/Workbench.xcodeproj -scheme Workbench -configuration Release -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2}')/Workbench.app

pkill -f "Workbench.app/Contents/MacOS/Workbench" || true
rm -rf $TARGET
cp -R $BUILT $TARGET
rm -rf $BUILT
# Inside out: nested code first, then the app with its entitlements.
find $TARGET/Contents -type f \( -name "*.dylib" -o -perm -u+x \) ! -path "*/MacOS/Workbench" -print0 \
  | xargs -0 -I{} sh -c 'file -b "{}" | grep -q Mach-O && codesign --force --sign "'"$IDENTITY"'" "{}"'
find $TARGET/Contents -name "*.framework" -prune -print0 | xargs -0 -I{} codesign --force --sign "$IDENTITY" "{}"
codesign --force --sign "$IDENTITY" --entitlements $REPO/Workbench.entitlements $TARGET
codesign --verify --strict $TARGET
codesign -d -r- $TARGET 2>&1 | tail -1
open -g $TARGET
