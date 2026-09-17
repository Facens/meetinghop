# MeetingHop — builds with Command Line Tools only. No Xcode, no xcodebuild.
SWIFT   ?= swift
CONFIG  ?= release
VERSION ?= 0.1.0
DIST    ?= dist

.PHONY: all build test bundle probe icons clean

all: build

build:
	$(SWIFT) build -c $(CONFIG)

# XCTest and swift-testing ship with Xcode, not with Command Line Tools, so
# the suite is an executable, not a `.testTarget`, and this is the command
# that runs it (U2 ports AgentMenu's hand-written harness and wires the first
# suites; today this just runs the placeholder).
#
# MeetingHopProbe is built first on purpose, mirroring AgentMenu's Makefile
# gotcha: if a future suite shells out to the probe/CLI, an absent binary
# would make those scenarios skip themselves silently — reporting a pass with
# fewer expectations — rather than fail on a clean checkout.
test:
	$(SWIFT) build --product MeetingHopProbe
	$(SWIFT) run MeetingHopKitTests

# Read-only diagnostics: Accessibility state, Zoom state, the joinable
# meetings MeetingHop can see. Never joins, never leaves, never clicks.
probe:
	$(SWIFT) run MeetingHopProbe

# The app icon and the menu-bar template are rendered from code rather than
# checked in as art — packaging/icon/make-icons.swift is the source of truth,
# and docs/brand.md documents this as the command that runs it.
icons:
	$(SWIFT) packaging/icon/make-icons.swift

bundle:
	@VERSION=$(VERSION) ./packaging/bundle.sh

clean:
	rm -rf .build $(DIST)
