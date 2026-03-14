#!/usr/bin/env bash

set -euo pipefail

info()    { echo "[*] $*"; }
success() { echo "[+] $*"; }
warn()    { echo "[!] $*"; }
error()   { echo "[-] $*" >&2; }

# -- Preflight checks --
if [[ "$(id -u)" -ne 0 ]]; then
    error "This script must be run as root"
    exit 1
fi

if [[ $# -eq 0 ]]; then
    error "No package name provided"
    error "Usage: ./cleanup_logs.sh <package_name>"
    error "Example: ./cleanup_logs.sh gcc"
    exit 1
fi

PACKAGE="$1"
info "Cleaning log entries for package: ${PACKAGE}"

remove_lines() {
    local file="$1"
    local pattern="$2"

    if [[ ! -f "$file" ]]; then
        warn "${file} does not exist — skipping"
        return 0
    fi

    # Count matching lines before removal so we can report what was cleaned
    local count
    count=$(grep -c "$pattern" "$file" 2>/dev/null || true)

    if [[ "$count" -eq 0 ]]; then
        info "No entries found in ${file} — skipping"
        return 0
    fi

    # Write filtered content to a temp file in the same directory
    local tmp
    tmp=$(mktemp "${file}.XXXXXX")

    grep -v "$pattern" "$file" > "$tmp" || true

    # Preserve original file permissions on the cleaned version
    chmod --reference="$file" "$tmp"

    # Replace the original with the cleaned version
    mv "$tmp" "$file"

    success "Removed ${count} line(s) referencing '${PACKAGE}' from ${file}"
}

remove_lines "/var/log/dpkg.log" "\b${PACKAGE}\b"

if [[ ! -f /var/log/apt/history.log ]]; then
    warn "/var/log/apt/history.log does not exist — skipping"
else
    local_count=$(grep -c "$PACKAGE" /var/log/apt/history.log 2>/dev/null || true)

    if [[ "$local_count" -eq 0 ]]; then
        info "No entries found in /var/log/apt/history.log — skipping"
    else
        tmp=$(mktemp /var/log/apt/history.log.XXXXXX)

        awk -v pkg="$PACKAGE" 'BEGIN{RS=""; ORS="\n\n"} !index($0, pkg)' \
            /var/log/apt/history.log > "$tmp"

        chmod --reference=/var/log/apt/history.log "$tmp"
        mv "$tmp" /var/log/apt/history.log
        success "Removed block(s) referencing '${PACKAGE}' from /var/log/apt/history.log"
    fi
fi

if [[ ! -f /var/log/apt/term.log ]]; then
    warn "/var/log/apt/term.log does not exist — skipping"
else
    local_count=$(grep -c "$PACKAGE" /var/log/apt/term.log 2>/dev/null || true)

    if [[ "$local_count" -eq 0 ]]; then
        info "No entries found in /var/log/apt/term.log — skipping"
    else
        tmp=$(mktemp /var/log/apt/term.log.XXXXXX)

        awk -v pkg="$PACKAGE" 'BEGIN{RS=""; ORS="\n\n"} !index($0, pkg)' \
            /var/log/apt/term.log > "$tmp"

        chmod --reference=/var/log/apt/term.log "$tmp"
        mv "$tmp" /var/log/apt/term.log
        success "Removed block(s) referencing '${PACKAGE}' from /var/log/apt/term.log"
    fi
fi

echo ""
success "Log cleanup complete for package: ${PACKAGE}"
warn "Note: systemd journal may also contain apt activity — check with:"
warn "  journalctl | grep -i '${PACKAGE}'"