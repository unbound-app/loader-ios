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
COMMON_FLAGS = -fobjc-arc -DPACKAGE_VERSION='@"$(THEOS_PACKAGE_BASE_VERSION)"' -DCOMMIT_HASH='@"$(COMMIT_HASH)"' -DCOMMIT_SHORT_HASH='@"$(COMMIT_SHORT_HASH)"' -DCOMMIT_SUBJECT='@"$(COMMIT_SUBJECT)"' -DCOMMIT_BRANCH='@"$(COMMIT_BRANCH)"' -DBUILD_TIMESTAMP='@"$(BUILD_TIMESTAMP)"' -I$(THEOS_PROJECT_DIR)/headers

$(TWEAK_NAME)_FILES = $(shell find sources -name "*.x*" -o -name "*.m*")
$(TWEAK_NAME)_CFLAGS = $(COMMON_FLAGS)
# _CCFLAGS (not _CXXFLAGS) is what Theos applies to C++/Objective-C++ compiles.
$(TWEAK_NAME)_CCFLAGS = $(COMMON_FLAGS) -std=c++20
# Resolve JSI/TurboModule symbols from Discord's React dylib at load time.
$(TWEAK_NAME)_LDFLAGS = -undefined dynamic_lookup
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation UniformTypeIdentifiers UserNotifications Security SafariServices AVKit AVFoundation CoreHaptics

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

	@if [ -n "$$UNBOUND_PK" ]; then \
		echo -n "$(COMMIT_HASH)" | openssl dgst -sha256 -sign <(printf '%s' "$$UNBOUND_PK" | tr -d '\r') -out resources/signature.bin 2>/dev/null; \
	elif [ -f "private_key.pem" ]; then \
		echo -n "$(COMMIT_HASH)" | openssl dgst -sha256 -sign private_key.pem -out resources/signature.bin 2>/dev/null; \
	fi

after-stage::
	find $(THEOS_STAGING_DIR) -name ".DS_Store" -delete

after-package::
	rm -f resources/signature.bin
