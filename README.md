# n8n-conjur-protectai-local_llm
Securing local AI Agent & LLM with CyberArk Conjur & LLM Guard from ProtectAI | Palo Alto Networks

# Tools
## LLM Guard
https://github.com/protectai/llm-guard
LLM Guard by Protect AI is a comprehensive tool designed to fortify the security of Large Language Models (LLMs).

## CyberArk Conjur OSS
https://www.conjur.org/
A seamless open source interface to securely authenticate, control and audit non-human access across tools, applications, containers and cloud environments via robust secrets management.

## n8n 
https://github.com/n8n-io/n8n
n8n is a workflow automation platform that gives technical teams the flexibility of code with the speed of no-code. With 400+ integrations, native AI capabilities, and a fair-code license, n8n lets you build powerful automations while maintaining full control over your data and deployments.

## Ollama
https://github.com/ollama/ollama
Get up and running with large language models.





## Procedure

### 1. Setup Servers
#### Step 1: Get all files

#### Step 2: Pull the images

`docker compose pull`

#### Step 3. Master Key

`printf "CONJUR_DATA_KEY=%s\n" "$(docker compose run --no-deps --rm conjur data-key generate | tail -n 1 | tr -d '\r')" > conjur.env && chmod 600 conjur.env`

#### Up!
`docker compose up`

#### Optional - n8n community license



### Create Credentials

### Load Conjur Policy


### Add database user and secure the password
```
PW="$(openssl rand -base64 32)" && \
psql -v ON_ERROR_STOP=1 -c "DO \$\$BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='demo_user') THEN CREATE ROLE demo_user LOGIN SUPERUSER PASSWORD '$PW'; ELSE ALTER ROLE demo_user WITH LOGIN SUPERUSER PASSWORD '$PW'; END IF; END\$\$;" && \
conjur variable values add 'data/n8n/demo/db-password' "$PW"
```

