#!/bin/zsh

set -euo pipefail

readonly helper_label="com.zhuhai.AwakeMac.PowerHelper"
readonly helper_destination="/Library/PrivilegedHelperTools/com.zhuhai.AwakeMac.PowerHelper"
readonly plist_destination="/Library/LaunchDaemons/com.zhuhai.AwakeMac.PowerHelper.plist"
readonly support_directory="/Library/Application Support/AwakeMac"
readonly requirement_destination="$support_directory/authorized-client.requirement"
readonly state_marker="/var/db/com.zhuhai.AwakeMac.PowerHelper.state"

readonly script_directory="${0:A:h}"
readonly app_bundle="${script_directory}/../.."
readonly source_helper="${app_bundle}/Contents/Library/LaunchDaemons/PowerHelper"
readonly source_plist="${script_directory}/com.zhuhai.AwakeMac.PowerHelper.local.plist"
typeset requirement_temporary=""

cleanup() {
  if [[ -n "$requirement_temporary" ]]; then
    /bin/rm -f "$requirement_temporary"
  fi
}

trap cleanup EXIT

fail() {
  echo "AwakeMac helper installer: $1" >&2
  exit 1
}

verify_fixed_targets() {
  [[ "$helper_destination" == "/Library/PrivilegedHelperTools/com.zhuhai.AwakeMac.PowerHelper" ]] || fail "invalid helper target"
  [[ "$plist_destination" == "/Library/LaunchDaemons/com.zhuhai.AwakeMac.PowerHelper.plist" ]] || fail "invalid plist target"
  [[ "$requirement_destination" == "/Library/Application Support/AwakeMac/authorized-client.requirement" ]] || fail "invalid requirement target"
}

verify_sources() {
  [[ -x "$source_helper" ]] || fail "embedded helper is missing"
  [[ -f "$source_plist" ]] || fail "local LaunchDaemon plist is missing"
  /usr/bin/codesign --verify --strict "$source_helper" || fail "embedded helper signature is invalid"
  /usr/bin/codesign --verify --deep --strict "$app_bundle" || fail "application signature is invalid"
  /usr/bin/plutil -lint "$source_plist" >/dev/null || fail "local LaunchDaemon plist is invalid"
}

require_root() {
  [[ "$EUID" -eq 0 ]] || fail "administrator authorization is required"
}

install_helper() {
  require_root
  verify_fixed_targets
  verify_sources

  requirement_temporary="$(/usr/bin/mktemp /tmp/AwakeMacRequirement.XXXXXX)"

  /usr/bin/codesign -d -r- "$app_bundle" 2>&1 \
    | /usr/bin/sed -n 's/^# designated => //p' \
    > "$requirement_temporary"
  [[ -s "$requirement_temporary" ]] || fail "unable to derive the client code requirement"

  /usr/bin/pmset -a disablesleep 0
  /bin/launchctl bootout "system/$helper_label" >/dev/null 2>&1 || true
  /bin/sleep 1

  /usr/bin/install -d -o root -g wheel -m 0755 "/Library/PrivilegedHelperTools"
  /usr/bin/install -d -o root -g wheel -m 0755 "$support_directory"
  /usr/bin/install -o root -g wheel -m 0755 "$source_helper" "$helper_destination"
  /usr/bin/install -o root -g wheel -m 0644 "$source_plist" "$plist_destination"
  /usr/bin/install -o root -g wheel -m 0644 "$requirement_temporary" "$requirement_destination"

  /bin/launchctl bootstrap system "$plist_destination"
  /bin/launchctl enable "system/$helper_label"
  /bin/launchctl kickstart -k "system/$helper_label"
  /bin/launchctl print "system/$helper_label" >/dev/null

  echo "AwakeMac local helper installed."
}

uninstall_helper() {
  require_root
  verify_fixed_targets

  /usr/bin/pmset -a disablesleep 0
  /bin/launchctl bootout "system/$helper_label" >/dev/null 2>&1 || true
  /bin/rm -f "$helper_destination"
  /bin/rm -f "$plist_destination"
  /bin/rm -f "$requirement_destination"
  /bin/rm -f "$state_marker"
  /bin/rmdir "$support_directory" >/dev/null 2>&1 || true

  echo "AwakeMac local helper removed; lid sleep restored."
}

case "${1:-}" in
  verify)
    verify_fixed_targets
    verify_sources
    echo "AwakeMac local helper payload is valid."
    ;;
  install)
    install_helper
    ;;
  uninstall)
    uninstall_helper
    ;;
  *)
    fail "usage: $0 verify|install|uninstall"
    ;;
esac
