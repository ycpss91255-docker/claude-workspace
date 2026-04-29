# claude-workspace test infra — local + CI entry point.
#
# All targets run inside the .claude/test/Dockerfile image so behaviour matches
# CI exactly (CLAUDE.md "驗證一律走 Docker"). Direct host bats / shellcheck /
# hadolint is not supported.
#
# Run from this directory (.claude/test/), or via `make -C .claude/test <target>`
# from the repo root.

IMAGE := claude-workspace-test:local
HADOLINT_IMAGE := hadolint/hadolint:latest-alpine

# Build context = repo root (two levels up); COPY paths inside the Dockerfile
# stay relative to that context (`.claude/hooks/`, `.claude/scripts/`).
REPO_ROOT := $(CURDIR)/../..

.PHONY: help build test lint hadolint tree-check check clean

help:  ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | sort \
	  | awk -F ':.*?## ' '{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

build:  ## Build the test docker image
	docker build -f $(CURDIR)/Dockerfile -t $(IMAGE) $(REPO_ROOT)

test: build  ## Run bats specs (smoke + integration) inside docker
	docker run --rm $(IMAGE)

lint: build  ## Run shellcheck against all hook + helper scripts inside docker
	docker run --rm --entrypoint sh $(IMAGE) -c \
	  'shellcheck /work/.claude/hooks/*.sh /work/.claude/scripts/*.sh'

hadolint:  ## Lint .claude/test/Dockerfile with Hadolint
	docker run --rm -i \
	  -v "$(REPO_ROOT)/.hadolint.yaml:/.hadolint.yaml:ro" \
	  $(HADOLINT_IMAGE) \
	  hadolint --config /.hadolint.yaml - < $(CURDIR)/Dockerfile

tree-check:  ## Audit CLAUDE.md `.claude/` tree listing vs filesystem (host bash+python3, no docker)
	$(REPO_ROOT)/.claude/scripts/check-claude-md-tree.sh $(REPO_ROOT)/CLAUDE.md

check: lint hadolint test tree-check  ## Full CI gate: shellcheck + Hadolint + bats + tree audit

clean:  ## Remove the test image
	docker image rm $(IMAGE) 2>/dev/null || true
