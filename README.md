# ForgeDeploy

**Simple GitHub Action for deploying Atlassian Forge apps.**

## 🔥 What This Solves

Most Forge app deployments are manual, tribal-knowledge-heavy, and hard to scale across environments or team members. `ForgeDeploy` solves this by offering a dead-simple GitHub Action that:

- Authenticates with Forge using secure GitHub secrets
- Deploys your app to a given environment
- Installs it to a specific Atlassian product and site

No more CLI guesswork. No more blocked deploys when one engineer is offline.

## 🚀 What You Get

- ✅ One-click deploy via GitHub Actions UI
- ✅ Works across environments (dev/staging/prod)
- ✅ Targets Jira or Confluence sites
- ✅ Minimal setup. No dashboard. No bloat.

## 🧩 Inputs

| Name        | Description                            | Required |
|-------------|----------------------------------------|----------|
| `email`     | Atlassian account email                | ✅       |
| `apiToken`  | Atlassian API token                    | ✅       |
| `environment` | Forge environment to deploy to       | ✅       |
| `siteUrl`   | Atlassian site URL (e.g. example.atlassian.net) | ✅ |
| `product`   | Target product (`jira` or `confluence`) | ✅       |

## 🔒 Secrets Required

| Secret Name       | Description                        |
|-------------------|------------------------------------|
| `FORGE_EMAIL`     | Atlassian email address            |
| `FORGE_API_TOKEN` | API token from Atlassian account   |

Generate your API token here: [https://id.atlassian.com/manage/api-tokens](https://id.atlassian.com/manage/api-tokens)

## 📦 Example Usage

Create `.github/workflows/deploy.yml` in your Forge app repo:
