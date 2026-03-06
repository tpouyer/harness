# Harness Module - AI Agent Framework
# Makefile-driven, container-native AI agent framework with Jira integration

SHELL := /bin/bash

# Include sub-modules
-include $(HARNESS_PATH)/modules/harness/defaults.mk
-include $(HARNESS_PATH)/modules/harness/Makefile.config
-include $(HARNESS_PATH)/modules/harness/Makefile.context
-include $(HARNESS_PATH)/modules/harness/Makefile.opencode
-include $(HARNESS_PATH)/modules/harness/Makefile.deps
-include $(HARNESS_PATH)/modules/harness/Makefile.aap-dev
-include $(HARNESS_PATH)/modules/harness/Makefile.spec-kit

# Load project and local config (if exists)
-include .harness/config.env
-include .harness.local.env

.PHONY: harness/help
## Display harness module help
harness/help:
	@echo "Harness - AI Agent Framework"
	@echo ""
	@echo "Setup:"
	@echo "  harness/init          Initialize harness (beads, opencode config, MCP servers)"
	@echo "  harness/scaffold      Create starter AGENTS.md, TOOLS.md, SKILLS.md"
	@echo "  harness/deps          Install all dependencies"
	@echo "  harness/deps/check    Check dependency status"
	@echo "  harness/config        Display resolved configuration"
	@echo ""
	@echo "Jira Sync:"
	@echo "  harness/jira-pull     Pull Epic from Jira into beads (EPIC=AAP-XXXXX)"
	@echo "  harness/jira-push     Push beads changes back to Jira"
	@echo "  harness/jira-sync     Bidirectional sync with conflict resolution"
	@echo "  harness/jira-status   Show sync state"
	@echo ""
	@echo "Work Planning & Execution:"
	@echo "  harness/plan          Decompose Epic into tasks with mandatory stories (EPIC=AAP-XXXXX)"
	@echo "  harness/ready         Show unblocked tasks"
	@echo "  harness/board         Full task board with dependencies"
	@echo "  harness/work          Single opencode session"
	@echo "  harness/swarm         Launch parallel swarm of opencode agents"
	@echo "  harness/swarm-status  Check swarm progress"
	@echo "  harness/epic-status   Check epic completion (EPIC=AAP-XXXXX)"
	@echo "  harness/status        Combined status overview"
	@echo ""
	@echo "AAP Development Environment:"
	@echo "  harness/aap-dev/help  Show all aap-dev commands"
	@echo ""
	@echo "Legacy Targets:"
	@echo "  harness/context       Assemble context (Jira + code)"
	@echo "  harness/intent-check  Check alignment between Jira and code"
	@echo "  harness/suggest-tests Generate tests from acceptance criteria"
	@echo "  harness/find-tests    Discover existing tests"
	@echo "  harness/assist        Interactive implementation assistance"
	@echo ""
	@echo "Configuration:"
	@echo "  EPIC                  Jira Epic key for plan/sync targets"
	@echo "  HARNESS_AI_PROVIDER   AI provider (anthropic|openai|local|vertex)"
	@echo "  HARNESS_AI_MODEL      AI model (default: claude-sonnet-4-6)"
	@echo "  HARNESS_SWARM_WORKERS Number of parallel swarm workers (default: 3)"
	@echo ""
	@echo "Examples:"
	@echo "  make harness/init"
	@echo "  make harness/plan EPIC=AAP-65162"
	@echo "  make harness/swarm"
	@echo "  make harness/jira-push"

# harness/init and harness/clean are defined in Makefile.opencode

.PHONY: harness/update
## Update harness to latest version
harness/update:
	@echo "Updating harness..."
	@cd $(HARNESS_PATH) && git pull origin $(HARNESS_BRANCH) 2>/dev/null || echo "Update skipped (not a git repo)"
	@echo "Update complete"
