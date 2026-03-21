#!usr/bin/env bash
# =============================================================================
# flag_hunt.sh — CTF Flag Hunter
#
# Searches a compromised Linux host for flags in the format FLAG{...}
# Designed to be run as root for maximum coverage.
#
# Usage:
#   bash flag_hunt.sh
#   bash flag_hunt.sh 2>/dev/null   # suppress permission errors
#
# Output:
#   Prints all discovered flags to stdout with source location.
#   Run from your attacker box via SSH:
#     ssh root@<target> 'bash -s' < flag_hunt.sh
#
# Layers (fastest to slowest):
#   1. High-probability filesystem locations
#   2. Service-specific locations (web roots, configs)
#   3. Running process environments
#   4. Database content (MySQL/MariaDB)
#   5. Full filesystem fallback (scoped grep)
# =============================================================================

FLAG_PATTERN="FLAG{[^}]*\}"
FOUND=0

declare -A SEEN

info() { echo "[*] $*" >&2; }
found() {
    local flag="$1"
    local src="$2"
    # Deduplicate
    if [[ -z "${SEEN[$flag]+x}" ]]; then
        SEEN[$flag]=1
        FOUND=$((FOUND + 1))
        echo ""
        echo "================================================================"
        echo "  FLAG FOUND (#${FOUND})"
        echo "  Value  : ${flag}"
        echo "  Source : ${src}"
        echo "================================================================"
    fi
}

# Scan a single file for flags
scan_file() {
    local file="$1"
    [[ -f "$file" && -r "$file" ]] || return
    local matches
    matches=$(grep -oP "$FLAG_PATTERN" "$file" 2>/dev/null)
    while IFS= read -r flag; do
        [[ -n "$flag" ]] && found "$flag" "$file"
    done <<< "$matches"
}

# Scan a directory tree (non-recursive call — uses find internally)
scan_dir() {
    local dir="$1"
    local maxdepth="${2:-10}"
    [[ -d "$dir" ]] || return
    while IFS= read -r file; do
        scan_file "$file"
    done < <(find "$dir" -maxdepth "$maxdepth" -type f -readable 2>/dev/null)
}

# Scan a string value directly
scan_string() {
    local value="$1"
    local src="$2"
    local matches
    matches=$(echo "$value" | grep -oP "$FLAG_PATTERN" 2>/dev/null)
    while IFS= read -r flag; do
        [[ -n "$flag" ]] && found "$flag" "$src"
    done <<< "$matches"
}

# =============================================================================
# Layer 1 — High-probability filesystem locations
# =============================================================================
 
info "Layer 1: High-probability locations..."
 
HIGH_PROB_DIRS=(
    /root
    /home
    /opt
    /srv
    /var/www
    /var/lib
    /var/backups
    /etc
    /tmp
    /var/tmp
)
 
for dir in "${HIGH_PROB_DIRS[@]}"; do
    info "  Scanning ${dir}..."
    scan_dir "$dir" 6
done
 
# Check common individual files that often hold flags in CTFs
HIGH_PROB_FILES=(
    /root/flag.txt
    /root/root.txt
    /root/flag
    /home/*/flag.txt
    /home/*/flag
    /home/*/user.txt
    /var/www/html/flag.txt
    /var/www/html/flag
    /opt/flag.txt
    /opt/flag
)
 
for pattern in "${HIGH_PROB_FILES[@]}"; do
    for file in $pattern; do
        scan_file "$file"
    done
done
 
# =============================================================================
# Layer 2 — Service-specific locations
# =============================================================================
 
info "Layer 2: Service-specific locations..."
 
# ── Web roots ────────────────────────────────────────────────────────────────
 
info "  Scanning web roots..."
 
# Find all web roots dynamically
while IFS= read -r webroot; do
    scan_dir "$webroot" 8
done < <(find /var/www /srv/www /usr/share/nginx /usr/share/apache2 \
    -maxdepth 3 -type d -name "html" -o -name "www" -o -name "public" \
    -o -name "public_html" -o -name "htdocs" 2>/dev/null | sort -u)
 
# ── WordPress specific ───────────────────────────────────────────────────────
 
info "  Scanning WordPress installations..."
 
while IFS= read -r wpconfig; do
    wproot=$(dirname "$wpconfig")
    info "    Found WordPress at ${wproot}"
    scan_dir "$wproot" 5
done < <(find / -maxdepth 8 -name "wp-config.php" \
    -not -path "*/proc/*" -not -path "*/sys/*" 2>/dev/null)
 
# ── Nginx / Apache configs ───────────────────────────────────────────────────
 
info "  Scanning web server configs..."
 
for dir in /etc/nginx /etc/apache2 /etc/httpd /etc/lighttpd; do
    scan_dir "$dir" 4
done
 
# Nginx vhost roots
while IFS= read -r root; do
    scan_dir "$root" 5
done < <(grep -rh 'root\s' /etc/nginx /etc/apache2 2>/dev/null \
    | grep -oP '(?<=root\s{1,4})/[^;]+' | sort -u)
 
# ── SSH / user files ─────────────────────────────────────────────────────────
 
info "  Scanning user home directories and SSH files..."
 
while IFS=: read -r user _ uid _ _ home _; do
    [[ "$uid" -lt 1000 && "$user" != "root" ]] && continue
    [[ -d "$home" ]] || continue
    scan_dir "$home" 5
done < /etc/passwd
 
# ── Common service config dirs ───────────────────────────────────────────────
 
info "  Scanning service config directories..."
 
SERVICE_DIRS=(
    /etc/vsftpd
    /etc/samba
    /etc/redis
    /etc/mysql
    /etc/postgresql
    /var/spool
    /var/log
    /var/lib/redis
)
 
for dir in "${SERVICE_DIRS[@]}"; do
    scan_dir "$dir" 4
done
 
# ── Redis ────────────────────────────────────────────────────────────────────
 
if command -v redis-cli &>/dev/null; then
    info "  Scanning Redis..."
    while IFS= read -r key; do
        val=$(redis-cli GET "$key" 2>/dev/null)
        scan_string "$val" "redis:key:${key}"
    done < <(redis-cli KEYS '*' 2>/dev/null)
fi
 
# ── FTP roots ────────────────────────────────────────────────────────────────
 
info "  Scanning FTP roots..."
 
for dir in /var/ftp /srv/ftp /home/ftp /var/vsftpd; do
    scan_dir "$dir" 5
done
 
# Detect vsftpd configured root
if [[ -f /etc/vsftpd.conf ]]; then
    ftp_root=$(grep -oP '(?<=local_root=).+' /etc/vsftpd.conf 2>/dev/null | head -1)
    [[ -n "$ftp_root" ]] && scan_dir "$ftp_root" 5
fi
 
# ── SMB / Samba shares ───────────────────────────────────────────────────────
 
info "  Scanning Samba share paths..."
 
while IFS= read -r sharepath; do
    scan_dir "$sharepath" 5
done < <(grep -oP '(?<=path = ).+' /etc/samba/smb.conf 2>/dev/null | sort -u)
 
# =============================================================================
# Layer 3 — Running process environments
# =============================================================================
 
info "Layer 3: Process environments..."
 
for pid in /proc/[0-9]*/environ; do
    [[ -r "$pid" ]] || continue
    env_content=$(tr '\0' '\n' < "$pid" 2>/dev/null)
    scan_string "$env_content" "process env: ${pid}"
done
 
# =============================================================================
# Layer 4 — Database content
# =============================================================================
 
info "Layer 4: Databases..."
 
# ── MySQL / MariaDB ──────────────────────────────────────────────────────────
 
if command -v mysql &>/dev/null; then
    info "  Scanning MySQL/MariaDB..."
 
    # Try connecting as root without password (common in CTF VMs)
    MYSQL_CMD="mysql -u root --batch --silent 2>/dev/null"
 
    # Get all databases
    while IFS= read -r db; do
        [[ "$db" =~ ^(information_schema|performance_schema|mysql|sys)$ ]] && continue
 
        # Get all tables
        while IFS= read -r table; do
            # Get all columns in each table
            while IFS= read -r col; do
                # Query the column for flag pattern
                result=$(echo "SELECT \`${col}\` FROM \`${db}\`.\`${table}\` WHERE \`${col}\` REGEXP 'FLAG\\\\{' LIMIT 20;" \
                    | $MYSQL_CMD 2>/dev/null)
                while IFS= read -r val; do
                    scan_string "$val" "mysql:${db}.${table}.${col}"
                done <<< "$result"
            done < <(echo "SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='${db}' AND TABLE_NAME='${table}';" \
                | $MYSQL_CMD 2>/dev/null)
        done < <(echo "SHOW TABLES IN \`${db}\`;" | $MYSQL_CMD 2>/dev/null)
    done < <(echo "SHOW DATABASES;" | $MYSQL_CMD 2>/dev/null)
fi
 
# ── PostgreSQL ───────────────────────────────────────────────────────────────
 
if command -v psql &>/dev/null && id postgres &>/dev/null; then
    info "  Scanning PostgreSQL..."
 
    while IFS= read -r db; do
        [[ "$db" =~ ^(template|postgres)$ ]] && continue
 
        while IFS= read -r table; do
            result=$(sudo -u postgres psql -d "$db" -t -c \
                "SELECT * FROM ${table} WHERE CAST(${table}::text AS text) ~ 'FLAG\{'" \
                2>/dev/null | grep -oP "$FLAG_PATTERN")
            while IFS= read -r flag; do
                [[ -n "$flag" ]] && found "$flag" "postgres:${db}.${table}"
            done <<< "$result"
        done < <(sudo -u postgres psql -d "$db" -t -c \
            "SELECT tablename FROM pg_tables WHERE schemaname='public';" 2>/dev/null \
            | tr -d ' ')
    done < <(sudo -u postgres psql -t -c "SELECT datname FROM pg_database;" 2>/dev/null \
        | tr -d ' ')
fi
 
# =============================================================================
# Layer 5 — Full filesystem fallback (scoped grep)
# =============================================================================
 
info "Layer 5: Full filesystem grep (this may take a moment)..."
 
# Explicitly exclude pseudo/virtual/noisy filesystems and already-scanned dirs
EXCLUDE_PATHS=(
    /proc
    /sys
    /dev
    /run
    /snap
    /boot
    /lib
    /lib64
    /usr/lib
    /usr/lib64
    /usr/share/doc
    /usr/share/man
    /usr/share/locale
    /var/cache/apt
    /var/lib/dpkg
    /var/lib/apt
)
 
PRUNE_EXPR=""
for path in "${EXCLUDE_PATHS[@]}"; do
    PRUNE_EXPR+=" -path ${path} -prune -o"
done
 
while IFS= read -r file; do
    scan_file "$file"
done < <(eval "find / $PRUNE_EXPR -type f -readable -print" 2>/dev/null)
 
# =============================================================================
# Summary
# =============================================================================
 
echo ""
echo "================================================================"
echo "  FLAG HUNT COMPLETE"
echo "  Total flags found: ${FOUND}"
echo "================================================================"