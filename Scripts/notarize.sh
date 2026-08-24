#!/bin/zsh
set -euo pipefail

if (( $# != 2 )); then
  print -u2 "Usage: $0 /path/to/QuotaGlass.app NOTARYTOOL_KEYCHAIN_PROFILE"
  exit 64
fi

app_path="${1:A}"
profile="$2"

if [[ ! -d "$app_path" || "${app_path:e}" != "app" ]]; then
  print -u2 "QuotaGlass.app was not found: $app_path"
  exit 66
fi

archive_path="${TMPDIR:-/tmp}/QuotaGlass-notarize-$$.zip"
trap 'rm -f "$archive_path"' EXIT

/usr/bin/ditto -c -k --keepParent "$app_path" "$archive_path"
/usr/bin/xcrun notarytool submit "$archive_path" --keychain-profile "$profile" --wait
/usr/bin/xcrun stapler staple "$app_path"
/usr/bin/spctl --assess --type execute --verbose=2 "$app_path"
