THEOS_PACKAGE_SCHEME=rootless
FINALPACKAGE=1
INSTALL_TARGET_PROCESSES = Discord

ARCHS := arm64 arm64e
TARGET := iphone:clang:latest:15.0
COMMIT_HASH := $(shell git rev-parse HEAD)
COMMIT_SHORT_HASH := $(shell git rev-parse --short HEAD)
# Strip quotes/backslashes so they can't break the -DCOMMIT_SUBJECT='@"..."' flag.
COMMIT_SUBJECT := $(shell git log -1 --pretty=format:%s | tr -d '"'\''\\')
COMMIT_BRANCH := $(shell git branch --show-current 2>/dev/null || echo detached)
BUILD_TIMESTAMP := $(shell date "+%Y-%m-%d %H:%M:%S %Z")

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Unbound
ATTESTATION_ENABLED := $(if $(filter 1,$(DEBUG)),0,1)
COMMON_FLAGS = -fobjc-arc -DATTESTATION_ENABLED=$(ATTESTATION_ENABLED) -DPACKAGE_VERSION='@"$(THEOS_PACKAGE_BASE_VERSION)"' -DCOMMIT_HASH='@"$(COMMIT_HASH)"' -DCOMMIT_SHORT_HASH='@"$(COMMIT_SHORT_HASH)"' -DCOMMIT_SUBJECT='@"$(COMMIT_SUBJECT)"' -DCOMMIT_BRANCH='@"$(COMMIT_BRANCH)"' -DBUILD_TIMESTAMP='@"$(BUILD_TIMESTAMP)"' -I$(THEOS_PROJECT_DIR)/headers

$(TWEAK_NAME)_FILES = $(shell find sources -name "*.x*" -o -name "*.m*")
$(TWEAK_NAME)_CFLAGS = $(COMMON_FLAGS)
# _CCFLAGS (not _CXXFLAGS) is what Theos applies to C++/Objective-C++ compiles.
$(TWEAK_NAME)_CCFLAGS = $(COMMON_FLAGS) -std=c++20
# Resolve JSI/TurboModule symbols from Discord's React dylib at load time.
$(TWEAK_NAME)_LDFLAGS = -undefined dynamic_lookup
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation AuthenticationServices UniformTypeIdentifiers UserNotifications Security SafariServices AVKit AVFoundation CoreHaptics

BUNDLE_NAME = UnboundResources
$(BUNDLE_NAME)_INSTALL_PATH = "/Library/Application\ Support/"
$(BUNDLE_NAME)_RESOURCE_DIRS = "resources"

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk

SHELL := /bin/bash

before-all::
	@$(MAKE) clean

	@if [ ! -d "resources" ] || [ -z "$$(ls -A resources 2>/dev/null)" ]; then \
		git submodule update --init --recursive || exit 1; \
	fi

after-stage::
	find $(THEOS_STAGING_DIR) -name ".DS_Store" -delete
	find $(THEOS_STAGING_DIR) -type f \( -name "signature.bin" -o -name "public_key.der" \) -delete
	if [ "$(DEBUG)" = "1" ]; then \
		echo "Skipping embedded attestation for debug build"; \
	else \
		key_file=$$(mktemp); \
		expected_key=$$(mktemp); \
		actual_key=$$(mktemp); \
		expected_key_pem=$$(mktemp); \
		trap 'rm -f "$$key_file" "$$expected_key" "$$actual_key" "$$expected_key_pem"' EXIT; \
		if [ -n "$$ATTESTATION_PK" ]; then \
			printf "%s" "$$ATTESTATION_PK" | tr -d '\r' > "$$key_file"; \
		elif [ -f "attestation_private.pem" ]; then \
			cp "attestation_private.pem" "$$key_file"; \
		else \
			echo "ATTESTATION_PK or attestation_private.pem is required for release attestation"; \
			exit 1; \
		fi; \
		openssl base64 -d -A -in tools/attestation_public_key.b64 -out "$$expected_key"; \
		openssl pkey -pubin -inform DER -in "$$expected_key" -out "$$expected_key_pem" 2>/dev/null; \
		openssl ec -in "$$key_file" -pubout -outform DER -out "$$actual_key" 2>/dev/null; \
		cmp -s "$$expected_key" "$$actual_key" || { echo "attestation private key does not match the pinned public key"; exit 1; }; \
		dylib=$$(find "$(THEOS_STAGING_DIR)" -type f -name "Unbound.dylib" -print -quit); \
		[ -n "$$dylib" ] || { echo "staged Unbound.dylib not found"; exit 1; }; \
		python3 tools/macho_attest.py sign "$$dylib" --private-key "$$key_file" --commit-hash "$(COMMIT_HASH)" --package-version "$(THEOS_PACKAGE_BASE_VERSION)"; \
		python3 tools/macho_attest.py verify "$$dylib" --public-key "$$expected_key_pem"; \
		ldid -S "$$dylib"; \
		python3 tools/macho_attest.py verify "$$dylib" --public-key "$$expected_key_pem"; \
	fi

after-package::
