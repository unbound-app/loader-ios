#!/bin/sh

set -eu

if [ "${DEBUG:-0}" = "1" ]; then
    printf '%s\n' 0
    exit 0
fi

key_file=$(mktemp)
expected_key=$(mktemp)
actual_key=$(mktemp)
trap 'rm -f "$key_file" "$expected_key" "$actual_key"' EXIT

if [ -n "${ATTESTATION_PK:-}" ]; then
    printf '%s' "$ATTESTATION_PK" | tr -d '\r' > "$key_file"
elif [ -f "attestation_private.pem" ]; then
    cp attestation_private.pem "$key_file"
else
    printf '%s\n' 0
    exit 0
fi

if ! openssl ec -in "$key_file" -check -noout >/dev/null 2>&1 || \
   ! openssl base64 -d -A -in tools/attestation_public_key.b64 -out "$expected_key" 2>/dev/null || \
   ! openssl ec -in "$key_file" -pubout -outform DER -out "$actual_key" 2>/dev/null; then
    printf '%s\n' 0
    exit 0
fi

if cmp -s "$expected_key" "$actual_key"; then
    printf '%s\n' 1
else
    printf '%s\n' 0
fi
