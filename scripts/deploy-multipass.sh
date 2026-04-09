#!/usr/bin/env bash
# deploy-multipass.sh — Run SecondPriceAuction on 5 Multipass VMs
# Usage: ./deploy-multipass.sh [SEED] [--run-only | --setup-only]
#   SEED         Random seed passed to FairplayMP (default: 12345)
#   --run-only   Skip VM creation / Java install, just run the protocol
#   --setup-only Set up VMs and transfer files, don't run the protocol

set -euo pipefail

SEED="${1:-12345}"
MODE="${2:-}"          # --run-only | --setup-only | (empty = full)

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VMS=(bidder0 bidder1 bidder2 bidder3 seller)
DEPLOY_DIR="${REPO_ROOT}/fpmp-deploy"

# ── helpers ──────────────────────────────────────────────────────────────────
log()  { echo "[$(date +%H:%M:%S)] $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# ── Phase 1: Launch VMs ───────────────────────────────────────────────────────
launch_vms() {
  log "Phase 1 — launching VMs (this takes a few minutes)..."
  for VM in "${VMS[@]}"; do
    if multipass info "$VM" &>/dev/null; then
      log "  $VM already exists, skipping"
    else
      log "  launching $VM"
      multipass launch --name "$VM" --network en0 22.04
    fi
  done
  log "All VMs running."
}

# ── Phase 2: Collect IPs ──────────────────────────────────────────────────────
# Store IPs in plain variables (bash 3 compat — no associative arrays)
collect_ips() {
  log "Phase 2 — collecting VM IPs..."
  IP_bidder0=$(multipass info bidder0 | awk '/IPv4/{print $2}')
  IP_bidder1=$(multipass info bidder1 | awk '/IPv4/{print $2}')
  IP_bidder2=$(multipass info bidder2 | awk '/IPv4/{print $2}')
  IP_bidder3=$(multipass info bidder3 | awk '/IPv4/{print $2}')
  IP_seller=$(multipass info seller   | awk '/IPv4/{print $2}')
  for VM in "${VMS[@]}"; do
    varname="IP_${VM//-/_}"
    IP="${!varname}"
    [[ -n "$IP" ]] || die "Could not get IP for $VM"
    log "  $VM => $IP"
  done
  # Export so subshells see them
  export IP_bidder0 IP_bidder1 IP_bidder2 IP_bidder3 IP_seller
}

# ── Phase 3: Build deployment package ────────────────────────────────────────
build_package() {
  log "Phase 3 — building deployment package at fpmp-deploy/ ..."
  rm -rf "$DEPLOY_DIR"
  mkdir -p "$DEPLOY_DIR/certificate"
  mkdir -p "$DEPLOY_DIR/runtime/build"

  cp -r "$REPO_ROOT/runtime/build/classes"              "$DEPLOY_DIR/runtime/build/classes"
  cp    "$REPO_ROOT/SecondPriceAuction-compiled.sfdl.cnv" "$DEPLOY_DIR/"
  cp    "$REPO_ROOT/runtime/src/certificate/ks"          "$DEPLOY_DIR/certificate/ks"
  cp    "$REPO_ROOT/runtime/src/certificate/ts"          "$DEPLOY_DIR/certificate/ts"
  log "  files copied."
}

# ── Phase 4: Generate config.xml with real IPs ───────────────────────────────
generate_config() {
  log "Phase 4 — generating config.xml with real IPs..."

  IP0="$IP_bidder0"
  IP1="$IP_bidder1"
  IP2="$IP_bidder2"
  IP3="$IP_bidder3"
  IP4="$IP_seller"

  cat > "$DEPLOY_DIR/config.xml" <<XML
<?xml version="1.0" encoding="utf-8" ?>

<Fairplay2>
	<!--  The circuit file to compute -->
	<Circuit>SecondPriceAuction-compiled.sfdl</Circuit>

	<!-- List of IP's of the computers involved in the computation. -->
	<Participates>
		<!-- List of players (IP or RP) -->
		<Players>
			<Player NameInFunction="bidder[0]">${IP0}</Player>
			<Player NameInFunction="bidder[1]">${IP1}</Player>
			<Player NameInFunction="bidder[2]">${IP2}</Player>
			<Player NameInFunction="bidder[3]">${IP3}</Player>
			<Player NameInFunction="seller">${IP4}</Player>
		</Players>
		<!-- List of IP of the CP -->
		<ComputationPlayers>
			${IP0},${IP1},${IP2},${IP3},${IP4}
		</ComputationPlayers>
	</Participates>

	<Security>
		<Port>
			12347
		</Port>
		<!-- The security parameter to use -->
		<K>
			64
		</K>
		<!-- The prime number to use as modulo, modulo % 4 should be equal 3 -->
		<Modulo>
			4271974071841820164790043412339104229205409044713305539894083215644439451561281100045924173874079
		</Modulo>
		<!-- The protocol to use for the Pseudo Random Generator -->
		<PRGProtocol>
			SHA1PRNG
		</PRGProtocol>
		<!-- The certificates to use for the SSL connection -->
		<Certificate>
			<KeyStore>
				certificate/ks
			</KeyStore>
			<KeyStorePassword>
				123456
			</KeyStorePassword>
			<TrustStore>
				certificate/ts
			</TrustStore>
			<TrustStorePassword>
				123456
			</TrustStorePassword>
		</Certificate>
	</Security>
</Fairplay2>
XML
  log "  config.xml written."
}

# ── Phase 4b: Fix /etc/hosts on each VM so InetAddress.getLocalHost() returns
#              the real bridged IP instead of the 127.0.1.1 Ubuntu default ────
fix_hosts() {
  log "Phase 4b — fixing /etc/hosts on each VM..."
  for VM in "${VMS[@]}"; do
    varname="IP_${VM//-/_}"
    REAL_IP="${!varname}"
    # Ubuntu /etc/hosts has a line like: "127.0.1.1  bidder0"
    # Replace it with the real bridged IP so InetAddress.getLocalHost() works.
    multipass exec "$VM" -- bash -c "
      HOSTNAME=\$(hostname)
      sudo sed -i \"s/^127\.0\.1\.1.*\${HOSTNAME}.*/\${HOSTNAME}/\" /etc/hosts
      grep -q \"^${REAL_IP}\" /etc/hosts || echo '${REAL_IP}  '\"\${HOSTNAME}\" | sudo tee -a /etc/hosts > /dev/null
    "
    log "  $VM: ${REAL_IP} -> $(multipass exec $VM -- hostname)"
  done
}

# ── Phase 5: Transfer package to each VM ─────────────────────────────────────
transfer_files() {
  log "Phase 5 — transferring files to VMs..."
  for VM in "${VMS[@]}"; do
    log "  -> $VM"
    # Remove any stale copy, then transfer the deploy dir itself.
    # "multipass transfer -r src/ vm:/parent/" copies src/ as a child named
    # after the directory, so transferring fpmp-deploy/ to /home/ubuntu/
    # produces /home/ubuntu/fpmp-deploy/ on the VM.  We then rename it to fpmp.
    multipass exec "$VM" -- rm -rf /home/ubuntu/fpmp-deploy /home/ubuntu/fpmp
    multipass transfer -r "$DEPLOY_DIR/" "${VM}:/home/ubuntu/"
    multipass exec "$VM" -- mv /home/ubuntu/fpmp-deploy /home/ubuntu/fpmp
  done
  log "  transfer complete."
}

# ── Phase 6: Install Java ─────────────────────────────────────────────────────
install_java() {
  log "Phase 6 — installing Java on all VMs (in parallel)..."
  for VM in "${VMS[@]}"; do
    (
      log "  installing Java on $VM..."
      multipass exec "$VM" -- bash -c \
        "sudo apt-get update -qq && sudo apt-get remove -y openjdk-11-jre openjdk-11-jre-headless -qq 2>/dev/null; sudo apt-get install -y openjdk-8-jre -qq" \
        > /tmp/java-install-${VM}.log 2>&1 \
        && log "  Java ready on $VM" \
        || { log "  ERROR installing Java on $VM (see /tmp/java-install-${VM}.log)"; exit 1; }
    ) &
  done
  wait
  log "Java installed on all VMs."
}

# ── Phase 7: Run the protocol ─────────────────────────────────────────────────
# Inputs are injected via "Test <value>" — one value per party in VMS order.
# Without an injected input the program blocks on stdin, so Test mode is required
# for non-interactive (background) execution.
# Default inputs: all parties bid 0 (neutral; vary with test-auction.sh).
INPUTS=(0 0 0 0 0)   # bidder0 bidder1 bidder2 bidder3 seller

run_protocol() {
  log "Phase 7 — killing any stale Java processes on all VMs..."
  for VM in "${VMS[@]}"; do
    multipass exec "$VM" -- bash -c "pkill -f FairplayMP 2>/dev/null; sleep 1" &
  done
  wait

  log "Phase 7 — starting FairplayMP on all VMs (seed=$SEED)..."
  for i in "${!VMS[@]}"; do
    VM="${VMS[$i]}"
    INPUT="${INPUTS[$i]}"
    log "  starting $VM (input=$INPUT)..."
    multipass exec "$VM" -- bash -c \
      "cd /home/ubuntu/fpmp && java -cp runtime/build/classes FairplayMP ${SEED} Test ${INPUT}" \
      > /tmp/fpmp-${VM}.log 2>&1 &
  done

  log "Waiting for all parties to finish..."
  wait

  log "──────────── Results ────────────"
  for VM in "${VMS[@]}"; do
    echo
    echo "=== $VM ==="
    cat /tmp/fpmp-${VM}.log
  done
}

# ── Main ──────────────────────────────────────────────────────────────────────
case "$MODE" in
  --run-only)
    collect_ips
    run_protocol
    ;;
  --setup-only)
    launch_vms
    collect_ips
    build_package
    generate_config
    fix_hosts
    transfer_files
    install_java
    log "Setup complete. Run with: ./deploy-multipass.sh $SEED --run-only"
    ;;
  *)
    launch_vms
    collect_ips
    build_package
    generate_config
    fix_hosts
    transfer_files
    install_java
    run_protocol
    ;;
esac
