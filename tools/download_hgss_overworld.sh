#!/usr/bin/env bash
set -euo pipefail

SOURCE_URL="https://veekun.com/static/pokedex/downloads/overworld.tar.gz"
OUTPUT_DIR="${1:-assets/pokemon/hgss_overworld}"
WORK_DIR="$(mktemp -d)"
ARCHIVE_PATH="$WORK_DIR/overworld.tar.gz"
EXTRACT_DIR="$WORK_DIR/extracted"

cleanup() {
    rm -rf "$WORK_DIR"
}

trap cleanup EXIT

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'error: required command not found: %s\n' "$1" >&2
        exit 1
    fi
}

require_command curl
require_command tar
require_command find

printf 'downloading hgss overworld sprites...\n'
curl --fail --location --retry 3 --retry-delay 2 --show-error --silent "$SOURCE_URL" --output "$ARCHIVE_PATH"

printf 'extracting archive...\n'
mkdir -p "$EXTRACT_DIR"
tar -xzf "$ARCHIVE_PATH" -C "$EXTRACT_DIR"
mkdir -p "$OUTPUT_DIR"

copied_count=0
skipped_count=0

while IFS= read -r -d '' source_path; do
    relative_path="${source_path#"$EXTRACT_DIR"/}"
    IFS='/' read -r -a path_parts <<< "$relative_path"
    is_shiny=false
    is_female=false
    direction=""
    frame="0"

    for part in "${path_parts[@]}"; do
        case "$part" in
            shiny) is_shiny=true ;;
            female) is_female=true ;;
            down|up|left|right) direction="$part" ;;
            frame2) frame="1" ;;
        esac
    done

    if [[ -z "$direction" ]]; then
        ((skipped_count += 1))
        continue
    fi

    filename="${source_path##*/}"
    sprite_key="${filename%.png}"
    dex_number="${sprite_key%%-*}"

    if [[ ! "$dex_number" =~ ^[0-9]+$ ]]; then
        ((skipped_count += 1))
        continue
    fi

    printf -v dex_folder '%03d' "$((10#$dex_number))"

    if [[ "$sprite_key" == *-* ]]; then
        form="${sprite_key#*-}"
        form="${form//-/_}"
    else
        form="default"
    fi

    if [[ "$is_shiny" == true && "$is_female" == true ]]; then
        variant="shiny_female"
    elif [[ "$is_shiny" == true ]]; then
        variant="shiny"
    elif [[ "$is_female" == true ]]; then
        variant="female"
    else
        variant="normal"
    fi

    destination_dir="$OUTPUT_DIR/$dex_folder/$form/$variant"
    destination_path="$destination_dir/${direction}_${frame}.png"
    mkdir -p "$destination_dir"
    cp "$source_path" "$destination_path"
    ((copied_count += 1))
done < <(find "$EXTRACT_DIR" -type f -name '*.png' -print0)

if ((copied_count == 0)); then
    printf 'error: no sprites were found in the downloaded archive.\n' >&2
    exit 1
fi

printf 'done. sprites copied: %d, skipped: %d\n' "$copied_count" "$skipped_count"
printf 'output: %s\n' "$OUTPUT_DIR"
