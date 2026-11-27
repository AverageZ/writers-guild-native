#!/bin/bash
# Throwaway issue #9 launcher. Same standalone bundle layout as the writing-surface prototype.
set -euo pipefail
cd "$(dirname "$0")/.."
options=(--scratch-path "$PWD/build/outline-cards-build")
swift build "${options[@]}" --target EditorHost
bin=$(swift build "${options[@]}" --show-bin-path)
if [[ -d "$bin/Modules" ]]; then
  modules="$bin/Modules"
  objects=("$bin"/EditorHost.build/*.swift.o "$bin"/GuildCore.build/*.swift.o)
else
  modules="$bin"
  objects=("$bin/EditorHost.o" "$bin/GuildCore.o")
fi
app="$PWD/build/OutlineCardsPrototype.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -swift-version 6 -parse-as-library -I "$modules" \
  Sources/Prototypes/OutlineCards{,Model,Smoke}.swift "${objects[@]}" \
  -o "$app/Contents/MacOS/OutlineCardsPrototype"
assets="$bin/WritersGuild_EditorHost.bundle"
if [[ -d "$assets/Contents/Resources" ]]; then assets="$assets/Contents/Resources"; fi
ditto "$assets/Editor" "$app/Contents/Resources/WritersGuild_EditorHost.bundle/Editor"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.writersguild.outline-cards-prototype</string>
<key>CFBundleExecutable</key><string>OutlineCardsPrototype</string>
<key>CFBundleName</key><string>Outline Cards Prototype</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$app"
printf '%s\n' "$app"
