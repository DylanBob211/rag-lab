#!/usr/bin/env bash
set -euo pipefail

: "${SUBSCRIPTION_ID:?SUBSCRIPTION_ID must be set}"
: "${SUFFIX:=4471}"

az account set --subscription "$SUBSCRIPTION_ID"
az config set extension.dynamic_install_allow_preview=true

export RG=ai200-rag-lab
export LOC=swedencentral
export AOAI=ai200-aoai-${SUFFIX}
export AOAI_SKU=S0
export COSMOS=ai200-cosmos-${SUFFIX}
export COSMOS_DB_NAME=docs
export COSMOS_CONTAINER_NAME=chunks
export APPINSIGHTS=ai200-ai
export KV=ai200-kv-${SUFFIX}
export APPCONFIG=ai200-appconfig-${SUFFIX}
export REDIS=ai200-redis-${SUFFIX}
export ACR=ai200acr${SUFFIX}          
export ACA_ENV=ai200-aca-env          
export APP=rag-api          
export STORAGE_ACCOUNT=ai200storage${SUFFIX}
export STORAGE_CONTAINER_NAME=ai200-docs-${SUFFIX}
export SBUS_NAMESPACE=ai200-service-bus-${SUFFIX}
export SBUS_QUEUE=ai200-docs-index
export FUNCTIONAPP_SERVICE_PLAN=ai200-appserviceplan-${SUFFIX}
export FUNCTIONAPP=ai200-funcapp-${SUFFIX}
export STORAGE_ACCOUNT_SYSTEM_TOPIC=ai200-storage-account-topic-${SUFFIX}
export SERVICE_BUS_STORAGE_ACCOUNT_SUBSCRIPTION_NAME=to-doc-sync

# campi deployment-name | model | version | format | sku | capacity
AOAI_DEPLOYMENTS=(
  "embedder|text-embedding-3-small|1|OpenAI|GlobalStandard|120"
  "chat|gpt-5-mini|2025-08-07|OpenAI|GlobalStandard|10"
)
