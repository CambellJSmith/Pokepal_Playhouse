# Poképal Playhouse

A Godot 4.6 HD-2D / 2.5D Pokémon-style prototype: real 3D terrain and collision with camera-facing HGSS Pokémon sprites.

## current prototype

- `CharacterBody3D` player with camera-relative movement.
- HGSS Ditto overworld frames temporarily used as the player visual.
- `AnimatedSprite3D` with fixed-Y billboarding, nearest filtering, alpha cut, and normal depth testing.
- reusable `BillboardCharacterVisual` component shared by the player and roaming Pokémon.
- collision-aware fixed perspective camera using `SpringArm3D`.
- a generated world approximately 144 × 120 world units rather than the original tiny test route.
- connected north/south, east/west, curved southern, and highland route branches.
- a winding river, two bridge crossings, a southeast lake, and a southwest pond.
- continuous 3D elevation with northern highlands, an eastern raised plaza, and a western hill.
- dense forest boundaries and internal woodland using batched `MultiMeshInstance3D` tree geometry.
- procedural terrain surfaces built from small texture crops sampled from actual HeartGold/SoulSilver route-map images.
- one combined static level collision mesh generated from the same height field as the visible terrain.
- random overworld Pokémon that enter through route gates, wander on valid terrain, hang out, then leave through the nearest gate.
- roaming Pokémon collide with the world, the player, and each other.
- runtime Pokémon sprite discovery that automatically sees numbered species folders and their forms.

## installing the complete Pokémon sprite folder

The project expects numbered folders directly inside:

```text
res://assets/pokemon/hgss_overworld/
```

For example:

```text
assets/pokemon/hgss_overworld/
├── 001/
│   └── default/
│       └── normal/
│           ├── down_0.png
│           ├── down_1.png
│           ├── left_0.png
│           ├── left_1.png
│           ├── right_0.png
│           ├── right_1.png
│           ├── up_0.png
│           └── up_1.png
├── 002/
├── 003/
├── ...
├── 132/
└── 493/
```

To populate the folder from the Veekun archive:

```bash
./tools/download_hgss_overworld.sh ./assets/pokemon/hgss_overworld
```

Godot must finish importing the PNG files before the runtime loader can see them.

## installing the HGSS world tiles

The 3D world can run with fallback colors, but the intended look samples its terrain pixels from clean HeartGold/SoulSilver route maps.

From the repository root run:

```bash
bash download_hgss_world_tiles.sh
```

That creates:

```text
assets/world/hgss/source_maps/
├── route_29.png
├── route_6.png
└── route_5.png
```

These downloaded PNG files are ignored by Git and therefore survive `sync_from_github.sh`, which uses `git clean -fd` rather than deleting ignored files.

The world builder uses `AtlasTexture` regions from those source maps for grass, dirt path, tall grass, water, and stone terrain. If the files are absent, the same terrain layout is generated with fallback colors so development can continue.

## roaming Pokémon

`WildPokemonSpawner` discovers installed species and asks `HgssWorldBuilder` for valid entry points and walkable wandering targets.

Current behaviour:

1. choose a random Pokédex species uniformly;
2. choose one of that species' available forms;
3. choose one of four route entrances;
4. spawn just beyond that map entrance;
5. walk into the generated world;
6. idle and wander between nearby walkable cells;
7. remain for roughly 14–32 seconds;
8. walk toward the nearest route exit;
9. despawn after leaving.

The current population cap is 18 temporary Pokémon. Only the `normal` visual variant is used for random spawning; female and shiny folders remain available for later encounter rules.

## run

Open `project.godot` with Godot 4.6 and press F5.

Controls:

- WASD, arrow keys, or left stick: move.
- Explore north for the highlands.
- Follow the east route to the raised plaza.
- Cross the river at the bridge routes.
- Explore the western woodland and southern encounter fields.

## architecture

```text
scenes/
├── camera/
│   └── camera_rig.tscn
├── characters/
│   ├── ditto_visual.tscn
│   ├── pokemon_visual.tscn
│   ├── player.tscn
│   └── wild_pokemon.tscn
└── world/
    └── main.tscn

scripts/
├── camera/
│   └── camera_rig.gd
├── characters/
│   ├── billboard_character_visual.gd
│   ├── player_controller.gd
│   ├── pokemon_sprite_library.gd
│   └── wild_pokemon.gd
├── core/
│   └── input_bootstrap.gd
└── world/
    ├── hgss_world_builder.gd
    └── wild_pokemon_spawner.gd
```

`HgssWorldBuilder` owns terrain classification, procedural geometry, static world collision, forest batching, water boundaries, and walkable-position queries. `WildPokemonSpawner` owns population policy. Each `WildPokemon` owns only its temporary behaviour and movement. `BillboardCharacterVisual` owns camera-relative sprite facing and animation selection.

## replacing the temporary player art

The current player visual points at `resources/sprite_frames/ditto_overworld.tres`. Later, replace it with a player-specific `SpriteFrames` resource containing the same animation names:

```text
idle_down
idle_up
idle_left
idle_right
walk_down
walk_up
walk_left
walk_right
```

The player movement controller does not need to change.

## asset sources

The included Ditto frames and downloaded Pokémon overworld sprites come from Veekun's collected HGSS game sprites.

The optional world source-map downloader currently retrieves clean HGSS route-map images used only as texture sources for the procedural 3D prototype. Pokémon and related game artwork remain property of their respective rights holders; replace or license assets appropriately for distributed work.
