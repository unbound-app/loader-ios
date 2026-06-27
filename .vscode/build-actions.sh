#!/bin/sh
set -euo pipefail

ACTION="${1:-Package}"
echo ">> action: ${ACTION}"

build_package() {
  rm -rf packages
  gmake clean package DEBUG=1
}

case "$ACTION" in
  "Install on vphone")
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

    # -O forces the legacy SCP/rcp protocol: the vphone's dropbear has no sftp-server,
    # which modern scp defaults to (fails with "/usr/libexec/sftp-server: No such file").
    sshpass -p alpine scp -O -P 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$DEB" "$SSH_TARGET:$REMOTE_DEB"
    sshpass -p alpine ssh $SSH_OPTS "$SSH_TARGET" "echo 'alpine' | sudo -S dpkg -i '$REMOTE_DEB' && echo 'alpine' | sudo -S killall -9 Discord; uiopen --bundleid com.hammerandchisel.discord"
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
  *)
    echo "Unknown action: $ACTION" >&2
    exit 1
    ;;
esac
