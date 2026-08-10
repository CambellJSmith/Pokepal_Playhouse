# Poképal Playhouse

A Godot 4.6 HD-2D / 2.5D Pokémon-style prototype: billboarded character sprites moving through a real 3D world.

## current prototype

- `CharacterBody3D` player with camera-relative movement.
- HGSS Ditto overworld frames temporarily used as the player visual.
- `AnimatedSprite3D` character visuals with fixed-Y billboarding.
- collision-aware fixed perspective camera using `SpringArm3D`.
- a generated world measuring 168 × 136 terrain cells, approximately 252 × 204 world units.
- seventeen contiguous type-biome regions: one for every Pokémon type available in Generation IV.
- a redundant grid/ring route network joining all regions, plus four world-edge entrances.
- broad continuous elevation rather than isolated platforms.
- procedural low-poly trees, water, bridge decks and type-specific landmarks.
- one combined static level collision mesh generated from the same world layout.
- one shared `AStarGrid2D` navigation cache built from the same water/tree walkability rules.
- random overworld Pokémon that enter through route edges, wander, and leave again.

## Generation IV type world

Generation IV has seventeen Pokémon types; Fairy did not exist yet. The world therefore contains one destination for each of these seventeen types:

- **Normal — Central Meadow:** open rolling grass and the main route hub.
- **Fire — Volcanic Basin:** rust-colored ground, a broad volcanic rise and warm vent pillars.
- **Water — Lake District:** a large contained lake, coves, shoreline and wooden causeways.
- **Electric — Electric Plains:** yellow-green open plains with tall pylon-like landmarks.
- **Grass — Deep Forest:** the densest living woodland, with a deliberate central clearing.
- **Ice — Snowfield:** pale icy stone, high cold terrain and ice-monolith landmarks.
- **Fighting — Training Plateau:** red-brown ground with repeated training-pillar forms.
- **Poison — Marsh:** purple terrain broken by contained swamp pools.
- **Ground — Badlands:** ochre raised terrain and scattered low boulder forms.
- **Flying — Wind Plateau:** a high pale plateau with sparse vertical wind-marker pillars.
- **Psychic — Psychic Garden:** lavender ground with geometric monoliths.
- **Bug — Bug Woods:** yellow-green woodland with a more open understory than the Grass forest.
- **Rock — Mountain Range:** one of the highest mountain regions, with dense rocky landmark forms.
- **Ghost — Ghost Hollow:** slate-violet ground, sparse dark woodland and gravestone-like monoliths.
- **Dragon — Dragon Peaks:** the highest dramatic peaks with tapered spire landmarks.
- **Dark — Dark Forest:** charcoal terrain and dark-canopy woodland.
- **Steel — Steel District:** cool metallic terrain with industrial pillar forms.

The biome layout is a contiguous nearest-region partition rather than seventeen disconnected islands. Designed route segments connect neighboring regions horizontally, vertically and through the central Normal hub, so there are multiple ways to travel around the map.

The world builder also performs a startup connectivity pass. Any tiny open pocket that cannot reach the central landmass is converted into blocking scenery before collision and navigation are constructed.

## world visuals

World art remains **asset-free and procedural**. There are no world tilesheets, route-map textures, imported terrain models, PDSMS assets, or external world-art setup steps.

Visuals are generated at runtime using Godot geometry and materials:

- biome-specific shaded ground colors;
- warm shared route surfaces;
- translucent water with a darker depth layer;
- low-poly trees made from cylinder trunks and layered sphere canopies;
- wooden bridge/causeway deck geometry where routes cross water;
- deterministic type-specific primitives used as environmental landmarks;
- broad mountain, plateau, basin and lowland height shaping blended continuously between regions.

## installing the Pokémon sprite folder

Character sprites are separate from the procedural world. The project expects numbered Pokémon folders inside:

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
- The player starts in the central Normal Meadow.
- Follow the connected route network outward to the sixteen surrounding type regions.
- Routes through the Water and Poison regions become visible wooden causeways where they cross liquid.

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
    ├── hgss_world_navigation.gd
    └── wild_pokemon_spawner.gd
```

`HgssWorldBuilder` owns biome classification, route layout, terrain surfaces, continuous elevation, connectivity cleanup, static collision, water, scenery batching, entry points, and walkable-position queries. `HgssWorldNavigation` owns the shared grid pathfinder. `WildPokemonSpawner` owns population policy.

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
