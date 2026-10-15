#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"   # where Dockerfile + *.py live

log() { echo "RELEASE ==> $*" >&2; }

# A unique tag per release. Reusing ':v1' would leave the image string unchanged,
# and 'containerapp update' might not create a new revision even though the code
# changed. A new tag guarantees a new revision. Override: ./release.sh v2
TAG="${1:-$(date +%Y%m%d-%H%M%S)}"
IMAGE="$ACR.azurecr.io/rag-api:$TAG"

# 1. Build in the cloud (ACR Tasks) with the app root as context. No local Docker needed.
log "Building $IMAGE (cloud build)"
az acr build -r "$ACR" -t "rag-api:$TAG" "$APP_ROOT"

# 2. Point the app at the private registry using its managed identity.
#    Idempotent. Requires AcrPull to be assigned already (run rbac.sh first).
log "Wiring $APP -> $ACR via managed identity"
az containerapp registry set -n "$APP" -g "$RG" \
  --server "$ACR.azurecr.io" --identity system

# 3. New revision with the real image. The app shell, FQDN, managed identity
#    and role assignments stay the same: only the revision changes.
log "Deploying $IMAGE (new revision)"
az containerapp update -n "$APP" -g "$RG" --image "$IMAGE"

log "Publishing function $FUNCTIONAPP (remote build)"
( cd "$APP_ROOT/functions" && func azure functionapp publish "$FUNCTIONAPP" --build remote --python )

FQDN=$(az containerapp show -n "$APP" -g "$RG" --query properties.configuration.ingress.fqdn -o tsv)
log "Live: https://$FQDN/ask?question=..."
log "Release done."
