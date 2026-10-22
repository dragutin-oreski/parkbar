#!/bin/zsh
# Creates a self-signed code-signing identity named "ParkBar Dev" in your login keychain, for
#   PARKBAR_SIGN_IDENTITY="ParkBar Dev" scripts/bundle.sh
#
# Why bother: an ad-hoc signature changes with every build, so macOS treats each build as a new app. The
# menu bar app does not mind, but the widget does: macOS may keep showing the old build's widget, or drop
# it from the gallery, until you re-add it. A stable identity keeps every build "the same app".
#
# You only need this for the widget. Run it once; macOS asks for your login password when the key is
# first used. "Allow" lets codesign use it once; "Always Allow" stops the question for this key.
set -euo pipefail

NAME="${1:-ParkBar Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "'$NAME' already exists:"
  security find-identity -v -p codesigning | grep "\"$NAME\""
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.conf" <<CONF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CONF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.conf" 2>/dev/null
PASS="$(openssl rand -hex 16)"
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
  -out "$WORK/identity.p12" -passout "pass:$PASS" -legacy 2>/dev/null \
  || openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
       -out "$WORK/identity.p12" -passout "pass:$PASS"

security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo "Created '$NAME'. Build with:"
echo "  PARKBAR_SIGN_IDENTITY=\"$NAME\" scripts/bundle.sh"
