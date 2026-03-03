# Harness - AI Agent Framework
# Makefile-driven, container-native AI agent framework with Jira integration

SHELL := /bin/bash
export HARNESS_PATH ?= $(shell pwd)

# Default target
.PHONY: help
help:
	@echo "Harness - Makefile Module System"
	@echo ""
	@echo "Available modules:"
	@echo "  harness    - AI agent framework with Jira integration"
	@echo ""
	@echo "Run 'make harness/help' for harness-specific targets"

# Include all modules
-include $(HARNESS_PATH)/modules/*/Makefile

# Module loader pattern
define include_module
-include $(HARNESS_PATH)/modules/$(1)/Makefile
endef

.PHONY: init
init:
	@echo "Harness initialized"
