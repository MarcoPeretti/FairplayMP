#!/usr/bin/env bash
# deploy-classes.sh — Transfer compiled .class files to all VMs
# Usage: ./deploy-classes.sh [file1.class file2.class ...]
#   With no args, transfers all recently modified .class files.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VMS=(bidder0 bidder1 bidder2 bidder3 seller)
CLASSES_DIR="$REPO_ROOT/runtime/build/classes"
REMOTE_DIR="/home/ubuntu/fpmp/runtime/build/classes"

if [[ $# -gt 0 ]]; then
  FILES=("$@")
else
  # Find all .class files (including inner classes like Server$MsgPair.class)
  while IFS= read -r f; do
    FILES+=("$f")
  done < <(find "$CLASSES_DIR" -name "*.class" | sed "s|^$CLASSES_DIR/||")
fi

echo "Deploying ${#FILES[@]} class file(s) to ${#VMS[@]} VMs..."

for VM in "${VMS[@]}"; do
  echo "-> $VM"
  for f in "${FILES[@]}"; do
    multipass transfer "${CLASSES_DIR}/${f}" "${VM}:${REMOTE_DIR}/${f}"
  done
done

echo "Done."
