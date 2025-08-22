# n8n-conjur-jwt-demo
Securing credentials of n8n by CyberArk Conjur without secrets zero using authn-jwt

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

