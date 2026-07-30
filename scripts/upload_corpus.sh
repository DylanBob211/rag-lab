#!/usr/bin/env bash
# Carica il corpus in blob storage per testare la pipeline doc-sync.
#
#   ./scripts/upload_corpus.sh              # carica tutti i corpus/*.md
#   ./scripts/upload_corpus.sh --clean      # cancella prima quelli già presenti
#
# Ogni upload di un .md fa scattare Microsoft.Storage.BlobCreated -> Event Grid
# -> coda doc-sync -> function DocSync -> Cosmos. Rilanciarlo sovrascrive i blob
# (--overwrite): stesso blob name, sequencer nuovo, quindi esercita il ramo
# "re-embed di un documento modificato" e il version guard sul sequencer.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/env.sh" >/dev/null          # RG, STORAGE_ACCOUNT, STORAGE_CONTAINER_NAME, ...

CORPUS_DIR="$HERE/../corpus"

ME=$(az ad signed-in-user show --query id -o tsv)
az role assignment create --assignee "$ME" \
  --role "Storage Blob Data Contributor" \
  --scope "$(az storage account show -g $RG -n $STORAGE_ACCOUNT --query id -o tsv)"

if [[ "${1:-}" == "--clean" ]]; then
  echo "svuoto il container $STORAGE_CONTAINER_NAME ..."
  az storage blob delete-batch \
    --account-name "$STORAGE_ACCOUNT" \
    --source "$STORAGE_CONTAINER_NAME" \
    --auth-mode login
fi

echo "carico $CORPUS_DIR/*.md  ->  $STORAGE_ACCOUNT/$STORAGE_CONTAINER_NAME"
az storage blob upload-batch \
  --account-name "$STORAGE_ACCOUNT" \
  --destination "$STORAGE_CONTAINER_NAME" \
  --source "$CORPUS_DIR" \
  --pattern "*.md" \
  --content-type "text/markdown" \
  --overwrite \
  --auth-mode login

echo "fatto. blob nel container:"
az storage blob list \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name "$STORAGE_CONTAINER_NAME" \
  --auth-mode login \
  --query "[].{name:name, size:properties.contentLength}" -o table
