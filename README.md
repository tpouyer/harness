# Harness

A Makefile-driven, container-native AI agent framework for Ansible Automation Platform development. Harness integrates with Jira, GitHub, and your AI provider of choice to bring context-aware assistance directly into your development workflow.

## Overview

Harness assembles context from your Jira story (including the full Epic → Feature → Initiative hierarchy and any linked SDP/Proposal documents from the handbook), your local code changes, and your project's test suite — then uses that context to power a set of AI-assisted development targets:

- **Intent checking** — verifies your code changes align with Jira acceptance criteria
- **Test generation** — generates unit and functional tests from acceptance criteria
- **Test discovery** — finds existing tests that cover your modified code
- **Implementation assistance** — interactive AI help with full project context
- **Spec-driven development** — structured spec → plan → tasks → implement workflow
- **AAP dev environment** — manages a local Kind/Kubernetes AAP instance for functional testing

## Installation

### Dynamic download (recommended)

Add this to the top of your project's `Makefile`:

```makefile
-include $(shell \
  gh api repos/ansible-automation-platform/harness/contents/bootstrap.mk \
    --jq '.content' | base64 -d > .harness 2>/dev/null; \
  echo .harness)
```

This requires the `gh` CLI (GitHub's official CLI tool) which handles enterprise SSO authentication automatically. On first run, this downloads `bootstrap.mk` into `.harness` and clones the full framework into `.harness-framework/`. Both are gitignored. Subsequent runs pull updates in the background without blocking your build.

**Installing gh CLI**: If you don't have `gh` installed:
- macOS: `brew install gh`
- Linux: See [github.com/cli/cli](https://github.com/cli/cli)
- Then authenticate: `gh auth login`

Add both to your `.gitignore`:

```
.harness
.harness-framework/
```

### Override defaults

To use a specific fork or branch, set these variables before the `-include` line:

```makefile
# Customize these for your enterprise org/fork
HARNESS_GITHUB_ORG    ?= your-enterprise-org
HARNESS_GITHUB_REPO   ?= harness-fork
HARNESS_BRANCH        ?= develop
HARNESS_FRAMEWORK_DIR ?= .harness-framework

-include $(shell \
  gh api repos/$(HARNESS_GITHUB_ORG)/$(HARNESS_GITHUB_REPO)/contents/bootstrap.mk \
    --jq '.content' | base64 -d > .harness 2>/dev/null; \
  echo .harness)
```

**Note**: The bootstrap download uses the repository's default branch. The `HARNESS_BRANCH` variable controls which branch is cloned into `.harness-framework/`.

### Local development (no network)

```bash
make HARNESS_BOOTSTRAP=../harness/bootstrap.mk <target>
```

## Configuration

### Project config — `.harness/config.env` (commit this)

```env
HARNESS_JIRA_PROJECT=MYPROJ
HARNESS_BRANCH_PATTERN=([A-Z]+-[0-9]+)
HARNESS_AI_PROVIDER=claude
HARNESS_AI_MODEL=claude-sonnet-4-6
HARNESS_LANGUAGE=python
HARNESS_TEST_FRAMEWORK=pytest
HARNESS_OUTPUT_FORMAT=markdown

# Functional test repo (separate repo where aap-dev tests live)
HARNESS_FUNC_TEST_REPO=../my-functional-tests
HARNESS_FUNC_TEST_BRANCH_PREFIX=harness/
HARNESS_FUNC_TEST_REMOTE=origin
HARNESS_FUNC_TEST_DEFAULT_BRANCH=main

# AAP dev environment
AAP_DEV_PATH=../aap-dev
AAP_DEV_PROFILE=dev
AAP_DEV_AUTO_DEPLOY=true
```

### Local credentials — `.harness.local.env` (gitignore this)

```env
HARNESS_JIRA_BASE_URL=https://your-company.atlassian.net
HARNESS_JIRA_EMAIL=you@redhat.com
HARNESS_JIRA_API_TOKEN=your-token

HARNESS_AI_PROVIDER=claude
HARNESS_AI_API_KEY=sk-ant-...

GITHUB_TOKEN=ghp_...
```

Copy `.harness.local.env.example` from the framework to get started.

### Branch naming

Harness detects your active Jira issue from your branch name. The default pattern matches `PROJ-123` anywhere in the branch name:

```
feature/AAP-1234-my-feature   →  AAP-1234
bugfix/PROJ-99-fix-thing       →  PROJ-99
```

Override with `HARNESS_BRANCH_PATTERN` in `config.env`.

---

## Targets

### Core

| Target | Description |
|--------|-------------|
| `harness/help` | Show all available harness targets |
| `harness/init` | Initialize harness for a new project |
| `harness/config` | Display resolved configuration and validate credentials |
| `harness/update` | Pull the latest harness framework |
| `harness/clean` | Remove cached context and stop paude sessions |

### Context

| Target | Description |
|--------|-------------|
| `harness/context` | Assemble full context (Jira + code) |
| `harness/context/jira` | Fetch and cache Jira context only |
| `harness/context/code` | Analyze local code changes only |
| `harness/context/show` | Display the assembled context |
| `harness/context/detect-issue` | Show the detected Jira issue for the current branch |

### Intent Check

Verifies that your code changes align with the acceptance criteria in your Jira story.

| Target | Description |
|--------|-------------|
| `harness/intent-check` | Full intent check (Jira + code + comparison) |
| `harness/intent-check/jira` | Extract intent from Jira artifacts only |
| `harness/intent-check/code` | Extract intent from code changes only |

### Tests

| Target | Description |
|--------|-------------|
| `harness/suggest-tests` | Generate unit and functional tests from Jira acceptance criteria |
| `harness/find-tests` | Discover existing tests that cover modified code |
| `harness/test-coverage` | Analyze test coverage for modified files |
| `harness/commit-func-tests` | Branch, commit, push, and PR generated functional tests to the functional test repo |

`harness/find-tests` searches both the local repo (unit tests) and `HARNESS_FUNC_TEST_REPO` (functional tests), tagging results by category.

`harness/commit-func-tests` requires `HARNESS_FUNC_TEST_REPO` to be configured and `harness/suggest-tests` to have been run first. It creates a `harness/<ISSUE>` branch in the functional test repo, commits all generated functional tests, pushes, and opens a GitHub PR via the `gh` CLI.

### Implementation Assistance

| Target | Description |
|--------|-------------|
| `harness/assist` | Interactive AI assistance with full Jira + code context |
| `harness/assist/query` | Run a single query against the assistant |
| `harness/cost` | Estimate token cost for an assist session |

### Spec-Driven Development

A structured workflow for translating Jira stories into implementable specs.

| Target | Description |
|--------|-------------|
| `harness/spec-kit/install` | Install the spec-kit CLI tool |
| `harness/spec-kit/specify` | Generate a spec from the current Jira story |
| `harness/spec-kit/specify-manual` | Create a spec interactively (no Jira required) |
| `harness/spec-kit/plan` | Create an implementation plan from the spec |
| `harness/spec-kit/tasks` | Break the plan into actionable tasks |
| `harness/spec-kit/implement` | Start AI-assisted implementation |
| `harness/spec-kit/workflow` | Run the full workflow: specify → plan → tasks |
| `harness/spec-kit/constitution` | Set up project principles and guidelines |
| `harness/spec-kit/view-spec` | View the current spec |
| `harness/spec-kit/view-plan` | View the current plan |
| `harness/spec-kit/view-tasks` | View the current tasks |
| `harness/spec-kit/status` | Show spec-kit status for the current issue |
| `harness/spec-kit/clean` | Remove generated spec-kit files |

### AAP Dev Environment

Manages a local Kind/Kubernetes AAP instance for functional test development.

| Target | Description |
|--------|-------------|
| `harness/aap-dev/install` | Clone and set up the aap-dev repository |
| `harness/aap-dev/start` | Start the AAP development environment |
| `harness/aap-dev/stop` | Stop the environment and remove the Kind cluster |
| `harness/aap-dev/status` | Show AAP pod status |
| `harness/aap-dev/deploy` | Deploy local changes to the running AAP instance |
| `harness/aap-dev/ensure-running` | Deploy AAP if not already running |
| `harness/aap-dev/wait-up` | Wait for the AAP API to become available |
| `harness/aap-dev/url` | Show the AAP access URL |
| `harness/aap-dev/admin-password` | Get the AAP admin password |
| `harness/aap-dev/logs` | Tail AAP logs |
| `harness/aap-dev/events` | Show Kubernetes events across all namespaces |
| `harness/aap-dev/shell` | Open a shell in the aap-dev directory |
| `harness/aap-dev/apply-license` | Apply an AAP license |
| `harness/aap-dev/backup` | Backup the AAP PostgreSQL database |
| `harness/aap-dev/restore` | Restore the AAP database from backup |
| `harness/aap-dev/versions` | List available AAP versions |
| `harness/aap-dev/update` | Update aap-dev to the latest version |
| `harness/aap-dev/registry-login` | Login to required container registries |
| `harness/aap-dev/clean` | Remove the Kind cluster and kubeconfig |
| `harness/aap-dev/uninstall` | Remove the aap-dev directory entirely |

#### AAP Test Targets

All test targets automatically ensure AAP is deployed before running.

| Target | Description |
|--------|-------------|
| `harness/aap-dev/test` | Run all ATF core tests |
| `harness/aap-dev/test/all` | Run all component test suites |
| `harness/aap-dev/test/controller` | Run controller component tests |
| `harness/aap-dev/test/eda` | Run EDA component tests |
| `harness/aap-dev/test/hub` | Run Hub component tests |
| `harness/aap-dev/test/portal` | Run ansible-portal component tests |
| `harness/aap-dev/test/platform-services` | Run platform-services tests |
| `harness/aap-dev/test/emerging-services` | Run emerging-services tests |
| `harness/aap-dev/test/init` | Initialize the ATF test suite |

### Paude Sessions

[Paude](https://github.com/ansible/paude) runs AI agents in isolated, network-restricted containers.

| Target | Description |
|--------|-------------|
| `harness/paude/create` | Create a new paude session for the current issue |
| `harness/paude/start` | Start or resume a paude session |
| `harness/paude/stop` | Stop the current paude session |
| `harness/paude/list` | List all active harness paude sessions |
| `harness/paude/logs` | Show logs from the current session |

### Dependencies

| Target | Description |
|--------|-------------|
| `harness/deps` | Install all dependencies |
| `harness/deps/check` | Check status of all dependencies |
| `harness/deps/paude` | Install paude |
| `harness/deps/jq` | Install jq |
| `harness/deps/podman` | Install podman |
| `harness/deps/gh` | Install GitHub CLI |
| `harness/deps/python` | Install/upgrade Python and pip |
| `harness/deps/podman-init` | Initialize podman machine (macOS only) |

---

## Typical Workflows

### Standard development workflow

```bash
# 1. Check out a branch named with your Jira issue
git checkout -b feature/AAP-1234-add-new-feature

# 2. Assemble context (fetches Jira + analyzes code changes)
make harness/context

# 3. Verify your changes align with the story
make harness/intent-check

# 4. Find existing tests that cover your changes
make harness/find-tests

# 5. Generate new tests for any gaps
make harness/suggest-tests

# 6. Get implementation help
make harness/assist
```

### Functional test PR workflow

```bash
# After running harness/suggest-tests:
make harness/commit-func-tests
# → creates harness/AAP-1234 branch in HARNESS_FUNC_TEST_REPO
# → commits all generated functional tests
# → pushes and opens a GitHub PR
```

### Spec-driven development workflow

```bash
git checkout -b feature/AAP-5678-complex-feature

# Generate a full spec from the Jira story, then plan and break into tasks
make harness/spec-kit/workflow

# Review the generated files
make harness/spec-kit/view-spec
make harness/spec-kit/view-plan
make harness/spec-kit/view-tasks

# Start implementing with AI assistance
make harness/spec-kit/implement
```

### AAP dev environment workflow

```bash
# First-time setup
make harness/aap-dev/install

# Start the environment
make harness/aap-dev/start

# Deploy your changes and run tests
make harness/aap-dev/deploy
make harness/aap-dev/test

# Stop when done
make harness/aap-dev/stop
```

---

## Unit vs Functional Tests

Harness distinguishes between two test categories:

| | Unit tests | Functional tests |
|---|---|---|
| **Location** | Local project repo (`tests/`) | Separate functional test repo |
| **Requires aap-dev** | No | Yes |
| **Run with** | `make test` | `make harness/aap-dev/test` |
| **PR process** | Committed directly | `make harness/commit-func-tests` |

When generating tests (`harness/suggest-tests`), the AI classifies each test and sets `repo: local` or `repo: functional` accordingly. `harness/commit-func-tests` reads those results and handles only the functional tests, leaving unit tests for you to commit in the normal flow.

---

## AI Providers

Set `HARNESS_AI_PROVIDER` and the corresponding `HARNESS_AI_API_KEY` in `.harness.local.env`:

| Provider | Value | Model example |
|----------|-------|---------------|
| Anthropic Claude | `claude` | `claude-sonnet-4-6` |
| OpenAI | `openai` | `gpt-4o` |
| Google Vertex AI | `vertex` | `gemini-1.5-pro` |
| Local (Ollama) | `local` | `llama3.2` |

You can route different capabilities to different providers:

```env
HARNESS_PROVIDER_INTENT=claude
HARNESS_PROVIDER_TESTS=claude
HARNESS_PROVIDER_ASSIST=openai
HARNESS_PROVIDER_DISCOVERY=local
```

---

## Requirements

- GNU Make
- git
- curl, jq
- Podman (for paude container execution)
- [paude](https://github.com/ansible/paude) (optional — enables full AI agent functionality)
- `gh` CLI (required for `harness/commit-func-tests` PR creation)

### For AAP development
- Kind (Kubernetes in Docker)
- Skaffold
- Docker or Podman

### For spec-kit
- Node.js
- uv (installed automatically by `harness/spec-kit/install`)

---

## Repository Structure

```
harness/
├── bootstrap.mk                  # Downloaded by projects at build time
├── bin/
│   └── install.sh                # Alternative install script
└── modules/harness/
    ├── Makefile                  # Main module (help, init, clean, update)
    ├── Makefile.aap-dev          # AAP dev environment targets
    ├── Makefile.assist           # Implementation assistance targets
    ├── Makefile.config           # Configuration validation targets
    ├── Makefile.context          # Context assembly targets
    ├── Makefile.deps             # Dependency installation targets
    ├── Makefile.intent           # Intent checking targets
    ├── Makefile.paude            # Container session targets
    ├── Makefile.spec-kit         # Spec-driven development targets
    ├── Makefile.tests            # Test generation and discovery targets
    ├── defaults.mk               # Default configuration values
    ├── containers/               # Containerfiles for each AI provider
    ├── prompts/                  # AI prompt templates
    │   ├── assist/
    │   ├── intent-check/
    │   └── test-generation/
    ├── scripts/                  # Shell scripts
    └── templates/                # config.env and local.env examples
```

---

## Contributing

Contributions are welcome! This project is maintained by the Ansible Automation Platform team.

For maintainers who need to build and publish container images or cut releases, see **[MAINTAINERS.md](MAINTAINERS.md)**.

### Reporting issues

- [Open an issue](https://github.com/ansible-automation-platform/harness/issues) for bugs or feature requests
- For security issues, follow the [Ansible security disclosure process](https://docs.ansible.com/ansible/latest/community/security.html)

### License

This project is licensed under the Apache License 2.0.
