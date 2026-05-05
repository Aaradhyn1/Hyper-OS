# =========================
# Hyper OS Build Orchestrator (v2)
# =========================

SHELL := /usr/bin/env bash
.ONESHELL:
.SHELLFLAGS := -Eeuo pipefail -c

# =========================
# Config
# =========================
IMAGE_NAME ?= hyperos
VERSION    ?= 0.1
ARCH       ?= amd64

ISO_NAME   := $(IMAGE_NAME)-v$(VERSION)-$(ARCH).iso
BUILD_DIR  := build
LOG_DIR    := $(BUILD_DIR)/logs
STAMP_DIR  := $(BUILD_DIR)/.stamps

REQUIRED_CMDS := grub-mkrescue mksquashfs xorriso debootstrap sha256sum

# =========================
# UI
# =========================
YELLOW := $(shell tput setaf 3)
GREEN  := $(shell tput setaf 2)
RED    := $(shell tput setaf 1)
RESET  := $(shell tput sgr0)

log = echo "$(YELLOW)[HYPER]$(RESET) $1"
ok  = echo "$(GREEN)[OK]$(RESET) $1"
err = echo "$(RED)[ERR]$(RESET) $1"

# =========================
# Phony Targets
# =========================
.PHONY: all help build clean check-deps info debug verify ci

all: build

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
	awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-18s\033[0m %s\n", $$1, $$2}'

info: ## Show build config
	@$(call log,"Build Configuration")
	@echo "  Version: $(VERSION)"
	@echo "  Arch:    $(ARCH)"
	@echo "  ISO:     $(ISO_NAME)"

# =========================
# Dependency Check
# =========================
check-deps: ## Validate dependencies
	@for cmd in $(REQUIRED_CMDS); do \
		command -v $$cmd >/dev/null || { $(call err,"Missing $$cmd"); exit 1; }; \
	done
	@$(call ok,"Dependencies satisfied")

# =========================
# Core Build
# =========================
$(STAMP_DIR)/build.done: build.sh | check-deps
	@mkdir -p $(LOG_DIR) $(STAMP_DIR)
	@$(call log,"Starting build pipeline")

	@sudo ./build.sh 2>&1 | tee $(LOG_DIR)/build.log

	@test -f "$(IMAGE_NAME).iso" || { $(call err,"ISO not generated"); exit 1; }

	@mv "$(IMAGE_NAME).iso" "$(ISO_NAME)"
	@sha256sum "$(ISO_NAME)" > "$(ISO_NAME).sha256"

	@touch $@
	@$(call ok,"Build completed → $(ISO_NAME)")

build: $(STAMP_DIR)/build.done ## Build ISO

# =========================
# Verification
# =========================
verify: ## Validate ISO integrity
	@test -f "$(ISO_NAME)" || { $(call err,"ISO missing"); exit 1; }
	@sha256sum -c "$(ISO_NAME).sha256"
	@$(call ok,"Checksum verified")

# =========================
# Debug Mode
# =========================
debug: ## Build with tracing
	@$(call log,"Debug mode enabled")
	@DEBUG=1 sudo -E bash -x ./build.sh

# =========================
# CI Mode (Non-root safe wrapper)
# =========================
ci: ## CI-safe execution
	@$(call log,"Running CI pipeline")
	@$(MAKE) check-deps
	@sudo -E $(MAKE) build
	@$(MAKE) verify

# =========================
# Clean
# =========================
clean: ## Remove all artifacts
	@$(call log,"Cleaning workspace")
	@sudo rm -rf $(BUILD_DIR) rootfs iso *.iso *.sha256
	@$(call ok,"Clean complete")
