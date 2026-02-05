# ForgeDeploy

A GitHub Action for deploying and installing Atlassian Forge applications to specified environments and Atlassian sites.

## Overview

ForgeDeploy automates the deployment process for Atlassian Forge applications by providing a standardized GitHub Action that handles authentication, deployment, and installation. This eliminates manual deployment steps and enables consistent, repeatable deployments across different environments and team members.

## Features

- Automated authentication with Forge using secure GitHub secrets
- Deploy to multiple environments (development, staging, production)
- Support for both Jira and Confluence products
- Optional installation to Atlassian sites
- Support for custom Forge apps in subdirectories
- Minimal configuration required

## Prerequisites

Before using this action, ensure you have:

- An Atlassian account with API token access
- A Forge application repository
- Node.js 18+ (automatically set up by the action)
- GitHub secrets configured (see Secrets section)

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `email` | Atlassian account email address used for authentication | Yes | - |
| `apiToken` | Atlassian API token for authentication | Yes | - |
| `environment` | Forge environment to deploy to (e.g., `development`, `staging`, `production`) | Yes | - |
| `product` | Target Atlassian product (`jira` or `confluence`) | Yes | - |
| `siteUrl` | Atlassian site URL where the app will be installed (e.g., `yourcompany.atlassian.net`). Required if `installToSite` is `true` | No | - |
| `installToSite` | Whether to install the app to the specified site after deployment. Set to `false` to skip installation (useful if the app is already installed) | No | `true` |
| `isCustomApp` | Set to `true` if this is a custom Forge app located in a subdirectory | No | `false` |
| `customAppPath` | Relative path to the custom Forge app directory (required if `isCustomApp` is `true`) | No | - |

## Secrets

The following GitHub secrets must be configured in your repository:

| Secret Name | Description |
|-------------|-------------|
| `FORGE_EMAIL` | Your Atlassian account email address |
| `FORGE_API_TOKEN` | API token from your Atlassian account |

### Generating an API Token

1. Navigate to [Atlassian Account API Tokens](https://id.atlassian.com/manage/api-tokens)
2. Click "Create API token"
3. Give it a label (e.g., "GitHub Actions Forge Deploy")
4. Copy the generated token
5. Add it as a GitHub secret named `FORGE_API_TOKEN`

## Usage

### Basic Workflow

Create a `.github/workflows/deploy.yml` file in your Forge app repository:

```yaml
name: Deploy Forge App

on:
  workflow_dispatch:
    inputs:
      environment:
        required: true
        description: 'Forge environment (development, staging, production)'
      product:
        required: true
        description: 'Product (jira or confluence)'
      siteUrl:
        required: false
        description: 'Atlassian site URL'
      installToSite:
        type: boolean
        required: false
        default: true
        description: 'Install app to Atlassian site?'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - uses: Forgeworx/forgedeploy@main
        with:
          email: ${{ secrets.FORGE_EMAIL }}
          apiToken: ${{ secrets.FORGE_API_TOKEN }}
          environment: ${{ github.event.inputs.environment }}
          product: ${{ github.event.inputs.product }}
          siteUrl: ${{ github.event.inputs.siteUrl }}
          installToSite: ${{ github.event.inputs.installToSite }}
```

### Deploy Without Installation

To deploy without installing to a site (useful for apps already installed):

```yaml
- uses: Forgeworx/forgedeploy@main
  with:
    email: ${{ secrets.FORGE_EMAIL }}
    apiToken: ${{ secrets.FORGE_API_TOKEN }}
    environment: production
    product: jira
    installToSite: false
```

### Custom App in Subdirectory

For Forge apps located in a subdirectory:

```yaml
- uses: Forgeworx/forgedeploy@main
  with:
    email: ${{ secrets.FORGE_EMAIL }}
    apiToken: ${{ secrets.FORGE_API_TOKEN }}
    environment: development
    product: confluence
    siteUrl: yourcompany.atlassian.net
    isCustomApp: true
    customAppPath: apps/my-forge-app
```

### Automated Deployment on Push

Deploy automatically when code is pushed to specific branches:

```yaml
name: Deploy Forge App

on:
  push:
    branches:
      - main
      - develop

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - uses: Forgeworx/forgedeploy@main
        with:
          email: ${{ secrets.FORGE_EMAIL }}
          apiToken: ${{ secrets.FORGE_API_TOKEN }}
          environment: ${{ github.ref == 'refs/heads/main' && 'production' || 'development' }}
          product: jira
          siteUrl: ${{ secrets.FORGE_SITE_URL }}
          installToSite: true
```

## How It Works

The action performs the following steps:

1. Sets up Node.js 18 environment
2. Installs Forge CLI globally
3. Disables Forge usage analytics
4. Installs root backend dependencies
5. If `isCustomApp` is `true`:
   - Installs frontend dependencies in the custom app directory
   - Builds the frontend
6. Deploys the Forge app to the specified environment
7. Optionally installs the app to the specified Atlassian site and product

## Troubleshooting

### Authentication Failures

**Issue**: Action fails with authentication errors

**Solutions**:
- Verify that `FORGE_EMAIL` and `FORGE_API_TOKEN` secrets are correctly set in your repository
- Ensure the API token is valid and has not expired
- Check that the email address matches your Atlassian account

### Deployment Failures

**Issue**: Deployment fails with build or validation errors

**Solutions**:
- Ensure your Forge app builds successfully locally using `forge deploy`
- Check that all required dependencies are listed in `package.json`
- Verify that the `environment` value matches an existing Forge environment
- For custom apps, ensure `customAppPath` is correct relative to the repository root

### Installation Failures

**Issue**: App deployment succeeds but installation fails

**Solutions**:
- Verify that `siteUrl` is correctly formatted (e.g., `yourcompany.atlassian.net`, not `https://yourcompany.atlassian.net`)
- Ensure the site URL matches a site where you have installation permissions
- Check that the `product` value matches the site's product type
- Verify the app is not already installed if you're trying to reinstall

### Custom App Path Issues

**Issue**: Custom app deployment fails with path errors

**Solutions**:
- Ensure `isCustomApp` is set to `true` when using `customAppPath`
- Verify `customAppPath` is relative to the repository root (e.g., `apps/my-app`, not `/apps/my-app`)
- Check that the custom app directory contains a valid `package.json` and Forge configuration

## Contributing

Contributions are welcome. Please ensure that:

- All changes maintain backward compatibility
- Documentation is updated for any new features
- Code follows existing patterns and style
- Tests are added for new functionality

## License

MIT License - see [LICENSE](LICENSE) file for details.
