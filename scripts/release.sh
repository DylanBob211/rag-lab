#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"   # dove stanno Dockerfile + *.py

log() { echo "RELEASE ==> $*" >&2; }

# Tag UNICO a ogni release. Se riusassi sempre ':v1', la STRINGA immagine non
# cambierebbe e 'containerapp update' potrebbe NON creare una nuova revision anche
# a codice modificato. Un tag nuovo -> nuova revision garantita. Override: ./release.sh v2
TAG="${1:-$(date +%Y%m%d-%H%M%S)}"
IMAGE="$ACR.azurecr.io/rag-api:$TAG"

# 1. Build IN CLOUD (ACR Tasks), context = root dell'app. Niente Docker locale.
log "Building $IMAGE (cloud build)"
az acr build -r "$ACR" -t "rag-api:$TAG" "$APP_ROOT"

# 2. Punta l'app al registry privato CON la sua managed identity. Idempotente
#    (rigirarlo non fa danni). Richiede AcrPull gia' assegnato -> rbac.sh prima.
log "Wiring $APP -> $ACR via managed identity"
az containerapp registry set -n "$APP" -g "$RG" \
  --server "$ACR.azurecr.io" --identity system

# 3. Nuova revision con l'immagine vera. Il guscio, l'FQDN, la MI e i 6 grant
#    restano invariati: cambia SOLO la revision.
log "Deploying $IMAGE (new revision)"
az containerapp update -n "$APP" -g "$RG" --image "$IMAGE"

log "Publishing function $FUNCTIONAPP (remote build)"
( cd "$APP_ROOT/functions" && func azure functionapp publish "$FUNCTIONAPP" --build remote )

FQDN=$(az containerapp show -n "$APP" -g "$RG" --query properties.configuration.ingress.fqdn -o tsv)
log "Live: https://$FQDN/ask?question=..."
log "Release done."
