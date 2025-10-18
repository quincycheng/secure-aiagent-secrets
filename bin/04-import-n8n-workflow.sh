#!/usr/bin/env bash

# This handles symlinks so we get the real script location.
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SCRIPT_SOURCE" ]; do
  SCRIPT_DIR="$( cd -P "$( dirname "$SCRIPT_SOURCE" )" >/dev/null 2>&1 && pwd )"
  SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
  [[ "$SCRIPT_SOURCE" != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR/$SCRIPT_SOURCE"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SCRIPT_SOURCE" )" >/dev/null 2>&1 && pwd )"
PROJECT_ROOT="$( dirname "$SCRIPT_DIR" )"
DATA_DIR="${PROJECT_ROOT}/data"

DB_ENV_FILE="${DATA_DIR}/.env.postgres"
N8N_ENV_FILE="${DATA_DIR}/.env.n8n"
CONJUR_ENV_FILE="${DATA_DIR}/.env.conjur"
LITELLM_ENV_FILE="${DATA_DIR}/.env.litellm"

IMPORT_FOLDER="/home/node/import"

#######################################
# Import Workflow with JWKS embedded
#######################################
jwks_file="data/conjur/jwt/jwks.json"
template_file="src/n8n/n8n-jwt-sync.json"
temp_workflow_file="temp_n8n-jwt-sync.json"

# Read JWKS content and escape double quotes and backslashes
escaped_jwks=$(cat "$jwks_file" | tr -d '\n' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')

# Replace <JWKS> in template and write to output
while IFS= read -r line; do
    echo "${line//<JWKS>/\"$escaped_jwks\"}"
done < "$template_file" > "$DATA_DIR/n8n/$temp_workflow_file"

# Import the workflow using docker compose
docker compose --env-file ${DB_ENV_FILE} --env-file ${N8N_ENV_FILE}  --env-file ${CONJUR_ENV_FILE} exec n8n \
  n8n import:workflow --input "$IMPORT_FOLDER/$temp_workflow_file"

# Activate all workflows
docker compose --env-file ${DB_ENV_FILE} --env-file ${N8N_ENV_FILE}  --env-file ${CONJUR_ENV_FILE} exec n8n \
  n8n update:workflow --all --active=true

############################################
# Import Credentials for Conjur JWT Authn
############################################

# Define paths to key files
PRIVATE_KEY_FILE="data/conjur/jwt/private_key.pem"
PUBLIC_KEY_FILE="data/conjur/jwt/public_key.pem"
temp_cred_file="temp_conjur_cred.json"

# Read key contents
PRIVATE_KEY=$(tr '\n' ' ' < "$PRIVATE_KEY_FILE")
PUBLIC_KEY=$(tr '\n' ' ' < "$PUBLIC_KEY_FILE")

source "${LITELLM_ENV_FILE}"
source "${DB_ENV_FILE}"

# Write JSON content to temp file
cat > "$DATA_DIR/n8n/$temp_cred_file" <<EOF
[
  {
    "name": "Conjur JWT Authn",
    "id": "zJJkw1J5y0b7nJDp",
    "createdAt": "2025-10-17T09:55:56.290Z",
    "updatedAt": "2025-10-17T10:00:36.538Z",
    "data": {
      "keyType": "pemKey",
      "privateKey": "$PRIVATE_KEY",
      "publicKey": "$PUBLIC_KEY",
      "algorithm": "RS256"
    },
    "type": "jwtAuth",
    "isManaged": false
  },
  {
    "createdAt": "2025-10-18T06:58:01.781Z",
    "updatedAt": "2025-10-18T06:58:01.778Z",
    "id": "YKDu3Ob9ZRjfV91G",
    "name": "LiteLLM with LLM Guard account",
    "data": {
      "apiKey": "$LITELLM_MASTER_KEY",
      "url": "http://host.docker.internal:4000"
    },
    "type": "openAiApi",
    "isManaged": false
  },
  {
    "createdAt": "2025-10-18T07:02:39.673Z",
    "updatedAt": "2025-10-18T07:03:19.218Z",
    "id": "UchuEkNQlMJuSom2",
    "name": "Postgres account",
    "data": {
      "host": "host.docker.internal",
      "database": "$POSTGRES_CHAT_MEMORY_DB",
      "user": "$POSTGRES_USER",
      "password": "$POSTGRES_PASSWORD"
    },
    "type": "postgres",
    "isManaged": false
  }
]
EOF

# Run the docker compose command
docker compose \
  --env-file "${DB_ENV_FILE}" \
  --env-file "${N8N_ENV_FILE}" \
  --env-file "${CONJUR_ENV_FILE}" \
  exec n8n \
  n8n import:credentials --input="$IMPORT_FOLDER/$temp_cred_file"


################################################################
# Restart n8n to apply changes and wait for it to be ready
################################################################

# Restart n8n
docker compose --env-file ${DB_ENV_FILE} --env-file ${N8N_ENV_FILE}  --env-file ${CONJUR_ENV_FILE} --env-file ${LITELLM_ENV_FILE} restart n8n

# Configuration
URL="http://localhost:5678/healthz" # The URL to check
EXPECTED_HTTP_CODE="200"          # The expected HTTP status code
INTERVAL_SECONDS=5                # How long to wait between checks
MAX_ATTEMPTS=60                   # Maximum number of attempts (e.g., 60 * 5 seconds = 5 minutes timeout)

echo "Waiting for $URL to return $EXPECTED_HTTP_CODE..."

attempt_count=0
while true; do
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "$URL")

    if [ "$http_code" == "$EXPECTED_HTTP_CODE" ]; then
        echo "$URL is ready (HTTP $http_code)."
        break
    else
        echo "Attempt $((attempt_count + 1)): $URL returned HTTP $http_code. Retrying in $INTERVAL_SECONDS seconds..."
        sleep "$INTERVAL_SECONDS"
        attempt_count=$((attempt_count + 1))

        if [ "$attempt_count" -ge "$MAX_ATTEMPTS" ]; then
            echo "Error: Maximum attempts reached. $URL did not become ready."
            exit 1
        fi
    fi
done

echo "n8n is ready."
# Add any further commands here that should run after the service is ready