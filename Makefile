THEOS_PACKAGE_SCHEME=rootless
FINALPACKAGE=1
INSTALL_TARGET_PROCESSES = Discord

ARCHS := arm64 arm64e
TARGET := iphone:clang:latest:15.0
COMMIT_HASH := $(shell git rev-parse HEAD)

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Unbound
$(TWEAK_NAME)_FILES = $(shell find sources -name "*.x*" -o -name "*.m*")
$(TWEAK_NAME)_CFLAGS = -fobjc-arc -DPACKAGE_VERSION='@"$(THEOS_PACKAGE_BASE_VERSION)"' -DCOMMIT_HASH='@"$(COMMIT_HASH)"' -I$(THEOS_PROJECT_DIR)/headers
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation UniformTypeIdentifiers UserNotifications Security

BUNDLE_NAME = UnboundResources
$(BUNDLE_NAME)_INSTALL_PATH = "/Library/Application\ Support/"
$(BUNDLE_NAME)_RESOURCE_DIRS = "resources"

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk

SHELL := /bin/bash

before-all::
	@if [ ! -d "resources" ] || [ -z "$$(ls -A resources 2>/dev/null)" ]; then \
		git submodule update --init --recursive || exit 1; \
	fi

	cp sources/preload.js resources/preload.js

	@if [ -n "$$UNBOUND_PK" ]; then \
		echo -n "$(COMMIT_HASH)" | openssl dgst -sha256 -sign <(printf '%s' "$$UNBOUND_PK" | tr -d '\r') -out resources/signature.bin 2>/dev/null; \
	elif [ -f "private_key.pem" ]; then \
		echo -n "$(COMMIT_HASH)" | openssl dgst -sha256 -sign private_key.pem -out resources/signature.bin 2>/dev/null; \
	fi

after-stage::
	find $(THEOS_STAGING_DIR) -name ".DS_Store" -delete

after-package::
	rm -f resources/preload.js resources/signature.bin
