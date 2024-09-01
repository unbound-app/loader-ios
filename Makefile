THEOS_PACKAGE_SCHEME=rootless
INSTALL_TARGET_PROCESSES = Discord

ARCHS := arm64 arm64e
TARGET := iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

LOGS = 0
SIDELOAD = 1

TWEAK_NAME = Unbound
$(TWEAK_NAME)_FILES = $(shell find Sources -name "*.x*")
$(TWEAK_NAME)_CFLAGS = -DLOGS=$(LOGS) -DSIDELOAD=$(SIDELOAD) -DDEBUG_URL=@\"$(DEBUG_URL)\" -fobjc-arc
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation

BUNDLE_NAME = UnboundResources
$(BUNDLE_NAME)_INSTALL_PATH = "/Library/Application\ Support/"

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk