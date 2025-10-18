#!/usr/bin/env bash
# Purpose: Check required commands and generate a Postgres password in data/.env.postgres
# Location: keep this script in ./bin/; it will always write to ../data/.env.postgres
# Platform: Ubuntu 22.04+ (Jetson-friendly)

set -euo pipefail

# ---------- colors ----------
red()   { printf "\033[31m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
yellow(){ printf "\033[33m%s\033[0m\n" "$*"; }

# ---------- resolve project paths relative to this script ----------
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
LLMGUARD_ENV_FILE="${DATA_DIR}/.env.llmguard"

PASS_LEN="${PG_PASS_LEN:-32}"

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    red "✗ Missing required command: $cmd"
    return 1
  fi
  green "✓ Found: $cmd"
}

check_docker_compose() {
  if docker compose version >/dev/null 2>&1; then
    green "✓ Found: docker compose (plugin)"
    return 0
  fi
  if command -v docker-compose >/dev/null 2>&1; then
    green "✓ Found: docker-compose (standalone)"
    return 0
  fi
  red "✗ Missing Docker Compose (neither 'docker compose' nor 'docker-compose' found)"
  return 1
}

generate_password() {
  # Prefer openssl; fallback to /dev/urandom. Limit to safe env-friendly characters.
  local pw
  if command -v openssl >/dev/null 2>&1; then
    pw="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9!@#%+=:_-' | head -c "$PASS_LEN")"
  else
    pw="$(LC_ALL=C tr -dc 'A-Za-z0-9!@#%+=:_-' < /dev/urandom | head -c "$PASS_LEN")"
  fi
  [ -n "${pw:-}" ] || { red "Failed to generate password"; exit 1; }
  printf "%s" "$pw"
}

generate_conjur_master_key() {

  touch ${DATA_DIR}/.env.conjur && \
  printf "CONJUR_DATA_KEY=%s\n" "$(docker compose  --env-file ${DB_ENV_FILE} --env-file ${N8N_ENV_FILE}  --env-file ${CONJUR_ENV_FILE} run --no-deps --rm conjur data-key generate \
  | tail -n 1 | tr -d '\r')" > \
  ${DATA_DIR}/.env.conjur && \
  chmod 600 ${DATA_DIR}/.env.conjur
}

main() {
  yellow "Project root: ${PROJECT_ROOT}"
  yellow "Target env file: ${DB_ENV_FILE}"


  #################
  # prerequisites
  #################
  yellow "Checking prerequisites..."
  require_cmd docker
  check_docker_compose
  require_cmd tail
  require_cmd touch
  require_cmd sed
  require_cmd ollama
  require_cmd conjur
  require_cmd python3
  require_cmd openssl

  yellow "Ensuring data directory exists..."
  mkdir -p "${DATA_DIR}"
  mkdir -p "${DATA_DIR}/postgres-data"
  mkdir -p "${DATA_DIR}/n8n"

  #################
  # n8n
  #################
  yellow "Writing config to ${N8N_ENV_FILE} (chmod 600)..."
  umask 177  # ensures files are created as 600 by default
  touch "${N8N_ENV_FILE}"
  chmod 600 "${N8N_ENV_FILE}"

  if grep -q '^DOMAIN_NAME=' "${N8N_ENV_FILE}"; then
    # Update existing line (in place)
    sed -i "s/^DOMAIN_NAME=.*/DOMAIN_NAME=$(hostname -f)/" "${N8N_ENV_FILE}"
  else
    # Append new line (ensure newline at end)
    #{ tail -c1 "${N8N_ENV_FILE}" | read -r _ || echo >> "${N8N_ENV_FILE}"; } 2>/dev/null || true
    printf "DOMAIN_NAME=%s\n" "$(hostname -f)" >> "${N8N_ENV_FILE}"
  fi

  grep -q "^SUBDOMAIN=" "$N8N_ENV_FILE" || echo "SUBDOMAIN=" >> "$N8N_ENV_FILE"
  grep -q "^GENERIC_TIMEZONE=" "$N8N_ENV_FILE" || echo "GENERIC_TIMEZONE=$(cat /etc/timezone)" >> "$N8N_ENV_FILE"
  grep -q "^SSL_EMAIL=" "$N8N_ENV_FILE" || echo "SSL_EMAIL=" >> "$N8N_ENV_FILE"
  green "✓ Config written to ${N8N_ENV_FILE}."

  #################
  # Postgres
  #################
  yellow "Generating random Postgres password (length: ${PASS_LEN})..."
  PW="$(generate_password)"
  POSTGRES_NON_ROOT_PASSWORD="$(generate_password)"
  POSTGRES_NON_ROOT_USER="n8n_service"

  POSTGRES_LITELLM_PASSWORD="$(generate_password)"
  POSTGRES_LITELLM_USER="litellm_service"
  POSTGRES_LITELLM_DB="litellm"

  POSTGRES_CHAT_MEMORY_DB="n8n_chat_memory"

  yellow "Writing password to ${DB_ENV_FILE} (chmod 600)..."
  umask 177  # ensures files are created as 600 by default
  touch "${DB_ENV_FILE}"
  chmod 600 "${DB_ENV_FILE}"
  POSTGRES_USER=n8n_user
  POSTGRES_DB=n8n

  # POSTGRES_LITELLM_PASSWORD
  if grep -q '^POSTGRES_LITELLM_PASSWORD=' "${DB_ENV_FILE}"; then
    # Update existing line (in place)
    sed -i "s/^POSTGRES_LITELLM_PASSWORD=.*/POSTGRES_LITELLM_PASSWORD=${POSTGRES_LITELLM_PASSWORD}/" "${DB_ENV_FILE}"
  else
    # Append new line (ensure newline at end)
    #{ tail -c1 "${DB_ENV_FILE}" | read -r _ || echo >> "${DB_ENV_FILE}"; } 2>/dev/null || true
    printf "POSTGRES_LITELLM_PASSWORD=%s\n" "${POSTGRES_LITELLM_PASSWORD}" >> "${DB_ENV_FILE}"
  fi

  # POSTGRES_LITELLM_USER
  if grep -q '^POSTGRES_LITELLM_USER=' "${DB_ENV_FILE}"; then
    # Update existing line (in place)
    sed -i "s/^POSTGRES_LITELLM_USER=.*/POSTGRES_LITELLM_USER=${POSTGRES_LITELLM_USER}/" "${DB_ENV_FILE}"
  else
    # Append new line (ensure newline at end)
    printf "POSTGRES_LITELLM_USER=%s\n" "${POSTGRES_LITELLM_USER}" >> "${DB_ENV_FILE}"
  fi

  # POSTGRES_LITELLM_DB
  if grep -q '^POSTGRES_LITELLM_DB=' "${DB_ENV_FILE}"; then
    # Update existing line (in place)
    sed -i "s/^POSTGRES_LITELLM_DB=.*/POSTGRES_LITELLM_DB=${POSTGRES_LITELLM_DB}/" "${DB_ENV_FILE}"
  else
    # Append new line (ensure newline at end)
    printf "POSTGRES_LITELLM_DB=%s\n" "${POSTGRES_LITELLM_DB}" >> "${DB_ENV_FILE}"
  fi

  # POSTGRES_CHAT_MEMORY_DB
  if grep -q '^POSTGRES_CHAT_MEMORY_DB=' "${DB_ENV_FILE}"; then
    # Update existing line (in place)
    sed -i "s/^POSTGRES_CHAT_MEMORY_DB=.*/POSTGRES_CHAT_MEMORY_DB=${POSTGRES_CHAT_MEMORY_DB}/" "${DB_ENV_FILE}"
  else
    # Append new line (ensure newline at end)
    printf "POSTGRES_CHAT_MEMORY_DB=%s\n" "${POSTGRES_CHAT_MEMORY_DB}" >> "${DB_ENV_FILE}"
  fi

  # POSTGRES_PASSWORD
  if grep -q '^POSTGRES_PASSWORD=' "${DB_ENV_FILE}"; then
    # Update existing line (in place)
    sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=${PW}/" "${DB_ENV_FILE}"
  else
    # Append new line (ensure newline at end)
    #{ tail -c1 "${DB_ENV_FILE}" | read -r _ || echo >> "${DB_ENV_FILE}"; } 2>/dev/null || true
    printf "POSTGRES_PASSWORD=%s\n" "${PW}" >> "${DB_ENV_FILE}"
  fi

  # POSTGRES_NON_ROOT_USER
  if grep -q '^POSTGRES_NON_ROOT_USER=' "${DB_ENV_FILE}"; then
    # Update existing line (in place)
    sed -i "s/^POSTGRES_NON_ROOT_USER=.*/POSTGRES_NON_ROOT_USER=${POSTGRES_NON_ROOT_USER}/" "${DB_ENV_FILE}"
  else
    # Append new line (ensure newline at end)
    #{ tail -c1 "${DB_ENV_FILE}" | read -r _ || echo >> "${DB_ENV_FILE}"; } 2>/dev/null || true
    printf "POSTGRES_NON_ROOT_USER=%s\n" "${POSTGRES_NON_ROOT_USER}" >> "${DB_ENV_FILE}"
  fi

  # POSTGRES_NON_ROOT_PASSWORD
  if grep -q '^POSTGRES_NON_ROOT_PASSWORD=' "${DB_ENV_FILE}"; then
    # Update existing line (in place)
    sed -i "s/^POSTGRES_NON_ROOT_PASSWORD=.*/POSTGRES_NON_ROOT_PASSWORD=${PW}/" "${DB_ENV_FILE}"
  else
    # Append new line (ensure newline at end)
    #{ tail -c1 "${DB_ENV_FILE}" | read -r _ || echo >> "${DB_ENV_FILE}"; } 2>/dev/null || true
    printf "POSTGRES_NON_ROOT_PASSWORD=%s\n" "${POSTGRES_NON_ROOT_PASSWORD}" >> "${DB_ENV_FILE}"
  fi

  # POSTGRES_DB
  if grep -q '^POSTGRES_DB=' "${DB_ENV_FILE}"; then
    # Update existing line (in place)
    sed -i "s/^POSTGRES_DB=.*/POSTGRES_DB=${POSTGRES_DB}/" "${DB_ENV_FILE}"
  else
    # Append new line (ensure newline at end)
    #{ tail -c1 "${DB_ENV_FILE}" | read -r _ || echo >> "${DB_ENV_FILE}"; } 2>/dev/null || true
    printf "POSTGRES_DB=%s\n" "${POSTGRES_DB}" >> "${DB_ENV_FILE}"
  fi

  # POSTGRES_USER
  if grep -q '^POSTGRES_USER=' "${DB_ENV_FILE}"; then
    # Update existing line (in place)
    sed -i "s/^POSTGRES_USER=.*/POSTGRES_USER=${POSTGRES_USER}/" "${DB_ENV_FILE}"
  else
    # Append new line (ensure newline at end)
    #{ tail -c1 "${DB_ENV_FILE}" | read -r _ || echo >> "${DB_ENV_FILE}"; } 2>/dev/null || true
    printf "POSTGRES_USER=%s\n" "POSTGRES_USER" >> "${DB_ENV_FILE}"
  fi

  green "✓ Password written to ${DB_ENV_FILE} (value redacted)."



  #################
  # LiteLLM
  #################
  yellow "Generating random LiteLLM password (length: ${PASS_LEN})..."
  PW="$(generate_password)"
  LITELLM_MASTER_KEY="sk-$(generate_password)"
  LITELLM_SALT_KEY="sk-$(generate_password)"
  PROXY_ADMIN_ID=admin
  UI_USERNAME=admin
  UI_PASSWORD=${LITELLM_MASTER_KEY}


  yellow "Writing password to ${LITELLM_ENV_FILE} (chmod 600)..."
  umask 177  # ensures files are created as 600 by default
  touch "${LITELLM_ENV_FILE}"
  chmod 600 "${LITELLM_ENV_FILE}"

  # LITELLM_MASTER_KEY
  if grep -q '^LITELLM_MASTER_KEY=' "${LITELLM_ENV_FILE}"; then
    # Update existing line (in place)
    sed -i "s/^LITELLM_MASTER_KEY=.*/LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}/" "${LITELLM_ENV_FILE}"
  else
    # Append new line (ensure newline at end)
    printf "LITELLM_MASTER_KEY=%s\n" "${LITELLM_MASTER_KEY}" >> "${LITELLM_ENV_FILE}"
  fi

  # LITELLM_SALT_KEY
  if grep -q '^LITELLM_SALT_KEY=' "${LITELLM_ENV_FILE}"; then
    # Update existing line (in place)
    sed -i "s/^LITELLM_SALT_KEY=.*/LITELLM_SALT_KEY=${LITELLM_SALT_KEY}/" "${LITELLM_ENV_FILE}"
  else
    # Append new line (ensure newline at end)
    printf "LITELLM_SALT_KEY=%s\n" "${LITELLM_SALT_KEY}" >> "${LITELLM_ENV_FILE}"
  fi


  # PROXY_ADMIN_ID
  if grep -q '^PROXY_ADMIN_ID=' "${LITELLM_ENV_FILE}"; then
    # Update existing line (in place)
    sed -i "s/^PROXY_ADMIN_ID=.*/PROXY_ADMIN_ID=${PROXY_ADMIN_ID}/" "${LITELLM_ENV_FILE}"
  else
    # Append new line (ensure newline at end)
    printf "PROXY_ADMIN_ID=%s\n" "${PROXY_ADMIN_ID}" >> "${LITELLM_ENV_FILE}"
  fi

  # UI_USERNAME
  if grep -q '^UI_USERNAME=' "${LITELLM_ENV_FILE}"; then
    # Update existing line (in place)
    sed -i "s/^UI_USERNAME=.*/UI_USERNAME=${UI_USERNAME}/" "${LITELLM_ENV_FILE}"
  else
    # Append new line (ensure newline at end)
    printf "UI_USERNAME=%s\n" "${UI_USERNAME}" >> "${LITELLM_ENV_FILE}"
  fi
  # UI_PASSWORD
  if grep -q '^UI_PASSWORD=' "${LITELLM_ENV_FILE}"; then
    # Update existing line (in place)
    sed -i "s/^UI_PASSWORD=.*/UI_PASSWORD=${UI_PASSWORD}/" "${LITELLM_ENV_FILE}"
  else
    # Append new line (ensure newline at end)
    printf "UI_PASSWORD=%s\n" "${UI_PASSWORD}" >> "${LITELLM_ENV_FILE}"
  fi

  #################
  # Conjur
  #################
  yellow "Generating Conjur Master Key..."
  generate_conjur_master_key

  yellow "Pull Docker Images..."
  docker compose --env-file ${DB_ENV_FILE} --env-file ${N8N_ENV_FILE}  --env-file ${CONJUR_ENV_FILE}  pull

  green "Preparation Completed!"

}

main "$@"