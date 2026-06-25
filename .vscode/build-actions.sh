#!/bin/sh
set -euo pipefail

ACTION="${1:-Package}"
echo ">> action: ${ACTION}"

icloud_dir="$HOME/Library/Mobile Documents/com~apple~CloudDocs"

build_package() {
  rm -rf packages
  gmake clean package DEBUG=1
}

clean_dest() {
  local srcs=("$@")
  for s in "${srcs[@]}"; do
    [[ -n "$s" && -e "$s" ]] || continue
    local base
    base=$(basename "$s")
    local dest="$icloud_dir/$base"
    if [[ -e "$dest" ]]; then
      rm -f "$dest" || { echo "Failed to remove existing $dest" >&2; exit 1; }
      echo "Removed existing $dest"
    fi
  done
}

case "$ACTION" in
  vphone)
    if ! command -v sshpass >/dev/null 2>&1; then
      echo "sshpass is required for vphone action but was not found" >&2
      exit 1
    fi

    SSH_OPTS="-p 2222 -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    SSH_TARGET="mobile@127.0.0.1"

    if ! sshpass -p alpine ssh $SSH_OPTS "$SSH_TARGET" "exit" >/dev/null 2>&1; then
      echo "Virtual iPhone could not be reached" >&2
      exit 1
    fi

    build_package

    DEB=$(ls packages/*.deb 2>/dev/null | head -n1 || true)
    if [[ -z "$DEB" ]]; then
      echo "No .deb artifacts found" >&2
      exit 1
    fi

    REMOTE_DEB="/tmp/$(basename "$DEB")"

    sshpass -p alpine scp -P 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$DEB" "$SSH_TARGET:$REMOTE_DEB"
    sshpass -p alpine ssh $SSH_OPTS "$SSH_TARGET" "echo 'alpine' | sudo -S dpkg -i '$REMOTE_DEB' && echo 'alpine' | sudo -S killall -9 SpringBoard"
    ;;
  Package)
    build_package
    ;;
  "AirDrop Tweak")
    build_package
    shortcuts run AirDrop -i ./packages/*.deb
    ;;
  "Build IPA")
    build_package
    chmod +x build-local.sh
    ./build-local.sh
    ;;
  ".dylib -> iCloud Drive")
    build_package
    DYLIB=$(ls .theos/obj/*.dylib 2>/dev/null | head -n1 || true)
    if [[ -n "$DYLIB" && -f "$DYLIB" ]]; then
      [[ -d "$icloud_dir" ]] || { echo "Destination directory missing: $icloud_dir" >&2; exit 1; }
      clean_dest "$DYLIB"
      cp -v "$DYLIB" "$icloud_dir/" || { echo "Copy failed" >&2; exit 1; }
    else
      echo "No dylib found in .theos/obj" >&2
      exit 1
    fi
    ;;
  ".deb -> iCloud Drive")
    build_package
    [[ -d "$icloud_dir" ]] || { echo "Destination directory missing: $icloud_dir" >&2; exit 1; }
    debs=(packages/*.deb)
    if [[ ${debs[1]} == 'packages/*.deb' ]]; then echo "No .deb artifacts found" >&2; exit 1; fi
    clean_dest "${debs[@]}"
    cp -v "${debs[@]}" "$icloud_dir/" || { echo "Copy failed" >&2; exit 1; }
    ;;
  ".ipa -> iCloud Drive")
    build_package
    chmod +x build-local.sh
    ./build-local.sh
    IPA=$(ls *.ipa 2>/dev/null | head -n1 || true)
    if [[ -n "${IPA}" ]]; then
      [[ -d "$icloud_dir" ]] || { echo "Destination directory missing: $icloud_dir" >&2; exit 1; }
      clean_dest "$IPA"
      cp -v "$IPA" "$icloud_dir/" || { echo "Copy failed" >&2; exit 1; }
    else
      echo "No IPA found" >&2
      exit 1
    fi
    ;;
  *)
    echo "Unknown action: $ACTION" >&2
    exit 1
    ;;
esac
