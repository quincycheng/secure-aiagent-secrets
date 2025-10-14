# n8n-conjur-protectai-local_llm
Securing local AI Agent & LLM with CyberArk Conjur & LLM Guard from ProtectAI | Palo Alto Networks

# Software 
- CyberArk Conjur OSS
https://www.conjur.org/
A seamless open source interface to securely authenticate, control and audit non-human access across tools, applications, containers and cloud environments via robust secrets management.

- n8n 
https://github.com/n8n-io/n8n
n8n is a workflow automation platform that gives technical teams the flexibility of code with the speed of no-code. With 400+ integrations, native AI capabilities, and a fair-code license, n8n lets you build powerful automations while maintaining full control over your data and deployments.

- Ollama
https://github.com/ollama/ollama
Get up and running with large language models.

- LLM Guard
https://github.com/protectai/llm-guard
LLM Guard by Protect AI is a comprehensive tool designed to fortify the security of Large Language Models (LLMs).

- LiteLLM 
https://www.litellm.ai/
LLM Gateway to provide model access, fallbacks and spend tracking across 100+ LLMs. All in the OpenAI format.

- llm-guard-litellm
https://github.com/quincycheng/llm-guard-litellm
LLM-Guard container as LiteLLM custom guardrails


# How to
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

## System Access

| Software          | Port  | Host/Container | Authn Info                                            |
|-------------------|-------|----------------|-------------------------------------------------------|
| Docker/podman     | n/a   | Host           | n/a                                                   |
| Ollama            | 11434 | Host           | n/a                                                   |
| n8n               | 5678  | Container      | User created during first access                      |
| Conjur            | 8080  | Container      | Generated during installation: `data/conjur/admin_data` |
| LiteLLM           | 4000  | Container      | Generated during installation: `data/.env.litellm`      |
| llm-guard-litellm | 4321  | Container      | Generated during installation: `data/.env.llm-guard`    |
| PostgreSQL        | 5432  | Container      | Generated during installation: `data/.env.postgres`    |

## Clean-up
Execute `bin/99-cleanup.sh`
