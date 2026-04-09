#!/usr/bin/env bash
# debug-multipass.sh — Run FairplayMP on all 5 VMs with one party in the foreground
# Usage: ./debug-multipass.sh [SEED] [INPUT] [--foreground VM]
#   SEED          Random seed (default: 12345)
#   INPUT         Bid value for all parties (default: 0)
#   --foreground  VM to run in foreground (default: bidder0); others log to /tmp/fpmp-<vm>.log

set -euo pipefail

SEED="${1:-12345}"
INPUT="${2:-0}"
FG_VM="${4:-bidder0}"   # default foreground VM (arg 4 after --foreground)
if [[ "${3:-}" == "--foreground" ]]; then
  FG_VM="${4:?--foreground requires a VM name}"
fi

VMS=(bidder0 bidder1 bidder2 bidder3 seller)

# Write runner script locally then transfer to each VM
cat > /tmp/run-fpmp.sh << EOF
#!/bin/bash
cd /home/ubuntu/fpmp
exec java -cp runtime/build/classes FairplayMP ${SEED} Test ${INPUT}
EOF

echo "Killing stale Java processes..."
for VM in "${VMS[@]}"; do
  multipass exec "$VM" -- bash -c 'pkill -f FairplayMP 2>/dev/null; true' >/dev/null 2>&1 &
done
wait
sleep 1

echo "Transferring runner script..."
for VM in "${VMS[@]}"; do
  multipass transfer /tmp/run-fpmp.sh ${VM}:/tmp/run-fpmp.sh
done

echo "Starting background parties (logging to /tmp/fpmp-<vm>.log)..."
for VM in "${VMS[@]}"; do
  if [[ "$VM" != "$FG_VM" ]]; then
    multipass exec "$VM" -- bash /tmp/run-fpmp.sh > /tmp/fpmp-${VM}.log 2>&1 &
  fi
done

echo "Running $FG_VM in foreground (seed=${SEED}, input=${INPUT})..."
echo "──────────────────────────────────────"
multipass exec "$FG_VM" -- bash /tmp/run-fpmp.sh

echo ""
echo "──────────── Background party tails ────────────"
for VM in "${VMS[@]}"; do
  if [[ "$VM" != "$FG_VM" ]]; then
    echo ""
    echo "=== $VM ==="
    tail -10 /tmp/fpmp-${VM}.log 2>/dev/null || echo "(no output)"
  fi
done
