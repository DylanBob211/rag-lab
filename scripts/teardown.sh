#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

az group delete -n "$RG" --yes
az cognitiveservices account purge -l "$LOC" -g "$RG" -n "$AOAI"
az keyvault purge -n "$KV" -l "$LOC"