#!/bin/sh

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
	echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
	echo -e "${GREEN}[+]${NC} $1"
}

print_error() {
	echo -e "${RED}[-]${NC} $1"
}

IPA_FILE=$(find . -maxdepth 1 -name "*.ipa" -print -quit)
UNAME=$(uname)
WITH_DEBUG=1

if [ -z "$IPA_FILE" ]; then
	print_status "No ipa found. Please enter Discord ipa URL:"
	read DISCORD_URL

	if [ -z "$DISCORD_URL" ]; then
		print_error "No URL provided"
		exit 1
	fi

	print_status "Downloading Discord ipa..."
	curl -L -o discord.ipa "$DISCORD_URL"

	if [ $? -ne 0 ]; then
		print_error "Failed to download Discord ipa"
		exit 1
	fi
	IPA_FILE="discord.ipa"
	print_success "Downloaded Discord ipa"
fi

print_status "Building tweak..."

if [ "$UNAME" = "Darwin" ]; then
	gmake package DEBUG="$WITH_DEBUG"
else
	make package DEBUG="$WITH_DEBUG"
fi
if [ $? -ne 0 ]; then
	print_error "Failed to build tweak"
	exit 1
fi
print_success "Built tweak"

print_status "Building patcher..."
rm -rf patcher-ios
git clone https://github.com/unbound-mod/patcher-ios
cd patcher-ios
go build -o patcher
cd ..

if [ $? -ne 0 ]; then
	print_error "Failed to build patcher"
	exit 1
fi
print_success "Built patcher"

print_status "Patching ipa..."
./patcher-ios/patcher "$IPA_FILE"

if [ $? -ne 0 ]; then
	print_error "Failed to patch ipa"
	exit 1
fi
print_success "Patched ipa"
if [ "$UNAME" = "Darwin" ]; then
	print_status "Cloning Safari extension..."
	rm -rf OpenInDiscord
	git clone https://github.com/castdrian/OpenInDiscord

	if [ $? -ne 0 ]; then
		print_error "Failed to clone Safari extension"
		exit 1
	fi
	print_success "Cloned Safari extension"

	print_status "Building Safari extension..."
	cd OpenInDiscord
	xcodebuild build \
		-target "OpenInDiscord Extension" \
		-configuration Release \
		-sdk iphoneos \
		CONFIGURATION_BUILD_DIR="build" \
		PRODUCT_NAME="OpenInDiscord" \
		PRODUCT_BUNDLE_IDENTIFIER="com.hammerandchisel.discord.OpenInDiscord" \
		PRODUCT_MODULE_NAME="OpenInDiscordExt" \
		SKIP_INSTALL=NO \
		DEVELOPMENT_TEAM="" \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO \
		ONLY_ACTIVE_ARCH=NO
	cd ..

	if [ $? -ne 0 ]; then
		print_error "Failed to build Safari extension"
		exit 1
	fi
	print_success "Built Safari extension"
	SAFARI_EXT=" OpenInDiscord/build/OpenInDiscord.appex"
else
	print_status "Not running on MacOS, skipping Safari Extension"
	SAFARI_EXT=""
fi
print_status "Setting up Python environment..."
python3 -m venv venv
source venv/bin/activate
pip install --force-reinstall https://github.com/asdfzxcvbn/pyzule-rw/archive/main.zip Pillow

if [ $? -ne 0 ]; then
	print_error "Failed to install cyan"
	exit 1
fi
print_success "Installed cyan"

NAME=$(grep '^Name:' control | cut -d ' ' -f 2)
PACKAGE=$(grep '^Package:' control | cut -d ' ' -f 2)
VERSION=$(grep '^Version:' control | cut -d ' ' -f 2)

if [ $WITH_DEBUG = 1 ]; then
	DEBUG="+debug"
else
	DEBUG=""
fi

DEB_FILE="packages/${PACKAGE}_${VERSION}${DEBUG}_iphoneos-arm64.deb"

print_status "Injecting tweak..."
yes | cyan -duwsgq -i "$NAME.ipa" -o "$NAME.ipa" -f "$DEB_FILE""$SAFARI_EXT"

if [ $? -ne 0 ]; then
	print_error "Failed to inject tweak"
	exit 1
fi

deactivate

print_status "Cleaning up..."
rm -rf patcher-ios OpenInDiscord venv

print_success "Successfully created $NAME.ipa"
