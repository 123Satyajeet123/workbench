#!/bin/sh
# Installs the native host the Workbench browser extension calls, and registers it for Brave and Chrome. Then load
# the Extension folder once: brave://extensions (or chrome://extensions) › Developer mode › Load unpacked.
set -e
root="$(cd "$(dirname "$0")/.." && pwd)"
support="$HOME/Library/Application Support"
bin="$support/Workbench/bin"
cd "$root/Packages/WorkbenchCore"
swift build -c release --product workbench-pages >/dev/null
mkdir -p "$bin"
cp .build/release/workbench-pages "$bin/workbench-pages"
if security find-identity -p codesigning | grep -q "Workbench Local Signing"; then
    codesign --force --sign "Workbench Local Signing" "$bin/workbench-pages"
fi
id=$(python3 -c "
import base64, hashlib, json, sys
key = json.load(open(sys.argv[1]))['key']
digest = hashlib.sha256(base64.b64decode(key)).hexdigest()[:32]
print(''.join(chr(ord('a') + int(c, 16)) for c in digest))" "$root/Extension/manifest.json")
for browser in "BraveSoftware/Brave-Browser" "Google/Chrome"; do
    [ -d "$support/$browser" ] || continue
    mkdir -p "$support/$browser/NativeMessagingHosts"
    cat > "$support/$browser/NativeMessagingHosts/com.hizen.workbench.pages.json" <<JSON
{
  "name": "com.hizen.workbench.pages",
  "description": "Workbench: keeps the text you see on a page when your capture policy allows",
  "path": "$bin/workbench-pages",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$id/"]
}
JSON
    echo "Registered for $browser (extension id $id)"
done
echo "Next: load $root/Extension in your browser's extensions page (Developer mode › Load unpacked)."
