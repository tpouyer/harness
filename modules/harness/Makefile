# Harness Module - AI Agent Framework
# Makefile-driven, container-native AI agent framework with Jira integration

SHELL := /bin/bash

# Include sub-modules
-include $(HARNESS_PATH)/modules/harness/defaults.mk
-include $(HARNESS_PATH)/modules/harness/Makefile.config
-include $(HARNESS_PATH)/modules/harness/Makefile.context
-include $(HARNESS_PATH)/modules/harness/Makefile.paude
-include $(HARNESS_PATH)/modules/harness/Makefile.intent
-include $(HARNESS_PATH)/modules/harness/Makefile.tests
-include $(HARNESS_PATH)/modules/harness/Makefile.assist
-include $(HARNESS_PATH)/modules/harness/Makefile.deps

# Load project and local config (if exists)
-include .harness/config.env
-include .harness.local.env

.PHONY: harness/help
## Display harness module help
harness/help:
	@echo "Harness - AI Agent Framework"
	@echo ""
	@echo "Setup & Dependencies:"
	@echo "  harness/init          Initialize harness for this project"
	@echo "  harness/deps          Install all dependencies (paude, jq, podman)"
	@echo "  harness/deps/check    Check dependency status"
	@echo "  harness/deps/help     Show all dependency install options"
	@echo ""
	@echo "Core Targets:"
	@echo "  harness/config        Display resolved configuration"
	@echo "  harness/context       Assemble and display context (Jira + code)"
	@echo "  harness/intent-check  Check alignment between Jira and code"
	@echo "  harness/suggest-tests Generate tests from Jira acceptance criteria"
	@echo "  harness/find-tests    Discover existing tests for modified code"
	@echo "  harness/assist        Interactive implementation assistance"
	@echo "  harness/cost          Estimate token cost for a command"
	@echo "  harness/clean         Remove cached context and stop sessions"
	@echo "  harness/update        Update harness to latest version"
	@echo ""
	@echo "Configuration:"
	@echo "  HARNESS_ISSUE         Override Jira issue detection"
	@echo "  HARNESS_AI_PROVIDER   AI provider (claude|openai|local|vertex)"
	@echo "  HARNESS_DRY_RUN       Show prompt without calling agent"
	@echo "  HARNESS_OUTPUT_FORMAT Output format (markdown|json)"
	@echo "  HARNESS_NO_CACHE      Skip Jira cache"
	@echo ""
	@echo "Examples:"
	@echo "  make harness/deps             # Install all dependencies"
	@echo "  make harness/intent-check"
	@echo "  make harness/intent-check HARNESS_ISSUE=PROJ-1234"
	@echo "  make harness/assist HARNESS_AI_PROVIDER=openai"

.PHONY: harness/init
## Initialize harness for a project
harness/init:
	@echo "Initializing Harness..."
	@mkdir -p .harness/.cache
	@mkdir -p .harness/prompts
	@if [ ! -f .harness/config.env ]; then \
		cp $(HARNESS_PATH)/modules/harness/templates/config.env.example .harness/config.env; \
		echo "Created .harness/config.env"; \
	fi
	@if [ ! -f .harness.local.env ]; then \
		cp $(HARNESS_PATH)/modules/harness/templates/local.env.example .harness.local.env.example; \
		echo "Created .harness.local.env.example"; \
		echo "Copy to .harness.local.env and add your credentials"; \
	fi
	@echo ""
	@echo "Validating prerequisites..."
	@$(HARNESS_PATH)/modules/harness/scripts/validate-prereqs.sh
	@echo ""
	@echo "Harness initialized successfully!"
	@echo "Next steps:"
	@echo "  1. Edit .harness/config.env with your project settings"
	@echo "  2. Copy .harness.local.env.example to .harness.local.env"
	@echo "  3. Add your credentials to .harness.local.env"
	@echo "  4. Run 'make harness/config' to validate"

.PHONY: harness/clean
## Remove cached context and stop paude sessions
harness/clean:
	@echo "Cleaning harness cache..."
	@rm -rf .harness/.cache/*
	@echo "Stopping paude sessions..."
	@$(HARNESS_PATH)/modules/harness/scripts/paude-session.sh cleanup || true
	@echo "Clean complete"

.PHONY: harness/update
## Update harness to latest version
harness/update:
	@echo "Updating harness..."
	@cd $(HARNESS_PATH) && git pull origin $(HARNESS_BRANCH) 2>/dev/null || echo "Update skipped (not a git repo)"
	@echo "Update complete"
