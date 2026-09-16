#!/usr/bin/env bash
# Shared helpers for ForgeDeploy. Safe to source from tests.

set -euo pipefail

OUTPUT_DELIM="FORGEDEPLOY_EOF"

trim() {
  local value="${1-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

lowercase() {
  printf '%s' "${1-}" | tr '[:upper:]' '[:lower:]'
}

# Empty and unknown values are false-closed except the explicit "invalid" signal.
normalize_bool() {
  local raw
  raw="$(lowercase "$(trim "${1-}")")"
  case "$raw" in
    true|1|yes|y) printf 'true' ;;
    false|0|no|n|'') printf 'false' ;;
    *) printf 'invalid' ;;
  esac
}

is_true() {
  [[ "$(normalize_bool "${1-}")" == "true" ]]
}

is_false() {
  [[ "$(normalize_bool "${1-}")" == "false" ]]
}

require_bool() {
  local label="$1"
  local raw="${2-}"
  local normalized
  normalized="$(normalize_bool "$raw")"
  if [[ "$normalized" == "invalid" ]]; then
    echo "Error: ${label} must be a boolean (true/false/yes/no/1/0)." >&2
    return 1
  fi
}

contains_crlf() {
  local value="${1-}"
  [[ "$value" == *$'\r'* || "$value" == *$'\n'* ]]
}

# Bash C-strings cannot hold NUL; a *$'\0'* test is always true and is not used.

# Strip scheme, port, and path only. Does NOT strip userinfo — callers must reject '@'.
normalize_site_url() {
  local site
  site="$(trim "${1-}")"
  site="${site#https://}"
  site="${site#http://}"
  site="${site%%/*}"
  site="${site%%:*}"
  printf '%s' "$site"
}

raw_site_has_userinfo() {
  local raw
  raw="$(trim "${1-}")"
  [[ "$raw" == *"@"* ]]
}

is_atlassian_host() {
  local host
  host="$(lowercase "$(trim "${1-}")")"
  [[ "$host" == *.atlassian.net ]]
}

validate_site_url() {
  local raw host
  raw="$(trim "${1-}")"
  if [[ -z "$raw" ]]; then
    echo "Error: siteUrl is empty." >&2
    return 1
  fi
  if contains_crlf "$raw"; then
    echo "Error: siteUrl must not contain CR or LF." >&2
    return 1
  fi
  if raw_site_has_userinfo "$raw"; then
    echo "Error: siteUrl must not contain '@' (userinfo and host hijack rejected)." >&2
    return 1
  fi
  host="$(normalize_site_url "$raw")"
  if [[ -z "$host" ]]; then
    echo "Error: siteUrl is empty after normalization." >&2
    return 1
  fi
  if ! is_atlassian_host "$host" && ! is_true "${ALLOW_NON_ATLASSIAN_SITE-}"; then
    echo "Error: siteUrl host must end in .atlassian.net (got '${host}'). Set allowNonAtlassianSite=true only for a documented exception." >&2
    return 1
  fi
}

path_has_dotdot_segment() {
  local raw="$1"
  local part
  local rest="$raw"
  while [[ -n "$rest" ]]; do
    if [[ "$rest" == */* ]]; then
      part="${rest%%/*}"
      rest="${rest#*/}"
    else
      part="$rest"
      rest=""
    fi
    if [[ "$part" == ".." ]]; then
      return 0
    fi
  done
  return 1
}

is_unsafe_rel_path() {
  local raw
  raw="${1-}"
  if contains_crlf "$raw"; then
    return 0
  fi
  if [[ "${raw#*'~'}" != "$raw" ]]; then
    return 0
  fi
  if path_has_dotdot_segment "$raw"; then
    return 0
  fi
  return 1
}

normalize_working_directory() {
  local dir
  dir="$(trim "${1-}")"
  if [[ -z "$dir" || "$dir" == "." || "$dir" == "./" ]]; then
    printf '.'
    return
  fi
  dir="${dir#./}"
  while [[ "$dir" == */ ]]; do
    dir="${dir%/}"
  done
  printf '%s' "$dir"
}

# Map aliases to the values Forge CLI accepts for --product.
normalize_product() {
  local raw
  raw="$(lowercase "$(trim "${1-}")")"
  case "$raw" in
    jira) printf 'jira' ;;
    confluence) printf 'confluence' ;;
    compass) printf 'compass' ;;
    bitbucket) printf 'bitbucket' ;;
    jsm|jira-service-management|jiraservicemanagement|"jira service management")
      printf 'Jira Service Management'
      ;;
    '') printf '' ;;
    *) printf '%s' "$(trim "${1-}")" ;;
  esac
}

is_known_product() {
  local normalized
  normalized="$(normalize_product "${1-}")"
  case "$(lowercase "$normalized")" in
    jira|confluence|compass|bitbucket|"jira service management") return 0 ;;
    *) return 1 ;;
  esac
}

# Split on commas only so "Jira Service Management" stays one product.
parse_products() {
  local raw rest item
  raw="$(trim "${1-}")"
  if [[ -z "$raw" ]]; then
    return 0
  fi
  rest="$raw"
  while [[ -n "$rest" ]]; do
    if [[ "$rest" == *","* ]]; then
      item="$(trim "${rest%%,*}")"
      rest="${rest#*,}"
    else
      item="$(trim "$rest")"
      rest=""
    fi
    [[ -z "$item" ]] && continue
    normalize_product "$item"
    printf '\n'
  done
}

normalize_phase() {
  local raw
  raw="$(lowercase "$(trim "${1-}")")"
  case "$raw" in
    ''|deploy) printf 'deploy' ;;
    install) printf 'install' ;;
    deploy-and-install|deploy_and_install|deployandinstall) printf 'deploy-and-install' ;;
    lint) printf 'lint' ;;
    *) printf 'invalid' ;;
  esac
}

# phase is authoritative. installToSite never upgrades deploy → deploy-and-install.
resolve_phase() {
  normalize_phase "${PHASE-}"
}

phase_includes_deploy() {
  case "$(resolve_phase)" in
    deploy|deploy-and-install) return 0 ;;
    *) return 1 ;;
  esac
}

phase_includes_install() {
  case "$(resolve_phase)" in
    install|deploy-and-install) return 0 ;;
    *) return 1 ;;
  esac
}

phase_includes_lint() {
  case "$(resolve_phase)" in
    lint) return 0 ;;
    *) is_true "${LINT-}" ;;
  esac
}

is_production_environment() {
  local env
  env="$(lowercase "$(trim "${1-}")")"
  case "$env" in
    production|prod|prd) return 0 ;;
    production-*|prod-*|prd-*) return 0 ;;
    *) return 1 ;;
  esac
}

# Only these GitHub Environment names are treated as protected production.
# Matching the Forge environment name (e.g. GH env "prod") is not enough.
is_protected_github_environment() {
  local gh
  gh="$(lowercase "$(trim "${1-}")")"
  case "$gh" in
    production|production-deploy|production-install) return 0 ;;
    *) return 1 ;;
  esac
}

# Bind phase to the SOD GitHub Environment suffix when one is set.
github_environment_matches_phase() {
  local gh phase
  gh="$(lowercase "$(trim "${1-}")")"
  phase="$(normalize_phase "${2-}")"
  if [[ -z "$gh" ]]; then
    return 0
  fi
  case "$phase" in
    deploy|lint)
      [[ "$gh" == *-deploy ]] && return 0
      return 1
      ;;
    install)
      [[ "$gh" == *-install ]] && return 0
      return 1
      ;;
    deploy-and-install)
      case "$gh" in
        production|production-deploy|production-install) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

path_resolves_inside_root() {
  local rel="$1"
  local root="${2:-${GITHUB_WORKSPACE:-$(pwd)}}"
  local resolved target root_p
  if [[ "$rel" == "." || -z "$rel" ]]; then
    return 0
  fi
  if ! root_p="$(cd "$root" && pwd -P)"; then
    return 1
  fi
  target="${root_p}/${rel}"
  if [[ ! -e "$target" ]]; then
    return 0
  fi
  if [[ -d "$target" ]]; then
    resolved="$(cd "$target" && pwd -P)"
  else
    resolved="$(cd "$(dirname "$target")" && pwd -P)/$(basename "$target")"
  fi
  case "$resolved" in
    "$root_p"|"$root_p"/*) return 0 ;;
    *) return 1 ;;
  esac
}

require_safe_rel_path() {
  local label="$1"
  local raw="$2"
  if [[ -z "$raw" || "$raw" == "." ]]; then
    return 0
  fi
  if contains_crlf "$raw"; then
    echo "Error: ${label} must not contain CR or LF." >&2
    return 1
  fi
  if [[ "$raw" == /* ]]; then
    echo "Error: ${label} must be a relative path from the repository root." >&2
    return 1
  fi
  if is_unsafe_rel_path "$raw"; then
    echo "Error: ${label} must not contain '..', '~', CR, or LF." >&2
    return 1
  fi
  if ! path_resolves_inside_root "$raw"; then
    echo "Error: ${label} '${raw}' resolves outside the repository root." >&2
    return 1
  fi
}

validate_node_version() {
  local v
  v="$(trim "${1-}")"
  case "$v" in
    22|24) return 0 ;;
    22.23.1|24.17.0)
      echo "Error: nodeVersion '${v}' is blocked (node-fetch premature close). Use 22 or 24." >&2
      return 1
      ;;
    *)
      echo "Error: nodeVersion must be exactly 22 or 24 (not '${v}')." >&2
      return 1
      ;;
  esac
}

is_allowed_license() {
  case "$(lowercase "$(trim "${1-}")")" in
    ''|active|standard|advanced|inactive|trial) return 0 ;;
    *) return 1 ;;
  esac
}

# Job env wins over legacy action inputs (composite inputs are not secret-typed).
resolve_forge_email() {
  local from_env from_input
  from_env="$(trim "${FORGE_EMAIL-}")"
  from_input="$(trim "${INPUT_FORGE_EMAIL-}")"
  if [[ -n "$from_env" ]]; then
    printf '%s' "$from_env"
    return
  fi
  printf '%s' "$from_input"
}

resolve_forge_token() {
  local from_env from_input from_install
  from_install="$(trim "${FORGE_INSTALL_API_TOKEN-}")"
  from_env="$(trim "${FORGE_API_TOKEN-}")"
  from_input="$(trim "${INPUT_FORGE_API_TOKEN-}")"
  if [[ "${1-}" == "install" && -n "$from_install" ]]; then
    printf '%s' "$from_install"
    return
  fi
  if [[ -n "$from_env" ]]; then
    printf '%s' "$from_env"
    return
  fi
  printf '%s' "$from_input"
}

mask_secret() {
  local value
  value="$(trim "${1-}")"
  if [[ -n "$value" ]]; then
    printf '::add-mask::%s\n' "$value"
  fi
}

write_output() {
  local name="$1"
  local value="${2-}"
  case "$(lowercase "$name")" in
    *token*|*password*|*secret*|*email*|*credential*)
      echo "Error: refusing to write credential-like output '${name}'." >&2
      return 1
      ;;
  esac
  if contains_crlf "$name"; then
    echo "Error: output name must not contain CR or LF." >&2
    return 1
  fi
  if contains_crlf "$value"; then
    echo "Error: output '${name}' must not contain CR or LF." >&2
    return 1
  fi
  if [[ -n "${GITHUB_OUTPUT-}" ]]; then
    {
      printf '%s<<%s\n' "$name" "$OUTPUT_DELIM"
      printf '%s\n' "$value"
      printf '%s\n' "$OUTPUT_DELIM"
    } >> "$GITHUB_OUTPUT"
  fi
}

require_nonempty() {
  local label="$1"
  local value
  value="$(trim "${2-}")"
  if [[ -z "$value" ]]; then
    echo "Error: ${label} is required." >&2
    return 1
  fi
}

# Validate action inputs. Reads environment variables (never argv secrets).
# Returns 0 on success. Prints one error per problem.
validate_inputs() {
  local errors=0
  local email token environment site product workdir custom_path phase

  email="$(resolve_forge_email)"
  token="$(resolve_forge_token)"
  environment="$(trim "${ENVIRONMENT-}")"
  site="$(trim "${SITE_URL-}")"
  product="$(trim "${PRODUCT-}")"
  workdir="$(normalize_working_directory "${WORKING_DIRECTORY-}")"
  custom_path="$(trim "${CUSTOM_APP_PATH-}")"
  phase="$(resolve_phase)"

  require_bool "installToSite" "${INSTALL_TO_SITE-}" || errors=1
  require_bool "allowProduction" "${ALLOW_PRODUCTION-}" || errors=1
  require_bool "allowCombinedPhase" "${ALLOW_COMBINED_PHASE-}" || errors=1
  require_bool "allowNoLockfile" "${ALLOW_NO_LOCKFILE-}" || errors=1
  require_bool "allowNonAtlassianSite" "${ALLOW_NON_ATLASSIAN_SITE-}" || errors=1
  require_bool "isCustomApp" "${IS_CUSTOM_APP-}" || errors=1
  require_bool "upgradeIfInstalled" "${UPGRADE_IF_INSTALLED-}" || errors=1
  require_bool "confirmScopes" "${CONFIRM_SCOPES-}" || errors=1
  require_bool "lint" "${LINT-}" || errors=1
  require_bool "verbose" "${VERBOSE-}" || errors=1
  require_bool "skipVerify" "${SKIP_VERIFY-}" || errors=1
  require_bool "cache" "${CACHE-}" || errors=1

  if [[ "$phase" == "invalid" ]]; then
    echo "Error: phase must be one of: deploy, install, deploy-and-install, lint." >&2
    errors=1
  fi

  if [[ "$phase" == "deploy" ]] && is_true "${INSTALL_TO_SITE-}"; then
    echo "Error: phase=deploy does not install. installToSite is not a shortcut. Use a separate install job (phase=install) or break-glass phase=deploy-and-install with allowCombinedPhase=true." >&2
    errors=1
  fi

  if [[ "$phase" == "deploy-and-install" ]] && ! is_true "${ALLOW_COMBINED_PHASE-}"; then
    echo "Error: phase=deploy-and-install requires allowCombinedPhase=true (break-glass). Prefer separate deploy and install jobs with different GitHub Environments." >&2
    errors=1
  fi

  if [[ -n "${NODE_VERSION-}" ]]; then
    validate_node_version "${NODE_VERSION}" || errors=1
  fi

  if [[ "$phase" != "lint" ]]; then
    if [[ -z "$email" ]]; then
      echo "Error: FORGE_EMAIL (job env, preferred) or email input is required." >&2
      errors=1
    fi
    if [[ -z "$token" ]]; then
      echo "Error: FORGE_API_TOKEN (job env, preferred) or apiToken input is required." >&2
      errors=1
    fi
  fi

  if [[ -z "$environment" && "$phase" != "lint" ]]; then
    echo "Error: environment is required." >&2
    errors=1
  fi

  if [[ "$phase" != "lint" ]] && is_production_environment "$environment"; then
    if ! is_true "${ALLOW_PRODUCTION-}"; then
      echo "Error: production-class environment '${environment}' requires allowProduction=true." >&2
      errors=1
    fi
    if [[ -z "$(trim "${GITHUB_ENVIRONMENT-}")" ]]; then
      echo "Error: production-class deploys require job environment: (GITHUB_ENVIRONMENT). allowProduction=true is insufficient alone." >&2
      errors=1
    elif ! is_protected_github_environment "${GITHUB_ENVIRONMENT}"; then
      echo "Error: GITHUB_ENVIRONMENT '${GITHUB_ENVIRONMENT}' is not a protected production environment (production, production-deploy, or production-install)." >&2
      errors=1
    fi
  fi

  if [[ -n "$(trim "${GITHUB_ENVIRONMENT-}")" ]] && ! github_environment_matches_phase "${GITHUB_ENVIRONMENT}" "$phase"; then
    echo "Error: GITHUB_ENVIRONMENT '${GITHUB_ENVIRONMENT}' is not allowed for phase=${phase}. Use a '*-deploy' environment for deploy/lint, '*-install' for install, and production/production-deploy/production-install only for break-glass deploy-and-install." >&2
    errors=1
  fi

  if phase_includes_install; then
    if ! validate_site_url "$site"; then
      errors=1
    fi
    if [[ -z "$product" ]]; then
      echo "Error: product is required when installing (phase=install or deploy-and-install)." >&2
      errors=1
    fi
  fi

  if [[ -n "$product" ]]; then
    local item unknown=0
    while IFS= read -r item; do
      [[ -z "$item" ]] && continue
      if ! is_known_product "$item"; then
        echo "Error: unsupported product '${item}'. Valid values: jira, confluence, compass, bitbucket, jira-service-management." >&2
        unknown=1
      fi
    done < <(parse_products "$product")
    if [[ "$unknown" -eq 1 ]]; then
      errors=1
    fi
  fi

  if [[ -n "$(trim "${LICENSE-}")" ]] && ! is_allowed_license "${LICENSE}"; then
    echo "Error: license must be one of: active, standard, advanced, inactive, trial." >&2
    errors=1
  fi

  if is_true "${IS_CUSTOM_APP-}" && { phase_includes_deploy || [[ "$phase" == "lint" ]]; }; then
    if [[ -z "$custom_path" ]]; then
      echo "Error: customAppPath is required when isCustomApp is true." >&2
      errors=1
    elif [[ "$custom_path" == /* ]]; then
      echo "Error: customAppPath must be a relative path from the repository root (e.g. apps/my-forge-app)." >&2
      errors=1
    elif is_unsafe_rel_path "$custom_path"; then
      echo "Error: customAppPath must not contain '..', '~', CR/LF, or NUL." >&2
      errors=1
    fi
  fi

  if [[ "$workdir" != "." ]]; then
    if [[ "$workdir" == /* ]]; then
      echo "Error: workingDirectory must be a relative path from the repository root." >&2
      errors=1
    elif is_unsafe_rel_path "$workdir"; then
      echo "Error: workingDirectory must not contain '..', '~', CR/LF, or NUL." >&2
      errors=1
    fi
  fi

  if [[ "$errors" -ne 0 ]]; then
    return 1
  fi
}

# Build forge deploy argv (one argument per line) for tests and execution.
build_deploy_args() {
  printf '%s\n' deploy
  printf '%s\n' --environment
  printf '%s\n' "$(trim "${ENVIRONMENT-}")"
  printf '%s\n' --non-interactive
  if is_true "${VERBOSE-}"; then
    printf '%s\n' --verbose
  fi
  if is_true "${SKIP_VERIFY-}"; then
    printf '%s\n' --no-verify
  fi
  local rest rule
  rest="$(trim "${APPROVE-}")"
  set -f
  while [[ -n "$rest" ]]; do
    if [[ "$rest" == *","* ]]; then
      rule="$(trim "${rest%%,*}")"
      rest="${rest#*,}"
    else
      rule="$(trim "$rest")"
      rest=""
    fi
    [[ -z "$rule" ]] && continue
    printf '%s\n' --approve
    printf '%s\n' "$rule"
  done
  set +f
}

# Build forge install argv for a single product (one argument per line).
build_install_args() {
  local product_name="$1"
  local site
  site="$(normalize_site_url "${SITE_URL-}")"

  printf '%s\n' install
  printf '%s\n' --product
  printf '%s\n' "$product_name"
  printf '%s\n' --site
  printf '%s\n' "$site"
  printf '%s\n' --environment
  printf '%s\n' "$(trim "${ENVIRONMENT-}")"
  printf '%s\n' --non-interactive
  if ! is_false "${UPGRADE_IF_INSTALLED:-true}"; then
    printf '%s\n' --upgrade
  fi
  if is_true "${CONFIRM_SCOPES-}"; then
    printf '%s\n' --confirm-scopes
  fi
  if is_true "${VERBOSE-}"; then
    printf '%s\n' --verbose
  fi
  if [[ -n "$(trim "${LICENSE-}")" ]]; then
    printf '%s\n' --license
    printf '%s\n' "$(trim "${LICENSE}")"
  fi
}

log_argv() {
  printf 'argv:'
  local arg
  for arg in "$@"; do
    printf ' %q' "$arg"
  done
  printf '\n'
}

run_cmd() {
  local -a args=("$@")
  log_argv "${args[@]}"
  if [[ "${DRY_RUN-}" == "1" ]]; then
    printf 'dry-run:'
    local arg
    for arg in "${args[@]}"; do
      printf ' %q' "$arg"
    done
    printf '\n'
    return 0
  fi
  "${args[@]}"
}
