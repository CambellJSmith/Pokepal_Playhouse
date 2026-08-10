#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$ROOT_DIR/assets/world/hgss/pdsms/source"
GENERATED_DIR="$ROOT_DIR/assets/world/hgss/pdsms/generated"
PDSMS_TILESET_PATH="src/main/resources/tilesets/Heart_Gold_-_Soul_Silver/Tileset_2_-_Overworld"
PDSMS_TILESET_FILE="Tileset_2_HGSS_Overworld.pdsts"
PDSMS_REPOSITORY="https://github.com/Trifindo/Pokemon-DS-Map-Studio.git"

for command_name in git python3; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'error: required command not found: %s\n' "$command_name" >&2
        exit 1
    fi
done

TEMP_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

printf 'fetching the PDSMS HeartGold/SoulSilver overworld tileset...\n'

git clone \
    --depth 1 \
    --filter=blob:none \
    --sparse \
    --quiet \
    "$PDSMS_REPOSITORY" \
    "$TEMP_DIR/pdsms"

git -C "$TEMP_DIR/pdsms" sparse-checkout set "$PDSMS_TILESET_PATH"

rm -rf "$SOURCE_DIR" "$GENERATED_DIR"
mkdir -p "$SOURCE_DIR"
cp -a "$TEMP_DIR/pdsms/$PDSMS_TILESET_PATH/." "$SOURCE_DIR/"

if [[ ! -f "$SOURCE_DIR/$PDSMS_TILESET_FILE" ]]; then
    printf 'error: expected PDSMS tileset was not found after checkout: %s\n' "$SOURCE_DIR/$PDSMS_TILESET_FILE" >&2
    exit 1
fi

printf 'converting the PDSMS .pdsts tileset into Godot-importable OBJ meshes...\n'
python3 \
    "$ROOT_DIR/tools/convert_pdsms_hgss_tileset.py" \
    "$SOURCE_DIR/$PDSMS_TILESET_FILE" \
    "$SOURCE_DIR" \
    "$GENERATED_DIR"

printf '\nHGSS 3D tile assets are ready under:\n  %s\n' "$GENERATED_DIR"
printf '\nNext steps:\n'
printf '  1. Open the project in Godot and let FileSystem imports finish.\n'
printf '  2. Open scenes/tools/hgss_tile_gallery.tscn and run the current scene (F6).\n'
printf '  3. Use Left/Right to page through tiles; press G to inspect PDSMS smart-grid groups.\n'
