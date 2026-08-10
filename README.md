# Poképal Playhouse

A Godot 4.6 HD-2D / 2.5D Pokémon-style prototype: billboarded character sprites moving through a real 3D world.

## current prototype

- `CharacterBody3D` player with camera-relative movement.
- HGSS Ditto overworld frames temporarily used as the player visual.
- bottom-anchored `AnimatedSprite3D` character visuals with fixed-Y billboarding.
- collision-aware free-orbit third-person camera using `SpringArm3D`.
- a generated world measuring 264 × 216 terrain cells, approximately 396 × 324 world units.
- seventeen large contiguous type-biome regions: one for every Pokémon type available in Generation IV.
- a redundant grid/ring route network joining all regions, plus four world-edge entrances.
- broad multi-feature elevation with mountain chains, peaks, plateaus, volcanic terrain, basins, badland ridges, forest hills and marsh lowlands.
- procedural low-poly trees, water, bridge decks and type-specific scenery.
- one large named signature landmark in every biome.
- an openable schematic world map with all seventeen landmarks and fast travel.
- wild Pokémon whose Generation IV primary type dictates their habitat region.
- one combined static level collision mesh generated from the same world layout.
- one shared `AStarGrid2D` navigation cache built from the same water/tree walkability rules.

## Generation IV type world

Generation IV has seventeen Pokémon types; Fairy did not exist yet. The world contains one large region and one major destination for each type:

- **Normal — Central Meadow:** Heartstone Plaza and broad rolling central grassland.
- **Fire — Volcanic Basin:** Ember Crater inside a raised volcanic bowl with a depressed crater center.
- **Water — Lake District:** Tide Shrine, a large lake system, coves, an inlet and a walkable island.
- **Electric — Electric Plains:** Volt Substation across broad open terrain intended to remain highly visible from the free camera.
- **Grass — Deep Forest:** Ancient Grove inside a much wider rolling forest with a deliberate central clearing.
- **Ice — Snowfield:** Crystal Sanctum on a broad elevated glacial shelf.
- **Fighting — Training Plateau:** Red Belt Dojo on raised terrain between western and central routes.
- **Poison — Poison Marsh:** Toxic Wells surrounded by a much larger patterned wetland and scattered pools.
- **Ground — Badlands:** Dust Gate across raised ochre terrain with repeated ridge undulation.
- **Flying — Wind Plateau:** Skywatch Tower on a high open plateau.
- **Psychic — Psychic Garden:** Mind Crystal Garden on gently raised terrain east of the central meadow.
- **Bug — Bug Woods:** Grand Hive inside a much larger open woodland.
- **Rock — Mountain Range:** Summit Cairn among a broad mountain mass with several separate peaks and rocky ridges.
- **Ghost — Ghost Hollow:** Haunted Ruins inside a shallow basin ringed by sparse dark woodland.
- **Dragon — Dragon Peaks:** Dragon Shrine among the world's highest multi-peak terrain.
- **Dark — Dark Forest:** Eclipse Obelisk inside a larger dense northern forest.
- **Steel — Steel District:** Iron Forge on a broad raised industrial plateau.

The biome layout is a contiguous nearest-region partition rather than seventeen disconnected islands. Region centers are spaced much farther apart than the earlier prototype, so each biome has a substantial interior rather than reading as a small color patch. Designed route segments connect neighboring regions horizontally, vertically and through the central Normal hub, so there are multiple ways to travel around the map.

The world builder performs a startup connectivity pass. Tiny exposed pockets that cannot reach the central landmass are converted into blocking scenery before collision, navigation and habitat spawn caches are constructed.

## primary-type wild habitats

Wild Pokémon use their **first / slot-one type as it existed in Generation IV** to determine where they appear.

The project contains an offline National Dex 001–493 primary-type lookup. The spawner first selects an installed species, resolves that species' Generation IV primary type, and then asks the world builder for a walkable boundary and interior target in the matching biome. No network request is needed while the game is running.

Examples:

- Bulbasaur is Grass first, so it belongs to Deep Forest even though it is also Poison.
- Charizard is Fire first, so it belongs to Volcanic Basin even though it is also Flying.
- Gyarados is Water first, so it belongs to Lake District even though it is also Flying.
- Garchomp is Dragon first, so it belongs to Dragon Peaks even though it is also Ground.

Roaming targets are also chosen from the Pokémon's assigned biome, so visitors hang around their habitat instead of being given arbitrary world-wide wander destinations. They leave through the nearest cached walkable path cell at that biome's border.

Under the strict first-type rule, the Flying region has no natural wild population in the National Dex through Generation IV because none of those species has Flying in slot one. The region and Skywatch Tower remain fully explorable and available for fast travel; no secondary-type fallback is applied.

The enlarged world currently allows up to 34 temporary wild Pokémon, with spawn attempts roughly every 1.0–2.4 seconds while capacity is available. Species are selected before habitat assignment, so types with fewer species are not artificially weighted to appear as often as types with many species.

## biome landmarks

`WorldLandmarkSystem` composes each major destination from built-in Godot primitives. These are intentionally larger and more recognizable than the repeated background motifs generated by `HgssWorldBuilder`.

Fast-travel arrival positions are separate from the visible landmark geometry. For every biome, the landmark system asks the world builder for a nearby verified walkable position, so map travel lands the player on ordinary navigable terrain rather than inside water or forest blockers.

All seventeen destinations are currently available immediately. Landmark unlocking/discovery can be layered on later without changing the destination interface.

## world map and fast travel

Press **Start / Esc** during gameplay to open the world map.

The map is schematic but is generated from the same biome centers and route graph used by the 3D world. Because it reads `WORLD_WIDTH`, `WORLD_DEPTH`, `BIOME_CENTERS` and `PATH_EDGES` directly, it automatically reflects the expanded region layout.

It displays:

- all seventeen biome landmarks;
- the route connections between biome centers;
- the player's current map position;
- the currently selected landmark.

Map controls:

- directional inputs / left stick: select a nearby landmark in that direction;
- `Button_A` / Space: fast travel to the selected landmark;
- `Button_Start` / Esc: close the map.

Player physics is disabled while the map is open and restored when it closes. Fast travel resets player velocity before resuming gameplay.

## camera

The camera is a collision-aware orbit rig centered above the player rather than a fixed-angle view.

Camera controls:

- hold right mouse and move the mouse: rotate and tilt;
- right stick: rotate and tilt continuously;
- mouse wheel: zoom between close and wide exploration distances.

Horizontal rotation is unrestricted. Vertical tilt is clamped from a near-horizontal view to a near top-down view so the camera cannot flip underneath the world. The existing `SpringArm3D` still shortens the camera distance when scenery blocks the view. Camera far distance is increased for the much larger world.

## world visuals

World art remains **asset-free and procedural**. There are no world tilesheets, route-map textures, imported terrain models, PDSMS assets, or external world-art setup steps.

Visuals are generated at runtime using Godot geometry and materials:

- biome-specific shaded ground colors;
- warm shared route surfaces;
- translucent water with a darker depth layer;
- low-poly trees made from cylinder trunks and layered sphere canopies;
- wooden bridge/causeway deck geometry where routes cross water;
- deterministic type-specific primitives used as environmental motifs;
- large composed landmark structures for each type region;
- broad mountains, secondary peaks, plateau shelves, a volcanic crater, lake/marsh basins, badland ridges and rolling forest terrain blended continuously between regions.

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

`WildPokemonSpawner` discovers installed species, `PokemonGen4TypeLibrary` resolves their Generation IV primary type, and `HgssWorldBuilder` provides matching biome entry, wandering and exit positions. `HgssWorldNavigation` maintains one shared A* grid so all temporary Pokémon still use the same water/tree collision rules.

Current behaviour:

1. choose a random installed species;
2. resolve its Generation IV first type;
3. choose one available form of that species;
4. enter on a walkable route cell at the matching type-biome boundary;
5. move to a walkable interior cell in the same biome;
6. idle and wander between nearby cells selected from that biome;
7. remain for roughly 22–48 seconds;
8. route toward the nearest walkable boundary cell of the same biome;
9. despawn on exit.

The current population cap is 34 temporary Pokémon.

## run

Open `project.godot` with Godot 4.6 and press F5.

Gameplay controls:

- WASD, arrow keys, or left stick: move;
- right mouse drag or right stick: rotate / tilt camera;
- mouse wheel: camera zoom;
- Start / Esc: open the world map;
- the player starts in the expanded central Normal Meadow;
- follow the connected route network outward or use the map to fast travel between landmark destinations.

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
│   ├── bottom_anchored_animated_sprite_3d.gd
│   ├── player_controller.gd
│   ├── pokemon_gen4_type_library.gd
│   ├── pokemon_sprite_library.gd
│   └── wild_pokemon.gd
├── core/
│   └── input_bootstrap.gd
├── ui/
│   ├── world_map_canvas.gd
│   └── world_map_overlay.gd
└── world/
    ├── hgss_world_builder.gd
    ├── hgss_world_navigation.gd
    ├── wild_pokemon_spawner.gd
    └── world_landmark_system.gd
```

`HgssWorldBuilder` owns biome classification, route layout, expanded height fields, terrain surfaces, connectivity cleanup, static collision, water, scenery batching, type-habitat caches, entry points and walkable-position queries. `PokemonGen4TypeLibrary` owns the offline Generation IV primary-type lookup. `WorldLandmarkSystem` owns the seventeen major landmark structures plus safe fast-travel destinations. `WorldMapOverlay` and `WorldMapCanvas` own map presentation and travel controls. `HgssWorldNavigation` owns the shared grid pathfinder. `WildPokemonSpawner` owns population policy.

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
