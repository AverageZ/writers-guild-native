#!/bin/bash
# Throwaway issue #11 launcher; builds no production targets or resources.
set -euo pipefail
cd "$(dirname "$0")/.."
app="$PWD/build/RepeatedEnterPrototype.app"
assets="$app/Contents/Resources/Editor"
mkdir -p "$app/Contents/MacOS" "$assets"
Editor/node_modules/.bin/esbuild Editor/prototypes/repeated-enter.ts --bundle --format=iife --target=safari16 --outfile="$assets/editor.js"
cp Editor/prototypes/repeated-enter.html "$assets/index.html"
cp Editor/src/editor.css "$assets/editor.css"
cp Editor/node_modules/wordgard/LICENSE "$assets/WORDGARD-LICENSE.txt"
cp Editor/node_modules/crelt/LICENSE "$assets/CRELT-LICENSE.txt"
cp Editor/node_modules/style-mod/LICENSE "$assets/STYLE-MOD-LICENSE.txt"
cp Editor/node_modules/@marijn/find-cluster-break/LICENSE "$assets/FIND-CLUSTER-BREAK-LICENSE.txt"
swiftc -swift-version 6 -parse-as-library Sources/Prototypes/RepeatedEnter.swift -o "$app/Contents/MacOS/RepeatedEnterPrototype"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.writersguild.repeated-enter-prototype</string>
<key>CFBundleExecutable</key><string>RepeatedEnterPrototype</string>
<key>CFBundleName</key><string>Repeated Enter Prototype</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$app"
printf '%s\n' "$app"
