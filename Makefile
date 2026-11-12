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

# Note the `grep GNU`: moreutils ships its own unrelated `parallel` with the same
# name and no --group/--tag/--keep-order, and the two brew formulae conflict, so
# check we have the right one rather than just that something named parallel exists.
.PHONY: require-parallel
require-parallel:
	@if ! parallel --version 2>/dev/null | grep -q '^GNU parallel'; then echo -e "\
	Error: GNU parallel not found. It buffers and tags each module's output so\n\
	parallel validation logs stay contiguous, prefixed, and in order.\n\
	Install it with:\n\
	  brew install parallel\n\
	Note: if \`parallel\` is already on your PATH, it may be the unrelated moreutils\n\
	version, which conflicts with GNU parallel in Homebrew.\n\
	"; exit 1; fi

.PHONY: require-flock
require-flock:
	@if ! command -v flock >/dev/null; then echo -e "\
	Error: flock not found. It serializes \`terraform init\` across modules, whose\n\
	shared provider cache is not safe to write concurrently.\n\
	Install it with:\n\
	  brew install flock\n\
	"; exit 1; fi

.PHONY: require-uv
require-uv:
	@if ! command -v uv >/dev/null; then echo -e "\
	Error: uv not found. scripts/autoupdate.py declares its dependencies inline\n\
	(PEP 723) and uv resolves them at run time, so there is nothing to install\n\
	but uv itself.\n\
	Install it with:\n\
	  brew install uv\n\
	"; exit 1; fi

# Both targets hit live registries and, for the Kubernetes and Postgres
# components on AWS, the AWS APIs — so they need AWS credentials
# (aws sso login). The Azure components read endoflife.date and need none. A
# component whose credentials are missing reports as a failed row and sets a
# non-zero exit without blocking the others.
.PHONY: autoupdate-report
autoupdate-report: require-uv
autoupdate-report: ## Show which AUTOUPDATE-marked versions are behind upstream, changing nothing
	@scripts/autoupdate.py report $(if $(ARGS),$(ARGS))

.PHONY: autoupdate
autoupdate: require-uv
autoupdate: ## Bump every AUTOUPDATE-marked version to the newest matching its constraint
	@scripts/autoupdate.py update $(if $(ARGS),$(ARGS))

# NOTE: examples/ source their modules from the public registry pinned to a
# released version, not from local relative paths. Validating an example
# therefore checks it against the last *published* release, not the working tree.
.PHONY: validate
validate: require-parallel
validate: require-flock
validate: TF ?= terraform
# Concurrency factor default
validate: VALIDATE_JOBS ?= 16
# Repo-local, gitignored provider cache. Without it each of the module dirs
# downloads its own copy of the AWS/Azure/GCP providers (~238MB each, ~6GB total).
validate: TF_PLUGIN_CACHE ?= $(CURDIR)/.terraform-plugin-cache
# All Terraform module roots. Both examples/ and modules/ are exactly one level
# deep, so this depth-2 glob matches every module root and, because globs skip
# dotfiles, never descends into vendored .terraform/ trees.
validate: TF_DIRS := $(sort $(patsubst %/,%,$(dir $(wildcard examples/*/*.tf modules/*/*.tf))))
validate: ## Run `terraform validate` in every module under examples/ and modules/ (VALIDATE_JOBS=16 concurrency default)
	@mkdir -p "$(TF_PLUGIN_CACHE)"
	@if printf '%s\n' $(TF_DIRS) \
	  | TF="$(TF)" TF_PLUGIN_CACHE_DIR="$(TF_PLUGIN_CACHE)" \
	    TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=true \
	    parallel --will-cite --group --keep-order --tagstring '{}:' \
	      -j $(VALIDATE_JOBS) scripts/tf-validate-module.sh {}; \
	then echo "All $(words $(TF_DIRS)) modules valid"; \
	else echo "Validation failed, see errors above"; exit 1; \
	fi

.PHONY: help
changelog-sync: ## Sync CHANGELOG.md from git history, using VERSION=... as to-be-released version if present
	npx auto-changelog -c .auto-changelog $(if $(VERSION),-v $(VERSION))

.PHONY: version-current
version-current: ## Print the latest tagged release version (without the v prefix)
	@git describe --tags --abbrev=0 --match='v*' origin/main | sed 's/^v//'
	
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
	@git describe --tags --abbrev=0 --match='v*' origin/main | sed 's/^v//' | awk -F. -v bump="$(BUMP)" \
		'BEGIN {if (!bump) bump="patch"} \
		{if (bump=="major") print $$1+1".0.0"; \
		 else if (bump=="minor") print $$1"."$$2+1".0"; \
		 else print $$1"."$$2"."$$3+1}'
	
# "Published" means the version tags on GitHub origin: release-push pushes the
# tag and creates the GitHub release together, so the highest v* tag on origin
# is the source of truth for what has been released. The VERSION file is only
# the *intended* version and may lag or lead it. Versions are handled without
# the v prefix everywhere (VERSION file, VERSION=... args, this output); only
# git tags carry the v.
.PHONY: version-published
version-published: ## Print the highest published version on origin, without the v prefix (source of truth for releases)
	@git ls-remote --tags --refs origin 'v*' \
	  | awk -F/ '{print $$3}' | sed 's/^v//' | sort -V | tail -1

# PR gate: merging a VERSION file behind the latest published release would
# break monotonic versioning (and the release workflow bails in that state),
# so fail the check. VERSION equal to or ahead of the latest published version
# is fine.
.PHONY: version-check-monotonic
version-check-monotonic: ## Fail if the VERSION file is strictly less than the latest published version
	@file=$$(cat VERSION); \
	published=$$($(MAKE) --no-print-directory version-published); \
	echo "VERSION file: $$file | latest published: $$published"; \
	if [ "$$(scripts/version-compare.sh $$file $$published)" -lt 0 ]; then \
	  echo "Error: VERSION ($$file) is behind the latest published release ($$published)."; \
	  echo "Bump the VERSION file in your PR to at least $$published."; \
	  exit 1; \
	fi

.PHONY: require-VERSION
require-VERSION:
	@if [ -z "$(VERSION)" ]; then echo -e "\
	Error: VERSION variable is required (e.g. 0.4.0).\n\
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

# Releases are normally driven by the VERSION file (VERSION=...), but BUMP=
# (patch|minor|major) still works and computes the target from the latest tag.
.PHONY: version-target
version-target: ## Print the release target version (no v prefix): VERSION=X.Y.Z if set, else computed from BUMP=(patch|minor|major)
	@if [ -n "$(VERSION)" ]; then echo "$(VERSION)"; \
	elif [ -n "$(BUMP)" ]; then $(MAKE) --no-print-directory version-next BUMP=$(BUMP); \
	else echo "Error: either VERSION=X.Y.Z or BUMP=(patch|minor|major) is required." >&2; \
	  echo "Use like:" >&2; \
	  echo "  make $(MAKECMDGOALS) VERSION=0.4.0" >&2; \
	  echo "  make $(MAKECMDGOALS) BUMP=patch" >&2; \
	  exit 1; fi

# release-prep rewrites the root VERSION file to the target version: the
# retool-helm module reads that file at apply time to stamp its deployment
# template identity, so the tree at a tag must carry the tag's version. For
# VERSION=-driven releases the file is already correct (a no-op); for
# BUMP=-driven releases this is what records the new version.
#
# Note: this implementation awkwardly generates the changelog twice: the first
# will error out if no non-chore commits have been made since the prior version,
# and the second happens after a (temporary, local-only) tag creation so the
# changelog entry gets a timestamp. The tag is removed again before exiting so
# release-push is the only step that leaves a tag behind.
.PHONY: release-prep
release-prep: ## Prepare a release commit (version bumps + changelog regen). Requires VERSION=X.Y.Z or BUMP=(patch|minor|major).
	@set -e -x; \
		target_version=$$($(MAKE) --no-print-directory version-target); \
		target_tag=v$$target_version; \
	  echo "Preparing $$target_tag"; \
	  $(MAKE) update-example-versions VERSION=$$target_version; \
		git add examples; \
		printf '%s\n' "$$target_version" > VERSION; \
		git add VERSION; \
	  $(MAKE) changelog-sync VERSION=$$target_tag; \
		git add CHANGELOG.md; \
		git commit -m "chore(release): $$target_tag [skip ci]"; \
	  git tag $$target_tag; \
	  $(MAKE) changelog-sync; \
		git add CHANGELOG.md; \
		git commit --amend --no-edit; \
	  git tag -d $$target_tag

.PHONY: release-push
release-push: require-on-main-branch
release-push: ## Tag, push, and publish the GitHub release for a prepared release. Requires VERSION=X.Y.Z or BUMP=(patch|minor|major). Can only be run on a clean `main` branch.
	@set -e -x; \
		target_version=$$($(MAKE) --no-print-directory version-target); \
		target_tag=v$$target_version; \
	  echo "Releasing $$target_tag"; \
	  git tag $$target_tag; \
	  git push origin main $$target_tag; \
	  gh release create $$target_tag -t "$$target_tag" --generate-notes

.PHONY: release
release: release-prep release-push
release: ## Prepare & push a new release. Requires VERSION=X.Y.Z or BUMP=(patch|minor|major). Can only be run on a clean `main` branch.

.PHONY: changelog-push
changelog-push: require-on-main-branch
changelog-push: ## Sync CHANGELOG.md and push a chore(changelog) commit to main, if it changed. Can only be run on a clean `main` branch.
	@$(MAKE) --no-print-directory changelog-sync; \
	if git diff --quiet CHANGELOG.md; then \
	  echo "CHANGELOG.md already in sync, nothing to push"; \
	else \
	  git add CHANGELOG.md; \
	  git commit -m "chore(changelog): sync CHANGELOG.md [skip ci]"; \
	  git push origin main; \
	fi

# Entry point for the release workflow (and its local reproduction). Compares
# the VERSION file against the latest published tag on origin:
#   VERSION <  published -> bail (would break monotonic versioning)
#   VERSION == published -> changelog-sync only, push a chore(changelog) commit
#   VERSION >  published -> full release of the VERSION-file version
.PHONY: release-auto
release-auto: require-on-main-branch
release-auto: ## Sync releases with the VERSION file: changelog-only, full release, or fail if VERSION is behind published
	@set -e; \
	file=$$(cat VERSION); \
	published=$$($(MAKE) --no-print-directory version-published); \
	cmp=$$(scripts/version-compare.sh $$file $$published); \
	echo "VERSION file: $$file | latest published: $$published"; \
	if [ "$$cmp" -lt 0 ]; then \
	  echo "Error: VERSION ($$file) is behind the latest published release ($$published)."; \
	  echo "Refusing to release; bump the VERSION file on main to at least $$published."; \
	  exit 1; \
	elif [ "$$cmp" -eq 0 ]; then \
	  echo "VERSION matches the latest published release: syncing changelog only"; \
	  $(MAKE) --no-print-directory changelog-push; \
	else \
	  echo "VERSION is ahead of the latest published release: releasing $$file"; \
	  $(MAKE) --no-print-directory release VERSION=$$file; \
	fi
