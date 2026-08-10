# HGSS 3D tile pipeline

The playable world is being migrated away from screenshot-derived terrain textures and toward the reusable HeartGold/SoulSilver 3D map pieces bundled with Pokemon DS Map Studio (PDSMS).

The PDSMS HGSS overworld preset is stored as `Tileset_2_HGSS_Overworld.pdsts`. That binary file contains the reusable tile geometry, UV coordinates, normals, material assignments, source texture references, logical tile dimensions, and PDSMS smart-drawing grids.

## Local setup

From the repository root run:

```bash
bash setup_hgss_3d_tiles.sh
```

The script performs a shallow sparse checkout of only the PDSMS HGSS overworld tileset, then runs `tools/convert_pdsms_hgss_tileset.py`.

The converter writes locally generated assets under:

```text
assets/world/hgss/pdsms/generated/
├── catalog.json
├── textures/
└── tiles/
    ├── tile_000.obj
    ├── tile_000.mtl
    ├── tile_001.obj
    └── ...
```

Both the downloaded source tileset and converted assets are Git-ignored. They are development inputs and are not committed to this repository.

After conversion, open Godot and let the FileSystem dock finish importing the OBJ and texture files.

## Verifying the real tile IDs

Open:

```text
scenes/tools/hgss_tile_gallery.tscn
```

Run the current scene with F6.

Controls:

- Left / Right: change page.
- G: toggle between the complete tile list and the PDSMS smart-drawing groups.

Every tile is labeled with its original PDSMS tile ID. Smart-grid pages display the exact 5×3 tile-ID matrices stored in the HGSS tileset.

This inspection step is intentional. The map builder should reference verified source tile IDs rather than guessing that a numeric tile corresponds to grass, water, path edges, trees, cliffs, or another terrain family.

## Why this replaces the old approach

The previous prototype downloaded complete route-map screenshots and cropped arbitrary regions from those images onto procedural ground quads. That does not reproduce the HGSS map construction system and produces stretched or repeated chunks of whole map artwork.

The PDSMS pipeline preserves the individual 3D pieces and their own UV/material data. Once the terrain-family IDs are verified, the production map can compose those pieces directly, batch repeated meshes, and generate collision/navigation from the same map data.

## Source note

Pokemon DS Map Studio is a public map-authoring tool for Nintendo DS Pokemon games and includes predesigned HeartGold/SoulSilver map resources. Pokemon and related game artwork remain property of their respective rights holders. Keep locally sourced game assets out of distributed builds unless you have the appropriate rights to distribute them.
