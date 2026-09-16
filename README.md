# ForgeDeploy

A composite GitHub Action that runs `forge deploy` and `forge install` for an Atlassian Forge app you already have.

## Who it is for

Teams with an existing Forge app who want CI instead of running `forge deploy` on a laptop. You do not move the app into this repository. You add a workflow next to your `manifest.yml`.

## Requirements

- An existing Forge app: `manifest.yml` (and usually `package.json`) in the directory you deploy from
- `FORGE_EMAIL` and `FORGE_API_TOKEN` in the job environment (GitHub Environment secrets, repo secrets, or a prior vault step)
- A [scoped Forge API token](https://id.atlassian.com/manage-profile/security/api-tokens) (app = Forge, 1–365 days)
- Node 22 or 24 (the action installs this; default **24**)

Pin the action to a commit SHA or release tag, not `@main`:

```yaml
- uses: Forgeworx/forgedeploy@<git-sha-or-tag>
```

## Use with an existing Forge app

Leave the Forge app where it is. Add `.github/workflows/deploy.yml` in **that** repo.

| Layout | What you set |
|--------|----------------|
| Typical app (`manifest.yml` + `package.json` at repo root) | Nothing extra. Defaults are for this. |
| Custom UI in a subdirectory | `isCustomApp: true` and `customAppPath` (frontend only). Deploy still runs from the repo root or `workingDirectory`. |
| Entire Forge app in a subdirectory | `workingDirectory` to that folder (the one with `manifest.yml`). |

`workingDirectory` and `isCustomApp` / `customAppPath` are independent. Do not use one in place of the other.

### Minimal deploy (fail-closed)

Default `phase` is **deploy only**. This does not install the app on a site. No job `environment:` is required for non-production Forge environments.

```yaml
name: Deploy Forge app

on:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - uses: Forgeworx/forgedeploy@<git-sha-or-tag>
        env:
          FORGE_EMAIL: ${{ secrets.FORGE_EMAIL }}
          FORGE_API_TOKEN: ${{ secrets.FORGE_API_TOKEN }}
        with:
          phase: deploy
          environment: development
```

Custom UI at `static/hello-world`:

```yaml
        with:
          phase: deploy
          environment: development
          isCustomApp: true
          customAppPath: static/hello-world
```

App lives in `apps/jira-plugin`:

```yaml
        with:
          phase: deploy
          environment: development
          workingDirectory: apps/jira-plugin
```

### Deploy and install (separate jobs)

Engineering deploys. Release installs. Use two GitHub Environments with different reviewers and secrets: `{env}-deploy` and `{env}-install`. `installToSite: true` does **not** turn a deploy job into an install; that combination errors.

Set `FORGE_EMAIL` / `FORGE_API_TOKEN` on the job (`env:`). Pull them from GitHub Environment secrets or from a previous step (Azure Key Vault, or any other vault). This action does not talk to vaults.

```yaml
name: Deploy Forge app

on:
  workflow_dispatch:
    inputs:
      environment:
        type: choice
        required: true
        default: development
        options: [development, staging, production]
      runInstall:
        type: boolean
        default: false
      allowProduction:
        type: boolean
        default: false
      product:
        type: string
      siteUrl:
        type: string

permissions:
  contents: read

concurrency:
  group: forge-${{ inputs.environment }}
  cancel-in-progress: false

jobs:
  deploy:
    runs-on: ubuntu-24.04
    environment: ${{ inputs.environment }}-deploy
    steps:
      - uses: actions/checkout@v7
      - uses: Forgeworx/forgedeploy@<git-sha-or-tag>
        env:
          FORGE_EMAIL: ${{ secrets.FORGE_EMAIL }}
          FORGE_API_TOKEN: ${{ secrets.FORGE_API_TOKEN }}
        with:
          phase: deploy
          environment: ${{ inputs.environment }}
          allowProduction: ${{ inputs.allowProduction }}

  install:
    needs: deploy
    if: ${{ inputs.runInstall }}
    runs-on: ubuntu-24.04
    environment: ${{ inputs.environment }}-install
    steps:
      - uses: actions/checkout@v7
      - uses: Forgeworx/forgedeploy@<git-sha-or-tag>
        env:
          FORGE_EMAIL: ${{ secrets.FORGE_EMAIL }}
          FORGE_API_TOKEN: ${{ secrets.FORGE_API_TOKEN }}
          FORGE_INSTALL_API_TOKEN: ${{ secrets.FORGE_INSTALL_API_TOKEN }}
        with:
          phase: install
          environment: ${{ inputs.environment }}
          allowProduction: ${{ inputs.allowProduction }}
          product: ${{ inputs.product }}
          siteUrl: ${{ inputs.siteUrl }}
```

`FORGE_INSTALL_API_TOKEN` is optional on install jobs. If unset, the action uses `FORGE_API_TOKEN`. Do not pass tokens via `with:`.

Full copy: [example/.github/workflows/deploy.yml](example/.github/workflows/deploy.yml). Drop that file into the Forge app repo (not this repo).

One-job deploy+install is break-glass: `phase: deploy-and-install` and `allowCombinedPhase: true`.

`phase: lint` runs `forge lint` only. It does not need credentials.

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `phase` | `deploy`, `install`, `deploy-and-install`, or `lint`. `deploy` never installs. | No | `deploy` |
| `email` | Legacy. Prefer job env `FORGE_EMAIL`. | No | - |
| `apiToken` | Legacy. Prefer job env `FORGE_API_TOKEN`. | No | - |
| `environment` | Forge environment name. Production-class names are gated. | Yes | - |
| `allowProduction` | Required for production-class Forge envs. Not enough by itself. | No | `false` |
| `allowCombinedPhase` | Required for `phase: deploy-and-install`. | No | `false` |
| `allowNoLockfile` | Allow JS install without a lockfile when `GITHUB_ACTIONS=true`. | No | `false` |
| `allowNonAtlassianSite` | Allow a `siteUrl` host that is not `*.atlassian.net`. | No | `false` |
| `product` | `jira`, `confluence`, `compass`, `bitbucket`, `jira-service-management`. | When installing | - |
| `siteUrl` | `yourcompany.atlassian.net`. `@` and userinfo are rejected. | When installing | - |
| `installToSite` | If `true` with `phase: deploy`, the action errors. Use a separate install job. | No | `false` |
| `upgradeIfInstalled` | Pass `--upgrade` on `forge install`. | No | `true` |
| `confirmScopes` | Pass `--confirm-scopes`. Opt-in. | No | `false` |
| `isCustomApp` | Build Custom UI in `customAppPath` before deploy/lint. | No | `false` |
| `customAppPath` | Relative Custom UI path. `..` / `~` / CR/LF rejected. | No | - |
| `workingDirectory` | Relative path to `manifest.yml`. Default: repo root. | No | `.` |
| `nodeVersion` | `22` or `24` only. | No | `24` |
| `forgeCliVersion` | Exact `@forge/cli` version. | No | `13.2.0` |
| `cache` | Cache lockfiles when present. | No | `true` |
| `lint` | Also run `forge lint`. `phase: lint` is lint only. | No | `false` |
| `verbose` | `--verbose`. | No | `false` |
| `skipVerify` | `--no-verify` on deploy. | No | `false` |
| `approve` | Comma-separated `--approve` rules. | No | - |
| `license` | `active`, `standard`, `advanced`, `inactive`, `trial`. | No | - |

## Outputs

`environment`, `deployed`, `installed`, `cli-version`, `working-directory`, `phase`. Written as heredoc outputs. Credentials are never written.

## Production

These Forge environment names are production-class: exact `production`, `prod`, `prd`; prefixes `production-*`, `prod-*`, `prd-*`.

They require **both**:

1. `allowProduction: true`
2. Job `environment:` set to exactly `production`, `production-deploy`, or `production-install`

A GitHub Environment that only matches the Forge name (`prod`, `prd`, `production-us`) is not enough. An empty `GITHUB_ENVIRONMENT` fails.

When the job sets `environment:`:

- Deploy / lint: `*-deploy` (for production, `production-deploy`)
- Install: `*-install` (for production, `production-install`)
- Combined break-glass: `production`, `production-deploy`, or `production-install`

```yaml
on:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-24.04
    environment: production-deploy
    steps:
      - uses: actions/checkout@v7
      - uses: Forgeworx/forgedeploy@<git-sha-or-tag>
        env:
          FORGE_EMAIL: ${{ secrets.FORGE_EMAIL }}
          FORGE_API_TOKEN: ${{ secrets.FORGE_API_TOKEN }}
        with:
          phase: deploy
          environment: production
          allowProduction: true
```

## How it works

1. `scripts/validate-node.sh` — allowlist Node 22 or 24
2. `scripts/detect-lockfile.sh` — find lockfiles; reject unsafe paths before writing outputs
3. `actions/setup-node@v7` — install Node (cache when a lockfile exists)
4. `scripts/deploy.sh` — validate phase, production gate, site, and paths
5. Install JS dependencies (tokens unset). Build Custom UI if `isCustomApp` is true
6. Install `@forge/cli@13.2.0`
7. Run `forge deploy` and/or `forge install` in a subshell that exports `FORGE_*` only for `forge`

## Example workflow

[example/.github/workflows/deploy.yml](example/.github/workflows/deploy.yml) is a two-job workflow to copy into an existing Forge app repo.

## Troubleshooting

- **App already installed on the site** — `phase: deploy` does not upgrade a site install. Use `phase: install` (and `upgradeIfInstalled`, default `true`).
- **`phase: deploy` did not install** — expected. Use a separate install job, or break-glass `allowCombinedPhase`.
- **Production failed** — set `allowProduction: true` and job `environment: production-deploy` or `production-install`.
- **`siteUrl` rejected** — use `yourcompany.atlassian.net` only. No `@`, no userinfo.
- **Node** — only 22 or 24. Not 18, 20, `22.23.1`, or `24.17.0`.
- **`workingDirectory` / `customAppPath`** — relative, no `..` or `~`, must stay inside the repo.
- **No lockfile** — commit one, or set `allowNoLockfile: true`.
- **`yarn.lock` / `pnpm-lock.yaml` but the tool is missing** — the action fails.

## For contributors and agents

This repository is the action, not a Forge app. There is no app `package.json` to install.

```bash
bash tests/run.sh
bash tests/lint.sh
```

Tests are offline. They do not call Atlassian.

How to change the action: [AGENTS.md](AGENTS.md).

## License

[MIT](LICENSE)
