# HGSS source map textures

This folder is populated locally by `download_hgss_world_tiles.sh`.

The generated 3D world samples small texture regions from clean Pokémon HeartGold/SoulSilver route-map images and maps those 2D pixels onto procedural 3D terrain surfaces.

Expected local files:

```text
route_29.png
route_6.png
route_5.png
```

The PNG files are intentionally ignored by Git so a local clone can keep them without adding copied game artwork to every source commit.

Run from the repository root:

```bash
bash download_hgss_world_tiles.sh
```

If these source images are absent, the world builder uses simple fallback colors so the project still loads.

Pokémon and related game artwork are property of their respective rights holders. The source-map images are used as temporary fan-development reference assets.
