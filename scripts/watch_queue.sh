#!/usr/bin/env bash
# Tail della PROFONDITÀ della coda doc-sync (control plane, sempre disponibile).
# Non legge i corpi dei messaggi — mostra i contatori: quanti attivi, quanti in
# dead-letter, quanti "scheduled". Rinfresca ogni 2s.
#
#   ./scripts/watch_queue.sh
#
# Con la function spenta vedrai activeMessageCount salire e restare; con la
# function accesa lo vedrai tornare a 0 quasi subito (la coda si drena).
# deadLetterMessageCount > 0 = un messaggio ha superato maxDeliveryCount.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/env.sh" >/dev/null

while true; do
  clear
  echo "coda $SBUS_QUEUE  @ $(date +%T)"
  az servicebus queue show \
    --resource-group "$RG" \
    --namespace-name "$SBUS_NAMESPACE" \
    --name "$SBUS_QUEUE" \
    --query "countDetails" -o yaml
  sleep 2
done
