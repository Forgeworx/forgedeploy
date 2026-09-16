#!/usr/bin/env bash
# Deploy and/or install a Forge app. Credentials come from the
# environment only — never interpolate secrets into the command line.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

REPO_ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
FORGE_BIN="${FORGE_BIN:-forge}"
CLI_SPEC="${FORGE_CLI_VERSION:-13.2.0}"
WORKDIR="$(normalize_working_directory "${WORKING_DIRECTORY-}")"
CUSTOM_PATH="$(trim "${CUSTOM_APP_PATH-}")"
PHASE="$(resolve_phase)"
INSTALLED="false"
DEPLOYED="false"
CLI_VERSION=""
RESOLVED_EMAIL=""
RESOLVED_TOKEN=""
RESOLVED_INSTALL_TOKEN=""

fail() {
  echo "Error: $*" >&2
  exit 1
}

test_skip() {
  local flag="${1-}"
  [[ "${FORGEDEPLOY_TEST-}" == "1" && "$flag" == "1" ]]
}

assert_inside_repo() {
  local label="$1"
  local rel="$2"
  local root resolved target
  root="$(cd "$REPO_ROOT" && pwd -P)"
  if [[ "$rel" == "." ]]; then
    return 0
  fi
  target="${REPO_ROOT}/${rel}"
  if [[ ! -e "$target" ]]; then
    fail "${label} '${rel}' does not exist relative to the repository root."
  fi
  if [[ -d "$target" ]]; then
    resolved="$(cd "$target" && pwd -P)"
  else
    resolved="$(cd "$(dirname "$target")" && pwd -P)/$(basename "$target")"
  fi
  case "$resolved" in
    "$root"|"$root"/*) return 0 ;;
    *) fail "${label} '${rel}' resolves outside the repository root." ;;
  esac
}

require_manifest() {
  local dir="$1"
  local abs="${REPO_ROOT}"
  if [[ "$dir" != "." ]]; then
    abs="${REPO_ROOT}/${dir}"
  fi
  if [[ ! -f "${abs}/manifest.yml" && ! -f "${abs}/manifest.yaml" ]]; then
    fail "workingDirectory '${dir}' must contain manifest.yml (or manifest.yaml)."
  fi
}

package_manager_for_dir() {
  local abs="$1"
  if [[ -f "${abs}/yarn.lock" ]]; then
    printf 'yarn'
  elif [[ -f "${abs}/pnpm-lock.yaml" ]]; then
    printf 'pnpm'
  elif [[ -f "${abs}/package-lock.json" ]]; then
    printf 'npm'
  else
    printf 'none'
  fi
}

install_js_dependencies() {
  local dir="$1"
  local abs="${REPO_ROOT}/${dir}"
  if [[ "$dir" == "." ]]; then
    abs="${REPO_ROOT}"
  fi
  if [[ ! -f "${abs}/package.json" ]]; then
    echo "No package.json in ${dir}; skipping dependency install."
    return 0
  fi

  local manager
  manager="$(package_manager_for_dir "$abs")"
  echo "Installing dependencies in ${dir} with ${manager}..."
  (
    unset FORGE_EMAIL FORGE_API_TOKEN FORGE_INSTALL_API_TOKEN INPUT_FORGE_EMAIL INPUT_FORGE_API_TOKEN
    cd "$abs"
    case "$manager" in
      yarn)
        command -v yarn >/dev/null 2>&1 || fail "yarn.lock found in ${dir} but yarn is not on PATH."
        yarn install --frozen-lockfile
        ;;
      pnpm)
        command -v pnpm >/dev/null 2>&1 || fail "pnpm-lock.yaml found in ${dir} but pnpm is not on PATH."
        pnpm install --frozen-lockfile
        ;;
      npm)
        npm ci
        ;;
      none)
        if [[ "${GITHUB_ACTIONS-}" == "true" ]] && ! is_true "${ALLOW_NO_LOCKFILE-}"; then
          fail "No lockfile in ${dir}. Commit package-lock.json (or yarn.lock / pnpm-lock.yaml) or set allowNoLockfile=true."
        fi
        npm install
        ;;
    esac
  )
}

build_frontend() {
  local dir="$1"
  local abs="${REPO_ROOT}/${dir}"
  local manager
  manager="$(package_manager_for_dir "$abs")"
  echo "Building frontend in ${dir} with ${manager}..."
  (
    unset FORGE_EMAIL FORGE_API_TOKEN FORGE_INSTALL_API_TOKEN INPUT_FORGE_EMAIL INPUT_FORGE_API_TOKEN
    cd "$abs"
    case "$manager" in
      yarn) yarn build ;;
      pnpm) pnpm run build ;;
      *) npm run build ;;
    esac
  )
}

run_forge() {
  local email="$1"
  local token="$2"
  shift 2
  (
    export FORGE_EMAIL="$email"
    export FORGE_API_TOKEN="$token"
    run_cmd "$FORGE_BIN" "$@"
  )
}

echo "::group::Validate inputs"
echo "Resolved phase=${PHASE} environment=$(trim "${ENVIRONMENT-}") allowProduction=$(normalize_bool "${ALLOW_PRODUCTION-}")"
validate_inputs || exit 1
if is_unsafe_rel_path "$WORKDIR" && [[ "$WORKDIR" != "." ]]; then
  fail "workingDirectory failed path safety checks."
fi
if [[ "$WORKDIR" != "." ]]; then
  assert_inside_repo "workingDirectory" "$WORKDIR"
fi
if ! test_skip "${SKIP_MANIFEST_CHECK-}"; then
  require_manifest "$WORKDIR"
fi
if is_true "${IS_CUSTOM_APP-}" && { phase_includes_deploy || [[ "$PHASE" == "lint" ]]; }; then
  if is_unsafe_rel_path "$CUSTOM_PATH"; then
    fail "customAppPath failed path safety checks."
  fi
  assert_inside_repo "customAppPath" "$CUSTOM_PATH"
fi
echo "::endgroup::"

RESOLVED_EMAIL="$(resolve_forge_email)"
RESOLVED_TOKEN="$(resolve_forge_token)"
RESOLVED_INSTALL_TOKEN="$(resolve_forge_token install)"
mask_secret "$RESOLVED_EMAIL"
mask_secret "$RESOLVED_TOKEN"
mask_secret "$RESOLVED_INSTALL_TOKEN"
unset FORGE_EMAIL FORGE_API_TOKEN FORGE_INSTALL_API_TOKEN INPUT_FORGE_EMAIL INPUT_FORGE_API_TOKEN

needs_cli=0
if phase_includes_deploy || phase_includes_install || phase_includes_lint; then
  needs_cli=1
fi

if [[ "$needs_cli" -eq 1 ]] && ! test_skip "${SKIP_CLI_INSTALL-}"; then
  echo "::group::Install Forge CLI"
  echo "Installing @forge/cli@${CLI_SPEC}"
  (
    unset FORGE_EMAIL FORGE_API_TOKEN FORGE_INSTALL_API_TOKEN
    npm install -g "@forge/cli@${CLI_SPEC}"
  )
  echo "::endgroup::"
fi

if command -v "$FORGE_BIN" >/dev/null 2>&1; then
  _ver="$("$FORGE_BIN" --version 2>/dev/null || true)"
  _ver="${_ver//$'\r'/}"
  CLI_VERSION="${_ver%%$'\n'*}"
  CLI_VERSION="$(trim "$CLI_VERSION")"
fi
echo "Forge CLI version: ${CLI_VERSION:-unknown}"

if [[ "$needs_cli" -eq 1 ]] && ! test_skip "${SKIP_FORGE_SETTINGS-}"; then
  echo "::group::Configure Forge CLI"
  (
    cd "${REPO_ROOT}"
    if [[ "$WORKDIR" != "." ]]; then
      cd "${REPO_ROOT}/${WORKDIR}"
    fi
    run_forge "$RESOLVED_EMAIL" "$RESOLVED_TOKEN" settings set usage-analytics false
  )
  echo "::endgroup::"
fi

if { phase_includes_deploy || [[ "$PHASE" == "lint" ]]; } && ! test_skip "${SKIP_DEP_INSTALL-}"; then
  echo "::group::Install app dependencies"
  install_js_dependencies "$WORKDIR"
  if [[ "$WORKDIR" != "." && -f "${REPO_ROOT}/package.json" ]]; then
    install_js_dependencies "."
  fi
  if is_true "${IS_CUSTOM_APP-}"; then
    install_js_dependencies "$CUSTOM_PATH"
    build_frontend "$CUSTOM_PATH"
  fi
  echo "::endgroup::"
fi

forge_workdir="${REPO_ROOT}"
if [[ "$WORKDIR" != "." ]]; then
  forge_workdir="${REPO_ROOT}/${WORKDIR}"
fi

if phase_includes_lint; then
  echo "::group::Lint Forge app"
  (
    cd "$forge_workdir"
    lint_args=(lint)
    if is_true "${VERBOSE-}"; then
      lint_args+=(--verbose)
    fi
    run_forge "$RESOLVED_EMAIL" "$RESOLVED_TOKEN" "${lint_args[@]}"
  )
  echo "::endgroup::"
fi

if phase_includes_deploy; then
  echo "::group::Deploy Forge app"
  (
    cd "$forge_workdir"
    deploy_args=()
    while IFS= read -r line; do
      deploy_args+=("$line")
    done < <(build_deploy_args)
    run_forge "$RESOLVED_EMAIL" "$RESOLVED_TOKEN" "${deploy_args[@]}"
  )
  if [[ "${DRY_RUN-}" != "1" ]]; then
    DEPLOYED="true"
  fi
  echo "::endgroup::"
else
  echo "Skipping deploy (phase=${PHASE})."
fi

if phase_includes_install; then
  echo "::group::Install Forge app"
  site="$(normalize_site_url "${SITE_URL-}")"
  while IFS= read -r product_name; do
    [[ -z "$product_name" ]] && continue
    echo "Installing for product ${product_name} on ${site}..."
    (
      cd "$forge_workdir"
      install_args=()
      while IFS= read -r line; do
        install_args+=("$line")
      done < <(build_install_args "$product_name")
      run_forge "$RESOLVED_EMAIL" "$RESOLVED_INSTALL_TOKEN" "${install_args[@]}"
    )
  done < <(parse_products "${PRODUCT-}")
  if [[ "${DRY_RUN-}" != "1" ]]; then
    INSTALLED="true"
  fi
  echo "::endgroup::"
else
  echo "Skipping site installation (phase=${PHASE})."
fi

write_output environment "$(trim "${ENVIRONMENT-}")"
write_output deployed "$DEPLOYED"
write_output installed "$INSTALLED"
write_output cli-version "$CLI_VERSION"
write_output working-directory "$WORKDIR"
write_output phase "$PHASE"

echo "phase=${PHASE} deployed=${DEPLOYED} installed=${INSTALLED} environment=$(trim "${ENVIRONMENT-}")"
