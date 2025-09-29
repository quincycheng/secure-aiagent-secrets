#!/usr/bin/env bash

# Set output directory
OUTPUT_DIR="data/conjur/jwt"
mkdir -p "$OUTPUT_DIR"

# Generate RSA private key (PEM format)
openssl genpkey -algorithm RSA -out "$OUTPUT_DIR/private_key.pem" -pkeyopt rsa_keygen_bits:2048

# Extract public key (PEM format)
openssl rsa -pubout -in "$OUTPUT_DIR/private_key.pem" -out "$OUTPUT_DIR/public_key.pem"

# Generate JWKS using Python
python3 - <<EOF
import base64, json
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend

with open("$OUTPUT_DIR/public_key.pem", "rb") as f:
    pub_key = serialization.load_pem_public_key(f.read(), backend=default_backend())
    numbers = pub_key.public_numbers()

    n = base64.urlsafe_b64encode(numbers.n.to_bytes((numbers.n.bit_length() + 7) // 8, 'big')).rstrip(b'=').decode('utf-8')
    e = base64.urlsafe_b64encode(numbers.e.to_bytes((numbers.e.bit_length() + 7) // 8, 'big')).rstrip(b'=').decode('utf-8')

jwks = {
    "keys": [
        {
            "kty": "RSA",
            "use": "sig",
            "alg": "RS256",
            "kid": "conjur-jwt-key",
            "n": n,
            "e": e
        }
    ]
}

with open("$OUTPUT_DIR/jwks.json", "w") as f:
    json.dump(jwks, f, indent=2)
EOF

echo "✅ RSA key pair and JWKS have been generated in $OUTPUT_DIR"


