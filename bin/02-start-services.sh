#!/usr/bin/env bash
# Purpose: Start the services
# Location: keep this script in ./bin/
# Platform: Ubuntu 22.04+ (Jetson-friendly)

#set -euo pipefail

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
CONJUR_SRC_FOLDER="${PROJECT_ROOT}/src/conjur"

conjur_check_service() {
 yellow "Check if Conjur is up..."
  URL="http://localhost:8080"
  while true; do
      STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$URL")

      if [ "$STATUS" -eq 200 ]; then
          green "Conjur is up (HTTP 200)."
          break
      else
          yellow "Wait 5 seconds for Conjur..."
          sleep 5s
      fi
  done
}

conjur_create_new_account() {

  yellow "Creating new account..."
  mkdir -p "${DATA_DIR}/conjur"
  CONJUR_ADMIN_DATA="${DATA_DIR}/conjur/admin_data"

  if [ ! -f "$CONJUR_ADMIN_DATA" ]; then
    docker compose --env-file ${DB_ENV_FILE} --env-file ${N8N_ENV_FILE}  --env-file ${CONJUR_ENV_FILE} exec conjur conjurctl account create conjur > "${CONJUR_ADMIN_DATA}" || true
  else
    yellow "Conjur Admin Data already exists"
  fi 
}

conjur_load_policies() {
  conjur whoami

  conjur policy load -b root -f "${CONJUR_SRC_FOLDER}/conjur_policy_data.yaml"
  conjur policy load -b root -f "${CONJUR_SRC_FOLDER}/conjur_policy_conjur.yaml"


  yellow authn-jwt-hosts.yaml
  conjur policy load -b data -f "${CONJUR_SRC_FOLDER}/authn-jwt-hosts.yaml"

  yellow authn-jwt-grant.yaml
  conjur policy load -b conjur/authn-jwt/n8n -f "${CONJUR_SRC_FOLDER}/authn-jwt-grant.yaml"

  yellow secret-access.yaml
  conjur policy load -b data -f "${CONJUR_SRC_FOLDER}/secret-access.yaml"


  conjur variable set -i conjur/authn-jwt/n8n/audience -v "http://$(hostname -f):5678"
  conjur variable set -i conjur/authn-jwt/n8n/identity-path -v "data/n8n/jwt-apps"
  conjur variable set -i conjur/authn-jwt/n8n/issuer -v "http://$(hostname -f):5678"
  conjur variable set -i conjur/authn-jwt/n8n/jwks-uri -v "http://host.docker.internal:5678/webhook/jwks"
  conjur variable set -i conjur/authn-jwt/n8n/token-app-property -v "subject"
}

conjur_logout() {
  conjur logout
}
conjur_login() {
 yellow "Extract the API key for admin..."

  # Extract the API key for admin
  CONJUR_ADMIN_APIKEY=$(grep "^API key for admin:" "${CONJUR_ADMIN_DATA}" | sed 's/^API key for admin: //')
  
  # Output the result
  yellow "Extracted API key: ${CONJUR_ADMIN_APIKEY}"

  yellow "Logging into Conjur..."
  conjur init -f -i -a conjur -u http://$(hostname -f):8080

  conjur login -i admin -p "${CONJUR_ADMIN_APIKEY}"
  green "Logged in successfully"
}

main() {
  yellow "Project root: ${PROJECT_ROOT}"

  ##################################
  # Start all services
  ##################################

  yellow "Starting Services..."
  docker compose --env-file ${DB_ENV_FILE} --env-file ${N8N_ENV_FILE}  --env-file ${CONJUR_ENV_FILE} up -d 


  ##################################
  # Conjur
  ##################################
  conjur_check_service
  conjur_create_new_account
  conjur_login
  conjur_load_policies
  #conjur_logout

  green "Services are ready!"

}

main "$@"