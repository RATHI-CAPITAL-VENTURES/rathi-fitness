# The commands the guards tell you to run.
#
# `guards.sh` names `make guards` and `make changelog-archive` in its failure
# messages. Until this file existed, neither was a real command — the remedy
# for a failing guard was to work out what it meant and do it by hand, which is
# how an escape-hatch label starts looking reasonable.

DEVELOPER_DIR ?= /Applications/Xcode-beta.app/Contents/Developer
# EXPORTED, not passed as a command prefix. `xcode-select -p` here is
# CommandLineTools, which has no `simctl`, and xcodebuild shells out to
# `xcrun simctl` to collect diagnostics when a run finishes. A prefix
# assignment did not reach that nested xcrun, so the collection failed with
# "unable to find utility simctl" and xcodebuild exited non-zero having passed
# every test — a green suite reported as a failure.
export DEVELOPER_DIR
SIMULATOR ?= platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2

.PHONY: guards guards-test changelog-archive test test-unit test-ui project \
	autoinstall-test autoinstall-install autoinstall-uninstall autoinstall-status

# Test runners. `test` is the gate; `test-unit` is the one you actually run
# while working — the unit bundle is 2.5 SECONDS of testing, and lived behind
# eight minutes of UI tests until v0.4.3 because there was only one target.
WORKERS ?= 4
# Parallel UI testing is a property of the MACHINE, not of the suite, so it is
# a knob with a measured default rather than a setting someone believed in.
#
# Measured, on the whole suite:
#
#   this Mac, 10 cores:   7:54 serial  ->  5:39 with the split and 4 workers
#   macos-15 runner, ~3:  the UI step alone took 19:26 with 3 workers, against
#                         a whole job of about 16:00 before this change
#
# Each clone is a whole simulator. Given cores to spare that is a win; on a
# runner with three, the clones fight over them and the UI step alone outruns
# what the entire job used to cost. So CI passes PARALLEL=NO.
PARALLEL ?= YES
XCTEST = cd app && xcodebuild \
	-project RathiFitness.xcodeproj -scheme RathiFitness \
	-destination '$(SIMULATOR)' -derivedDataPath /tmp/rf-build \
	CODE_SIGNING_ALLOWED=NO

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

## The full suite: the unit bundle, then the UI bundle. TWO invocations, not
## one, and that is the whole fix rather than a tidiness preference.
##
## Run together, `HandsFreeTests` crashes with the CoreAudio abort v0.3.3 is
## about. Those tests reach a real `AVAudioEngine` through `RemoteControls`,
## and while four UI clones are hammering the audio server it answers a
## timeout with `abort()` — a SIGABRT in AudioToolbox's own frame, which no
## `try?` catches. It is not about which BUNDLE is parallel: marking the unit
## target `parallelizable: false` does not help, because the contention is
## machine-wide. Only not overlapping them does.
##
## 0:53 + 4:40 sequential, against 7:54 for one serial run of everything.
test: test-unit test-ui

## The unit bundle only. Seconds, not minutes — no app launches, no simulator
## clones. This is the inner loop; `make test` is the gate before you push.
test-unit: project
	$(XCTEST) -only-testing:RathiFitnessTests test

## The UI bundle only. Everything slow is in here: 22 tests against ~2.5s for
## all 139 unit tests. `-parallel-testing-enabled` is safe HERE, unlike in
## `test`, because -only-testing already excludes the unit bundle it would
## otherwise drag in.
test-ui: project
	$(XCTEST) -only-testing:RathiFitnessUITests \
		-parallel-testing-enabled $(PARALLEL) \
		-maximum-parallel-testing-workers $(WORKERS) test

## The auto-installer's own tests. Stubs the device and Xcode, so it runs in
## milliseconds and never touches the phone.
autoinstall-test:
	bash bin/rf-autoinstall.test.sh

## Turn on auto-install: every ~10 min, if origin/main has moved and the app is
## NOT open on the phone, build and install it.
autoinstall-install:
	mkdir -p ~/Library/Logs/rathi-fitness
	cp deploy/com.rathi.fitness.autoinstall.plist ~/Library/LaunchAgents/
	launchctl bootout gui/$$(id -u)/com.rathi.fitness.autoinstall 2>/dev/null || true
	launchctl bootstrap gui/$$(id -u) ~/Library/LaunchAgents/com.rathi.fitness.autoinstall.plist
	@echo "on — tail ~/Library/Logs/rathi-fitness/autoinstall.log"

autoinstall-uninstall:
	launchctl bootout gui/$$(id -u)/com.rathi.fitness.autoinstall 2>/dev/null || true
	rm -f ~/Library/LaunchAgents/com.rathi.fitness.autoinstall.plist
	@echo "off"

autoinstall-status:
	@launchctl print gui/$$(id -u)/com.rathi.fitness.autoinstall 2>/dev/null \
		| grep -E "state|last exit" || echo "not loaded"
	@tail -5 ~/Library/Logs/rathi-fitness/autoinstall.log 2>/dev/null || true
