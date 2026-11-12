.DEFAULT_GOAL := help

BUILD_DIR ?= .build/xcode
CONFIGURATION ?= Debug
ARCH ?= $(shell uname -m)
BASE_REF ?=
VERSION = $(shell awk '/MARKETING_VERSION:/ { print $$2; exit }' project.yml)
XCODE_FLAGS = -project AIUsage.xcodeproj -scheme AIUsage \
	-configuration "$(CONFIGURATION)" -derivedDataPath "$(BUILD_DIR)" \
	CODE_SIGNING_ALLOWED=NO ARCHS="$(ARCH)" ONLY_ACTIVE_ARCH=YES

.PHONY: help generate build app test test-all check-process release-check verify dmg

help:
	@echo "make generate       Generate the Xcode project after editing project.yml"
	@echo "make build          Build the app for the current architecture (alias: app)"
	@echo "make test           Run all Swift tests (alias: test-all)"
	@echo "make check-process  Check About and changelog updates; BASE_REF=<git-ref> for a PR"
	@echo "make release-check  Verify the configured release version"
	@echo "make verify         Check the update process, run tests, and verify the built version"
	@echo "make dmg            Build the existing ad-hoc signed release DMG"

generate:
	xcodegen generate

build:
	xcodebuild $(XCODE_FLAGS) build

app: build

test:
	xcodebuild $(XCODE_FLAGS) -destination "platform=macOS,arch=$(ARCH)" test

test-all: test

check-process:
	python3 -m unittest discover -s Tests/WorkflowTests -p 'test_*.py'
	python3 scripts/check-project-update.py $(if $(BASE_REF),--base "$(BASE_REF)")

release-check:
	./scripts/verify-release-version.sh "$(VERSION)"

verify: check-process test
	./scripts/verify-release-version.sh "$(VERSION)" "$(BUILD_DIR)/Build/Products/$(CONFIGURATION)/AIUsage.app"

dmg:
	./scripts/build-direct-release.sh
