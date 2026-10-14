#!/bin/zsh
# Build/package the current app locally. Optional SIGNING_IDENTITY replaces ad-hoc
# signing; notarization remains a separate release step. No monitor access.
set -euo pipefail
project_root=${0:A:h:h}
app_path="$project_root/build/MSI Firmware Updater.app"
scratch_path="$project_root/.build"
/usr/sbin/taskpolicy -c utility nice -n 10 swift build --package-path "$project_root" --scratch-path "$scratch_path" -c release
mkdir -p "$project_root/build"
staging_path=$(mktemp -d "$project_root/build/.MSI Firmware Updater.XXXXXX")
trap 'rm -rf "$staging_path"' EXIT
staged_app_path="$staging_path/MSI Firmware Updater.app"
mkdir -p "$staged_app_path/Contents/MacOS" "$staged_app_path/Contents/Resources"
cp "$scratch_path/release/MSIUpdater" "$staged_app_path/Contents/MacOS/MSIUpdater"
# Remove local debug/object paths from the distribution copy before signing.
strip -S "$staged_app_path/Contents/MacOS/MSIUpdater"
cp "$project_root/Resources/Info.plist" "$staged_app_path/Contents/Info.plist"
cp "$project_root/Resources/AppIcon.icns" "$staged_app_path/Contents/Resources/AppIcon.icns"
cp "$project_root/LICENSE" "$project_root/THIRD_PARTY.md" "$staged_app_path/Contents/Resources/"
signing_identity="${SIGNING_IDENTITY:--}"
signing_arguments=(--force --sign "$signing_identity")
if [[ "$signing_identity" != - ]]; then
    signing_arguments+=(--options runtime --timestamp)
fi
codesign "${signing_arguments[@]}" "$staged_app_path"
codesign --verify --deep --strict "$staged_app_path"
# Replace only after the fresh bundle passes signing and verification.
rm -rf "$app_path"
mv "$staged_app_path" "$app_path"
print -r -- "$app_path"
