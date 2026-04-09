#!/usr/bin/env bash
# test-auction.sh — Run SecondPriceAuction with specific bid values
# Usage: ./test-auction.sh SEED BID0 BID1 BID2 BID3 SELLER_INPUT
#   Each bidder[i] receives BID_i as input; seller receives SELLER_INPUT.
#   Example: ./test-auction.sh 42 10 25 7 15 0
#     => bidder[1] should win (bid=25), second price=15

set -euo pipefail

SEED="${1:?Usage: $0 SEED BID0 BID1 BID2 BID3 SELLER_INPUT}"
BID0="${2:?Missing BID0}"
BID1="${3:?Missing BID1}"
BID2="${4:?Missing BID2}"
BID3="${5:?Missing BID3}"
SELLER_IN="${6:-0}"

VMS=(bidder0 bidder1 bidder2 bidder3 seller)
INPUTS=("$BID0" "$BID1" "$BID2" "$BID3" "$SELLER_IN")

echo "Running auction: bids=[$BID0,$BID1,$BID2,$BID3] seed=$SEED"

echo "Killing stale Java processes..."
for VM in "${VMS[@]}"; do
  multipass exec "$VM" -- bash -c 'pkill -f FairplayMP 2>/dev/null; true' >/dev/null 2>&1 &
done
wait
sleep 1

for i in "${!VMS[@]}"; do
  VM="${VMS[$i]}"
  INPUT="${INPUTS[$i]}"
  echo "  starting $VM (input=$INPUT)..."
  multipass exec "$VM" -- bash -c \
    "cd /home/ubuntu/fpmp && java -cp runtime/build/classes FairplayMP ${SEED} Test ${INPUT}" \
    > /tmp/fpmp-${VM}.log 2>&1 &
done

wait

echo ""
echo "──────────── Results ────────────"
for VM in "${VMS[@]}"; do
  echo ""
  echo "=== $VM ==="
  cat /tmp/fpmp-${VM}.log
done
