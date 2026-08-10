#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="assets/world/hgss/source_maps"
USER_AGENT="Mozilla/5.0 (compatible; PokepalPlayhouseAssetSetup/1.0)"

mkdir -p "$OUTPUT_DIR"

download_png() {
    local url="$1"
    local destination="$2"

    printf 'downloading %s...\n' "$destination"

    curl \
        --fail \
        --location \
        --retry 3 \
        --retry-delay 2 \
        --show-error \
        --silent \
        --user-agent "$USER_AGENT" \
        "$url" \
        --output "$destination"

    if [[ ! -s "$destination" ]]; then
        printf 'error: downloaded file is empty: %s\n' "$destination" >&2
        exit 1
    fi
}

download_png \
    "https://www.pokemontrash.com/images/heartgold-soulsilver/lieux/routes/route-29.png" \
    "$OUTPUT_DIR/route_29.png"

download_png \
    "https://www.pokebip.com/pages/jeux-video/pokemon-heartgold-soulsilver/guide-complet-johto-kanto/images/map/route-6.png" \
    "$OUTPUT_DIR/route_6.png"

download_png \
    "https://www.pokebip.com/pages/jeux-video/pokemon-heartgold-soulsilver/guide-complet-johto-kanto/images/map/route-5.png" \
    "$OUTPUT_DIR/route_5.png"

printf '\nHGSS source maps downloaded to %s\n' "$OUTPUT_DIR"
printf 'Open Godot and let the FileSystem dock finish importing the PNG files before running the project.\n'
