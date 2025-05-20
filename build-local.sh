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

if [ ! -f "control" ]; then
    print_error "Control file not found. Cannot continue."
    exit 1
fi

NAME=$(grep '^Name:' control | cut -d ' ' -f 2)
if [ -z "$NAME" ]; then
    print_error "Package name not found in control file. Cannot continue."
    exit 1
fi

print_status "Building package: $NAME"

print_status "Initializing submodules..."
git submodule update --init --recursive
if [ $? -ne 0 ]; then
    print_error "Failed to initialize submodules"
    exit 1
fi
print_success "Initialized submodules"

IPA_FILE=$(find . -maxdepth 1 -name "*.ipa" -print -quit)
UNAME=$(uname)

print_status "Build debug version? (y/n):"
read -t 3 DEBUG_INPUT
if [ $? -gt 128 ]; then
    echo "n"
    DEBUG_ARG=""
    print_status "Building release version... (default)"
elif [[ $DEBUG_INPUT =~ ^[Yy]$ ]]; then
    DEBUG_ARG="DEBUG=1"
    print_status "Building debug version..."
else
    DEBUG_ARG=""
    print_status "Building release version..."
fi

USE_EXTENSION=0
if [ "$UNAME" = "Darwin" ]; then
    print_status "Include extensions? (y/n):"
    read -t 3 EXTENSIONS_INPUT
    if [ $? -gt 128 ]; then
        echo "y"
        USE_EXTENSION=1
        print_status "Including extensions... (default)"
    elif [[ $EXTENSIONS_INPUT =~ ^[Nn]$ ]]; then
        USE_EXTENSION=0
        print_status "Skipping extensions..."
    else
        USE_EXTENSION=1
        print_status "Including extensions..."
    fi
fi

if [ -z "$IPA_FILE" ]; then
    print_status "No ipa found. Please enter Discord ipa URL or file path:"
    read DISCORD_INPUT

    if [ -z "$DISCORD_INPUT" ]; then
        print_error "No input provided"
        exit 1
    fi

    if [[ "$DISCORD_INPUT" =~ ^https?:// ]]; then
        print_status "Downloading Discord ipa..."
        curl -L -o discord.ipa "$DISCORD_INPUT"
        if [ $? -ne 0 ]; then
            print_error "Failed to download Discord ipa"
            exit 1
        fi
        print_success "Downloaded Discord ipa"
    else
        if [ ! -f "$DISCORD_INPUT" ]; then
            print_error "File not found: $DISCORD_INPUT"
            exit 1
        fi
        print_status "Copying Discord ipa..."
        cp "$DISCORD_INPUT" discord.ipa
        if [ $? -ne 0 ]; then
            print_error "Failed to copy Discord ipa"
            exit 1
        fi
        print_success "Copied Discord ipa"
    fi
    IPA_FILE="discord.ipa"
fi

print_status "Building tweak..."

if [ "$UNAME" = "Darwin" ]; then
	gmake package $DEBUG_ARG
else
	make package $DEBUG_ARG
fi
if [ $? -ne 0 ]; then
	print_error "Failed to build tweak"
	exit 1
fi
print_success "Built tweak"

if [ ! -f "patcher-ios/patcher" ]; then
    print_status "Building patcher..."
    rm -rf patcher-ios
    git clone https://github.com/unbound-app/patcher-ios
    cd patcher-ios
    go build -o patcher
    cd ..

    if [ $? -ne 0 ]; then
        print_error "Failed to build patcher"
        exit 1
    fi
    print_success "Built patcher"
else
    print_status "Using existing patcher..."
fi

OUTPUT_IPA="${NAME}.ipa"
TEMP_PATCHED_IPA="patched.ipa"

print_status "Patching ipa..."
./patcher-ios/patcher -i "$IPA_FILE" -o "$TEMP_PATCHED_IPA"

if [ $? -ne 0 ]; then
	print_error "Failed to patch ipa"
	exit 1
fi
print_success "Patched ipa"

EXTENSIONS=""
if [ "$USE_EXTENSION" = "1" ] && [ "$UNAME" = "Darwin" ]; then
    # OpenInDiscord Extension
    SAFARI_EXT="extensions/OpenInDiscord/build/OpenInDiscord.appex"
    
    if [ ! -f "$SAFARI_EXT" ]; then
        print_status "Building Safari extension..."
        mkdir -p extensions/OpenInDiscord/build
        cd extensions/OpenInDiscord
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
            ONLY_ACTIVE_ARCH=NO | xcbeautify
        cd ../..

        if [ $? -ne 0 ]; then
            print_error "Failed to build Safari extension"
            exit 1
        fi
        print_success "Built Safari extension"
    else
        print_status "Using existing Safari extension..."
    fi
    
    EXTENSIONS="$SAFARI_EXT"
    
    # ShareToDiscord Extension
    SHARE_EXT="extensions/ShareToDiscord/build/Share.appex"
    
    # Update the Info.plist to change URLScheme from 'discord' to 'unbound'
    print_status "Updating ShareToDiscord Info.plist..."
    INFO_PLIST_PATH="extensions/ShareToDiscord/Share/Info.plist"
    if [ -f "$INFO_PLIST_PATH" ]; then
        /usr/libexec/PlistBuddy -c "Set :URLScheme unbound" "$INFO_PLIST_PATH" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Add :URLScheme string unbound" "$INFO_PLIST_PATH"
        print_success "Updated ShareToDiscord Info.plist"
    else
        print_error "ShareToDiscord Info.plist not found at $INFO_PLIST_PATH"
    fi
    
    if [ ! -f "$SHARE_EXT" ]; then
        print_status "Building Share extension..."
        mkdir -p extensions/ShareToDiscord/build
        cd extensions/ShareToDiscord
        xcodebuild build \
            -target "Share" \
            -configuration Release \
            -sdk iphoneos \
            CONFIGURATION_BUILD_DIR="build" \
            PRODUCT_NAME="Share" \
            PRODUCT_BUNDLE_IDENTIFIER="com.hammerandchisel.discord.Share" \
            PRODUCT_MODULE_NAME="Share" \
            SKIP_INSTALL=NO \
            DEVELOPMENT_TEAM="" \
            CODE_SIGN_IDENTITY="" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO \
            ONLY_ACTIVE_ARCH=NO | xcbeautify
        cd ../..

        if [ $? -ne 0 ]; then
            print_error "Failed to build Share extension"
            exit 1
        fi
        print_success "Built Share extension"
    else
        print_status "Using existing Share extension..."
    fi
    
    EXTENSIONS="$EXTENSIONS $SHARE_EXT"
fi

if [ ! -d "venv" ] || [ ! -f "venv/bin/cyan" ]; then
    print_status "Setting up Python environment..."
    [ -d "venv" ] && rm -rf venv
    python3 -m venv venv
    source venv/bin/activate
    pip install --force-reinstall https://github.com/asdfzxcvbn/pyzule-rw/archive/main.zip Pillow

    if [ $? -ne 0 ]; then
        print_error "Failed to install cyan"
        exit 1
    fi
    print_success "Installed cyan"
else
    print_status "Using existing Python environment..."
    source venv/bin/activate
fi

DEB_FILE=$(find packages -maxdepth 1 -name "*.deb" -print -quit)

print_status "Injecting tweak..."
if [ "$USE_EXTENSION" = "1" ] && [ -n "$EXTENSIONS" ]; then
    cyan -duwsgq -i "$TEMP_PATCHED_IPA" -o "$OUTPUT_IPA" -f "$DEB_FILE" $EXTENSIONS
else
    cyan -duwsgq -i "$TEMP_PATCHED_IPA" -o "$OUTPUT_IPA" -f "$DEB_FILE"
fi

if [ $? -ne 0 ]; then
    print_error "Failed to inject tweak"
    exit 1
fi

deactivate

print_status "Cleaning up..."
rm -rf packages "$TEMP_PATCHED_IPA"

print_success "Successfully created $OUTPUT_IPA"
