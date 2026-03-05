# Maintainer Guide

This document is for harness project maintainers who run tests, build and publish container images, cut releases, and manage the framework infrastructure.

## Testing

Harness includes a self-test framework in `Makefile.test` that validates the Jira fetch pipeline, issue detection, auth logic, caching, and API version detection.

### Running tests

Run all tests (no credentials required for unit tests):

```bash
make -f Makefile.test test
```

Run a specific test group:

```bash
make -f Makefile.test test/jira/detect-issue
make -f Makefile.test test/jira/auth-setup
make -f Makefile.test test/jira/placeholder
make -f Makefile.test test/jira/cache
make -f Makefile.test test/jira/api-version
make -f Makefile.test test/jira/fetch-integration
```

### Integration tests

The `test/jira/fetch-integration` target performs a live fetch against a real Jira instance. It is skipped unless credentials are configured.

Create `.test.harness.local.env` in the repo root (gitignored):

```env
HARNESS_JIRA_BASE_URL=https://issues.redhat.com
HARNESS_JIRA_API_TOKEN=your-jira-pat
HARNESS_JIRA_AUTH_TYPE=bearer
HARNESS_ISSUE=AAP-12345
```

The Makefile loads this file automatically and exports the variables to scripts.

### Inspecting fetch output

To run a live Jira fetch and pretty-print the context (hierarchy, handbook links, full JSON):

```bash
make -f Makefile.test test/jira/fetch-inspect
```

### Test coverage

| Test group | Tests | What's tested |
|---|---|---|
| `detect-issue` | 6 | Explicit override, project keys, branch parsing, commit messages, error exit |
| `auth-setup` | 4 | Bearer/basic selection, auto mode, quote stripping |
| `placeholder` | 4 | File creation, issue key, meta flag, JSON structure |
| `cache` | 4 | Cache hit, `HARNESS_NO_CACHE` bypass, TTL expiry, config hash invalidation |
| `api-version` | 5 | Explicit v2/v3, auto-detect v3, v2 fallback, unreachable default |
| `fetch-integration` | 1 | Live Jira fetch (requires credentials) |

---

## Container Image Publishing

Harness provides pre-built container images for each AI provider (Claude, OpenAI, Vertex AI, local/Ollama). These images are used by paude to run AI agents in isolated, network-restricted containers.

### Prerequisites

- Podman or Docker installed
- GitHub CLI (`gh`) installed and authenticated, or `GITHUB_TOKEN` environment variable set
- Push access to `ghcr.io/ansible-automation-platform/harness-*` images

### Logging in to ghcr.io

```bash
# Using gh CLI (recommended - handles SSO automatically)
make -f Makefile.publish login

# Or set GITHUB_TOKEN manually
export GITHUB_TOKEN=ghp_...
export GITHUB_USER=your-username
make -f Makefile.publish login
```

### Building images

Build all provider images:

```bash
make -f Makefile.publish build-all
```

Build a specific provider:

```bash
make -f Makefile.publish build-claude
make -f Makefile.publish build-openai
make -f Makefile.publish build-vertex
make -f Makefile.publish build-local
```

### Pushing images to the registry

Push all images:

```bash
make -f Makefile.publish push-all
```

Push a specific provider:

```bash
make -f Makefile.publish push-claude
```

### Build and push in one step

```bash
make -f Makefile.publish publish-all
```

### Tagging with a version

By default, images are tagged with the current git describe output (e.g., `v1.2.3` or `v1.2.3-5-gabcdef`). Override with:

```bash
make -f Makefile.publish VERSION=v1.3.0 publish-all
```

This tags images with both `v1.3.0` and `latest`.

### Testing built images

Run smoke tests on all built images:

```bash
make -f Makefile.publish test-images
```

### Cleaning up local images

Remove all locally built harness images:

```bash
make -f Makefile.publish clean
```

### Configuration variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CONTAINER_RUNTIME` | Auto-detected | `podman` or `docker` |
| `REGISTRY` | `ghcr.io` | Container registry |
| `ORG` | `ansible-automation-platform` | GitHub organization |
| `PROJECT` | `harness` | Project name |
| `VERSION` | Git describe or `latest` | Image version tag |

Example with custom registry:

```bash
make -f Makefile.publish \
  REGISTRY=myregistry.example.com \
  ORG=myorg \
  VERSION=v2.0.0 \
  publish-all
```

---

## Release Process

### 1. Prepare the release

- Update version references if needed
- Update CHANGELOG.md (if we add one)
- Run tests: `make -f Makefile.publish build-all test-images`

### 2. Tag the release

```bash
git tag -a v1.3.0 -m "Release v1.3.0"
git push origin v1.3.0
git push aap v1.3.0
```

### 3. Build and publish container images

```bash
make -f Makefile.publish login
make -f Makefile.publish VERSION=v1.3.0 publish-all
```

### 4. Create GitHub release

Via the GitHub UI or:

```bash
gh release create v1.3.0 \
  --title "v1.3.0" \
  --notes "Release notes here" \
  --repo ansible-automation-platform/harness
```

---

## Multi-Architecture Builds

For multi-arch support (amd64 + arm64), use buildx with podman or docker:

```bash
# Create a builder (one-time)
podman manifest create harness-claude-multiarch

# Build for multiple architectures
podman build \
  --platform linux/amd64,linux/arm64 \
  --manifest harness-claude-multiarch \
  --file modules/harness/containers/Containerfile.claude \
  modules/harness/containers

# Push the manifest
podman manifest push harness-claude-multiarch \
  ghcr.io/ansible-automation-platform/harness-claude:v1.3.0
```

*(Future: automate this in Makefile.publish or GitHub Actions)*

---

## Automated Builds (GitHub Actions)

*(Future: add `.github/workflows/publish-images.yml` for automated builds on tag push)*

Example workflow structure:

```yaml
name: Publish Container Images

on:
  push:
    tags:
      - 'v*'

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    permissions:
      packages: write
      contents: read
    strategy:
      matrix:
        provider: [claude, openai, vertex, local]
    steps:
      - uses: actions/checkout@v4
      - name: Login to ghcr.io
        run: echo "${{ secrets.GITHUB_TOKEN }}" | podman login ghcr.io -u ${{ github.actor }} --password-stdin
      - name: Build and push
        run: make -f Makefile.publish VERSION=${{ github.ref_name }} publish-${{ matrix.provider }}
```

---

## Troubleshooting

### Authentication fails

Ensure your GitHub token has the `write:packages` scope:

```bash
gh auth refresh -s write:packages
```

For SSO orgs, authorize the token:

```bash
# Visit the SSO link shown in the error, then re-login
make -f Makefile.publish login
```

### Build fails with "permission denied"

Ensure the entrypoint scripts are executable:

```bash
chmod +x modules/harness/containers/entrypoint-*.sh
```

### Image push fails with "unauthorized"

Check that you're logged in and have push access to the `ansible-automation-platform` org:

```bash
gh auth status
podman login ghcr.io  # or docker login
```

### Container runtime not found

Install podman or docker:

```bash
# macOS
brew install podman
make -f Makefile.publish CONTAINER_RUNTIME=podman build-all

# Linux
sudo dnf install podman
```
