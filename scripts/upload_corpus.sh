#!/usr/bin/env bash
# Uploads the corpus to blob storage to exercise the doc-sync pipeline.
#
#   ./scripts/upload_corpus.sh              # upload every corpus/*.md
#   ./scripts/upload_corpus.sh --clean      # delete existing blobs first
#
# Each .md upload fires Microsoft.Storage.BlobCreated -> Event Grid ->
# Service Bus queue -> DocSync function -> Cosmos DB. Re-running it overwrites
# the blobs (--overwrite): same blob name, new sequencer, so it exercises the
# "re-embed a modified document" path and the sequencer version guard.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/env.sh" >/dev/null          # RG, STORAGE_ACCOUNT, STORAGE_CONTAINER_NAME, ...

CORPUS_DIR="$HERE/../corpus"

ME=$(az ad signed-in-user show --query id -o tsv)
az role assignment create --assignee "$ME" \
  --role "Storage Blob Data Contributor" \
  --scope "$(az storage account show -g $RG -n $STORAGE_ACCOUNT --query id -o tsv)"

if [[ "${1:-}" == "--clean" ]]; then
  echo "emptying container $STORAGE_CONTAINER_NAME ..."
  az storage blob delete-batch \
    --account-name "$STORAGE_ACCOUNT" \
    --source "$STORAGE_CONTAINER_NAME" \
    --auth-mode login
fi

echo "uploading $CORPUS_DIR/*.md  ->  $STORAGE_ACCOUNT/$STORAGE_CONTAINER_NAME"
az storage blob upload-batch \
  --account-name "$STORAGE_ACCOUNT" \
  --destination "$STORAGE_CONTAINER_NAME" \
  --source "$CORPUS_DIR" \
  --pattern "*.md" \
  --content-type "text/markdown" \
  --overwrite \
  --auth-mode login

echo "done. blobs in container:"
az storage blob list \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name "$STORAGE_CONTAINER_NAME" \
  --auth-mode login \
  --query "[].{name:name, size:properties.contentLength}" -o table
