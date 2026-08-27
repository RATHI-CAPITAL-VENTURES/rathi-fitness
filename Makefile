# The commands the guards tell you to run.
#
# `guards.sh` names `make guards` and `make changelog-archive` in its failure
# messages. Until this file existed, neither was a real command — the remedy
# for a failing guard was to work out what it meant and do it by hand, which is
# how an escape-hatch label starts looking reasonable.

DEVELOPER_DIR ?= /Applications/Xcode-beta.app/Contents/Developer
SIMULATOR ?= platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2

.PHONY: guards guards-test changelog-archive test project

## Run every guard against this branch. CLOSE to the way CI does, not identical:
## CI runs ubuntu with bash 5, macOS ships bash 3.2, and 3.2 does NOT enforce
## `set -u` on a `local` that was declared without a value. A guard that dies on
## CI with "unbound variable" passes here in silence. Initialise your locals.
guards:
	BASE_SHA=$$(git merge-base origin/main HEAD) HEAD_SHA=$$(git rev-parse HEAD) \
		bash .github/scripts/guards.sh all

## The guards' own self-tests — the shared ones and this project's.
guards-test:
	bash .github/scripts/guards.test.sh
	bash .github/scripts/guards.d.test.sh

## Move closed minor series out of CHANGELOG.md into docs/changelog/.
changelog-archive:
	python3 bin/changelog-archive

## Regenerate the Xcode project. Required after adding ANY source file —
## app/RathiFitness.xcodeproj is generated and gitignored, and a file that is
## not in it compiles nowhere. A test suite missing a file reports success
## having run nothing.
project:
	cd app && xcodegen generate

## The full suite on the simulator.
test: project
	cd app && DEVELOPER_DIR=$(DEVELOPER_DIR) xcodebuild \
		-project RathiFitness.xcodeproj -scheme RathiFitness \
		-destination '$(SIMULATOR)' -derivedDataPath /tmp/rf-build \
		CODE_SIGNING_ALLOWED=NO test
