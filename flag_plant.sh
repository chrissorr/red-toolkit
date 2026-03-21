#!/usr/bin/env bash
# =============================================================================
# plant_flags.sh — CTF Flag Planting Script for Testing
#
# Plants test flags across multiple layers to validate flag_hunt.sh coverage.
# Must be run as root on the target VM.
#
# Usage:
#   sudo bash plant_flags.sh
#   sudo bash plant_flags.sh --wordpress   # also plant WordPress DB flag
#   sudo bash plant_flags.sh --clean       # remove all planted flags
#
# Flags planted:
#   Easy   (filesystem)       — /root, home dir, web root
#   Medium (service configs)  — apache/nginx config, web root subdir
#   Hard   (database/env)     — MySQL row, environment variable via cron
# =============================================================================

set -uo pipefail

MODE="plant"
HAS_WORDPRESS=false

for arg in "$@"; do
    case "$arg" in
        --wordpress) HAS_WORDPRESS=true ;;
        --clean)     MODE="clean" ;;
    esac
done

info()    { echo "[*] $*"; }
success() { echo "[+] $*"; }
warn()    { echo "[!] $*" >&2; }
error()   { echo "[-] $*" >&2; }

if [[ "$(id -u)" -ne 0 ]]; then
    error "This script must be run as root"
    exit 1
fi

# =============================================================================
# Flag definitions — edit values here if needed
# =============================================================================

# Easy — filesystem
FLAG_ROOT="FLAG{easy_root_homedir_r00t}"
FLAG_USER="FLAG{easy_user_homedir_l00k}"
FLAG_WEBROOT="FLAG{easy_webroot_index_f1nd}"

# Medium — service configs / subdirectories
FLAG_APACHE="FLAG{medium_apache_config_sneak}"
FLAG_WEBDIR="FLAG{medium_webroot_subdir_hidd}"
FLAG_ETC="FLAG{medium_etc_service_conf_x}"

# Hard — database / environment
FLAG_DB="FLAG{hard_database_row_s3cr3t}"
FLAG_ENV="FLAG{hard_process_env_v4r1bl}"

# Planted file/location tracking for clean mode
PLANTED_FILES=(
    /root/flag.txt
    /home/target/flag.txt
    /var/www/html/flag.txt
    /var/www/html/assets/config.txt
    /etc/cron.d/ctf-flag
)

# =============================================================================
# Clean mode — remove all planted flags
# =============================================================================

if [[ "$MODE" == "clean" ]]; then
    info "Cleaning up planted flags..."

    for file in "${PLANTED_FILES[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            success "Removed: ${file}"
        fi
    done

    # Remove apache flag from config
    if [[ -f /etc/apache2/apache2.conf ]]; then
        sed -i '/FLAG{/d' /etc/apache2/apache2.conf
        success "Removed flag from /etc/apache2/apache2.conf"
    fi

    # Remove nginx flag from config
    if [[ -f /etc/nginx/flag.conf ]]; then
        rm -f /etc/nginx/flag.conf
        success "Removed: /etc/nginx/flag.conf"
    fi

    # Remove /etc/flag.conf if we planted it
    rm -f /etc/flag.conf

    # Remove assets dir if we created it
    rmdir /var/www/html/assets 2>/dev/null || true

    # Remove DB flag
    if command -v mysql &>/dev/null; then
        mysql -u root 2>/dev/null <<SQL
DELETE FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='ctf_flags';
DROP DATABASE IF EXISTS ctf_flags;
SQL
        # Also try WordPress DB cleanup if applicable
        if [[ "$HAS_WORDPRESS" == true ]]; then
            WP_CONFIG=$(find /var/www -name "wp-config.php" 2>/dev/null | head -1)
            if [[ -n "$WP_CONFIG" ]]; then
                DB_NAME=$(grep -oP "define\s*\(\s*'DB_NAME'\s*,\s*'\K[^']+" "$WP_CONFIG" | head -1)
                DB_USER=$(grep -oP "define\s*\(\s*'DB_USER'\s*,\s*'\K[^']+" "$WP_CONFIG" | head -1)
                DB_PASS=$(grep -oP "define\s*\(\s*'DB_PASSWORD'\s*,\s*'\K[^']+" "$WP_CONFIG" | head -1)
                DB_PREFIX=$(grep -oP "\\\$table_prefix\s*=\s*'\K[^']+" "$WP_CONFIG" | head -1)
                mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" 2>/dev/null \
                    -e "DELETE FROM ${DB_PREFIX}options WHERE option_name='ctf_flag';" \
                    && success "Removed WordPress DB flag"
            fi
        fi
    fi

    echo ""
    success "Cleanup complete"
    exit 0
fi

# =============================================================================
# Plant mode
# =============================================================================

info "Planting test flags..."
echo ""

# ── Easy: Filesystem ─────────────────────────────────────────────────────────

info "Planting easy flags (filesystem)..."

echo "$FLAG_ROOT" > /root/flag.txt
success "  /root/flag.txt -> ${FLAG_ROOT}"

# Find first real user home dir
USER_HOME=$(awk -F: '$3 >= 1000 && $7 != "/usr/sbin/nologin" {print $6}' /etc/passwd | head -1)
if [[ -n "$USER_HOME" && -d "$USER_HOME" ]]; then
    echo "$FLAG_USER" > "${USER_HOME}/flag.txt"
    success "  ${USER_HOME}/flag.txt -> ${FLAG_USER}"
else
    warn "  No user home dir found — skipping user flag"
fi

if [[ -d /var/www/html ]]; then
    echo "$FLAG_WEBROOT" > /var/www/html/flag.txt
    success "  /var/www/html/flag.txt -> ${FLAG_WEBROOT}"
else
    warn "  /var/www/html not found — skipping web root flag"
fi

echo ""

# ── Medium: Service configs / subdirectories ──────────────────────────────────

info "Planting medium flags (service configs / subdirectories)..."

# Apache config append
if [[ -f /etc/apache2/apache2.conf ]]; then
    echo "# ctf_flag=${FLAG_APACHE}" >> /etc/apache2/apache2.conf
    success "  /etc/apache2/apache2.conf -> ${FLAG_APACHE}"
elif [[ -d /etc/nginx ]]; then
    echo "# ctf_flag=${FLAG_APACHE}" > /etc/nginx/flag.conf
    success "  /etc/nginx/flag.conf -> ${FLAG_APACHE}"
else
    echo "ctf_flag=${FLAG_APACHE}" > /etc/flag.conf
    success "  /etc/flag.conf -> ${FLAG_APACHE}"
fi

# Web root subdirectory
if [[ -d /var/www/html ]]; then
    mkdir -p /var/www/html/assets
    echo "api_key=${FLAG_WEBDIR}" > /var/www/html/assets/config.txt
    success "  /var/www/html/assets/config.txt -> ${FLAG_WEBDIR}"
fi

# Generic etc location
echo "secret=${FLAG_ETC}" > /etc/flag.conf
success "  /etc/flag.conf -> ${FLAG_ETC}"

echo ""

# ── Hard: Database ────────────────────────────────────────────────────────────

info "Planting hard flags (database)..."

if command -v mysql &>/dev/null; then
    # Try root with no password first (common in CTF VMs)
    if mysql -u root 2>/dev/null -e "SELECT 1;" &>/dev/null; then
        mysql -u root 2>/dev/null <<SQL
CREATE DATABASE IF NOT EXISTS ctf_flags;
USE ctf_flags;
CREATE TABLE IF NOT EXISTS secrets (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(255), value TEXT);
INSERT INTO secrets (name, value) VALUES ('flag', '${FLAG_DB}');
SQL
        success "  mysql:ctf_flags.secrets -> ${FLAG_DB}"
    else
        warn "  MySQL root login failed — skipping DB flag"
        warn "  Plant manually: INSERT INTO <db>.secrets VALUES ('flag','${FLAG_DB}');"
    fi

    # Also plant in WordPress DB if applicable
    if [[ "$HAS_WORDPRESS" == true ]]; then
        WP_CONFIG=$(find /var/www -name "wp-config.php" 2>/dev/null | head -1)
        if [[ -n "$WP_CONFIG" ]]; then
            DB_NAME=$(grep -oP "define\s*\(\s*'DB_NAME'\s*,\s*'\K[^']+" "$WP_CONFIG" | head -1)
            DB_USER=$(grep -oP "define\s*\(\s*'DB_USER'\s*,\s*'\K[^']+" "$WP_CONFIG" | head -1)
            DB_PASS=$(grep -oP "define\s*\(\s*'DB_PASSWORD'\s*,\s*'\K[^']+" "$WP_CONFIG" | head -1)
            DB_PREFIX=$(grep -oP "\\\$table_prefix\s*=\s*'\K[^']+" "$WP_CONFIG" | head -1)
            mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" 2>/dev/null \
                -e "INSERT INTO ${DB_PREFIX}options (option_name, option_value, autoload) VALUES ('ctf_flag', '${FLAG_DB}', 'yes') ON DUPLICATE KEY UPDATE option_value='${FLAG_DB}';" \
                && success "  mysql:${DB_NAME}.${DB_PREFIX}options (WordPress) -> ${FLAG_DB}"
        else
            warn "  --wordpress specified but wp-config.php not found"
        fi
    fi
else
    warn "  mysql not found — skipping DB flag"
fi

echo ""

# ── Hard: Environment variable via cron ──────────────────────────────────────

info "Planting hard flags (environment variable)..."

cat > /etc/cron.d/ctf-flag << CRON
# CTF environment flag
* * * * * root /bin/bash -c 'export CTF_FLAG=${FLAG_ENV}; sleep 30'
CRON
chmod 644 /etc/cron.d/ctf-flag
success "  /etc/cron.d/ctf-flag (env var) -> ${FLAG_ENV}"
info "  Note: env flag will appear in /proc after cron fires (up to 1 min)"

echo ""

# =============================================================================
# Summary
# =============================================================================

echo "============================================================"
success "Flag planting complete"
echo "============================================================"
echo ""
info "Planted flags:"
printf "  %-10s %s\n" "Easy"   "${FLAG_ROOT}"
printf "  %-10s %s\n" "Easy"   "${FLAG_USER}"
printf "  %-10s %s\n" "Easy"   "${FLAG_WEBROOT}"
printf "  %-10s %s\n" "Medium" "${FLAG_APACHE}"
printf "  %-10s %s\n" "Medium" "${FLAG_WEBDIR}"
printf "  %-10s %s\n" "Medium" "${FLAG_ETC}"
printf "  %-10s %s\n" "Hard"   "${FLAG_DB}"
printf "  %-10s %s\n" "Hard"   "${FLAG_ENV}"
echo ""
info "Now run flag_hunt.sh to verify coverage:"
info "  bash flag_hunt.sh 2>/dev/null"
echo ""
info "To remove all planted flags:"
info "  sudo bash plant_flags.sh --clean"
[[ "$HAS_WORDPRESS" == true ]] && info "  sudo bash plant_flags.sh --wordpress --clean"