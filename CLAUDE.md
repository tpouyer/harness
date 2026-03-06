# CLAUDE.md

## Project Overview
Harness is a Makefile-driven, container-native AI agent framework for AAP development with Jira integration, GitHub handbook document fetching, and spec-driven workflows.

## Repository Layout
- `Makefile` — top-level, includes `modules/*/Makefile`
- `Makefile.test` — self-test framework (24 jira fetch tests + container image tests)
- `Makefile.publish` — container image build/push/publish to quay.io/aap
- `modules/harness/Makefile` — main module, includes sub-Makefiles (config, context, paude, intent, tests, assist, deps, aap-dev, spec-kit)
- `modules/harness/defaults.mk` — default configuration values
- `modules/harness/scripts/jira-fetch.sh` — Jira context fetching with full hierarchy traversal
- `modules/harness/scripts/detect-issue.sh` — Jira issue detection from branch/commit/env
- `modules/harness/containers/` — Containerfiles + entrypoints per AI provider (claude, openai, vertex, local)
- `modules/harness/templates/` — config.env.example and local.env.example

## Remotes
- `origin` — user fork (tpouyer/harness)
- `aap` — upstream (ansible-automation-platform/harness)
- Always push to both remotes

## Build and Test Commands
```bash
# Unit + integration tests (no containers needed)
make -f Makefile.test test

# Full suite including container build/smoke/model tests
make -f Makefile.test test-all

# Run specific test group
make -f Makefile.test test/jira/detect-issue
make -f Makefile.test test/containers/build
make -f Makefile.test test/containers/smoke
make -f Makefile.test test/containers/model-claude

# Inspect Jira fetch output
make -f Makefile.test test/jira/fetch-inspect

# Build and publish container images
make -f Makefile.publish build-all
make -f Makefile.publish publish-all
```

## Container Registry
- Default: `quay.io/aap` (configurable via `REGISTRY` and `ORG`)
- Images: `harness-claude`, `harness-openai`, `harness-vertex`, `harness-local`

## Jira Custom Fields
Red Hat Jira uses non-standard custom field IDs. The script discovers them dynamically from `/rest/api/{version}/field`:
- **Parent Link** — links Epic to Initiative/Outcome (override: `HARNESS_JIRA_PARENT_LINK_FIELD`)
- **Epic Link** — links Story to Epic (override: `HARNESS_JIRA_EPIC_LINK_FIELD`)
- **Acceptance Criteria** — (override: `HARNESS_JIRA_AC_FIELD`)

## Hierarchy
`jira-fetch.sh` traverses: Story -> Epic -> Initiative -> Outcome (up to 5 levels). Acceptance criteria is extracted at every level. Handbook documents linked as GitHub PRs are fetched using commit SHA via `gh` CLI.

## Paude (Container Session Manager)
`paude-session.sh` wraps the `paude` CLI for managing AI agent container sessions.
- Valid paude subcommands: `create`, `start`, `stop`, `connect`, `list`, `cp`, `remote`, `delete`
- `create` options: `--yolo`, `--allowed-domains`, `--backend`, `--args`, `--rebuild`, `--dry-run`, `--platform`
- **No** `--image`, `--mount`, `--env`, `interactive`, `exec`, `rm`, or `logs` commands exist
- `--allowed-domains` must be repeated per domain; `build_domain_flags()` handles splitting
- `delete` requires `--confirm` flag
- `start` starts and connects to a session; `connect` attaches to an already-running session
- `cp` copies files between local and session (e.g. prompts in, results out)
- `ensure_session()` auto-creates a session if none exists (used by `run`)
- The `run` action: ensures session, renders prompt, copies via `paude cp`, then `paude start`
- Simulation mode only triggers when paude is not installed

## Key Implementation Details
- `gh` CLI calls must unset `GITHUB_TOKEN`/`GH_TOKEN` env vars to prevent overriding keyring auth with a less-privileged token
- GitHub PR content fetched by head commit SHA (not branch ref) to survive branch deletion on merged PRs
- Filenames with spaces require `while IFS= read -r` loops and URL-encoded paths for GitHub API
- Container volume mounts need `chmod 777` on temp dirs for the `harness` user to write results
- Default AI model: `claude-sonnet-4-6` (configurable via `HARNESS_AI_MODEL`)

## Credentials
- `.test.harness.local.env` — test credentials (gitignored)
- `.harness.local.env` — runtime credentials (gitignored)
- GCP: `GCP_PROJECT_ID` and `GCP_QUOTA_PROJECT` can differ (billing vs API project)
