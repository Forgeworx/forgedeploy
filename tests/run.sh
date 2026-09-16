#!/usr/bin/env bash
# Offline unit and argv tests for ForgeDeploy. No Atlassian network calls.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "${ROOT}/scripts/lib.sh"

PASS=0
FAIL=0

assert_eq() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "ok - ${label}"
  else
    FAIL=$((FAIL + 1))
    echo "not ok - ${label}"
    echo "  expected: ${expected}"
    echo "  actual:   ${actual}"
  fi
}

assert_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
    echo "ok - ${label}"
  else
    FAIL=$((FAIL + 1))
    echo "not ok - ${label}"
    echo "  missing: ${needle}"
    echo "  in: ${haystack}"
  fi
}

assert_not_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    PASS=$((PASS + 1))
    echo "ok - ${label}"
  else
    FAIL=$((FAIL + 1))
    echo "not ok - ${label}"
    echo "  should not contain: ${needle}"
  fi
}

assert_success() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    PASS=$((PASS + 1))
    echo "ok - ${label}"
  else
    FAIL=$((FAIL + 1))
    echo "not ok - ${label} (expected success)"
  fi
}

assert_failure() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    FAIL=$((FAIL + 1))
    echo "not ok - ${label} (expected failure)"
  else
    PASS=$((PASS + 1))
    echo "ok - ${label}"
  fi
}

output_value() {
  local file="$1"
  local key="$2"
  local line capturing=0
  local value=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$capturing" -eq 1 ]]; then
      if [[ "$line" == "FORGEDEPLOY_EOF" ]]; then
        printf '%s' "$value"
        return 0
      fi
      if [[ -n "$value" ]]; then
        value+=$'\n'
      fi
      value+="$line"
    elif [[ "$line" == "${key}<<FORGEDEPLOY_EOF" ]]; then
      capturing=1
    fi
  done < "$file"
  printf '%s' "$value"
}

echo "# normalization"

assert_eq "site strips https" "acme.atlassian.net" "$(normalize_site_url 'https://acme.atlassian.net/')"
assert_eq "site does not strip at-sign" "acme.atlassian.net" "$(normalize_site_url 'https://acme.atlassian.net/@evil.example')"
assert_success "atlassian host" is_atlassian_host "acme.atlassian.net"
assert_failure "evil host not atlassian" is_atlassian_host "evil.example"
assert_success "userinfo detected" raw_site_has_userinfo "https://user:pass@acme.atlassian.net"
assert_success "at-path hijack detected" raw_site_has_userinfo "https://acme.atlassian.net/@evil.example"

assert_eq "bool True" "true" "$(normalize_bool 'True')"
assert_eq "bool FALSE" "false" "$(normalize_bool 'FALSE')"
assert_eq "bool empty is false" "false" "$(normalize_bool '')"
assert_failure "is_true rejects empty" is_true ""

assert_eq "default phase is deploy" "deploy" "$(PHASE='' resolve_phase)"
assert_eq "GHA default PHASE=deploy stays deploy" "deploy" "$(PHASE=deploy INSTALL_TO_SITE=true resolve_phase)"
assert_eq "phase install wins" "install" "$(PHASE=install resolve_phase)"

assert_success "production alias" is_production_environment "production"
assert_success "prod alias" is_production_environment "prod"
assert_success "prd alias" is_production_environment "prd"
assert_success "production-us alias" is_production_environment "production-us"
assert_success "prod-eu alias" is_production_environment "prod-eu"
assert_success "prd-us alias" is_production_environment "prd-us"
assert_failure "product is not production" is_production_environment "product"

assert_success "protected production-deploy" is_protected_github_environment "production-deploy"
assert_success "protected production-install" is_protected_github_environment "production-install"
assert_success "protected bare production" is_protected_github_environment "production"
assert_failure "staging gh env not protected for prod" is_protected_github_environment "staging"
assert_failure "prod is not a protected GH env name" is_protected_github_environment "prod"
assert_failure "prd is not a protected GH env name" is_protected_github_environment "prd"
assert_failure "production-us is not a protected GH env name" is_protected_github_environment "production-us"

assert_success "deploy matches production-deploy" github_environment_matches_phase "production-deploy" "deploy"
assert_failure "deploy rejects production-install" github_environment_matches_phase "production-install" "deploy"
assert_failure "deploy rejects bare production" github_environment_matches_phase "production" "deploy"
assert_failure "install rejects production-deploy" github_environment_matches_phase "production-deploy" "install"
assert_success "install matches production-install" github_environment_matches_phase "production-install" "install"
assert_success "combined accepts bare production" github_environment_matches_phase "production" "deploy-and-install"
assert_failure "bare development GH env fails for deploy" github_environment_matches_phase "development" "deploy"
assert_success "development-deploy matches deploy" github_environment_matches_phase "development-deploy" "deploy"

assert_success "node 24 allowed" validate_node_version 24
assert_success "node 22 allowed" validate_node_version 22
assert_failure "node 18 rejected" validate_node_version 18
assert_failure "node 20 rejected" validate_node_version 20
assert_failure "node 22.23.1 rejected" validate_node_version 22.23.1
assert_failure "node 24.17.0 rejected" validate_node_version 24.17.0

assert_success "dotdot rejected" is_unsafe_rel_path "../etc"
assert_success "tilde rejected" is_unsafe_rel_path $'~/secrets'
assert_success "nested dotdot rejected" is_unsafe_rel_path "apps/../../etc"
assert_failure "normal relative path ok" is_unsafe_rel_path "apps/my-forge-app"

assert_eq "jsm display name parses" "Jira Service Management" "$(parse_products 'Jira Service Management' | tr -d '\n')"

echo "# credentials"

FORGE_EMAIL="env@example.com"
INPUT_FORGE_EMAIL="input@example.com"
assert_eq "job env email wins" "env@example.com" "$(resolve_forge_email)"
FORGE_API_TOKEN="env-token"
FORGE_INSTALL_API_TOKEN="install-token"
assert_eq "install token preferred" "install-token" "$(resolve_forge_token install)"
assert_eq "deploy token ignores install unless asked" "env-token" "$(resolve_forge_token)"
unset INPUT_FORGE_EMAIL FORGE_INSTALL_API_TOKEN

echo "# write_output"

out_tmp="$(mktemp)"
GITHUB_OUTPUT="$out_tmp"
: > "$out_tmp"
write_output environment "development"
assert_contains "heredoc output key" "$(cat "$out_tmp")" "environment<<FORGEDEPLOY_EOF"
assert_eq "heredoc output value" "development" "$(output_value "$out_tmp" environment)"
assert_failure "LF in scalar output rejected" write_output environment $'dev\nmalicious=injected'
assert_failure "LF in path output rejected" write_output path $'package-lock.json\nmalicious=injected'
assert_failure "CR in output rejected" write_output environment $'dev\rinjected'
assert_failure "credential output name rejected" write_output apiToken "secret"
rm -f "$out_tmp"
unset GITHUB_OUTPUT

echo "# validate_inputs"

reset_validate_env() {
  unset PHASE INSTALL_TO_SITE SITE_URL PRODUCT ALLOW_PRODUCTION IS_CUSTOM_APP CUSTOM_APP_PATH
  unset WORKING_DIRECTORY INPUT_FORGE_EMAIL INPUT_FORGE_API_TOKEN LINT VERBOSE SKIP_VERIFY
  unset UPGRADE_IF_INSTALLED CONFIRM_SCOPES CACHE ALLOW_COMBINED_PHASE ALLOW_NO_LOCKFILE
  unset ALLOW_NON_ATLASSIAN_SITE GITHUB_ENVIRONMENT NODE_VERSION LICENSE
  FORGE_EMAIL="dev@example.com"
  FORGE_API_TOKEN="token-value"
  ENVIRONMENT="development"
}

valid_deploy() {
  reset_validate_env
  PHASE="deploy"
}

valid_install() {
  reset_validate_env
  PHASE="install"
  SITE_URL="acme.atlassian.net"
  PRODUCT="jira"
}

valid_deploy
assert_success "default deploy does not need site or product" validate_inputs

valid_deploy
INSTALL_TO_SITE="true"
assert_failure "PHASE=deploy + installToSite=true errors" validate_inputs

valid_deploy
PHASE="deploy-and-install"
SITE_URL="acme.atlassian.net"
PRODUCT="jira"
assert_failure "combined phase without break-glass errors" validate_inputs

valid_deploy
PHASE="deploy-and-install"
ALLOW_COMBINED_PHASE="true"
SITE_URL="acme.atlassian.net"
PRODUCT="jira"
assert_success "combined phase with break-glass" validate_inputs

valid_install
assert_success "valid install inputs" validate_inputs

valid_install
SITE_URL="https://acme.atlassian.net/@evil.example"
assert_failure "site at-hijack rejected" validate_inputs

valid_install
SITE_URL="https://user:pass@acme.atlassian.net"
assert_failure "site userinfo rejected" validate_inputs

valid_install
SITE_URL="evil.example"
assert_failure "non-atlassian host rejected" validate_inputs

valid_install
SITE_URL=""
assert_failure "missing siteUrl when installing" validate_inputs

valid_install
PRODUCT=""
assert_failure "missing product when installing" validate_inputs

valid_deploy
IS_CUSTOM_APP="True"
CUSTOM_APP_PATH=""
assert_failure "isCustomApp True requires customAppPath" validate_inputs

valid_deploy
IS_CUSTOM_APP="true"
CUSTOM_APP_PATH="../etc"
assert_failure "customAppPath .. rejected" validate_inputs

valid_deploy
WORKING_DIRECTORY="../outside"
assert_failure "workingDirectory .. rejected" validate_inputs

valid_deploy
WORKING_DIRECTORY=$'~/secrets'
assert_failure "workingDirectory tilde rejected" validate_inputs

valid_deploy
ENVIRONMENT="prod"
ALLOW_PRODUCTION=""
assert_failure "prod blocked without allowProduction" validate_inputs

valid_deploy
ENVIRONMENT="prd"
ALLOW_PRODUCTION="true"
GITHUB_ENVIRONMENT=""
assert_failure "prd with flag but empty GITHUB_ENVIRONMENT fails" validate_inputs

valid_deploy
ENVIRONMENT="production-us"
ALLOW_PRODUCTION="true"
GITHUB_ENVIRONMENT=""
assert_failure "production-us empty GITHUB_ENVIRONMENT fails" validate_inputs

valid_deploy
ENVIRONMENT="production"
ALLOW_PRODUCTION="true"
GITHUB_ENVIRONMENT="production-deploy"
assert_success "production allowed with protected gh env" validate_inputs

valid_deploy
ENVIRONMENT="prod"
ALLOW_PRODUCTION="true"
GITHUB_ENVIRONMENT="prod"
assert_failure "prod GH env matching Forge env is not protected" validate_inputs

valid_deploy
ENVIRONMENT="prd-us"
ALLOW_PRODUCTION="false"
GITHUB_ENVIRONMENT=""
assert_failure "prd-us blocked without allowProduction" validate_inputs

valid_deploy
ENVIRONMENT="production"
ALLOW_PRODUCTION="true"
GITHUB_ENVIRONMENT="production-deploy"
PHASE="deploy"
assert_success "production + production-deploy + deploy passes" validate_inputs

valid_deploy
ENVIRONMENT="production"
ALLOW_PRODUCTION="true"
GITHUB_ENVIRONMENT="production-install"
PHASE="deploy"
assert_failure "deploy rejects production-install GH env" validate_inputs

valid_install
ENVIRONMENT="production"
ALLOW_PRODUCTION="true"
GITHUB_ENVIRONMENT="production-deploy"
assert_failure "install rejects production-deploy GH env" validate_inputs

valid_install
ENVIRONMENT="production"
ALLOW_PRODUCTION="true"
GITHUB_ENVIRONMENT="production-install"
assert_success "install accepts production-install GH env" validate_inputs

valid_deploy
ENVIRONMENT="development"
GITHUB_ENVIRONMENT="development"
assert_failure "bare development GH env fails closed" validate_inputs

valid_deploy
ENVIRONMENT="development"
GITHUB_ENVIRONMENT="development-deploy"
assert_success "development-deploy accepted for deploy" validate_inputs

valid_deploy
ENVIRONMENT="prod"
ALLOW_PRODUCTION="true"
GITHUB_ENVIRONMENT="staging"
assert_failure "prod with unprotected gh env fails" validate_inputs

valid_deploy
NODE_VERSION="18"
assert_failure "node 18 fails validate" validate_inputs

valid_deploy
PHASE="lint"
FORGE_EMAIL=""
FORGE_API_TOKEN=""
ENVIRONMENT="production"
assert_success "lint does not require credentials or production gate" validate_inputs

valid_deploy
PHASE="lint"
FORGE_EMAIL=""
FORGE_API_TOKEN=""
ENVIRONMENT="production"
ALLOW_PRODUCTION="true"
GITHUB_ENVIRONMENT="production-install"
assert_failure "lint rejects production-install GH env" validate_inputs

valid_install
PRODUCT="Jira Service Management"
assert_success "JSM display name accepted" validate_inputs

valid_deploy
FORGE_API_TOKEN=""
assert_failure "token required for deploy" validate_inputs

echo "# argv builders"

ENVIRONMENT="staging"
VERBOSE="true"
SKIP_VERIFY="true"
export APPROVE="rule-a,rule-b"
deploy_argv="$(build_deploy_args | tr '\n' ' ')"
assert_contains "deploy approve rules" "$deploy_argv" "--approve rule-a"

SITE_URL="https://acme.atlassian.net/wiki"
ENVIRONMENT="production"
UPGRADE_IF_INSTALLED="true"
CONFIRM_SCOPES=""
install_argv="$(build_install_args jira | tr '\n' ' ')"
assert_contains "install upgrades by default" "$install_argv" "--upgrade"
assert_not_contains "confirm-scopes off by default" "$install_argv" "--confirm-scopes"

CONFIRM_SCOPES="true"
install_argv="$(build_install_args jira | tr '\n' ' ')"
assert_contains "confirm-scopes opt-in" "$install_argv" "--confirm-scopes"

echo "# detect-lockfile"

lock_tmp="$(mktemp -d)"
GITHUB_OUTPUT="${lock_tmp}/out"
: > "$GITHUB_OUTPUT"
(
  cd "$lock_tmp"
  export WORKING_DIRECTORY="."
  export CUSTOM_APP_PATH=""
  bash "${ROOT}/scripts/detect-lockfile.sh" >"${lock_tmp}/stdout"
)
if grep -qx 'cache=' "${lock_tmp}/stdout"; then
  PASS=$((PASS + 1))
  echo "ok - no lockfile means empty cache"
else
  FAIL=$((FAIL + 1))
  echo "not ok - no lockfile means empty cache"
fi
mkdir -p "${lock_tmp}/apps/ui"
echo '{}' > "${lock_tmp}/package-lock.json"
echo '{}' > "${lock_tmp}/apps/ui/package-lock.json"
GITHUB_OUTPUT="${lock_tmp}/out2"
: > "$GITHUB_OUTPUT"
(
  cd "$lock_tmp"
  export WORKING_DIRECTORY="."
  export CUSTOM_APP_PATH="apps/ui"
  bash "${ROOT}/scripts/detect-lockfile.sh" >"${lock_tmp}/stdout2"
)
assert_contains "finds npm cache" "$(cat "${lock_tmp}/stdout2")" "cache=npm"
assert_contains "emits root lockfile" "$(cat "${lock_tmp}/stdout2")" "package-lock.json"
assert_contains "emits UI lockfile" "$(cat "${lock_tmp}/stdout2")" "apps/ui/package-lock.json"
rm -rf "$lock_tmp"

unsafe_tmp="$(mktemp -d)"
GITHUB_OUTPUT="${unsafe_tmp}/out"
: > "$GITHUB_OUTPUT"
set +e
(
  cd "$unsafe_tmp"
  export WORKING_DIRECTORY="../outside"
  export CUSTOM_APP_PATH=""
  bash "${ROOT}/scripts/detect-lockfile.sh" >"${unsafe_tmp}/stdout" 2>"${unsafe_tmp}/stderr"
)
unsafe_rc=$?
set -e
assert_eq "detect-lockfile rejects .." "1" "$unsafe_rc"
if [[ -s "$GITHUB_OUTPUT" ]]; then
  FAIL=$((FAIL + 1))
  echo "not ok - detect-lockfile .. must not write GITHUB_OUTPUT"
  echo "  wrote: $(cat "$GITHUB_OUTPUT")"
else
  PASS=$((PASS + 1))
  echo "ok - detect-lockfile .. must not write GITHUB_OUTPUT"
fi
assert_not_contains "detect-lockfile .. no injected output" "$(cat "$GITHUB_OUTPUT")" "cache="

: > "$GITHUB_OUTPUT"
set +e
(
  cd "$unsafe_tmp"
  export WORKING_DIRECTORY=$'apps\nmalicious=injected'
  export CUSTOM_APP_PATH=""
  bash "${ROOT}/scripts/detect-lockfile.sh" >"${unsafe_tmp}/stdout3" 2>"${unsafe_tmp}/stderr3"
)
nl_rc=$?
set -e
assert_eq "detect-lockfile rejects newline path" "1" "$nl_rc"
if [[ -s "$GITHUB_OUTPUT" ]]; then
  FAIL=$((FAIL + 1))
  echo "not ok - detect-lockfile newline must not write GITHUB_OUTPUT"
  echo "  wrote: $(cat "$GITHUB_OUTPUT")"
else
  PASS=$((PASS + 1))
  echo "ok - detect-lockfile newline must not write GITHUB_OUTPUT"
fi
assert_not_contains "detect-lockfile newline no injection" "$(cat "$GITHUB_OUTPUT")" "malicious="
rm -rf "$unsafe_tmp"
unset GITHUB_OUTPUT

unset VERBOSE SKIP_VERIFY APPROVE UPGRADE_IF_INSTALLED CONFIRM_SCOPES LICENSE
unset INSTALL_TO_SITE PRODUCT SITE_URL WORKING_DIRECTORY IS_CUSTOM_APP CUSTOM_APP_PATH
unset PHASE ALLOW_PRODUCTION INPUT_FORGE_EMAIL INPUT_FORGE_API_TOKEN LINT ENVIRONMENT
unset ALLOW_COMBINED_PHASE GITHUB_ENVIRONMENT NODE_VERSION FORGE_INSTALL_API_TOKEN

echo "# mocked forge phases"

chmod +x "${ROOT}/tests/mocks/forge" "${ROOT}/tests/mocks/npm"
run_mocked_deploy() {
  local work
  work="$(mktemp -d)"
  mkdir -p "${work}/apps/ui" "${work}/packages/app"
  : > "${work}/manifest.yml"
  : > "${work}/packages/app/manifest.yml"
  : > "${work}/forge.log"
  : > "${work}/github_output"
  : > "${work}/npm.log"
  (
    cd "$work"
    export PATH="${ROOT}/tests/mocks:${PATH}"
    export FORGE_ARGV_LOG="${work}/forge.log"
    export NPM_ARGV_LOG="${work}/npm.log"
    export GITHUB_OUTPUT="${work}/github_output"
    export MOCK_FORGE_VERSION="13.2.0"
    export FORGEDEPLOY_TEST="${FORGEDEPLOY_TEST:-1}"
    export SKIP_CLI_INSTALL="${SKIP_CLI_INSTALL:-1}"
    export SKIP_DEP_INSTALL="${SKIP_DEP_INSTALL:-1}"
    export SKIP_FORGE_SETTINGS="${SKIP_FORGE_SETTINGS:-1}"
    export FORGE_EMAIL="${FORGE_EMAIL:-dev@example.com}"
    export FORGE_API_TOKEN="${FORGE_API_TOKEN:-super-secret-token}"
    export ENVIRONMENT="${ENVIRONMENT:-development}"
    export PHASE="${PHASE:-deploy}"
    export INSTALL_TO_SITE="${INSTALL_TO_SITE:-false}"
    export ALLOW_PRODUCTION="${ALLOW_PRODUCTION:-false}"
    export ALLOW_COMBINED_PHASE="${ALLOW_COMBINED_PHASE:-false}"
    export GITHUB_ENVIRONMENT="${GITHUB_ENVIRONMENT-}"
    export SITE_URL="${SITE_URL-}"
    export PRODUCT="${PRODUCT-}"
    export IS_CUSTOM_APP="${IS_CUSTOM_APP:-false}"
    export CUSTOM_APP_PATH="${CUSTOM_APP_PATH:-}"
    export WORKING_DIRECTORY="${WORKING_DIRECTORY:-.}"
    export UPGRADE_IF_INSTALLED="${UPGRADE_IF_INSTALLED:-true}"
    export CONFIRM_SCOPES="${CONFIRM_SCOPES:-false}"
    export VERBOSE="${VERBOSE:-false}"
    export LINT="${LINT:-false}"
    export SKIP_VERIFY="${SKIP_VERIFY:-false}"
    export DRY_RUN="${DRY_RUN-}"
    set +e
    bash "${ROOT}/scripts/deploy.sh" >"${work}/deploy.out" 2>&1
    echo "$?" >"${work}/exitcode"
    set -e
  )
  printf '%s\n' "$work"
}

assert_exit() {
  local label="$1"
  local work="$2"
  local expected="$3"
  local actual
  actual="$(tr -d '[:space:]' <"${work}/exitcode")"
  assert_eq "$label" "$expected" "$actual"
}

work="$(run_mocked_deploy)"
log="$(cat "${work}/forge.log")"
outputs="$(cat "${work}/github_output")"
assert_exit "default PHASE=deploy exits 0" "$work" 0
assert_contains "default deploys" "$log" "+ deploy --environment development --non-interactive"
assert_not_contains "default does not install" "$log" "+ install"
assert_eq "default installed=false" "false" "$(output_value "${work}/github_output" installed)"
assert_eq "default deployed=true" "true" "$(output_value "${work}/github_output" deployed)"
assert_eq "default phase output" "deploy" "$(output_value "${work}/github_output" phase)"
assert_not_contains "token never on forge argv" "$log" "super-secret-token"
assert_contains "token is masked" "$(cat "${work}/deploy.out")" "::add-mask::super-secret-token"
rm -rf "$work"

PHASE="deploy"
INSTALL_TO_SITE="true"
work="$(run_mocked_deploy)"
assert_exit "deploy + installToSite errors" "$work" 1
assert_contains "SOD collapse error" "$(cat "${work}/deploy.out")" "does not install"
rm -rf "$work"
unset INSTALL_TO_SITE

PHASE="deploy-and-install"
SITE_URL="acme.atlassian.net"
PRODUCT="jira"
ALLOW_COMBINED_PHASE=""
work="$(run_mocked_deploy)"
assert_exit "combined without break-glass fails" "$work" 1
rm -rf "$work"

ALLOW_COMBINED_PHASE="true"
work="$(run_mocked_deploy)"
log="$(cat "${work}/forge.log")"
assert_exit "combined with break-glass exits 0" "$work" 0
assert_contains "combined deploys" "$log" "+ deploy --environment development --non-interactive"
assert_contains "combined installs" "$log" "+ install --product jira --site acme.atlassian.net"
assert_not_contains "combined default no confirm-scopes" "$log" "--confirm-scopes"
assert_eq "combined installed=true" "true" "$(output_value "${work}/github_output" installed)"
rm -rf "$work"
unset PHASE SITE_URL PRODUCT ALLOW_COMBINED_PHASE

PHASE="install"
SITE_URL="acme.atlassian.net"
PRODUCT="jira"
work="$(run_mocked_deploy)"
log="$(cat "${work}/forge.log")"
assert_exit "install-only exits 0" "$work" 0
assert_not_contains "install-only skips deploy" "$log" "+ deploy"
assert_contains "install-only installs" "$log" "+ install --product jira --site acme.atlassian.net"
assert_eq "install-only deployed=false" "false" "$(output_value "${work}/github_output" deployed)"
rm -rf "$work"
unset PHASE SITE_URL PRODUCT

PHASE="lint"
FORGE_EMAIL=""
FORGE_API_TOKEN=""
work="$(run_mocked_deploy)"
assert_exit "lint-only without credentials exits 0" "$work" 0
assert_contains "lint-only lints" "$(cat "${work}/forge.log")" "+ lint"
rm -rf "$work"
unset PHASE FORGE_EMAIL FORGE_API_TOKEN

PHASE="install"
SITE_URL="https://acme.atlassian.net/@evil.example"
PRODUCT="jira"
work="$(run_mocked_deploy)"
assert_exit "mocked site hijack fails" "$work" 1
assert_contains "mocked site hijack message" "$(cat "${work}/deploy.out")" "must not contain '@'"
rm -rf "$work"
unset PHASE SITE_URL PRODUCT

WORKING_DIRECTORY="../outside"
work="$(run_mocked_deploy)"
assert_exit "mocked path traversal fails" "$work" 1
assert_contains "mocked path traversal message" "$(cat "${work}/deploy.out")" "must not contain"
rm -rf "$work"
unset WORKING_DIRECTORY

ENVIRONMENT="production"
ALLOW_PRODUCTION="true"
GITHUB_ENVIRONMENT=""
work="$(run_mocked_deploy)"
assert_exit "production flag without gh env fails" "$work" 1
assert_contains "requires GITHUB_ENVIRONMENT" "$(cat "${work}/deploy.out")" "GITHUB_ENVIRONMENT"
rm -rf "$work"

ENVIRONMENT="prod"
ALLOW_PRODUCTION="true"
GITHUB_ENVIRONMENT="production-deploy"
work="$(run_mocked_deploy)"
assert_exit "prod with protected env succeeds" "$work" 0
assert_contains "prod deploy runs" "$(cat "${work}/forge.log")" "+ deploy --environment prod --non-interactive"
rm -rf "$work"

ENVIRONMENT="prod"
ALLOW_PRODUCTION="true"
GITHUB_ENVIRONMENT="prod"
work="$(run_mocked_deploy)"
assert_exit "prod GH env matching Forge env fails" "$work" 1
rm -rf "$work"

ENVIRONMENT="prd-us"
ALLOW_PRODUCTION="false"
GITHUB_ENVIRONMENT=""
work="$(run_mocked_deploy)"
assert_exit "prd-us without allowProduction fails" "$work" 1
rm -rf "$work"

ENVIRONMENT="production"
ALLOW_PRODUCTION="true"
GITHUB_ENVIRONMENT="production-install"
PHASE="deploy"
work="$(run_mocked_deploy)"
assert_exit "deploy under production-install GH env fails" "$work" 1
rm -rf "$work"
unset ENVIRONMENT ALLOW_PRODUCTION GITHUB_ENVIRONMENT PHASE

PHASE="deploy-and-install"
ALLOW_COMBINED_PHASE="true"
SITE_URL="acme.atlassian.net"
PRODUCT="jira"
DRY_RUN="1"
work="$(run_mocked_deploy)"
assert_exit "dry-run exits 0" "$work" 0
assert_eq "dry-run deployed stays false" "false" "$(output_value "${work}/github_output" deployed)"
assert_eq "dry-run installed stays false" "false" "$(output_value "${work}/github_output" installed)"
rm -rf "$work"
unset PHASE ALLOW_COMBINED_PHASE SITE_URL PRODUCT DRY_RUN

echo "{}" > /dev/null
work="$(mktemp -d)"
mkdir -p "$work"
: > "${work}/manifest.yml"
printf '%s\n' '{"name":"app"}' > "${work}/package.json"
printf '%s\n' '{"lockfileVersion":3}' > "${work}/package-lock.json"
: > "${work}/forge.log"
: > "${work}/npm.log"
: > "${work}/github_output"
(
  cd "$work"
  export PATH="${ROOT}/tests/mocks:${PATH}"
  export FORGE_ARGV_LOG="${work}/forge.log"
  export NPM_ARGV_LOG="${work}/npm.log"
  export GITHUB_OUTPUT="${work}/github_output"
  export FORGEDEPLOY_TEST=1
  export SKIP_CLI_INSTALL=1
  export SKIP_DEP_INSTALL=0
  export SKIP_FORGE_SETTINGS=1
  export FORGE_EMAIL="dev@example.com"
  export FORGE_API_TOKEN="super-secret-token"
  export ENVIRONMENT="development"
  export PHASE="deploy"
  bash "${ROOT}/scripts/deploy.sh" >"${work}/deploy.out" 2>&1
)
assert_contains "fake npm ci ran" "$(cat "${work}/npm.log")" "+ ci"
assert_not_contains "npm did not see forge token" "$(cat "${work}/npm.log")" "LEAKED_FORGE_CREDENTIALS"
rm -rf "$work"

FORGEDEPLOY_TEST=""
SKIP_CLI_INSTALL="1"
work="$(mktemp -d)"
: > "${work}/manifest.yml"
: > "${work}/forge.log"
: > "${work}/npm.log"
: > "${work}/github_output"
(
  cd "$work"
  export PATH="${ROOT}/tests/mocks:${PATH}"
  export FORGE_ARGV_LOG="${work}/forge.log"
  export NPM_ARGV_LOG="${work}/npm.log"
  export GITHUB_OUTPUT="${work}/github_output"
  export FORGEDEPLOY_TEST=""
  export SKIP_CLI_INSTALL=1
  export SKIP_DEP_INSTALL=1
  export SKIP_FORGE_SETTINGS=1
  export FORGE_EMAIL="dev@example.com"
  export FORGE_API_TOKEN="super-secret-token"
  export ENVIRONMENT="development"
  export PHASE="deploy"
  bash "${ROOT}/scripts/deploy.sh" >"${work}/deploy.out" 2>&1
  echo "$?" >"${work}/exitcode"
)
assert_contains "SKIP_CLI_INSTALL ignored without test flag" "$(cat "${work}/npm.log")" "+ install -g @forge/cli@13.2.0"
rm -rf "$work"
unset FORGEDEPLOY_TEST SKIP_CLI_INSTALL

echo "# action.yml hygiene"

action="$(cat "${ROOT}/action.yml")"
assert_contains "setup-node v7" "$action" "actions/setup-node@v7"
assert_contains "cli exact pin" "$action" "default: \"13.2.0\""
assert_contains "phase default deploy" "$action" "default: \"deploy\""
assert_contains "confirmScopes default false" "$action" "default: \"false\""
assert_contains "allowCombinedPhase input" "$action" "allowCombinedPhase:"
assert_contains "GITHUB_ENVIRONMENT from context" "$action" "github.environment"
assert_contains "legacy token as input fallback" "$action" "INPUT_FORGE_API_TOKEN: \${{ inputs.apiToken }}"
if grep -E '^[[:space:]]*FORGE_API_TOKEN:' "${ROOT}/action.yml" >/dev/null; then
  FAIL=$((FAIL + 1))
  echo "not ok - does not clobber FORGE_API_TOKEN from inputs"
else
  PASS=$((PASS + 1))
  echo "ok - does not clobber FORGE_API_TOKEN from inputs"
fi

example="$(cat "${ROOT}/example/.github/workflows/deploy.yml")"
assert_contains "example deploy environment suffix" "$example" "environment: \${{ inputs.environment }}-deploy"
assert_contains "example install environment suffix" "$example" "environment: \${{ inputs.environment }}-install"
assert_contains "example choice environment" "$example" "type: choice"
assert_contains "example install token" "$example" "FORGE_INSTALL_API_TOKEN"
assert_not_contains "example avoids event.inputs" "$example" "github.event.inputs"
if [[ "$example" == *"environment: \${{ inputs.environment }}-deploy"* && "$example" == *"environment: \${{ inputs.environment }}-install"* ]]; then
  PASS=$((PASS + 1))
  echo "ok - example jobs use different GitHub Environments"
else
  FAIL=$((FAIL + 1))
  echo "not ok - example jobs use different GitHub Environments"
fi

readme="$(cat "${ROOT}/README.md")"
assert_contains "readme pin sha" "$readme" "git-sha-or-tag"
assert_contains "readme production-deploy" "$readme" "production-deploy"
assert_contains "readme allowCombinedPhase" "$readme" "allowCombinedPhase"
assert_contains "readme scoped token URL" "$readme" "manage-profile/security/api-tokens"
assert_not_contains "readme has no Node.js 18 prerequisite" "$readme" "Node.js 18"
assert_not_contains "readme has no old token URL" "$readme" "id.atlassian.com/manage/api-tokens"
assert_not_contains "readme avoids event.inputs" "$readme" "github.event.inputs"

if grep -E '^[[:space:]]*run:.*inputs\.(apiToken|email)' "${ROOT}/action.yml" >/dev/null; then
  FAIL=$((FAIL + 1))
  echo "not ok - secrets must not be interpolated into run: strings"
else
  PASS=$((PASS + 1))
  echo "ok - secrets are not interpolated into run: strings"
fi

if grep -n 'dev-03-install-or-deploy' \
  "${ROOT}/example/.github/workflows/deploy.yml" \
  "${ROOT}/README.md" \
  "${ROOT}/action.yml" >/dev/null; then
  FAIL=$((FAIL + 1))
  echo "not ok - stale example branch pin still present"
else
  PASS=$((PASS + 1))
  echo "ok - example no longer pins a stale branch"
fi

if ruby -ryaml -e "YAML.load_file('${ROOT}/example/.github/workflows/deploy.yml')" >/dev/null 2>&1; then
  PASS=$((PASS + 1))
  echo "ok - SOD example workflow YAML parses"
else
  FAIL=$((FAIL + 1))
  echo "not ok - SOD example workflow YAML parses"
fi

echo
echo "Passed: ${PASS}  Failed: ${FAIL}"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
