THEOS_PACKAGE_SCHEME=rootless
FINALPACKAGE=1
INSTALL_TARGET_PROCESSES = Discord

ARCHS := arm64 arm64e
TARGET := iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Unbound
$(TWEAK_NAME)_FILES = $(shell find sources -name "*.x*" -o -name "*.m*")
$(TWEAK_NAME)_CFLAGS =  -fobjc-arc -DPACKAGE_VERSION='@"$(THEOS_PACKAGE_BASE_VERSION)"' -I$(THEOS_PROJECT_DIR)/headers
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation UniformTypeIdentifiers

BUNDLE_NAME = UnboundResources
$(BUNDLE_NAME)_INSTALL_PATH = "/Library/Application\ Support/"
$(BUNDLE_NAME)_RESOURCE_DIRS = "resources"

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk

before-all::
	@if [ ! -d "resources" ] || [ -z "$$(ls -A resources 2>/dev/null)" ]; then \
		echo "Resources folder empty or missing, initializing submodule..."; \
		git submodule update --init --recursive || exit 1; \
	fi

	$(ECHO_NOTHING)VERSION_NUM=$$(echo "$(THEOS_PACKAGE_BASE_VERSION)" | cut -d'.' -f1,2) && \
		sed "s/VERSION_PLACEHOLDER/$$VERSION_NUM/" sources/preload.js > resources/preload.js && cp Info.plist resources/Info.plist$(ECHO_END)

after-stage::
	$(ECHO_NOTHING)find $(THEOS_STAGING_DIR) -name ".DS_Store" -delete$(ECHO_END)

after-package::
	$(ECHO_NOTHING)rm resources/preload.js resources/Info.plist$(ECHO_END)
