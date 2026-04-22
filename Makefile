SHELL := /usr/bin/env
.SHELLFLAGS = bash -e -c
.DEFAULT_GOAL := help
.ONESHELL:
.SILENT:

ifneq (,$(wildcard ./.env))
    include .env
    export
endif

UNAME_S := $(shell uname -s)

PREFIX ?= /usr/local/bin

RALPH := $(CURDIR)/src/ralph.bash

SHELL_FILES := $(shell find . -type f -name "*.sh" -o -name "*.bash")

##@ Environment setup

.PHONY: setup
setup: setup/copilot setup/shellcheck setup/bats ## Setup development environment

.PHONY: setup/copilot
setup/copilot:
	if command -v copilot &> /dev/null; then
		echo "GitHub Copilot CLI is already installed."
		exit 0
	fi
ifeq ($(UNAME_S),Linux)
	npm install -g @github/copilot
else ifeq ($(UNAME_S),Darwin)
	if command -v brew &> /dev/null; then
		brew install copilot-cli
	elif command -v npm &> /dev/null; then
		npm install -g @github/copilot
	else
		echo "Error: Neither Homebrew nor npm is available. Please install one of them to proceed."
		exit 1
	fi
else
	
endif

.PHONY: setup/shellcheck
setup/shellcheck: ## Install shellcheck
	if command -v shellcheck &> /dev/null; then
		echo "ShellCheck is already installed."
		exit 0
	fi
ifeq ($(UNAME_S),Linux)
	sudo apt-get install -y shellcheck
else ifeq ($(UNAME_S),Darwin)
	brew install shellcheck
else
	echo "Unsupported OS: $(UNAME_S)"
	exit 1
endif

.PHONY: setup/bats
setup/bats: ## Install bats-core
	if command -v bats &> /dev/null; then
		echo "bats-core is already installed."
		exit 0
	fi
ifeq ($(UNAME_S),Linux)
	sudo apt-get install -y bats
else ifeq ($(UNAME_S),Darwin)
	brew install bats-core
else
	echo "Unsupported OS: $(UNAME_S)"
	exit 1
endif

##@ Code quality

.PHONY: check
check: check/lint check/test ## Check code for linting and quality issues

.PHONY: check/lint
check/lint: ## Check code for linting and quality issues
	shellcheck $(SHELL_FILES)

.PHONY: test
test: ## Run unit tests
	bats tests/

.PHONY: check/test
check/test: test ## Run unit tests as check

##@ Utilities

.PHONY: clean
clean: ## Clean build artifacts
	rm -rf $(CURDIR)/.ralph

.PHONY: install
install: env-PREFIX ## Install the project
	if [ -w "$(PREFIX)" ]; then \
		ln -sf "$(RALPH)" "$(PREFIX)/ralph"
	else
		sudo ln -sf "$(RALPH)" "$(PREFIX)/ralph"
	fi

##@ Helpers

env-%: ## Check for env var
	if [ -z "$($*)" ]; then \
		echo "Error: Environment variable '$*' is not set."; \
		exit 1; \
	fi

.PHONY: help
help: ## Displays help info
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
