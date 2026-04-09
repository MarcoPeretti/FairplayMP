#!/usr/bin/env bash
# deploy-cert.sh — Transfer SSL certificates to all VMs
# Usage: ./deploy-cert.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VMS=(bidder0 bidder1 bidder2 bidder3 seller)
CERT_DIR="$REPO_ROOT/runtime/src/certificate"
REMOTE_DIR="/home/ubuntu/fpmp/certificate"

echo "Deploying certificates to ${#VMS[@]} VMs..."

for VM in "${VMS[@]}"; do
  echo "-> $VM"
  multipass transfer "${CERT_DIR}/ks" "${VM}:${REMOTE_DIR}/ks"
  multipass transfer "${CERT_DIR}/ts" "${VM}:${REMOTE_DIR}/ts"
done

echo "Done."
