#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
info_plist="$repo_root/SpaceLens/Resources/Info.plist"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")
identity=${SPACELENS_SIGNING_IDENTITY:-}
notary_profile=${SPACELENS_NOTARY_PROFILE:-}

if [ -z "$identity" ]; then
    echo "Set SPACELENS_SIGNING_IDENTITY to a Developer ID Application identity." >&2
    exit 1
fi

derived_data="/tmp/SpaceLensRelease-$version-$build"
stage_root=$(mktemp -d /tmp/SpaceLensPackage.XXXXXX)
trap 'rm -rf "$stage_root"' EXIT INT TERM
output_dir="$repo_root/dist"
app_source="$derived_data/Build/Products/Release/SpaceLens.app"
app_staged="$stage_root/SpaceLens.app"
dmg_root="$stage_root/dmg"
dmg_path="$output_dir/SpaceLens-$version.dmg"

xcodebuild -quiet \
    -project "$repo_root/SpaceLens.xcodeproj" \
    -scheme SpaceLens \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    build

cp -R "$app_source" "$app_staged"
codesign --force --deep --options runtime --timestamp --sign "$identity" "$app_staged"
codesign --verify --deep --strict --verbose=2 "$app_staged"

mkdir -p "$dmg_root" "$output_dir"
cp -R "$app_staged" "$dmg_root/SpaceLens.app"
ln -s /Applications "$dmg_root/Applications"
hdiutil create -quiet -ov \
    -volname "SpaceLens $version" \
    -srcfolder "$dmg_root" \
    -format UDZO \
    "$dmg_path"
codesign --force --timestamp --sign "$identity" "$dmg_path"

if [ -n "$notary_profile" ]; then
    xcrun notarytool submit "$dmg_path" \
        --keychain-profile "$notary_profile" \
        --wait
    xcrun stapler staple "$dmg_path"
    xcrun stapler validate "$dmg_path"
fi

echo "Created $dmg_path"
