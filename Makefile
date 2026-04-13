# --- Configuration & Defaults ---
IMAGE_NAME ?= hyperos
VERSION    ?= 0.1
ARCH       ?= amd64
ISO_NAME   := $(IMAGE_NAME)-v$(VERSION)-$(ARCH).iso
BUILD_DIR  := build
LOG_DIR    := $(BUILD_DIR)/logs

# Tools required for the build process
REQUIRED_CMDS := grub-mkrescue mksquashfs xorriso debootstrap

# --- UI & Logging ---
SHELL := /usr/bin/bash
YELLOW := $(shell tput setaf 3)
GREEN  := $(shell tput setaf 2)
RESET  := $(shell tput sgr0)

.PHONY: all help build clean check-deps info

all: build

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

info: ## Display current build configuration
	@echo "$(YELLOW)Hyper OS Build Configuration:$(RESET)"
	@echo "  Version:  $(VERSION)"
	@echo "  Arch:     $(ARCH)"
	@echo "  Output:   $(ISO_NAME)"

check-deps: ## Ensure build dependencies are installed
	@for cmd in $(REQUIRED_CMDS); do \
		command -v $$cmd >/dev/null 2>&1 || (echo "Error: $$cmd not found. Install it first." && exit 1); \
	done
	@echo "$(GREEN)All dependencies met.$(RESET)"

build: check-deps info ## Build the Hyper OS ISO
	@echo "$(YELLOW)Starting build process...$(RESET)"
	@mkdir -p $(LOG_DIR)
	sudo ./build.sh 2>&1 | tee $(LOG_DIR)/make-build.log
	@if [ -f "$(IMAGE_NAME).iso" ]; then \
		mv $(IMAGE_NAME).iso $(ISO_NAME); \
		echo "$(GREEN)Build successful: $(ISO_NAME)$(RESET)"; \
	fi

clean: ## Purge build artifacts, logs, and ISOs
	@echo "$(YELLOW)Cleaning up...$(RESET)"
	sudo rm -rf $(BUILD_DIR) rootfs iso *.iso
	@echo "$(GREEN)Clean complete.$(RESET)"

debug: ## Run build with shell tracing enabled
	DEBUG=1 sudo -E ./build.sh
