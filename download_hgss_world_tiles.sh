#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="assets/world/hgss/source_maps"
USER_AGENT="PokepalPlayhouseAssetSetup/1.1"
PNG_MAGIC="89504e470d0a1a0a"

mkdir -p "$OUTPUT_DIR"

download_png() {
    local url="$1"
    local destination="$2"
    local temporary_path="${destination}.part"

    printf 'downloading %s...\n' "$destination"

    rm -f "$temporary_path"

    curl \
        --fail \
        --location \
        --retry 3 \
        --retry-delay 2 \
        --show-error \
        --silent \
        --user-agent "$USER_AGENT" \
        "$url" \
        --output "$temporary_path"

    if [[ ! -s "$temporary_path" ]]; then
        printf 'error: downloaded file is empty: %s\n' "$destination" >&2
        rm -f "$temporary_path"
        exit 1
    fi

    local downloaded_magic
    downloaded_magic="$(od -An -t x1 -N 8 "$temporary_path" | tr -d ' \n')"

    if [[ "$downloaded_magic" != "$PNG_MAGIC" ]]; then
        printf 'error: downloaded file is not a PNG: %s\n' "$destination" >&2
        rm -f "$temporary_path"
        exit 1
    fi

    mv "$temporary_path" "$destination"
}

download_png \
    "https://archives.bulbagarden.net/wiki/Special:Redirect/file/Johto_Route_29_HGSS.png" \
    "$OUTPUT_DIR/route_29.png"

download_png \
    "https://archives.bulbagarden.net/wiki/Special:Redirect/file/Kanto_Route_6_HGSS.png" \
    "$OUTPUT_DIR/route_6.png"

download_png \
    "https://archives.bulbagarden.net/wiki/Special:Redirect/file/Kanto_Route_5_HGSS.png" \
    "$OUTPUT_DIR/route_5.png"

printf '\nHGSS source maps downloaded to %s\n' "$OUTPUT_DIR"
printf 'Open Godot and let the FileSystem dock finish importing the PNG files before running the project.\n'
