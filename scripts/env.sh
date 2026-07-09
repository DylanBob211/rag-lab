#!/usr/bin/env bash
set -euo pipefail

: "${SUBSCRIPTION_ID:?SUBSCRIPTION_ID must be set}"
: "${SUFFIX:=4471}"

export RG=ai200-rag-lab
export LOC=swedencentral
export AOAI=ai200-aoai-${SUFFIX}
export AOAI_SKU=S0
export COSMOS=ai200-cosmos-${SUFFIX}
export APPINSIGHTS=ai200-ai
export KV=ai200-kv-${SUFFIX}
export APPCONFIG=ai200-appconfig-${SUFFIX}

# campi deployment-name | model | version | format | sku | capacity
AOAI_DEPLOYMENTS=(
  "embedder|text-embedding-3-small|1|OpenAI|GlobalStandard|120"
  "chat|gpt-5-mini|2025-08-07|OpenAI|GlobalStandard|10"
)
