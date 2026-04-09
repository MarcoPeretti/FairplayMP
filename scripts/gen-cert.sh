#!/usr/bin/env bash
# Regenerate the FairplayMP SSL keystore and truststore.
# Outputs: runtime/src/certificate/ks  (keystore)
#          runtime/src/certificate/ts  (truststore)
# Password for both: 123456  Alias: a

set -euo pipefail

CERT_DIR="$(cd "$(dirname "$0")/../runtime/src/certificate" && pwd)"
PASS=123456
ALIAS=a
TMPDER="$(mktemp /tmp/fairplay-cert-XXXXXX)"

rm -f "$CERT_DIR/ks" "$CERT_DIR/ts"
echo "Generating keypair in $CERT_DIR/ks ..."
keytool -genkeypair \
  -alias "$ALIAS" \
  -keyalg RSA -keysize 2048 \
  -validity 3650 \
  -dname "CN=Unknown, OU=Unknown, O=Unknown, L=Unknown, ST=Unknown, C=Unknown" \
  -storetype JKS \
  -keystore "$CERT_DIR/ks" \
  -storepass "$PASS" \
  -keypass "$PASS"

echo "Exporting certificate ..."
keytool -exportcert \
  -alias "$ALIAS" \
  -keystore "$CERT_DIR/ks" \
  -storepass "$PASS" \
  -file "$TMPDER"

echo "Building truststore $CERT_DIR/ts ..."
keytool -importcert \
  -alias "$ALIAS" \
  -file "$TMPDER" \
  -storetype JKS \
  -keystore "$CERT_DIR/ts" \
  -storepass "$PASS" \
  -noprompt

rm "$TMPDER"
echo "Done. ks and ts written to $CERT_DIR/"
