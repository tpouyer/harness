# Harness Bootstrap
# This file is downloaded at build time and bootstraps the harness framework.
# It clones the harness repo locally if not present, then includes it.
#
# Usage in your project Makefile:
#   -include $(shell \
#     gh api repos/ansible-automation-platform/harness/contents/bootstrap.mk \
#       --jq '.content' | base64 -d > .harness 2>/dev/null; \
#     echo .harness)

# ── Configuration (override before including this file) ──────────────────────
HARNESS_GITHUB_ORG    ?= ansible-automation-platform
HARNESS_GITHUB_REPO   ?= harness
HARNESS_BRANCH        ?= main
HARNESS_FRAMEWORK_DIR ?= .harness-framework
# ─────────────────────────────────────────────────────────────────────────────

HARNESS_GITHUB_URL := https://github.com/$(HARNESS_GITHUB_ORG)/$(HARNESS_GITHUB_REPO).git

# Clone on first use; pull to update if already present
ifeq ($(wildcard $(HARNESS_FRAMEWORK_DIR)/Makefile),)
  $(info [harness] Downloading framework from $(HARNESS_GITHUB_URL)...)
  $(shell git clone --quiet --depth=1 --branch=$(HARNESS_BRANCH) \
      $(HARNESS_GITHUB_URL) $(HARNESS_FRAMEWORK_DIR) 2>/dev/null)
else
  # Refresh in the background so the current build is never blocked
  $(shell cd $(HARNESS_FRAMEWORK_DIR) && git pull --quiet --ff-only 2>/dev/null &)
endif

export HARNESS_PATH := $(CURDIR)/$(HARNESS_FRAMEWORK_DIR)

-include $(HARNESS_FRAMEWORK_DIR)/Makefile
