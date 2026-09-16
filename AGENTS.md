# Agent guide — ForgeDeploy

Read this before changing the repo. Product contract for **consumers** is [README.md](README.md). This file is how to work **in** the repo.

## What this is

A **composite GitHub Action** (`runs: using: composite`) that wraps Atlassian Forge CLI: auth, `forge deploy`, optional `forge install`, optional `forge lint`.

- Not a Forge app. There is no app `manifest.yml` or `package.json` here.
- Not a secret broker. Do not add Azure Key Vault, AWS Secrets Manager, GCP Secret Manager, or any vault SDK. Consumers compose a prior vault step and export `FORGE_EMAIL` / `FORGE_API_TOKEN` into the job env.
- Credentials are consumed from the environment. Composite `with:` inputs are not secret-typed; job env wins.

## Existing Forge apps

Consumers add a workflow to **their** Forge repo. They do not move or rewrite the app, and they do not commit the app into this repo.

| Layout | Inputs |
|--------|--------|
| Typical app: `manifest.yml` + `package.json` at repo root | Defaults. No extra inputs. |
| Custom UI in a subdirectory | `isCustomApp: true` and `customAppPath` (frontend build only). `forge deploy` still uses `workingDirectory` (default `.`). |
| Entire Forge app in a subdirectory | `workingDirectory` to the folder that contains `manifest.yml`. |

`workingDirectory` and `isCustomApp` / `customAppPath` stay independent. README is the consumer homepage; keep this table aligned with it.

## Layout

| Path | Role |
|------|------|
| `action.yml` | Public surface: inputs, outputs, step wiring. Keep thin. |
| `scripts/lib.sh` | Validation, path/site rules, credential resolve, argv builders, `write_output`. |
| `scripts/deploy.sh` | Phase runner. Sources `lib.sh`. |
| `scripts/detect-lockfile.sh` | Runs **before** `deploy.sh`. Validates paths, then writes `cache` / `path` for `setup-node`. |
| `scripts/validate-node.sh` | Allowlist Node 22 or 24 only. |
| `tests/run.sh` | Offline unit + mocked `forge`/`npm` argv tests. No Atlassian network. |
| `tests/lint.sh` | shellcheck, yamllint, actionlint, `github-action.json` schema (skips missing tools). |
| `tests/mocks/` | Fake `forge` and `npm`. |
| `example/.github/workflows/deploy.yml` | SOD consumer example (`{env}-deploy` / `{env}-install`). |
| `.github/workflows/ci.yml` | Offline `tests/run.sh` + lint. No live Forge. |
| `.github/dependabot.yml` | GitHub Actions updates. |

## Local setup

No Node app to install. Need bash 4+. Optional: `shellcheck`, `yamllint`, `actionlint`, `check-jsonschema` (CI installs these; `tests/lint.sh` skips if absent).

```bash
bash tests/run.sh    # helpers in lib.sh + mocked deploy.sh
bash tests/lint.sh   # shellcheck / yamllint / actionlint / action schema
```

Default CI does **not** call Atlassian. Do not add live deploy/install jobs.

`SKIP_CLI_INSTALL`, `SKIP_DEP_INSTALL`, `SKIP_FORGE_SETTINGS`, `SKIP_MANIFEST_CHECK` work only when `FORGEDEPLOY_TEST=1`. `DRY_RUN=1` must leave outputs `deployed` / `installed` as `false`.

## Consumer usage (do not invent a different contract)

1. `actions/checkout@v7`, then this action pinned to a **SHA or tag** (not `@main`).
2. Set job env `FORGE_EMAIL` and `FORGE_API_TOKEN` from GitHub Environment secrets **or** a prior vault action. Optional `FORGE_INSTALL_API_TOKEN` on install jobs. Do not pass tokens via `with:`.
3. `phase`: `deploy` (default, never installs), `install` (needs `product` + `siteUrl`), `lint` (no credentials), or break-glass `deploy-and-install` + `allowCombinedPhase: true`.
4. Job `environment:` is optional for non-production. When it is set, it must be `{forge-env}-deploy` for deploy/lint and `{forge-env}-install` for install (example: `development-deploy`). Bare `development` / `staging` fail closed.
5. Production-class **Forge** names: exact `production` / `prod` / `prd`, prefixes `production-*` / `prod-*` / `prd-*`. Require `allowProduction: true` **and** `GITHUB_ENVIRONMENT` exactly `production`, `production-deploy`, or `production-install`. Matching the Forge name (`prod`) is not enough. Empty GH env fails.
6. Phase binding: `production-deploy` for deploy/lint, `production-install` for install, bare `production` only for combined break-glass.
7. `workingDirectory` = where `manifest.yml` lives. `isCustomApp` / `customAppPath` = Custom UI build dir only. Independent. Relative, no `..` / `~` / CR/LF, must stay inside the repo.
8. Runtime: Node **22 or 24** (default **24**). CLI **`@forge/cli@13.2.0`** exact. `actions/setup-node@v7`.

## Do not undo

- Fail-closed install: default phase is deploy; `installToSite: true` with `phase: deploy` **errors** (not a shortcut).
- No vault adapters in this action.
- Never write credentials to `GITHUB_OUTPUT`. `write_output` rejects `*token*` / `*password*` / `*secret*` / `*email*` / `*credential*` names and **all** CR/LF (including `path=`).
- Unset `FORGE_*` / `INPUT_FORGE_*` around npm/yarn/pnpm. Export tokens only in the `forge` subshell.
- Do not map `FORGE_API_TOKEN: ${{ inputs.apiToken }}` in `action.yml` (clobbers job secrets). Use `INPUT_FORGE_*` only.
- Keep `detect-lockfile.sh` path checks **before** any output write. Multiple lockfiles are one comma-separated line (no LF in `path=`).
- Do not invent a CODEOWNERS team in this repo.
- Do not retarget `@dev-03-install-or-deploy` or document Node 18 / install-by-default.

## Change the action safely

1. Edit `scripts/lib.sh` / `scripts/deploy.sh` and add a test in `tests/run.sh` that would have failed before the change.
2. Wire new inputs in `action.yml` (`inputs:` + `env:` on the deploy step). Do not put secrets in `run:` strings.
3. Keep `workingDirectory` vs `isCustomApp` / `customAppPath` split.
4. Keep `@forge/cli` an **exact** version (default `13.2.0`).
5. Update README, this Existing Forge apps section, and `example/.github/workflows/deploy.yml` if the consumer contract changed.
6. Re-run `bash tests/run.sh` and `bash tests/lint.sh`. Stay at 0 failures.

## Common tasks

**Add an input.** `action.yml` input + `env:` pass-through → read it in `validate_inputs` or `deploy.sh` → test in `tests/run.sh` → README inputs table.

**Add a Forge flag.** Put it in `build_deploy_args` / `build_install_args` in `lib.sh`. Assert argv in `tests/run.sh`. Do not interpolate secrets onto the command line.

**Add a test.** Use existing helpers (`assert_success`, `assert_failure`, `valid_deploy`, `run_mocked_deploy`). Keep tests offline; put fakes in `tests/mocks/`.

**Update the example.** `example/.github/workflows/deploy.yml` must keep two jobs, different GitHub Environments, choice `environment`, and job-env credentials. Do not collapse SOD into one `environment:`.
