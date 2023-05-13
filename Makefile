THEOS_DEVICE_IP=192.168.0.27

ARCHS := arm64 arm64e
TARGET := iphone:clang:latest:11.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Enmity

$(TWEAK_NAME)_FILES = $(shell find Sources -name "*.x*")
$(TWEAK_NAME)_CFLAGS = -fobjc-arc
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation

BUNDLE_NAME = EnmityResources

$(BUNDLE_NAME)_INSTALL_PATH = "/Library/Application\ Support/Enmity"

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk
