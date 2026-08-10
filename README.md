# hgss_hd3d_starter

A Godot 4.6 starter scene for an HD-2D / 2.5D Pokémon-style game: real 3D world geometry with camera-facing pixel sprites.

## included

- `CharacterBody3D` player with camera-relative movement.
- HGSS Ditto overworld frames temporarily used as the player visual.
- `AnimatedSprite3D` with fixed-Y billboarding, nearest filtering, alpha cut, and normal depth testing.
- reusable `BillboardCharacterVisual` component shared by the player, follower, and roaming Pokémon.
- collision-aware fixed perspective camera using `SpringArm3D`.
- one simple 3D route with ground, an elevated terrace, visible stairs backed by an invisible walkable ramp, and occluding tree geometry.
- one static NPC placeholder and one following Pokémon placeholder, both currently using Ditto.
- random overworld Pokémon that enter the lower route, pause and wander for a while, then walk back out and despawn.
- runtime Pokémon sprite discovery that automatically sees numbered species folders and their forms.
- project-local input bootstrap using the action names `StickLeft_North`, `StickLeft_South`, `StickLeft_West`, `StickLeft_East`, `Button_A`, and `Button_Start`.
- optional `tools/download_hgss_overworld.sh` for filling `assets/pokemon/hgss_overworld/` with the complete HGSS overworld set.

## installing the complete pokemon sprite folder

The project expects the numbered folders to be directly inside:

```text
res://assets/pokemon/hgss_overworld/
```

The important part is that the resulting structure looks like this:

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

Do not accidentally create an extra nested folder such as:

```text
assets/pokemon/hgss_overworld/hgss_overworld/001/
```

If you use the included downloader from the project root, run:

```bash
./tools/download_hgss_overworld.sh ./assets/pokemon/hgss_overworld
```

Godot must import the PNG files before the runtime loader can use them. If the editor is already open when you copy the full set in, allow the FileSystem dock to finish importing before running the scene.

## roaming pokemon

`wild_pokemon_spawner` in `scenes/world/main.tscn` scans the sprite directory when the scene starts.

The current prototype behaviour is deliberately simple:

1. choose a random Pokédex species uniformly;
2. choose one of that species' available forms;
3. spawn just outside one edge of the lower-route roaming rectangle;
4. walk into the area;
5. idle and wander between nearby points;
6. remain for roughly 10-22 seconds;
7. walk out through the nearest edge;
8. free the temporary character.

Only the `normal` visual variant is used for random wild spawning right now. Female and shiny folders remain available for later encounter rules without changing the asset layout.

The test scene caps the temporary population at seven Pokémon. The roaming rectangle and timing values are ordinary private variables in `scripts/world/wild_pokemon_spawner.gd`, not editor exports.

## run

Open `project.godot` with Godot 4.6 and press F6/F5.

Controls:

- WASD, arrow keys, or left stick: move.
- Walk north through the stone stairs to test elevation and slope handling.
- Walk behind the tree proxies to test normal 3D depth/occlusion against billboard sprites.
- Stay around the lower route to watch temporary wild Pokémon enter and leave.

## architecture

```text
scenes/
├── camera/
│   └── camera_rig.tscn
├── characters/
│   ├── ditto_visual.tscn
│   ├── pokemon_visual.tscn
│   ├── follower.tscn
│   ├── npc.tscn
│   ├── player.tscn
│   └── wild_pokemon.tscn
└── world/
    └── main.tscn

scripts/
├── camera/
│   └── camera_rig.gd
├── characters/
│   ├── billboard_character_visual.gd
│   ├── follower_controller.gd
│   ├── player_controller.gd
│   ├── pokemon_sprite_library.gd
│   └── wild_pokemon.gd
├── core/
│   └── input_bootstrap.gd
└── world/
    └── wild_pokemon_spawner.gd
```

The movement controllers own physics. `BillboardCharacterVisual` owns only camera-relative visual facing and animation selection. `PokemonSpriteLibrary` owns sprite discovery and cached runtime `SpriteFrames` construction. The roaming spawner owns population and spawn-zone policy; each `WildPokemon` owns its own temporary behaviour state.

## replacing the temporary player art

The current player visual scene points at `resources/sprite_frames/ditto_overworld.tres`. Later, replace that `SpriteFrames` resource with a player-specific resource containing the same animation names:

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

Nothing in `player_controller.gd` needs to change.

## sprite source

The included Ditto frames are HGSS overworld sprites obtained from Veekun's sprite archive. The helper downloader uses the same archive and preserves its form/gender/shiny structure in predictable Godot-friendly directories.

Pokémon and related characters/assets are property of their respective rights holders. The source code in this starter is independent project code; the included game sprites are provided only as temporary development assets for this prototype.
