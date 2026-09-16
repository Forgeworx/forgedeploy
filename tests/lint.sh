#!/usr/bin/env bash
# Offline-friendly lint runner. Skips tools that are not installed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PASS=0
FAIL=0
SKIP=0

ok() {
  PASS=$((PASS + 1))
  echo "ok - $1"
}

not_ok() {
  FAIL=$((FAIL + 1))
  echo "not ok - $1"
}

skipped() {
  SKIP=$((SKIP + 1))
  echo "skipped - $1"
}

if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -x scripts/*.sh tests/lint.sh tests/mocks/forge \
    && shellcheck -x -e SC2030,SC2031,SC2034 tests/run.sh; then
    ok "shellcheck"
  else
    not_ok "shellcheck"
  fi
else
  skipped "shellcheck (not installed)"
fi

if command -v yamllint >/dev/null 2>&1; then
  if yamllint -c .yamllint.yml \
    action.yml \
    .github/workflows/ci.yml \
    .github/dependabot.yml \
    example/.github/workflows/deploy.yml \
    .yamllint.yml; then
    ok "yamllint"
  else
    not_ok "yamllint"
  fi
else
  skipped "yamllint (not installed)"
fi

if command -v actionlint >/dev/null 2>&1; then
  if actionlint -color \
    .github/workflows/ci.yml \
    example/.github/workflows/deploy.yml; then
    ok "actionlint"
  else
    not_ok "actionlint"
  fi
else
  skipped "actionlint (not installed)"
fi

SCHEMA_BIN=""
if command -v check-jsonschema >/dev/null 2>&1; then
  SCHEMA_BIN="check-jsonschema"
elif [[ -x /tmp/schema-venv/bin/check-jsonschema ]]; then
  SCHEMA_BIN="/tmp/schema-venv/bin/check-jsonschema"
fi

if [[ -n "$SCHEMA_BIN" ]]; then
  if "$SCHEMA_BIN" --schemafile https://json.schemastore.org/github-action.json action.yml; then
    ok "github-action schema"
  else
    not_ok "github-action schema"
  fi
else
  skipped "github-action schema (check-jsonschema not installed)"
fi

echo
echo "Lint passed: ${PASS}  failed: ${FAIL}  skipped: ${SKIP}"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
