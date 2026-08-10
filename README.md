# Poképal Playhouse

A Godot 4.6 HD-2D / 2.5D Pokémon-style prototype: billboarded character sprites moving through a real 3D world.

## current prototype

- `CharacterBody3D` player with camera-relative movement.
- HGSS Ditto overworld frames temporarily used as the player visual.
- `AnimatedSprite3D` character visuals with fixed-Y billboarding.
- collision-aware fixed perspective camera using `SpringArm3D`.
- a generated world approximately 144 × 120 world units.
- connected north/south, east/west, curved southern, and highland route branches.
- a winding river, two bridge crossings, a southeast lake, and a southwest pond.
- continuous 3D elevation with northern highlands, an eastern raised plaza, and a western hill.
- dense forest boundaries and internal woodland.
- one combined static level collision mesh generated from the same world layout.
- one shared `AStarGrid2D` navigation cache built from the same water/tree walkability rules.
- random overworld Pokémon that enter through route edges, wander, and leave again.

## world visuals

The world intentionally uses **flat colors only** while the layout and gameplay are being developed.

Current representation:

- ordinary grass: green;
- paths and bridges: tan;
- tall grass: dark green;
- water: blue;
- stone / raised terrain: gray;
- forest blockers / tree objects: dark green boxes.

There are no world tilesheets, route-map textures, imported terrain models, PDSMS assets, or external world-art setup steps. The terrain layout, elevation, collision, navigation, water, bridges, and forest positions remain procedural.

## installing the Pokémon sprite folder

Character sprites are separate from the world-art prototype. The project expects numbered Pokémon folders inside:

```text
res://assets/pokemon/hgss_overworld/
```

To populate them from the existing sprite source:

```bash
./tools/download_hgss_overworld.sh ./assets/pokemon/hgss_overworld
```

Godot must finish importing the PNG files before the runtime Pokémon loader can see them.

## roaming Pokémon

`WildPokemonSpawner` discovers installed species and asks the world builder for valid entry cells and walkable wandering targets. `HgssWorldNavigation` maintains one shared A* grid so all temporary Pokémon use the same terrain rules.

Current behaviour:

1. choose a random available species and form;
2. choose one of four route entrances;
3. enter through a route-edge cell;
4. wander between nearby walkable cells;
5. path around water and forest blockers;
6. remain for roughly 14–32 seconds;
7. route toward a reachable edge;
8. despawn on exit.

The current population cap is 18 temporary Pokémon.

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
    ├── flat_color_world_builder.gd
    ├── hgss_world_builder.gd
    ├── hgss_world_navigation.gd
    └── wild_pokemon_spawner.gd
```

`FlatColorWorldBuilder` supplies the temporary flat-color presentation. It reuses the established procedural layout, height field, collision generation, forest positions, entry points, and navigation-facing queries from `HgssWorldBuilder` without loading any world textures or imported models.

## temporary player art

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
