#!/bin/bash
set -euo pipefail

configuration="release"
case "${1:-}" in
  "") ;;
  --debug) configuration="debug" ;;
  --help|-h)
    printf 'Usage: %s [--debug]\nBuilds dist/iTelier.app for the current Mac architecture.\n' "$0"
    exit 0
    ;;
  *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
esac
if [ "$#" -gt 1 ]; then
  printf 'Only one optional argument is supported.\n' >&2
  exit 2
fi

if [ "$(uname -s)" != "Darwin" ]; then
  printf 'iTelier requires macOS to build its SwiftUI application.\n' >&2
  exit 1
fi
if ! command -v swift >/dev/null 2>&1; then
  printf 'Swift is missing. Install the Apple Command Line Tools before building.\n' >&2
  exit 1
fi

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_directory="$(cd "$script_directory/.." && pwd)"
distribution_directory="$project_directory/dist"
application_bundle="$distribution_directory/iTelier.app"
runtime_tag="sonoma"
if [ "$(uname -m)" = "arm64" ]; then runtime_tag="arm64_sonoma"; fi
runtime_directory="${ITELIER_RUNTIME_ROOT:-$project_directory/.runtime/$runtime_tag}"
if [ ! -f "$runtime_directory/_sources/sources.json" ]; then
  printf 'USB runtime missing. Run python3 scripts/prepare-runtime.py before building.\n' >&2
  exit 1
fi

cd "$project_directory"
swift_flags=()
if [ "$configuration" = "release" ]; then
  # A distributable development bundle does not require a separate dSYM.
  # This also supports CLT installations where dsymutil cannot write its cache.
  swift_flags+=("-debug-info-format" "none")
fi
if [ "${ITELIER_SWIFT_DISABLE_SANDBOX:-0}" = "1" ]; then
  # Opt in only where a parent sandbox prevents SwiftPM's nested sandbox.
  swift_flags+=(--disable-sandbox)
fi
# The + form supports macOS Bash 3.2 with nounset and an empty flags array.
swift build ${swift_flags[@]+"${swift_flags[@]}"} --configuration "$configuration" --product iTelier
swift build ${swift_flags[@]+"${swift_flags[@]}"} --configuration "$configuration" --product iTelierRestoreHost
swift build ${swift_flags[@]+"${swift_flags[@]}"} --configuration "$configuration" --product iTelierWallpaperHost
binary_directory="$(swift build ${swift_flags[@]+"${swift_flags[@]}"} --configuration "$configuration" --show-bin-path)"
if [ ! -x "$binary_directory/iTelier" ]; then
  printf 'The iTelier executable was not produced.\n' >&2
  exit 1
fi

mkdir -p "$distribution_directory"
staging_directory="$(mktemp -d "$distribution_directory/.itelier-build.XXXXXX")"
trap 'rm -rf "$staging_directory"' EXIT
staged_bundle="$staging_directory/iTelier.app"
mkdir -p "$staged_bundle/Contents/MacOS" "$staged_bundle/Contents/Resources"
cp "$binary_directory/iTelier" "$staged_bundle/Contents/MacOS/iTelier"

# Keep resource bundles in the macOS resource directory so strict code signing
# seals them. In-app illustrations are drawn natively in SwiftUI.
for resource_bundle in "$binary_directory/iTelier_iTelier.bundle"; do
  if [ -d "$resource_bundle" ]; then
    ditto "$resource_bundle" "$staged_bundle/Contents/Resources/$(basename "$resource_bundle")"
  fi
done
# Main-bundle localization lets AppKit translate its standard menus and panels.
mkdir -p "$staged_bundle/Contents/Resources/fr.lproj"
cp "$project_directory/Sources/iTelier/Resources/fr.lproj/InfoPlist.strings" "$staged_bundle/Contents/Resources/fr.lproj/InfoPlist.strings"
mkdir -p "$staged_bundle/Contents/Resources/en.lproj"
cp "$project_directory/Sources/iTelier/Resources/en.lproj/InfoPlist.strings" "$staged_bundle/Contents/Resources/en.lproj/InfoPlist.strings"
python3 "$script_directory/bundle-runtime.py" "$runtime_directory" "$staged_bundle"
cp "$binary_directory/iTelierRestoreHost" "$staged_bundle/Contents/Helpers/iTelierRestoreHost"
codesign --force --sign - "$staged_bundle/Contents/Helpers/iTelierRestoreHost"
cp "$binary_directory/iTelierWallpaperHost" "$staged_bundle/Contents/Helpers/iTelierWallpaperHost"
codesign --force --sign - "$staged_bundle/Contents/Helpers/iTelierWallpaperHost"

cat > "$staged_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>iTelier</string>
  <key>CFBundleDisplayName</key><string>iTelier</string>
  <key>CFBundleIdentifier</key><string>com.itelier.app</string>
  <key>CFBundleExecutable</key><string>iTelier</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2.0</string>
  <key>CFBundleVersion</key><string>39</string>
  <key>CFBundleDevelopmentRegion</key><string>fr</string>
  <key>CFBundleLocalizations</key><array><string>fr</string><string>en</string></array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

if [ -f "$project_directory/assets/AppIcon.icns" ]; then
  cp "$project_directory/assets/AppIcon.icns" "$staged_bundle/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon' "$staged_bundle/Contents/Info.plist"
fi
/usr/bin/plutil -lint "$staged_bundle/Contents/Info.plist"

signature_description="unsigned"
if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$staged_bundle"
  codesign --verify --strict "$staged_bundle"
  signature_description="ad-hoc signed"
fi

# Replace only the generated bundle after compilation and signing have succeeded.
if [ -L "$application_bundle" ]; then
  printf 'Refusing to replace a symbolic link at %s\n' "$application_bundle" >&2
  exit 1
fi
rm -rf "$application_bundle"
mv "$staged_bundle" "$application_bundle"
printf '\nBuilt %s (%s, %s).\n' "$application_bundle" "$configuration" "$(uname -m)"
printf 'This development bundle is %s, not notarized.\n' "$signature_description"
