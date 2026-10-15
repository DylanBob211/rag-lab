#!/usr/bin/env bash
# Shows the depth of the doc-sync queue (control plane, always available).
# It doesn't read message bodies, only the counters: active, dead-lettered and
# scheduled messages. Refreshes every 2s.
#
#   ./scripts/watch_queue.sh
#
# With the function stopped, activeMessageCount grows and stays up; with the
# function running it drops back to 0 almost immediately (the queue drains).
# deadLetterMessageCount > 0 means a message exceeded maxDeliveryCount.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/env.sh" >/dev/null

while true; do
  clear
  echo "queue $SBUS_QUEUE  @ $(date +%T)"
  az servicebus queue show \
    --resource-group "$RG" \
    --namespace-name "$SBUS_NAMESPACE" \
    --name "$SBUS_QUEUE" \
    --query "countDetails" -o yaml
  sleep 2
done
