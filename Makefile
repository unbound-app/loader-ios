THEOS_PACKAGE_SCHEME=rootless
FINALPACKAGE=1
INSTALL_TARGET_PROCESSES = Discord

ARCHS := arm64 arm64e
TARGET := iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

LOGS = 0

TWEAK_NAME = Unbound
$(TWEAK_NAME)_FILES = $(shell find Sources -name "*.x*")
$(TWEAK_NAME)_CFLAGS =  -fobjc-arc -DPACKAGE_VERSION='@"$(THEOS_PACKAGE_BASE_VERSION)"' -DLOGS=$(LOGS) -I$(THEOS_PROJECT_DIR)/headers
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation UniformTypeIdentifiers

BUNDLE_NAME = UnboundResources
$(BUNDLE_NAME)_INSTALL_PATH = "/Library/Application\ Support/"

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk

before-all::
	$(ECHO_NOTHING)VERSION_NUM=$$(echo "$(THEOS_PACKAGE_BASE_VERSION)" | cut -d'.' -f1,2) && \
		sed "s/VERSION_PLACEHOLDER/$$VERSION_NUM/" sources/preload.template.js > resources/preload.js$(ECHO_END)

after-stage::
	$(ECHO_NOTHING)find $(THEOS_STAGING_DIR) -name ".DS_Store" -delete$(ECHO_END)

after-package::
	$(ECHO_NOTHING)rm resources/preload.js$(ECHO_END)