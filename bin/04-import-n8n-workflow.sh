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

#docker compose --env-file ${DB_ENV_FILE} --env-file ${N8N_ENV_FILE}  --env-file ${CONJUR_ENV_FILE} exec n8n \
#  n8n import:workflow --help

#docker compose --env-file ${DB_ENV_FILE} --env-file ${N8N_ENV_FILE}  --env-file ${CONJUR_ENV_FILE} exec n8n \
#  n8n import:credentials --help

#docker compose --env-file ${DB_ENV_FILE} --env-file ${N8N_ENV_FILE}  --env-file ${CONJUR_ENV_FILE} exec n8n \
#  n8n  --help

#docker compose --env-file ${DB_ENV_FILE} --env-file ${N8N_ENV_FILE}  --env-file ${CONJUR_ENV_FILE} exec n8n \
#  n8n import:credentials --input /home/node/import/n8n_jwt_cred.json

docker compose --env-file ${DB_ENV_FILE} --env-file ${N8N_ENV_FILE}  --env-file ${CONJUR_ENV_FILE} exec n8n \
  n8n import:workflow --input /home/node/import/n8n_jwt_sync.json  