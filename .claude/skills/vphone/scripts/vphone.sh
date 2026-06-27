#!/usr/bin/env bash
#
# vphone.sh — thin wrapper around the virtual iPhone (vphone) reachable over SSH.
#
# The vphone is a jailbroken iOS VM running Discord + the Unbound loader. Its
# dropbear sshd has NO sftp-server, so file copies MUST use `scp -O` (legacy
# rcp protocol). `sudo` is password-based (`sudo -S`). There is no python on the
# device, so JSON edits are done host-side and pushed back.
#
# Connection (overridable via env):
#   VPHONE_HOST=127.0.0.1  VPHONE_PORT=2222  VPHONE_USER=mobile  VPHONE_PASS=alpine
#
# Usage:
#   vphone.sh ping                          # check reachability
#   vphone.sh ssh   <cmd...>                # run a command (no sudo)
#   vphone.sh sudo  <cmd...>                # run a command as root
#   vphone.sh push  <local> <remote>        # copy host -> device (scp -O)
#   vphone.sh pull  <remote> <local>        # copy device -> host (scp -O)
#   vphone.sh app-data <bundleid>           # print app Data container path
#   vphone.sh unbound-dir                   # print the Unbound directory path
#   vphone.sh settings-path                 # print Unbound settings.json path
#   vphone.sh settings-get [<jq-filter>]    # cat Unbound settings.json (host jq optional)
#   vphone.sh settings-set <dot.key> <json> # set unbound.<dot.key> = <json>, backup + push
#   vphone.sh restart                       # kill & relaunch Discord
#
set -euo pipefail

VPHONE_HOST="${VPHONE_HOST:-127.0.0.1}"
VPHONE_PORT="${VPHONE_PORT:-2222}"
VPHONE_USER="${VPHONE_USER:-mobile}"
VPHONE_PASS="${VPHONE_PASS:-alpine}"
DISCORD_BID="com.hammerandchisel.discord"

SSH_BASE=(-p "$VPHONE_PORT" -o ConnectTimeout=8 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
TARGET="${VPHONE_USER}@${VPHONE_HOST}"

need_sshpass() {
  command -v sshpass >/dev/null 2>&1 || { echo "sshpass not found (brew install sshpass)" >&2; exit 1; }
}

_ssh()  { need_sshpass; sshpass -p "$VPHONE_PASS" ssh "${SSH_BASE[@]}" "$TARGET" "$@"; }
# scp -O forces legacy protocol; modern scp defaults to sftp which dropbear lacks.
_scp()  { need_sshpass; sshpass -p "$VPHONE_PASS" scp -O -P "$VPHONE_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$@"; }
_sudo() { need_sshpass; sshpass -p "$VPHONE_PASS" ssh "${SSH_BASE[@]}" "$TARGET" "echo '$VPHONE_PASS' | sudo -S sh -c \"$*\" 2>/dev/null"; }

app_data() {
  local bid="${1:?bundle id required}"
  _sudo "find /var/mobile/Containers/Data/Application -maxdepth 4 -name '.com.apple.mobile_container_manager.metadata.plist' -exec grep -l '$bid' {} +" \
    | sed 's#/\.com\.apple\.mobile_container_manager\.metadata\.plist##' | head -n1
}

unbound_dir() {
  local p; p="$(settings_path)"
  [ -n "$p" ] && dirname "$p"
}

settings_path() {
  # Unbound writes to Documents/Unbound/settings.json in the Discord data container.
  _sudo "find /var/mobile/Containers/Data/Application -maxdepth 5 -path '*Documents/Unbound/settings.json'" | head -n1
}

case "${1:-}" in
  ping)
    if _ssh "exit" >/dev/null 2>&1; then echo "vphone reachable ($TARGET:$VPHONE_PORT)"; else echo "vphone UNREACHABLE ($TARGET:$VPHONE_PORT)" >&2; exit 1; fi ;;

  ssh)   shift; _ssh "$@" ;;
  sudo)  shift; _sudo "$*" ;;
  push)  shift; _scp "${1:?local}" "$TARGET:${2:?remote}" ;;
  pull)  shift; _scp "$TARGET:${1:?remote}" "${2:?local}" ;;

  app-data)      shift; app_data "${1:-$DISCORD_BID}" ;;
  unbound-dir)   unbound_dir ;;
  settings-path) settings_path ;;

  settings-get)
    shift
    p="$(settings_path)"; [ -n "$p" ] || { echo "settings.json not found" >&2; exit 1; }
    if [ -n "${1:-}" ] && command -v jq >/dev/null 2>&1; then
      _sudo "cat '$p'" | jq "$1"
    else
      _sudo "cat '$p'"
    fi ;;

  settings-set)
    shift
    key="${1:?dot.key required (e.g. loader.update.hmr)}"; val="${2:?json value required (e.g. true)}"
    command -v jq >/dev/null 2>&1 || { echo "jq required on host for settings-set" >&2; exit 1; }
    p="$(settings_path)"; [ -n "$p" ] || { echo "settings.json not found" >&2; exit 1; }
    tmp="$(mktemp)"; out="$(mktemp)"
    _sudo "cat '$p'" > "$tmp"
    # Merge under the "unbound" store using a dotted path -> nested object.
    jq --arg k "$key" --argjson v "$val" '
      ($k | split(".")) as $path
      | .unbound = (.unbound // {})
      | .unbound |= setpath($path; $v)
    ' "$tmp" > "$out"
    _sudo "cp '$p' '$p.bak'"
    _scp "$out" "$TARGET:/tmp/unbound-settings.json"
    _sudo "cp /tmp/unbound-settings.json '$p' && rm -f /tmp/unbound-settings.json"
    rm -f "$tmp" "$out"
    echo "set unbound.$key = $val (backup at $p.bak)" ;;

  restart)
    _sudo "killall -9 Discord" || true
    _ssh "uiopen --bundleid $DISCORD_BID"
    echo "Discord restarted" ;;

  *)
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
    exit 1 ;;
esac
