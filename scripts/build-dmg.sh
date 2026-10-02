#!/bin/bash
set -euo pipefail

case "${1:-}" in
  "") ;;
  --help|-h)
    printf 'Usage: %s\nCrée un DMG iTelier depuis le bundle déjà compilé dans dist/.\n' "$0"
    exit 0
    ;;
  *) printf 'Option inconnue : %s\n' "$1" >&2; exit 2 ;;
esac
if [ "$#" -gt 1 ]; then
  printf 'Aucun argument supplémentaire n’est accepté.\n' >&2
  exit 2
fi
if [ "$(uname -s)" != "Darwin" ]; then
  printf 'La création du DMG nécessite macOS.\n' >&2
  exit 1
fi
architecture="$(uname -m)"
case "$architecture" in
  arm64|x86_64) ;;
  *) printf 'Architecture non prise en charge : %s\n' "$architecture" >&2; exit 1 ;;
esac

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_directory="$(cd "$script_directory/.." && pwd)"
distribution_directory="$project_directory/dist"
application_bundle="$distribution_directory/iTelier.app"
if [ ! -d "$application_bundle" ]; then
  printf 'Bundle absent. Lancez d’abord bash scripts/build-app.sh.\n' >&2
  exit 1
fi
/usr/bin/codesign --verify --deep --strict "$application_bundle"

# L’image n’est remplacée qu’une fois sa création et son intégrité vérifiées.
staging_directory="$(mktemp -d "$distribution_directory/.itelier-dmg.XXXXXX")"
trap 'rm -rf "$staging_directory"' EXIT
content_directory="$staging_directory/content"
mkdir "$content_directory"
/usr/bin/ditto "$application_bundle" "$content_directory/iTelier.app"
ln -s /Applications "$content_directory/Applications"
icon="$application_bundle/Contents/Resources/AppIcon.icns"
if [ -f "$icon" ]; then
  cp "$icon" "$content_directory/.VolumeIcon.icns"
  /usr/bin/xcrun SetFile -a C "$content_directory"
fi
image_name="iTelier-macOS-$architecture.dmg"
staged_image="$staging_directory/$image_name"
/usr/bin/hdiutil create -volname iTelier -srcfolder "$content_directory" \
  -fs HFS+ -format UDZO "$staged_image"
/usr/bin/hdiutil verify "$staged_image"
mv -f "$staged_image" "$distribution_directory/$image_name"
printf 'DMG prêt : %s\n' "$distribution_directory/$image_name"
