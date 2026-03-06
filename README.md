# Harness

A Makefile-driven AI agent framework for Ansible Automation Platform development. Harness uses OpenCode, SwarmTools, and Beads to enable multi-agent workflows with Jira integration, automated quality gates, and AAP development environment management.

## Overview

Harness brings together three tools into a cohesive, Makefile-driven workflow:

- **[OpenCode](https://github.com/opencode-ai/opencode)** — terminal AI coding assistant (multi-provider, pinned version)
- **[SwarmTools](https://www.swarmtools.ai/)** — multi-agent coordination, parallel task decomposition
- **[Beads](https://github.com/steveyegge/beads)** — distributed git-backed issue tracker with bidirectional Jira sync

Users interact with harness entirely through `make` targets. All dependencies (opencode, swarmtools, beads, dolt) are installable via included make targets.

### What It Does

1. **Pull Epics from Jira** into a local beads database with bidirectional sync
2. **Decompose Epics** into implementation tasks plus 9 mandatory quality stories (security audit, intent alignment, test coverage, etc.)
3. **Run a swarm** of parallel OpenCode agents, each with their own AAP-Dev instance, iterating with hot-reload
4. **Push results back to Jira** — new stories, status updates, and cross-team issues all sync automatically

## Installation

### Dynamic download (recommended)

Add this to the top of your project's `Makefile`:

```makefile
-include $(shell \
  gh api repos/ansible-automation-platform/harness/contents/bootstrap.mk \
    --jq '.content' | base64 -d > .harness.mk 2>/dev/null; \
  echo .harness.mk)
```

This requires the `gh` CLI which handles enterprise SSO authentication automatically. On first run, this downloads `bootstrap.mk` and clones the full framework. Both are gitignored.

Add to `.gitignore`:

```
.harness.mk
.harness-framework/
```

### Override defaults

```makefile
HARNESS_GITHUB_ORG    ?= your-enterprise-org
HARNESS_GITHUB_REPO   ?= harness-fork
HARNESS_BRANCH        ?= develop

-include $(shell \
  gh api repos/$(HARNESS_GITHUB_ORG)/$(HARNESS_GITHUB_REPO)/contents/bootstrap.mk \
    --jq '.content' | base64 -d > .harness.mk 2>/dev/null; \
  echo .harness.mk)
```

### Local development (no network)

```bash
make HARNESS_BOOTSTRAP=../harness/bootstrap.mk <target>
```

---

## Quick Start

```bash
# 1. Install dependencies
make harness/deps

# 2. Initialize harness (creates .beads/, .opencode.json, MCP servers)
make harness/init

# 3. Create starter instruction files
make harness/scaffold

# 4. Edit AGENTS.md, TOOLS.md, SKILLS.md for your project

# 5. Pull an Epic from Jira and decompose into tasks
make harness/plan EPIC=AAP-65162

# 6. Launch parallel swarm of AI agents
make harness/swarm

# 7. Push results back to Jira
make harness/jira-push
```

---

## AI Instruction Files

Harness uses three standardized markdown files to give AI agents context about your project. These files are loaded into every OpenCode session via the `contextPaths` config.

### AGENTS.md — Repository Identity

The primary instruction file. Tells the AI **what this repo is and how to work in it**.

```markdown
# AGENTS.md

## Repository Overview
Brief description of what this project does.

## Language & Runtime
Primary language(s), version(s), package manager.

## Repository Structure
Directory layout with descriptions.

## Build Process
How to build, lint, and run the project locally.

## Test Location
Where tests live. If tests are in a separate repo, specify the repo URL,
branch, and how test directories map to source directories.

## Code Conventions
Naming conventions, file organization, PR/commit format.

## Architecture
Key patterns and decisions.

## Documentation
Where docs live for this component and who owns them.

### Documentation Sources
| Type | Location | Owner |
|------|----------|-------|
| User docs | https://docs.example.com/ | Jira: AAP, component: Documentation |
| API reference | docs/api/ | This team |

### Filing Doc Issues
- Project: AAP
- Issue Type: Task
- Component: Documentation
- Labels: docs-update, harness-generated

## Team Ownership
How to file issues against other teams.

### Component Teams
| Component | Jira Project | Component |
|-----------|-------------|-----------|
| Controller | AAP | Controller |
| Documentation | AAP | Documentation |
| Security | SECBUGS | (security disclosure process) |
```

The **Documentation** and **Team Ownership** sections are critical. They tell the mandatory audit stories (M3 security, M8 compatibility, M9 docs) where to file cross-team Jira issues when findings affect other teams.

### TOOLS.md — Available Tools

Documents the MCP tools available to AI agents. Harness provides two MCP servers with 31 tools total (4 jira + 27 aap-dev):

- **harness-jira** (4 tools) — `jira_fetch_context`, `jira_detect_issue`, `jira_create_issue`, `jira_add_comment`
- **harness-aap-dev** (25 tools) — environment, testing, source configuration, data seeding, content regeneration, observability, management

Add your own project-specific tools here (CLI commands, additional MCP servers, etc.).

### SKILLS.md — Specialized Workflows

Defines higher-level workflows and patterns the AI should follow:

- **Feature implementation pattern** — your team's standard development workflow
- **Cross-team Jira filing** — how to create issues against other teams (security, docs, etc.)
- **Hot reload workflow** — efficient iteration with aap-dev local sources
- **Security requirements** — project-specific security rules
- **Debugging guide** — common issues and diagnosis steps

### Multi-Repo Support

When tests live in a separate repo, `AGENTS.md` declares the mapping:

```markdown
## Test Location
Tests are maintained in a separate repository:
- Repo: git@github.com:org/my-project-tests.git
- Branch: main
- Mapping: src/api/ -> tests/integration/api/
```

The test repo should have its own `AGENTS.md`, `TOOLS.md`, and `SKILLS.md` describing the test structure and conventions.

---

## Configuration

### Project config — `.harness/config.env` (commit this)

```env
HARNESS_JIRA_PROJECT=AAP
HARNESS_JIRA_BASE_URL=https://issues.redhat.com
HARNESS_AI_PROVIDER=anthropic
HARNESS_AI_MODEL=claude-sonnet-4-6
HARNESS_SWARM_WORKERS=3

# Functional test repo
HARNESS_FUNC_TEST_REPO=../my-functional-tests
```

### Local credentials — `.harness.local.env` (gitignore this)

```env
# Jira (Server/DC uses bearer auth with PAT)
HARNESS_JIRA_API_TOKEN=your-jira-pat
HARNESS_JIRA_AUTH_TYPE=bearer

# AI provider API key
HARNESS_AI_API_KEY=sk-...

# Claude via Google Cloud Vertex AI
GCP_PROJECT_ID=your-gcp-project-id
GCP_REGION=us-east5

# AAP-Dev directory override (if you already have it cloned elsewhere)
# AAP_DEV_DIR=/home/engineer/aap-dev
```

**Values must not be quoted** -- Make's `-include` does not strip quotes.

---

## Targets

### Setup

| Target | Description |
|--------|-------------|
| `harness/init` | Initialize harness (beads, opencode config, MCP servers) |
| `harness/scaffold` | Create starter AGENTS.md, TOOLS.md, SKILLS.md |
| `harness/deps` | Install all dependencies (opencode, beads, dolt, swarmtools) |
| `harness/deps/check` | Check status of all dependencies |
| `harness/config` | Display resolved configuration and validate credentials |
| `harness/update` | Pull the latest harness framework |

### Jira Sync

| Target | Description |
|--------|-------------|
| `harness/jira-pull` | Pull Epic from Jira into beads (`EPIC=AAP-XXXXX`) |
| `harness/jira-push` | Push beads changes back to Jira |
| `harness/jira-sync` | Bidirectional sync with conflict resolution |
| `harness/jira-sync-dry` | Dry run — show what would change |
| `harness/jira-status` | Show sync state and linked issues |

### Work Planning & Execution

| Target | Description |
|--------|-------------|
| `harness/plan` | Decompose Epic into tasks + 9 mandatory stories (`EPIC=AAP-XXXXX`) |
| `harness/ready` | Show unblocked tasks ready for work |
| `harness/board` | Full task board with dependencies |
| `harness/work` | Single OpenCode session |
| `harness/swarm` | Launch parallel swarm of OpenCode agents |
| `harness/swarm-status` | Check swarm worker progress |
| `harness/epic-status` | Check epic completion gate (`EPIC=AAP-XXXXX`) |
| `harness/status` | Combined status overview |
| `harness/clean` | Remove cached context and swarm worktrees |

### AAP Dev Environment

| Target | Description |
|--------|-------------|
| `harness/aap-dev/help` | Show all aap-dev commands |
| `harness/aap-dev/install` | Clone aap-dev into `.harness/aap-dev` |
| `harness/aap-dev/start` | Start AAP (creates Kind cluster, deploys, tails logs) |
| `harness/aap-dev/stop` | Stop AAP and remove Kind cluster |
| `harness/aap-dev/status` | Show AAP pod status |
| `harness/aap-dev/deploy` | Deploy AAP non-blocking |
| `harness/aap-dev/ensure-running` | Deploy if not running, wait for API |
| `harness/aap-dev/url` | Show AAP access URL |
| `harness/aap-dev/admin-password` | Get admin password |
| `harness/aap-dev/test` | Run ATF tests (auto-deploys AAP) |
| `harness/aap-dev/test/controller` | Run controller tests |
| `harness/aap-dev/test/eda` | Run EDA tests |
| `harness/aap-dev/test/hub` | Run Hub tests |
| `harness/aap-dev/configure-sources` | Interactive source configuration |
| `harness/aap-dev/configure-sources-auto` | Non-interactive (`ANSWERS_FILE=path`) |
| `harness/aap-dev/show-sources` | Show configured source overrides |
| `harness/aap-dev/reset-sources` | Reset to nightly defaults |
| `harness/aap-dev/seed` | Seed data using default playbook |
| `harness/aap-dev/seed-custom` | Seed with custom playbook (`SEED_PLAYBOOK=path`) |
| `harness/aap-dev/metrics` | Show CPU/memory per pod |
| `harness/aap-dev/observability` | Install Prometheus + Grafana stack |
| `harness/aap-dev/regenerate-containerfiles` | Update Containerfiles from upstream |
| `harness/aap-dev/regenerate-k8s-manifests` | Extract K8s manifests from live AAP |

### Dependencies

| Target | Description |
|--------|-------------|
| `harness/deps/opencode` | Install OpenCode (pinned version) |
| `harness/deps/beads` | Install Beads issue tracker |
| `harness/deps/dolt` | Install Dolt database (beads backend) |
| `harness/deps/swarmtools` | Install SwarmTools coordinator |
| `harness/deps/jq` | Install jq |
| `harness/deps/podman` | Install podman |
| `harness/deps/gh` | Install GitHub CLI |

---

## Mandatory Quality Stories

When `make harness/plan EPIC=AAP-XXXXX` runs, it creates 9 mandatory stories under the epic in addition to AI-decomposed feature tasks. These ensure every epic passes quality gates before closing.

| ID | Story | Priority | Depends On | Requires AAP |
|----|-------|----------|------------|--------------|
| M1 | Test Discovery: find existing test coverage | P1 | -- | No |
| M2 | Test Creation: fill coverage gaps | P1 | M1 | Yes (functional test verification) |
| M3 | Security Audit: OWASP Top 10 review | P0 | features + M2 | No |
| M4 | Quality Audit: readability, maintainability | P1 | features + M2 | No |
| M5 | Intent Alignment: code vs Jira intent (0-100 score) | P0 | features + M2 | No |
| M6 | Test Execution: run full suite, verify all pass | P0 | M2 + features + M8 | Yes |
| M7 | Complexity Audit: unnecessary complexity, bad deps | P1 | features + M2 | No |
| M8 | Compatibility Check: breaking API/schema/config changes | P0 | features + M2 | Yes (API spec diffing) |
| M9 | Documentation Check: verify docs match code, file issues | P2 | features + M8 | No |

The dependency graph ensures:
- **M1** runs immediately in parallel with feature work
- **M2** runs after M1 completes
- **Audits (M3-M5, M7-M8)** run after all features and M2 complete
- **M6** (test execution) runs after audits confirm no blocking issues
- **M9** (docs) runs last, files Jira issues against doc team per AGENTS.md

### Cross-Team Issue Filing

Audit stories (M3, M8, M9) can file Jira issues against other teams when findings require action outside the current team. The process is defined in SKILLS.md and uses AGENTS.md's "Team Ownership" section to determine the correct Jira project and component. All filed issues link back to the originating audit task.

---

## MCP Servers

Harness provides two MCP servers that give OpenCode agents access to Jira and AAP-Dev functionality.

### harness-jira (4 tools)

| Tool | Description |
|------|-------------|
| `jira_fetch_context` | Full Jira hierarchy + custom fields + acceptance criteria + handbook docs |
| `jira_detect_issue` | Detect issue from git branch/commit/environment |
| `jira_create_issue` | Create Jira issues with optional linking (for cross-team filing) |
| `jira_add_comment` | Add comments to existing issues |

### harness-aap-dev (27 tools)

All tools accept optional `instance_id` for concurrent swarm operation (each worker gets its own Kind cluster).

**Environment**: `aap_dev_status`, `aap_dev_ensure_running`, `aap_dev_stop`, `aap_dev_url`, `aap_dev_admin_password`

**Testing**: `aap_dev_test`, `aap_dev_test_init`, `aap_dev_discover_tests`, `aap_dev_commit_func_tests`

**Sources**: `aap_dev_configure_sources`, `aap_dev_show_sources`, `aap_dev_reset_sources`, `aap_dev_sync_status`

**Data**: `aap_dev_seed_default`, `aap_dev_seed_data`

**Content**: `aap_dev_regenerate_containerfiles`, `aap_dev_regenerate_k8s_manifests`

**Observability**: `aap_dev_metrics_top`, `aap_dev_observability_install`, `aap_dev_observability_status`

**API Compatibility**: `aap_dev_download_specs`, `aap_dev_get_baseline_specs`

**Management**: `aap_dev_preflight`, `aap_dev_logs`, `aap_dev_events`, `aap_dev_versions`, `aap_dev_backup`, `aap_dev_restore`

---

## AAP-Dev Instances and the Swarm

Not every swarm worker needs an AAP-Dev instance. Only tasks labeled `requires-aap` get one -- typically M2 (test creation with functional test verification), M6 (full test execution), and feature tasks that involve functional/integration testing.

Tasks like code audits (M3-M5, M7-M8), documentation checks (M9), test discovery (M1), and feature implementation that only needs unit tests run as plain OpenCode sessions against the local codebase -- no Kind cluster, no deployment overhead.

### Concurrent Instances (for `requires-aap` tasks)

When multiple tasks need AAP-Dev, each gets its own isolated deployment:

- Different `AAP_PORT` (range 30000-44999, auto-derived from `instance_id`)
- Different `KIND_CLUSTER_NAME` (auto-derived)
- Separate directory (harness creates git worktrees under `.harness/aap-dev-swarm-wN`)

The shared container registry is preserved -- harness never runs `really-clean` from MCP tools.

`make harness/swarm` automatically counts `requires-aap` tasks and only creates worktrees for those.

### Hot Reload

When using local source paths, Skaffold auto-syncs file changes into running containers without rebuilding. Set `polling: true` in `aap_dev_configure_sources` (or `SKAFFOLD_TRIGGER=polling`) when using local paths.

---

## Typical Workflows

### Epic-to-code workflow (swarm)

```bash
# Pull an epic and decompose with mandatory quality stories
make harness/plan EPIC=AAP-65162

# Launch parallel agents (each with own AAP instance)
make harness/swarm

# Check progress
make harness/epic-status EPIC=AAP-65162

# Push results back to Jira
make harness/jira-push
```

### Single-agent development

```bash
# Initialize and start working
make harness/init
make harness/work
# OpenCode launches with AGENTS.md, TOOLS.md, SKILLS.md context
# and access to jira + aap-dev MCP tools
```

### AAP-Dev with custom sources

```bash
# Test your feature branch in a full AAP deployment
make harness/aap-dev/install
make harness/aap-dev/configure-sources   # select your component + branch
make harness/aap-dev/start               # builds from your branch
make harness/aap-dev/test/controller     # run tests against it
make harness/aap-dev/reset-sources       # back to defaults
```

### AAP-Dev with observability

```bash
make harness/aap-dev/start
make harness/aap-dev/observability
# Grafana at http://localhost:13000 (admin/prom-operator)
make harness/aap-dev/metrics
```

---

## Requirements

- GNU Make, git, curl, jq
- `gh` CLI (GitHub authentication)

### AI Agent Stack (installed via `make harness/deps`)
- [OpenCode](https://github.com/opencode-ai/opencode) (pinned version)
- [Beads](https://github.com/steveyegge/beads) + [Dolt](https://www.dolthub.com/)
- [SwarmTools](https://www.swarmtools.ai/) (requires Node.js)

### For AAP-Dev
- Podman
- Kind, Skaffold (installed by aap-dev)

---

## Repository Structure

```
harness/
├── bootstrap.mk                      # Downloaded by projects at build time
├── Makefile                           # Top-level
├── Makefile.test                      # Self-test framework
├── CLAUDE.md                          # Project instructions for AI
└── modules/harness/
    ├── Makefile                       # Main module (help, update)
    ├── Makefile.opencode              # OpenCode + SwarmTools + Beads integration
    ├── Makefile.aap-dev               # AAP dev environment management
    ├── Makefile.config                # Configuration validation
    ├── Makefile.context               # Context assembly
    ├── Makefile.deps                  # Dependency installation
    ├── Makefile.spec-kit              # Spec-driven development
    ├── defaults.mk                    # Default configuration values
    ├── mcp/                           # MCP servers for AI agents
    │   ├── jira-context-server.sh     # Jira context + issue creation (4 tools)
    │   └── aap-dev-server.sh          # AAP-Dev management (25 tools)
    ├── prompts/
    │   ├── plan/                      # 9 mandatory story templates (m1-m9)
    │   ├── intent-check/              # Intent alignment prompts
    │   └── test-generation/           # Test generation prompts
    ├── scripts/
    │   ├── jira-fetch.sh              # Jira hierarchy traversal + custom fields
    │   ├── detect-issue.sh            # Issue detection from branch/commit
    │   ├── generate-opencode-config.sh # Generates .opencode.json
    │   ├── test-discovery.sh          # Structural test discovery
    │   ├── func-test-pr.sh            # Functional test PR creation
    │   └── ...
    └── templates/
        ├── AGENTS.md.example          # Starter AGENTS.md
        ├── TOOLS.md.example           # Starter TOOLS.md
        ├── SKILLS.md.example          # Starter SKILLS.md
        ├── opencode.json.tmpl         # OpenCode config template
        ├── config.env.example
        └── local.env.example
```

---

## Contributing

Contributions are welcome! This project is maintained by the Ansible Automation Platform team.

For maintainers, see **[MAINTAINERS.md](MAINTAINERS.md)**.

### Reporting issues

- [Open an issue](https://github.com/ansible-automation-platform/harness/issues) for bugs or feature requests
- For security issues, follow the [Ansible security disclosure process](https://docs.ansible.com/ansible/latest/community/security.html)

### License

This project is licensed under the Apache License 2.0.
