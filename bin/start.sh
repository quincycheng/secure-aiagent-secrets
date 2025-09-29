#!/bin/bash

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SCRIPT_SOURCE" ]; do
  SCRIPT_DIR="$( cd -P "$( dirname "$SCRIPT_SOURCE" )" >/dev/null 2>&1 && pwd )"
  SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
  [[ "$SCRIPT_SOURCE" != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR/$SCRIPT_SOURCE"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SCRIPT_SOURCE" )" >/dev/null 2>&1 && pwd )"
PROJECT_ROOT="$( dirname "$SCRIPT_DIR" )"
BIN_DIR="${PROJECT_ROOT}/bin"

${BIN_DIR}/01-preparation.sh && \
${BIN_DIR}/02-start-services.sh  && \
${BIN_DIR}/03-generate-jwks.sh  && \
${BIN_DIR}/04-import-n8n-workflow.sh  