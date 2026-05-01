#!/bin/bash
# Create a self-signed code-signing certificate so KeyCheck rebuilds keep the
# same identity, so the Input Monitoring permission stops resetting.
#
# Fully automated. No Keychain Access GUI required.

set -e

cd "$(dirname "$0")"

CERT_NAME="KeyCheck Local Signer"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo "✓ Certificate '$CERT_NAME' already exists in your login keychain."
    echo "  Run ./build.sh to use it."
    exit 0
fi

echo "Creating self-signed code-signing certificate: $CERT_NAME"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

cat > "$TMPDIR/openssl.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
[dn]
CN = $CERT_NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 \
    -newkey rsa:2048 \
    -keyout "$TMPDIR/key.pem" \
    -out "$TMPDIR/cert.pem" \
    -days 3650 \
    -nodes \
    -config "$TMPDIR/openssl.cnf" \
    -extensions ext 2>/dev/null

P12_PASS="keycheck-tmp-$$"

# -macalg SHA1 + legacy PBE so macOS's libsecurity (LibreSSL-era) can read it.
openssl pkcs12 -export \
    -out "$TMPDIR/cert.p12" \
    -inkey "$TMPDIR/key.pem" \
    -in "$TMPDIR/cert.pem" \
    -password "pass:$P12_PASS" \
    -macalg SHA1 \
    -keypbe PBE-SHA1-3DES \
    -certpbe PBE-SHA1-3DES \
    -name "$CERT_NAME" 2>/dev/null

# Import. -A allows any tool (codesign etc.) to use the key without prompting.
security import "$TMPDIR/cert.p12" \
    -k "$KEYCHAIN" \
    -P "$P12_PASS" \
    -A \
    >/dev/null

# Try to grant codesign access without password prompt.
# If this prompts for your login password, that's fine — enter it and continue.
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s -k "" \
    "$KEYCHAIN" >/dev/null 2>&1 || true

if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo ""
    echo "✓ Done. Now run:"
    echo "    ./build.sh"
    echo ""
    echo "After this, every rebuild will use the SAME signature, so the"
    echo "Input Monitoring permission will only need to be granted once."
else
    echo "✗ Cert was created but not visible to codesign. Check Keychain Access."
    exit 1
fi
