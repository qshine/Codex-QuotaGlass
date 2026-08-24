#!/bin/zsh
set -euo pipefail

version="${1:-0.0.1}"
project_dir="${0:A:h:h}"
app_path="$project_dir/.build/app/QuotaGlass.app"
dist_dir="$project_dir/dist"
dmg_path="$dist_dir/Codex-QuotaGlass-$version-macos-arm64.dmg"

if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  print -u2 "Version must use semantic version format, for example 0.0.1"
  exit 64
fi

"$project_dir/Scripts/package-app.sh" release
mkdir -p "$dist_dir"

if [[ -e "$dmg_path" ]]; then
  print -u2 "Refusing to overwrite an existing disk image: $dmg_path"
  exit 73
fi

staging_dir=$(mktemp -d /tmp/codex-quotaglass-dmg.XXXXXX)
trap 'rm -rf "$staging_dir"' EXIT

cp -R "$app_path" "$staging_dir/QuotaGlass.app"
ln -s /Applications "$staging_dir/Applications"

/usr/bin/hdiutil create \
  -volname "Codex QuotaGlass" \
  -srcfolder "$staging_dir" \
  -format UDZO \
  "$dmg_path"

/usr/bin/hdiutil verify "$dmg_path"
print "$dmg_path"
