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





## Setup
1. Execute `bin/start.sh` to pull and create containers
2. Access n8n web ui at http://<FQDN>:5678, e.g. http://quincy-jetson.local:5678
3. Answer the n8n popup to create an user account for first time access
4. Create a JWT Credential at n8n by copying the values from the generated files accordingly:
- Key Type: *PEM Key*
- Private Key: file content from *data/conjur/jwt/private_key.pem*
- Private Key: file content from *data/conjur/jwt/private_key.pem*
- Algorithm: *RS256*
5. Open the imported workflow named *n8n-jwt-sync* 
6. Update the credential of "Sign JWT Token" created in previous step
7. Update Webhook value with the content from the file *data/conjur/jwt/jwk.json*.   Be sure it is set as *production*
8. Click *Execute Workflow* and check if n8n & conjur integeation is successful 


## Clean-up
Execute `bin/99-cleanup.sh`

## Access
visit port 5678
setup owner account

new crednetial
key type: PEM KEy
Update private key and public key
Algorithm
RS256
save it

Workflow

webhook
Update jwks
change to production


payload of jwt token
update aud, iss

Sign JWT Token
Select cred

Save

Activiate it

New workflow
execute sub workflow
select n8n-jwt-sync
secrets_id
data/n8n/demo/host


### 1. Setup Servers
#### Step 1: Get all files

#### Step 2: Pull the images

`docker compose pull`

#### Step 3. Master Key

`touch data/.env.conjur && printf "CONJUR_DATA_KEY=%s\n" "$(docker compose run --no-deps --rm conjur data-key generate | tail -n 1 | tr -d '\r')" > data/.env.conjur && chmod 600 data/.env.conjur`

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

