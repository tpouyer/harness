# Build Harness - Forked from cloudposse/build-harness
# Extended with Harness AI agent integration modules

SHELL := /bin/bash
export BUILD_HARNESS_PATH ?= $(shell pwd)

# Default target
.PHONY: help
help:
	@echo "Build Harness - Makefile Module System"
	@echo ""
	@echo "Available modules:"
	@echo "  harness    - AI agent framework with Jira integration"
	@echo ""
	@echo "Run 'make harness/help' for harness-specific targets"

# Include all modules
-include $(BUILD_HARNESS_PATH)/modules/*/Makefile

# Module loader pattern
define include_module
-include $(BUILD_HARNESS_PATH)/modules/$(1)/Makefile
endef

.PHONY: init
init:
	@echo "Build Harness initialized"
