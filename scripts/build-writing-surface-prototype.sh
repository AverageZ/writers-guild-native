#!/bin/bash
# Throwaway issue #8 launcher. Link the existing native editor modules into a separate app.
set -euo pipefail
cd "$(dirname "$0")/.."
build_options=(--scratch-path "$PWD/build/writing-surface-build")
swift build "${build_options[@]}" --target EditorHost
bin=$(swift build "${build_options[@]}" --show-bin-path)
if [[ -d "$bin/Modules" ]]; then
  modules="$bin/Modules"
  objects=("$bin"/EditorHost.build/*.swift.o "$bin"/GuildCore.build/*.swift.o)
else
  modules="$bin"
  objects=("$bin/EditorHost.o" "$bin/GuildCore.o")
fi
app="$PWD/build/WritingSurfacePrototype.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -swift-version 6 -parse-as-library -I "$modules" \
  Sources/Prototypes/WritingSurface.swift \
  "${objects[@]}" \
  -o "$app/Contents/MacOS/WritingSurfacePrototype"
# Use SwiftPM's flat bundle layout in this scratch app. In the Contents/Resources
# layout Foundation produces a base-relative URL that current EditorHost rejects.
assets="$bin/WritersGuild_EditorHost.bundle"
if [[ -d "$assets/Contents/Resources" ]]; then assets="$assets/Contents/Resources"; fi
editor_bundle="$app/Contents/Resources/WritersGuild_EditorHost.bundle"
rm -rf "$editor_bundle"
ditto "$assets/Editor" "$editor_bundle/Editor"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.writersguild.writing-surface-prototype</string>
<key>CFBundleExecutable</key><string>WritingSurfacePrototype</string>
<key>CFBundleName</key><string>Writing Surface Prototype</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$app"
printf '%s\n' "$app"
