# claude-workspace — local + CI entry point.
#
# All targets run inside the Dockerfile.test image so behaviour matches CI
# (CLAUDE.md "驗證一律走 Docker"). Direct host bats / shellcheck / hadolint
# is not supported.

IMAGE := claude-workspace-test:local
HADOLINT_IMAGE := hadolint/hadolint:latest-alpine

.PHONY: help build test lint hadolint check clean

help:  ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | sort \
	  | awk -F ':.*?## ' '{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

build:  ## Build the test docker image
	docker build -f Dockerfile.test -t $(IMAGE) .

test: build  ## Run bats specs (smoke + integration) inside docker
	docker run --rm $(IMAGE)

lint: build  ## Run shellcheck against all hook scripts inside docker
	docker run --rm --entrypoint sh $(IMAGE) -c \
	  'shellcheck /work/.claude/hooks/*.sh'

hadolint:  ## Lint Dockerfile.test with Hadolint
	docker run --rm -i \
	  -v "$(CURDIR)/.hadolint.yaml:/.hadolint.yaml:ro" \
	  $(HADOLINT_IMAGE) \
	  hadolint --config /.hadolint.yaml - < Dockerfile.test

check: lint hadolint test  ## Full CI gate: shellcheck + Hadolint + bats

clean:  ## Remove the test image
	docker image rm $(IMAGE) 2>/dev/null || true
