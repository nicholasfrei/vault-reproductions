#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_TREE_OUTPUT="$SCRIPT_DIR/vault_storage_tree.txt"

MODE=""
NEEDLE=""
START_PATH="sys/raw/core"
OUTPUT_FILE=""

info() {
  echo "INFO: $*" >&2
}

warn() {
  echo "WARN: $*" >&2
}

usage() {
  cat <<'EOF'
Usage:
  sys-raw-inspector.sh tree [--output FILE]
  sys-raw-inspector.sh search --needle VALUE [--start-path PATH] [--output FILE]

Description:
  tree    Walk mounted logical/auth storage using /sys/raw and print an ASCII tree.
  search  Recursively LIST and GET under a /sys/raw path and print files whose raw
          JSON response contains the provided needle.

Required environment variables:
  VAULT_ADDR
  VAULT_TOKEN

Optional environment variables:
  VAULT_CACERT, VAULT_CAPATH, VAULT_SKIP_VERIFY, VAULT_NAMESPACE

Examples:
  VAULT_ADDR=https://127.0.0.1:8200 VAULT_TOKEN=... ./sys-raw-inspector.sh tree
  VAULT_ADDR=https://127.0.0.1:8200 VAULT_TOKEN=... ./sys-raw-inspector.sh search \
    --needle 1234abcd-uuid --start-path sys/raw/core
EOF
}

require_commands() {
  local missing=0
  local cmd
  for cmd in vault jq grep; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      warn "Missing required command: $cmd"
      missing=1
    fi
  done

  if [[ "$missing" -ne 0 ]]; then
    exit 1
  fi
}

normalize_raw_path() {
  local raw_path="$1"
  raw_path="${raw_path#/}"
  raw_path="${raw_path#v1/}"
  raw_path="${raw_path#sys/raw/}"
  printf '%s\n' "$raw_path"
}

write_line() {
  local line="$1"
  printf '%s\n' "$line"
  if [[ -n "$OUTPUT_FILE" ]]; then
    printf '%s\n' "$line" >> "$OUTPUT_FILE"
  fi
}

api_request() {
  local method="$1"
  local path="$2"

  case "$method" in
    GET)
      vault read -format=json "$path"
      ;;
    LIST)
      vault list -format=json "$path"
      ;;
    *)
      warn "Unsupported method: $method"
      return 1
      ;;
  esac
}

list_raw_keys() {
  local path_suffix="$1"
  local response

  response="$(api_request LIST "sys/raw/${path_suffix}" 2>/dev/null || true)"
  if [[ -z "$response" ]]; then
    return 0
  fi

  jq -r 'if type == "array" then .[] else .data.keys[]? end' <<<"$response"
}

get_raw_json_value() {
  local path_suffix="$1"
  local response

  response="$(api_request GET "sys/raw/${path_suffix}" 2>/dev/null || true)"
  if [[ -z "$response" ]]; then
    return 0
  fi

  jq -cr 'if .data.encoding == "base64" then (.data.value | @base64d) else .data.value end // empty' <<<"$response"
}

get_mount_entries() {
  local path_suffix="$1"
  local decoded

  decoded="$(get_raw_json_value "$path_suffix")"
  if [[ -z "$decoded" ]]; then
    return 0
  fi

  jq -cr '.entries[]?' <<<"$decoded"
}

walk_raw_tree() {
  local path_suffix="$1"
  local prefix="${2:-}"
  local -a keys
  local index=0
  local key
  local connector
  local next_prefix

  keys=()
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    keys+=("$key")
  done < <(list_raw_keys "$path_suffix")

  if [[ "${#keys[@]}" -eq 0 ]]; then
    return 0
  fi

  for key in "${keys[@]}"; do
    if (( index == ${#keys[@]} - 1 )); then
      connector='`-- '
      next_prefix="${prefix}    "
    else
      connector='|-- '
      next_prefix="${prefix}|   "
    fi

    write_line "${prefix}${connector}${key}"

    if [[ "$key" == */ ]]; then
      walk_raw_tree "${path_suffix}${key}" "$next_prefix"
    fi

    ((index += 1))
  done
}

print_mount_tree() {
  local header="$1"
  local mount_metadata_path="$2"
  local root_prefix="$3"
  local entry
  local mount_path
  local mount_uuid
  local mount_type

  write_line ""
  write_line "$header"

  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue

    mount_path="$(jq -r '.path // empty' <<<"$entry")"
    mount_uuid="$(jq -r '.uuid // empty' <<<"$entry")"
    mount_type="$(jq -r '.type // empty' <<<"$entry")"

    if [[ -z "$mount_path" || -z "$mount_uuid" || -z "$mount_type" ]]; then
      continue
    fi

    if [[ "$mount_metadata_path" == "core/mounts" ]]; then
      case "$mount_type" in
        system|ns_system|token|ns_token)
          continue
          ;;
      esac
      write_line "|-- ${mount_path} (type=${mount_type}, uuid=${mount_uuid})"
      walk_raw_tree "logical/${mount_uuid}/" "$root_prefix"
    else
      case "$mount_type" in
        token|ns_token)
          continue
          ;;
      esac
      write_line "|-- ${mount_path} (type=${mount_type}, uuid=${mount_uuid})"
      walk_raw_tree "auth/${mount_uuid}/" "$root_prefix"
    fi
  done < <(get_mount_entries "$mount_metadata_path")
}

run_tree_mode() {
  if [[ -z "$OUTPUT_FILE" ]]; then
    OUTPUT_FILE="$DEFAULT_TREE_OUTPUT"
  fi

  : > "$OUTPUT_FILE"

  write_line "Vault Storage Inspector: ${VAULT_ADDR%/}"
  write_line "============================================================"
  print_mount_tree "[ SECRET ENGINES (sys/raw/logical/) ]" "core/mounts" "|   "
  print_mount_tree "[ AUTH METHODS (sys/raw/auth/) ]" "core/auth" "|   "

  info "Tree output written to $OUTPUT_FILE"
}

search_raw_path() {
  local path_suffix="$1"
  local -a keys
  local key
  local full_path
  local content

  keys=()
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    keys+=("$key")
  done < <(list_raw_keys "$path_suffix")

  if [[ "${#keys[@]}" -eq 0 ]]; then
    return 0
  fi

  for key in "${keys[@]}"; do
    full_path="${path_suffix}${key}"
    if [[ "$key" == */ ]]; then
      search_raw_path "$full_path"
      continue
    fi

    content="$(api_request GET "sys/raw/${full_path}" 2>/dev/null || true)"
    if [[ -n "$content" ]] && grep -Fq -- "$NEEDLE" <<<"$content"; then
      write_line "MATCH FOUND: sys/raw/${full_path}"
    fi
  done
}

run_search_mode() {
  local normalized_path

  if [[ -z "$NEEDLE" ]]; then
    warn "search mode requires --needle"
    usage
    exit 1
  fi

  if [[ -n "$OUTPUT_FILE" ]]; then
    : > "$OUTPUT_FILE"
  fi

  normalized_path="$(normalize_raw_path "$START_PATH")"
  if [[ -z "$normalized_path" ]]; then
    warn "Invalid start path: $START_PATH"
    exit 1
  fi

  write_line "Searching for: $NEEDLE"
  write_line "Start path: sys/raw/${normalized_path}"
  search_raw_path "${normalized_path%/}/"
}

parse_args() {
  if [[ "$#" -eq 0 ]]; then
    usage
    exit 1
  fi

  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
    exit 0
  fi

  MODE="$1"
  shift

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --needle)
        [[ "$#" -lt 2 ]] && { warn "--needle requires a value"; exit 1; }
        NEEDLE="$2"
        shift 2
        ;;
      --start-path)
        [[ "$#" -lt 2 ]] && { warn "--start-path requires a value"; exit 1; }
        START_PATH="$2"
        shift 2
        ;;
      --output)
        [[ "$#" -lt 2 ]] && { warn "--output requires a value"; exit 1; }
        OUTPUT_FILE="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        warn "Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
  done

  case "$MODE" in
    tree|search)
      ;;
    *)
      warn "Unknown mode: $MODE"
      usage
      exit 1
      ;;
  esac
}

main() {
  parse_args "$@"
  require_commands

  if [[ -z "${VAULT_ADDR:-}" || -z "${VAULT_TOKEN:-}" ]]; then
    warn "Set VAULT_ADDR and VAULT_TOKEN before running this script."
    exit 1
  fi

  case "$MODE" in
    tree)
      run_tree_mode
      ;;
    search)
      run_search_mode
      ;;
  esac
}

main "$@"