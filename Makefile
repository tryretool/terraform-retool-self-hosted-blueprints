SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

.PHONY: help
help: ## Display help message
	@echo "Usage:"
	@echo "  make <target>"
	@echo ""
	@echo "Makefile targets:"
	@awk '/^[a-zA-Z._-]+:.*?## .*$$/ { \
		printf "  %-21s %s\n", substr($$1, 1, index($$1, ":")-1), substr($$0, index($$0, "##")+3) \
	}' $(firstword $(MAKEFILE_LIST))

.PHONY: help
changelog-sync: ## Sync CHANGELOG.md from git history, using VERSION=... as to-be-released version if present
	npx auto-changelog -c .auto-changelog $(if $(VERSION),-v $(VERSION))

.PHONY: version-current
version-current: ## Print the latest tagged release version
	@git describe --tags --abbrev=0 --match='v*' origin/main
	
.PHONY: require-BUMP
require-BUMP:
	@if [ -z "$(BUMP)" ]; then echo -e "\
	Error: BUMP variable is required (patch|minor|major).\n\
	Use like:\n\
	  make $(MAKECMDGOALS) BUMP=patch\n\
	"; exit 1; fi

.PHONY: version-next
version-next: require-BUMP
version-next: ## Increment the current version using BUMP=(patch|minor|major) and print new version
	@git describe --tags --abbrev=0 --match='v*' origin/main | awk -F. -v bump="$(BUMP)" \
		'BEGIN {if (!bump) bump="patch"} \
		{if (bump=="major") print "v"$$1+1".0.0"; \
		 else if (bump=="minor") print $$1"."$$2+1".0"; \
		 else print $$1"."$$2"."$$3+1}'
	
.PHONY: require-VERSION
require-VERSION:
	@if [ -z "$(VERSION)" ]; then echo -e "\
	Error: VERSION variable is required (e.g. v0.4.0).\n\
	Use like:\n\
	  make $(MAKECMDGOALS) VERSION=v0.4.0\n\
	"; exit 1; fi

.PHONY: update-example-versions
update-example-versions: require-VERSION
update-example-versions: ## Update examples/ module version constraints to the major.minor of VERSION=...
	@minor_version=$$(echo "$(VERSION)" | sed -E 's/^v//' | cut -d. -f1-2); \
	scripts/update-example-versions.sh "$$minor_version"

# ensure local branch is main, clean, and up to date with origin, otherwise error
.PHONY: require-on-main-branch
require-on-main-branch:
	@current_branch=$$(git rev-parse --abbrev-ref HEAD); \
	if [ "$$current_branch" != "main" ]; then \
	  echo "Error: must be on main branch, currently $$current_branch"; \
	  exit 1; \
	fi; \
	if ! git diff --quiet --ignore-submodules -- || ! git diff --cached --quiet --ignore-submodules --; then \
	  echo "Error: working tree has uncommitted changes"; \
	  git status --short --branch; \
	  exit 1; \
	fi; \
	git fetch origin main >/dev/null 2>&1; \
	if ! git merge-base --is-ancestor origin/main HEAD; then \
	  echo "Error: local branch is missing commits from origin/main, please pull"; \
	  git status --short --branch; \
	  exit 1; \
	fi

# Note: this implementation awkwardly generates the changelog twice: the first
# will error out if no non-chore commits have been made since the prior version,
# and the second happens after a (temporary, local-only) tag creation so the
# changelog entry gets a timestamp. The tag is removed again before exiting so
# release-push is the only step that leaves a tag behind.
.PHONY: release-prep
release-prep: require-BUMP
release-prep: ## Prepare a release commit (version bumps + changelog regen). Requires a BUMP=(patch|minor|major) argument.
	@set -e -x; \
		target_version=$$($(MAKE) version-next BUMP=${BUMP}); \
	  echo "Preparing $$target_version"; \
	  $(MAKE) update-example-versions VERSION=$$target_version; \
	  git add examples; \
	  $(MAKE) changelog-sync VERSION=$$target_version; \
		git add CHANGELOG.md; \
		git commit -m "chore(release): $$target_version"; \
	  git tag $$target_version; \
	  $(MAKE) changelog-sync; \
		git add CHANGELOG.md; \
		git commit --amend --no-edit; \
	  git tag -d $$target_version

.PHONY: release-push
release-push: require-BUMP
release-push: require-on-main-branch
release-push: ## Tag, push, and publish the GitHub release for a prepared release. Requires a BUMP=(patch|minor|major) argument. Can only be run on a clean `main` branch.
	@set -e -x; \
		target_version=$$($(MAKE) version-next BUMP=${BUMP}); \
	  echo "Releasing $$target_version"; \
	  git tag $$target_version; \
	  git push origin main $$target_version; \
	  gh release create $$target_version -t "$$target_version" --generate-notes

.PHONY: release
release: require-BUMP
release: release-prep release-push
release: ## Prepare & push a new release. Requires a BUMP=(patch|minor|major) argument. Can only be run on a clean `main` branch.
