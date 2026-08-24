#!/bin/zsh
set -euo pipefail

configuration="${1:-release}"
project_dir="${0:A:h:h}"
app_dir="$project_dir/.build/app/QuotaGlass.app"
contents_dir="$app_dir/Contents"

cd "$project_dir"
swift build -c "$configuration" --product QuotaGlass
binary_dir=$(swift build -c "$configuration" --show-bin-path)

rm -rf "$app_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$binary_dir/QuotaGlass" "$contents_dir/MacOS/QuotaGlass"
cp "$project_dir/Packaging/Info.plist" "$contents_dir/Info.plist"
cp "$project_dir/Resources/QuotaGlassIcon.svg" "$contents_dir/Resources/QuotaGlassIcon.svg"

icon_work_dir=$(mktemp -d /tmp/quotaglass-icon.XXXXXX)
trap 'rm -rf "$icon_work_dir"' EXIT
/usr/bin/qlmanage -t -s 1024 -o "$icon_work_dir" "$project_dir/Resources/QuotaGlassIcon.svg" >/dev/null 2>&1
source_icon="$icon_work_dir/QuotaGlassIcon.svg.png"
iconset_dir="$icon_work_dir/QuotaGlassIcon.iconset"
mkdir -p "$iconset_dir"

for specification in \
    "16 icon_16x16.png" \
    "32 icon_16x16@2x.png" \
    "32 icon_32x32.png" \
    "64 icon_32x32@2x.png" \
    "128 icon_128x128.png" \
    "256 icon_128x128@2x.png" \
    "256 icon_256x256.png" \
    "512 icon_256x256@2x.png" \
    "512 icon_512x512.png" \
    "1024 icon_512x512@2x.png"
do
    size="${specification%% *}"
    filename="${specification#* }"
    /usr/bin/sips -z "$size" "$size" "$source_icon" --out "$iconset_dir/$filename" >/dev/null
done

/usr/bin/iconutil -c icns "$iconset_dir" -o "$contents_dir/Resources/QuotaGlassIcon.icns"

sign_identity="${QUOTAGLASS_SIGN_IDENTITY:--}"
/usr/bin/codesign --force --options runtime --entitlements "$project_dir/Packaging/QuotaGlass.entitlements" --sign "$sign_identity" "$app_dir"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_dir"

print "$app_dir"
