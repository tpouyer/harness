# CLAUDE.md

## Project Overview
Harness is a Makefile-driven AI agent framework for AAP development. It uses OpenCode + SwarmTools + Beads for multi-agent workflows with Jira integration, GitHub handbook document fetching, and spec-driven development.

## Repository Layout
- `Makefile` — top-level, includes `modules/*/Makefile`
- `Makefile.test` — self-test framework (jira fetch tests)
- `modules/harness/Makefile` — main module, includes sub-Makefiles (config, context, opencode, deps, aap-dev, spec-kit)
- `modules/harness/defaults.mk` — default configuration values
- `modules/harness/Makefile.opencode` — OpenCode + SwarmTools + Beads integration (init, plan, swarm, jira sync)
- `modules/harness/Makefile.aap-dev` — AAP development environment management
- `modules/harness/mcp/jira-context-server.sh` — MCP server for Jira context (4 tools)
- `modules/harness/mcp/aap-dev-server.sh` — MCP server for AAP-Dev (27 tools)
- `modules/harness/scripts/jira-fetch.sh` — Jira context fetching with full hierarchy traversal
- `modules/harness/scripts/detect-issue.sh` — Jira issue detection from branch/commit/env
- `modules/harness/scripts/generate-opencode-config.sh` — generates .opencode.json
- `modules/harness/prompts/plan/` — 9 mandatory story templates (m1-m9)
- `modules/harness/templates/` — AGENTS.md.example, TOOLS.md.example, SKILLS.md.example, opencode.json.tmpl

## Remotes
- `origin` — user fork (tpouyer/harness)
- `aap` — upstream (ansible-automation-platform/harness)
- Always push to both remotes

## Build and Test Commands
```bash
# Unit + integration tests
make -f Makefile.test test

# Full suite
make -f Makefile.test test-all

# Run specific test group
make -f Makefile.test test/jira/detect-issue
make -f Makefile.test test/jira/fetch-inspect
```

## Agent Stack
- **OpenCode** — pinned terminal AI coding assistant (multi-provider)
- **SwarmTools** — multi-agent coordination, task decomposition, parallel workers
- **Beads** — distributed git-backed issue tracker (Dolt DB), bidirectional Jira sync via `bd sync --tracker jira`

## MCP Servers
Two MCP servers provide tools to OpenCode agents:

### harness-jira (4 tools)
- `jira_fetch_context` — full Jira hierarchy + custom fields + acceptance criteria + handbook docs
- `jira_detect_issue` — detect issue from branch/commit/env
- `jira_create_issue` — create Jira issues (for cross-team filing)
- `jira_add_comment` — add comments to existing issues

### harness-aap-dev (25 tools)
Environment, testing, source configuration, data seeding, content regeneration, observability, and management tools. All accept optional `instance_id` for concurrent swarm operation.

## Instruction Files (for consuming repos)
- `AGENTS.md` — repo structure, build process, test locations, documentation sources, team ownership
- `TOOLS.md` — MCP tool documentation for AI agents
- `SKILLS.md` — specialized workflows, cross-team Jira filing, hot reload, security process

## Plan Target & Mandatory Stories
`make harness/plan EPIC=AAP-XXXXX` creates 9 mandatory stories under every epic:
- M1: Test Discovery, M2: Test Creation (requires-aap), M3: Security Audit, M4: Quality Audit
- M5: Intent Alignment, M6: Test Execution (requires-aap), M7: Complexity Audit
- M8: Compatibility Check (requires-aap for API spec diffing), M9: Documentation Currency
Dependency graph ensures audits run after feature work completes.
Tasks labeled `requires-aap` get their own AAP-Dev instance; all others run as plain OpenCode sessions.
Feature tasks should only get `requires-aap` if they need functional/integration tests against a live AAP deployment.

## AAP-Dev Integration
- Default clone location: `.harness/aap-dev` (override via `AAP_DEV_DIR` in `.harness.local.env`)
- Supports concurrent instances via `instance_id` (separate kind clusters, ports 30000-44999)
- Source configuration via answers files (non-interactive `make configure-sources`)
- Hot reload with local paths (`SKAFFOLD_TRIGGER=polling`)
- Data seeding via Ansible playbooks (`ansible.platform` + `ansible.controller` collections)
- Observability via Prometheus + Grafana stack

## Jira Custom Fields
Red Hat Jira uses non-standard custom field IDs. The script discovers them dynamically from `/rest/api/{version}/field`:
- **Parent Link** — links Epic to Initiative/Outcome (override: `HARNESS_JIRA_PARENT_LINK_FIELD`)
- **Epic Link** — links Story to Epic (override: `HARNESS_JIRA_EPIC_LINK_FIELD`)
- **Acceptance Criteria** — (override: `HARNESS_JIRA_AC_FIELD`)

## Hierarchy
`jira-fetch.sh` traverses: Story -> Epic -> Initiative -> Outcome (up to 5 levels). Acceptance criteria is extracted at every level. Handbook documents linked as GitHub PRs are fetched using commit SHA via `gh` CLI.

## Key Implementation Details
- `gh` CLI calls must unset `GITHUB_TOKEN`/`GH_TOKEN` env vars to prevent overriding keyring auth with a less-privileged token
- GitHub PR content fetched by head commit SHA (not branch ref) to survive branch deletion on merged PRs
- Filenames with spaces require `while IFS= read -r` loops and URL-encoded paths for GitHub API
- Default AI model: `claude-sonnet-4-6` (configurable via `HARNESS_AI_MODEL`)

## Credentials
- `.test.harness.local.env` — test credentials (gitignored)
- `.harness.local.env` — runtime credentials (gitignored)
- GCP: `GCP_PROJECT_ID` and `GCP_QUOTA_PROJECT` can differ (billing vs API project)
