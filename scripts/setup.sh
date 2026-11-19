#!/bin/zsh
# One-time setup on a new Mac: checks the tools Workbench needs, then makes the local code-signing identity that lets
# macOS keep the app's Accessibility and microphone permissions across updates. Run it once, then scripts/install.sh.
set -euo pipefail
IDENTITY="${WORKBENCH_IDENTITY:-Workbench Local Signing}"
KEYCHAIN="${WORKBENCH_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

fail() { print -u2 "setup: $1"; exit 1 }

[[ "$(sw_vers -productVersion)" == (15|26|27).* ]] || fail "Workbench needs macOS 15 or later."
xcodebuild -version >/dev/null 2>&1 || fail "Install Xcode from the App Store, open it once, then run this again."
for tool in claude codex; do
  if [[ -x ~/.local/bin/$tool || -x /opt/homebrew/bin/$tool || -x /usr/local/bin/$tool ]] || command -v $tool >/dev/null; then
    print "found $tool"
  else
    print "not found: $tool (Workbench reads with claude or codex; install one and sign in)"
  fi
done

if security find-identity -v -p codesigning "$KEYCHAIN" | grep -q "\"$IDENTITY\""; then
  print "signing identity \"$IDENTITY\" is ready. Next: scripts/install.sh"
  exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
if security find-certificate -c "$IDENTITY" -p "$KEYCHAIN" > "$WORK/cert.pem" 2>/dev/null; then
  print "the identity exists but is not trusted yet. macOS now asks for your password to trust it for code signing."
  security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"
  print "trusted \"$IDENTITY\". Next: scripts/install.sh"
  exit 0
fi

cat > "$WORK/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF
PASS=$(/usr/bin/openssl rand -hex 16)
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/cert.cnf" \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -out "$WORK/identity.p12" \
  -passout "pass:$PASS" 2>/dev/null
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null
print "macOS now asks for your password to trust the identity for code signing."
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"
print "made signing identity \"$IDENTITY\". Next: scripts/install.sh"
