#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
info_plist="$repo_root/SpaceLens/Resources/Info.plist"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")
identity=${SPACELENS_SIGNING_IDENTITY:-}
notary_profile=${SPACELENS_NOTARY_PROFILE:-}

if [ -z "$identity" ]; then
    echo "Set SPACELENS_SIGNING_IDENTITY to an Apple Development or Developer ID Application identity." >&2
    exit 1
fi

case "$identity" in
    "Developer ID Application:"*) distribution_identity=true ;;
    *) distribution_identity=false ;;
esac

if [ -n "$notary_profile" ] && [ "$distribution_identity" != true ]; then
    echo "Notarization requires a Developer ID Application identity." >&2
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
zip_path="$output_dir/SpaceLens-$version.zip"

xcodebuild -quiet \
    -project "$repo_root/SpaceLens.xcodeproj" \
    -scheme SpaceLens \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    build

cp -R "$app_source" "$app_staged"
if [ "$distribution_identity" = true ]; then
    codesign --force --deep --options runtime --timestamp --sign "$identity" "$app_staged"
else
    codesign --force --deep --options runtime --sign "$identity" "$app_staged"
fi
codesign --verify --deep --strict --verbose=2 "$app_staged"

mkdir -p "$dmg_root" "$output_dir"
cp -R "$app_staged" "$dmg_root/SpaceLens.app"
ln -s /Applications "$dmg_root/Applications"
if hdiutil create -quiet -ov \
    -volname "SpaceLens $version" \
    -srcfolder "$dmg_root" \
    -format UDZO \
    "$dmg_path"; then
    artifact_path="$dmg_path"
    if [ "$distribution_identity" = true ]; then
        codesign --force --timestamp --sign "$identity" "$dmg_path"
    else
        codesign --force --sign "$identity" "$dmg_path"
    fi
else
    if [ "$distribution_identity" = true ] || [ -n "$notary_profile" ]; then
        echo "DMG creation failed; refusing a non-stapleable distribution fallback." >&2
        exit 1
    fi
    echo "DMG creation unavailable; creating a Development ZIP instead." >&2
    ditto -c -k --sequesterRsrc --keepParent "$app_staged" "$zip_path"
    artifact_path="$zip_path"
fi

if [ -n "$notary_profile" ]; then
    xcrun notarytool submit "$artifact_path" \
        --keychain-profile "$notary_profile" \
        --wait
    xcrun stapler staple "$artifact_path"
    xcrun stapler validate "$artifact_path"
fi

echo "Created $artifact_path"
if [ "$distribution_identity" != true ]; then
    echo "Development-signed build: Gatekeeper may warn on other Macs."
fi
