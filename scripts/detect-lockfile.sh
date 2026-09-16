#!/usr/bin/env bash
# Emit cache= and path= for actions/setup-node.
# Path inputs are validated before any GITHUB_OUTPUT is written.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

workdir="$(normalize_working_directory "${WORKING_DIRECTORY-}")"
custom="$(trim "${CUSTOM_APP_PATH-}")"

require_safe_rel_path "workingDirectory" "$workdir" || exit 1
if [[ -n "$custom" ]]; then
  require_safe_rel_path "customAppPath" "$custom" || exit 1
fi

candidates=()
if [[ "$workdir" != "." ]]; then
  candidates+=("${workdir}/package-lock.json" "${workdir}/pnpm-lock.yaml" "${workdir}/yarn.lock")
fi
candidates+=("package-lock.json" "pnpm-lock.yaml" "yarn.lock")
if [[ -n "$custom" ]]; then
  candidates+=("${custom}/package-lock.json" "${custom}/pnpm-lock.yaml" "${custom}/yarn.lock")
fi

found=()
cache=""
for candidate in "${candidates[@]}"; do
  if contains_crlf "$candidate" || [[ "$candidate" == *","* ]]; then
    echo "Error: lockfile path must not contain CR, LF, or comma." >&2
    exit 1
  fi
  if [[ -f "$candidate" ]]; then
    found+=("$candidate")
    if [[ -z "$cache" ]]; then
      case "$candidate" in
        *pnpm-lock.yaml) cache="pnpm" ;;
        *yarn.lock) cache="yarn" ;;
        *) cache="npm" ;;
      esac
    fi
  fi
done

path=""
if [[ "${#found[@]}" -gt 0 ]]; then
  path="$(IFS=','; printf '%s' "${found[*]}")"
fi

write_output cache "$cache"
write_output path "$path"
printf 'cache=%s\n' "$cache"
printf 'path=%s\n' "$path"
