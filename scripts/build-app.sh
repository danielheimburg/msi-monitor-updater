#!/bin/zsh
# Build/package the current app locally. Optional SIGNING_IDENTITY replaces ad-hoc
# signing; notarization remains a separate release step. No monitor access.
set -euo pipefail
project_root=${0:A:h:h}
app_path="$project_root/build/MSI Firmware Updater.app"
scratch_path="$project_root/.build"
/usr/sbin/taskpolicy -c utility nice -n 10 swift build --package-path "$project_root" --scratch-path "$scratch_path" -c release
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$scratch_path/release/MSIUpdater" "$app_path/Contents/MacOS/MSIUpdater"
cp "$project_root/Resources/Info.plist" "$app_path/Contents/Info.plist"
cp "$project_root/Resources/AppIcon.icns" "$app_path/Contents/Resources/AppIcon.icns"
codesign --force --sign "${SIGNING_IDENTITY:--}" "$app_path"
codesign --verify --deep --strict "$app_path"
print -r -- "$app_path"
