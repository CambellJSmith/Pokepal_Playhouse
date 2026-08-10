class_name HgssWorldBuilder # Coordinates deterministic field generation, terrain rendering, collision, scenery, and habitat queries.
extends Node3D # Owns generated world nodes while delegating continuous mathematical fields to WorldFieldSampler.

enum TerrainKind { LAND, PATH, WATER, STONE } # Defines logical terrain categories shared by rendering, collision, and navigation.
enum BiomeKind { NORMAL, FIRE, WATER, ELECTRIC, GRASS, ICE, FIGHTING, POISON, GROUND, FLYING, PSYCHIC, BUG, ROCK, GHOST, DRAGON, DARK, STEEL } # Defines all seventeen Generation IV type regions.

const WORLD_WIDTH: int = 264 # Keeps the existing broad playable region width in logical terrain cells.
const WORLD_DEPTH: int = 216 # Keeps the existing broad playable region depth in logical terrain cells.
const TILE_SIZE: float = 1.5 # Converts one logical generation cell into world-space distance.
const WATER_LEVEL: float = -0.62 # Defines the shared visible water surface used by lakes, marshes, and streams.
const PATH_WIDTH: float = 2.6 # Defines the generated route core radius in logical cell-space units.
const PATH_SHOULDER: float = 6.0 # Defines the vegetation-clearance and terrain-blending radius around generated routes.
const ROUTE_SAMPLE_SPACING: float = 0.72 # Controls how densely smooth mathematical route curves are rasterized into the logical grid.
const MAX_WALKABLE_SLOPE: float = 1.12 # Prevents navigation and habitat selection from treating severe non-route slopes as ordinary walkable ground.
const TREE_COLLISION_RADIUS: float = 0.34 # Matches generated tree collision closely to trunks instead of blocking an entire visual cell.
const TREE_COLLISION_HEIGHT: float = 2.35 # Gives generated tree trunks enough vertical collision to stop character capsules.

const PATH_COLOR: Color = Color(0.49, 0.39, 0.24, 1.0) # Uses a grounded dirt tone rather than a bright prototype route color.
const WATER_COLOR: Color = Color(0.12, 0.39, 0.58, 0.76) # Uses a deeper translucent water tone for stronger world depth.
const WATER_DEPTH_COLOR: Color = Color(0.035, 0.13, 0.19, 1.0) # Gives generated water visible depth beneath the transparent surface.
const STONE_COLOR: Color = Color(0.37, 0.38, 0.36, 1.0) # Provides a neutral exposed-rock blend shared by steep terrain.
const TREE_TRUNK_COLOR: Color = Color(0.23, 0.13, 0.065, 1.0) # Gives generated low-poly trunks a darker natural base.
const GRASS_CANOPY_COLOR: Color = Color(0.13, 0.34, 0.13, 1.0) # Defines ordinary and Grass-biome canopy color.
const BUG_CANOPY_COLOR: Color = Color(0.31, 0.43, 0.10, 1.0) # Defines the lighter yellow-green Bug woodland canopy.
const DARK_CANOPY_COLOR: Color = Color(0.09, 0.11, 0.12, 1.0) # Defines dense Dark and Ghost woodland canopy color.
const WET_CANOPY_COLOR: Color = Color(0.12, 0.29, 0.24, 1.0) # Defines muted shoreline and marsh tree color.
const BRIDGE_COLOR: Color = Color(0.34, 0.20, 0.09, 1.0) # Defines generated wooden bridge deck color.
const GRASS_DETAIL_COLOR: Color = Color(0.21, 0.43, 0.16, 1.0) # Defines inexpensive generated ground-cover clumps.
const SHRUB_COLOR: Color = Color(0.14, 0.31, 0.12, 1.0) # Defines generated low shrub clusters.
const ROCK_DETAIL_COLOR: Color = Color(0.33, 0.33, 0.31, 1.0) # Defines generated boulder and outcrop objects.

const BIOME_CENTERS: Array[Vector2] = [ # Keeps stable region anchors while WorldFieldSampler mathematically warps their actual boundaries.
    Vector2(0.0, 20.0), # Anchors Normal around the central meadow hub.
    Vector2(100.0, -26.0), # Anchors Fire around the volcanic basin.
    Vector2(94.0, 72.0), # Anchors Water around the lake district.
    Vector2(34.0, 72.0), # Anchors Electric around the open plains.
    Vector2(-52.0, 20.0), # Anchors Grass around the deep forest.
    Vector2(-31.0, -76.0), # Anchors Ice around the southern snow shelf.
    Vector2(-50.0, -26.0), # Anchors Fighting around the raised training plateau.
    Vector2(-90.0, 72.0), # Anchors Poison around the marsh lowlands.
    Vector2(-100.0, -26.0), # Anchors Ground around the western badlands.
    Vector2(31.0, -76.0), # Anchors Flying around the southern wind plateau.
    Vector2(54.0, 20.0), # Anchors Psychic around the eastern garden.
    Vector2(-102.0, 20.0), # Anchors Bug around the western woods.
    Vector2(-92.0, -76.0), # Anchors Rock around the southern mountain range.
    Vector2(104.0, 20.0), # Anchors Ghost around the eastern hollow.
    Vector2(92.0, -76.0), # Anchors Dragon around the high southern peaks.
    Vector2(-30.0, 72.0), # Anchors Dark around the northern forest.
    Vector2(50.0, -26.0), # Anchors Steel around the industrial plateau.
] # Ends the stable anchor table used by world generation and the schematic world map.

const PATH_EDGES: Array[Vector2i] = [ # Preserves region topology while physical routes are now curved mathematical paths rather than straight corridors.
    Vector2i(BiomeKind.ROCK, BiomeKind.ICE), Vector2i(BiomeKind.ICE, BiomeKind.FLYING), Vector2i(BiomeKind.FLYING, BiomeKind.DRAGON), # Connects the southern mountain chain.
    Vector2i(BiomeKind.GROUND, BiomeKind.FIGHTING), Vector2i(BiomeKind.FIGHTING, BiomeKind.STEEL), Vector2i(BiomeKind.STEEL, BiomeKind.FIRE), # Connects the lower middle route band.
    Vector2i(BiomeKind.BUG, BiomeKind.GRASS), Vector2i(BiomeKind.GRASS, BiomeKind.NORMAL), Vector2i(BiomeKind.NORMAL, BiomeKind.PSYCHIC), Vector2i(BiomeKind.PSYCHIC, BiomeKind.GHOST), # Connects the central route band.
    Vector2i(BiomeKind.POISON, BiomeKind.DARK), Vector2i(BiomeKind.DARK, BiomeKind.ELECTRIC), Vector2i(BiomeKind.ELECTRIC, BiomeKind.WATER), # Connects the northern route band.
    Vector2i(BiomeKind.ROCK, BiomeKind.GROUND), Vector2i(BiomeKind.GROUND, BiomeKind.BUG), Vector2i(BiomeKind.BUG, BiomeKind.POISON), # Connects the western vertical route band.
    Vector2i(BiomeKind.ICE, BiomeKind.FIGHTING), Vector2i(BiomeKind.FIGHTING, BiomeKind.GRASS), Vector2i(BiomeKind.GRASS, BiomeKind.DARK), # Connects the west-central vertical route band.
    Vector2i(BiomeKind.FLYING, BiomeKind.STEEL), Vector2i(BiomeKind.STEEL, BiomeKind.PSYCHIC), Vector2i(BiomeKind.PSYCHIC, BiomeKind.ELECTRIC), # Connects the east-central vertical route band.
    Vector2i(BiomeKind.DRAGON, BiomeKind.FIRE), Vector2i(BiomeKind.FIRE, BiomeKind.GHOST), Vector2i(BiomeKind.GHOST, BiomeKind.WATER), # Connects the eastern vertical route band.
    Vector2i(BiomeKind.NORMAL, BiomeKind.FIGHTING), Vector2i(BiomeKind.NORMAL, BiomeKind.STEEL), Vector2i(BiomeKind.NORMAL, BiomeKind.DARK), Vector2i(BiomeKind.NORMAL, BiomeKind.ELECTRIC), # Gives the central meadow redundant radial connectivity.
] # Ends the stable region graph used by generation and map presentation.

const WORLD_EXIT_POINTS: Array[Vector2] = [Vector2(-92.0, -107.0), Vector2(34.0, 107.0), Vector2(-131.0, 20.0), Vector2(131.0, 20.0)] # Defines four mathematical route endpoints at the world boundary.
const WORLD_EXIT_BIOMES: Array[int] = [BiomeKind.ROCK, BiomeKind.ELECTRIC, BiomeKind.BUG, BiomeKind.GHOST] # Associates each world-edge endpoint with the nearest region anchor.

var world_seed: int = 493017 # Defines the deterministic world seed without exposing editor-only configuration.
var field_sampler: WorldFieldSampler # Owns all continuous FastNoiseLite fields used by terrain, biome, route, and object generation.
var height_vertices: PackedFloat32Array = PackedFloat32Array() # Stores one generated height value for every terrain-grid vertex.
var route_distance_cache: Dictionary = {} # Stores approximate distance to the nearest curved route for cells inside the route influence band.
var terrain_cache: Dictionary = {} # Stores logical terrain classification for each map cell.
var biome_cache: Dictionary = {} # Stores warped biome ownership for each map cell.
var slope_cache: Dictionary = {} # Stores local generated slope used by navigation and object-placement rules.
var underlying_water_cache: Dictionary = {} # Marks water-field cells even where a generated route overrides them with a bridge.
var blocked_cells: Dictionary = {} # Stores tree-occupied logical cells used by navigation and habitat queries.
var unreachable_cells: Dictionary = {} # Stores disconnected walkable cells without inventing visible blocker geometry around them.
var biome_spawn_cells: Dictionary = {} # Stores non-route reachable habitat cells grouped by Generation IV primary type.
var biome_entry_cells: Dictionary = {} # Stores curved route cells where each warped biome meets a neighboring region.
var entry_spawn_positions: Array[Vector3] = [] # Stores the four world-edge spawn positions used by the legacy global entry API.
var entry_target_positions: Array[Vector3] = [] # Stores the matching first in-world targets for the legacy global entry API.
var tree_cells: Array[Vector2i] = [] # Stores generated tree locations separately from logical unreachable cells.
var grass_cells: Array[Vector2i] = [] # Stores generated ground-cover object locations.
var shrub_cells: Array[Vector2i] = [] # Stores generated shrub object locations.
var rock_cells: Array[Vector2i] = [] # Stores generated rock and boulder object locations.
var bridge_cells: Array[Vector2i] = [] # Stores generated route cells crossing mathematically generated water.
var accent_cells_by_biome: Dictionary = {} # Stores sparse type-specific object accents grouped by biome.

func _ready() -> void: # Generates one complete deterministic world before dependent systems query its caches.
    add_to_group(&"world_builder") # Exposes this world service through the existing semantic group API.
    field_sampler = WorldFieldSampler.new(world_seed, BIOME_CENTERS) # Creates independent continuous fields from the configured world seed.
    _build_route_field() # Generates smooth curved route polylines and rasterizes their influence into the logical grid.
    _prepare_height_cache() # Generates one continuous heightmap from layered domain-warped terrain fields.
    _grade_route_heights() # Smooths terrain around route corridors so generated travel remains physically practical.
    _prepare_layout_cache() # Classifies warped biomes, terrain, water, slope, and tree blockers from the generated fields.
    _prune_isolated_walkable_regions() # Removes disconnected pockets from navigation and spawn eligibility without adding fake scenery walls.
    _rebuild_biome_spawn_cache() # Builds primary-type habitat and biome-boundary entry caches from the final logical world.
    _prepare_environment_scatter() # Converts density fields into deterministic object locations after walkability is known.
    _build_terrain_geometry() # Builds vertex-colored terrain, water, depth geometry, and one combined collision mesh.
    _build_environment_visuals() # Builds batched trees, ground cover, rocks, bridges, and type-specific accent objects.
    _prepare_entry_points() # Restores the existing four global world-edge entry/exit positions.

func get_random_biome_entry_pair(biome_kind: int, random: RandomNumberGenerator) -> Array[Vector3]: # Starts a roaming Pokémon on a route crossing the boundary of its assigned type habitat.
    var entries: Array = biome_entry_cells.get(biome_kind, []) # Reads cached curved-route boundary cells for this biome.
    if entries.is_empty(): # Handles rare regions where warping produced no cached route boundary cell.
        var fallback: Vector3 = get_random_walkable_world_position_in_biome(biome_kind, random) # Picks a reachable interior fallback.
        var inward_fallback: Vector3 = get_random_walkable_world_position_near_in_biome(fallback, 18.0, biome_kind, random) # Picks a second local point so entry movement still has direction.
        return [fallback, inward_fallback] # Preserves the existing two-position API contract.
    var entry_cell: Vector2i = entries[random.randi_range(0, entries.size() - 1)] # Selects one valid boundary route cell uniformly.
    var entry_position: Vector3 = cell_to_world(entry_cell) # Converts the logical route cell into generated terrain world space.
    var target_position: Vector3 = get_random_walkable_world_position_near_in_biome(entry_position, 20.0, biome_kind, random) # Picks a reachable inward target from the same warped biome.
    return [entry_position, target_position] # Returns the entry and initial habitat target expected by WildPokemonSpawner.

func get_biome_exit_target_from(world_position: Vector3, biome_kind: int) -> Vector3: # Returns the nearest cached route boundary belonging to one Pokémon habitat.
    var entries: Array = biome_entry_cells.get(biome_kind, []) # Reads cached boundary route cells for the requested biome.
    if entries.is_empty(): # Handles a malformed or unusually warped region with no route boundary cache.
        var center_hint: Vector2 = BIOME_CENTERS[biome_kind] # Uses the stable biome anchor as a deterministic fallback hint.
        return get_nearest_walkable_world_position(Vector3(center_hint.x * TILE_SIZE, world_position.y, center_hint.y * TILE_SIZE)) # Snaps the anchor to reachable generated terrain.
    var best_cell: Vector2i = entries[0] # Seeds nearest-boundary comparison from the first valid entry cell.
    var best_position: Vector3 = cell_to_world(best_cell) # Converts that first candidate into world space.
    var best_distance: float = world_position.distance_squared_to(best_position) # Stores squared distance to avoid square roots in the search loop.
    for value: Variant in entries: # Tests every cached boundary route cell for the nearest exit.
        var cell: Vector2i = value # Converts the untyped dictionary array value into a logical cell coordinate.
        var candidate: Vector3 = cell_to_world(cell) # Converts the candidate to generated terrain world space.
        var distance: float = world_position.distance_squared_to(candidate) # Measures inexpensive squared distance from the Pokémon.
        if distance < best_distance: # Detects a closer habitat boundary.
            best_distance = distance # Stores the improved nearest distance.
            best_position = candidate # Stores the matching world-space exit target.
    return best_position # Returns the nearest reachable curved-route boundary point.

func get_random_walkable_world_position_in_biome(biome_kind: int, random: RandomNumberGenerator) -> Vector3: # Picks one cached reachable non-route habitat cell in a specific warped biome.
    var cells: Array = biome_spawn_cells.get(biome_kind, []) # Reads the precomputed habitat pool without scanning the world at spawn time.
    if cells.is_empty(): # Handles an empty habitat cache defensively.
        var center_hint: Vector2 = BIOME_CENTERS[biome_kind] # Uses the stable region anchor as a fallback search hint.
        return get_nearest_walkable_world_position(Vector3(center_hint.x * TILE_SIZE, 0.0, center_hint.y * TILE_SIZE)) # Snaps the hint to the generated walkable world.
    var selected_cell: Vector2i = cells[random.randi_range(0, cells.size() - 1)] # Selects a habitat cell uniformly from the cached pool.
    return cell_to_world(selected_cell) # Returns the generated terrain position at that cell.

func get_random_walkable_world_position_near_in_biome(world_position: Vector3, radius: float, biome_kind: int, random: RandomNumberGenerator) -> Vector3: # Picks a local reachable wander target that remains inside one warped habitat.
    var centre_cell: Vector2i = world_to_cell(world_position) # Converts the current world position into logical generation coordinates.
    var radius_cells: int = maxi(1, int(ceil(radius / TILE_SIZE))) # Converts requested world-space radius into a logical search radius.
    for attempt: int in range(64): # Uses bounded random sampling to avoid unbounded searches in dense terrain.
        var candidate: Vector2i = centre_cell + Vector2i(random.randi_range(-radius_cells, radius_cells), random.randi_range(-radius_cells, radius_cells)) # Samples one nearby logical cell.
        if is_cell_walkable(candidate) and int(_biome_for_cell(candidate)) == biome_kind: # Requires final walkability and the assigned warped biome.
            return cell_to_world(candidate) # Returns the first suitable generated terrain position.
    if is_cell_walkable(centre_cell) and int(_biome_for_cell(centre_cell)) == biome_kind: # Reuses the current cell if random sampling found no better destination.
        return cell_to_world(centre_cell) # Keeps the Pokémon in place rather than sending it outside its habitat.
    return get_random_walkable_world_position_in_biome(biome_kind, random) # Falls back to the biome-wide cached habitat pool.

func get_random_entry_pair(random: RandomNumberGenerator) -> Array[Vector3]: # Preserves the original global world-edge entry API for systems that ignore biome identity.
    if entry_spawn_positions.is_empty(): # Rebuilds the small cache defensively if queried unusually early.
        _prepare_entry_points() # Restores deterministic edge entry positions.
    var index: int = random.randi_range(0, entry_spawn_positions.size() - 1) # Selects one of the four world-edge entrances.
    return [entry_spawn_positions[index], entry_target_positions[index]] # Returns the outside spawn point and first in-world target.

func get_exit_target_from(world_position: Vector3) -> Vector3: # Preserves the original nearest global world-edge exit API.
    if entry_spawn_positions.is_empty(): # Rebuilds the small cache defensively if required.
        _prepare_entry_points() # Restores deterministic edge entry positions.
    var best: Vector3 = entry_spawn_positions[0] # Seeds nearest-exit comparison from the first edge location.
    var best_distance: float = world_position.distance_squared_to(best) # Stores squared distance for inexpensive comparisons.
    for candidate: Vector3 in entry_spawn_positions: # Tests every generated world-edge exit.
        var distance: float = world_position.distance_squared_to(candidate) # Measures squared distance from the supplied world position.
        if distance < best_distance: # Detects a closer exit.
            best_distance = distance # Stores the improved nearest distance.
            best = candidate # Stores the matching edge position.
    return best # Returns the nearest world-edge exit point.

func get_random_walkable_world_position_near(world_position: Vector3, radius: float, random: RandomNumberGenerator) -> Vector3: # Picks a nearby reachable position without imposing biome identity.
    var centre_cell: Vector2i = world_to_cell(world_position) # Converts the supplied world position into logical generation coordinates.
    var radius_cells: int = maxi(1, int(ceil(radius / TILE_SIZE))) # Converts world radius into cell radius.
    for attempt: int in range(48): # Uses a bounded number of random attempts for predictable runtime.
        var candidate: Vector2i = centre_cell + Vector2i(random.randi_range(-radius_cells, radius_cells), random.randi_range(-radius_cells, radius_cells)) # Samples one nearby logical cell.
        if is_cell_walkable(candidate): # Accepts only final reachable generated terrain.
            return cell_to_world(candidate) # Returns the matching world-space position immediately.
    if is_cell_walkable(centre_cell): # Reuses the current cell when nearby random sampling fails.
        return cell_to_world(centre_cell) # Returns the generated height at the current logical location.
    return get_nearest_walkable_world_position(world_position) # Falls back to deterministic outward search from the supplied position.

func get_nearest_walkable_world_position(world_position: Vector3) -> Vector3: # Finds the nearest logical cell accepted by final terrain, slope, connectivity, and blocker rules.
    var centre_cell: Vector2i = world_to_cell(world_position) # Converts the supplied position into logical grid coordinates.
    for radius_cells: int in range(0, 48): # Expands a bounded square search around the starting cell.
        for offset_x: int in range(-radius_cells, radius_cells + 1): # Traverses candidate columns within the current search radius.
            for offset_z: int in range(-radius_cells, radius_cells + 1): # Traverses candidate rows within the current search radius.
                var candidate: Vector2i = centre_cell + Vector2i(offset_x, offset_z) # Builds one logical candidate cell.
                if is_cell_walkable(candidate): # Accepts only reachable final terrain.
                    return cell_to_world(candidate) # Returns the first valid generated terrain position found.
    return Vector3.ZERO # Returns a safe deterministic fallback if no walkable cell exists inside the bounded search.

func is_cell_walkable(cell: Vector2i) -> bool: # Reports whether final generated terrain accepts ordinary character navigation.
    if not _is_cell_in_bounds(cell): # Rejects cells outside the generated world rectangle.
        return false # Prevents navigation and spawning beyond world bounds.
    if blocked_cells.has(cell) or unreachable_cells.has(cell): # Rejects tree-occupied cells and disconnected pockets.
        return false # Keeps navigation and habitats consistent with generated obstacles and connectivity.
    var terrain: TerrainKind = _terrain_for_cell(cell) # Reads the cached logical terrain category.
    if terrain == TerrainKind.WATER: # Rejects water surfaces from ordinary walking.
        return false # Leaves only generated bridge PATH cells traversable across water.
    if terrain != TerrainKind.PATH and float(slope_cache.get(cell, 0.0)) > MAX_WALKABLE_SLOPE: # Rejects severe natural slopes while always allowing deliberately graded routes.
        return false # Keeps A* and habitat queries aligned with practical CharacterBody3D traversal.
    return true # Accepts reachable non-water terrain that passed generated slope and blocker rules.

func cell_to_world(cell: Vector2i) -> Vector3: # Converts one logical cell center into generated 3D terrain coordinates.
    var local_x: float = float(cell.x) - float(WORLD_WIDTH) * 0.5 + 0.5 # Converts the cell center into centered local generation coordinates.
    var local_z: float = float(cell.y) - float(WORLD_DEPTH) * 0.5 + 0.5 # Converts the cell center into centered local generation coordinates.
    var local_y: float = _sample_height(local_x, local_z) # Bilinearly samples the cached generated heightmap at the cell center.
    if _terrain_for_cell(cell) == TerrainKind.PATH and underlying_water_cache.has(cell): # Detects generated bridge cells where the route crosses water.
        local_y = maxf(local_y, WATER_LEVEL + 0.22) # Keeps characters and bridge geometry safely above the visible water surface.
    return Vector3(local_x * TILE_SIZE, local_y + 0.06, local_z * TILE_SIZE) # Returns scaled world coordinates with a small floor-contact lift.

func world_to_cell(world_position: Vector3) -> Vector2i: # Converts world-space X/Z coordinates into logical generation cells.
    var cell_x: int = int(floor(world_position.x / TILE_SIZE + float(WORLD_WIDTH) * 0.5)) # Converts world X into the centered logical column index.
    var cell_z: int = int(floor(world_position.z / TILE_SIZE + float(WORLD_DEPTH) * 0.5)) # Converts world Z into the centered logical row index.
    return Vector2i(cell_x, cell_z) # Returns the logical terrain cell coordinate.

func _build_route_field() -> void: # Generates curved deterministic routes from the stable region graph and rasterizes their influence band.
    route_distance_cache.clear() # Removes stale route influence before generating the active seed.
    var edge_index: int = 0 # Gives every route a stable independent curvature identity.
    for edge: Vector2i in PATH_EDGES: # Generates every region-to-region connection in the topology graph.
        var start: Vector2 = BIOME_CENTERS[edge.x] # Reads the first region anchor for this graph edge.
        var finish: Vector2 = BIOME_CENTERS[edge.y] # Reads the second region anchor for this graph edge.
        _rasterize_route(_create_route_polyline(start, finish, edge_index)) # Converts one smooth mathematical curve into a distance field around its sampled points.
        edge_index += 1 # Advances the deterministic route identity for the next edge.
    for exit_index: int in range(WORLD_EXIT_POINTS.size()): # Generates the four route extensions from outer biomes to world-edge entrances.
        var biome_kind: int = WORLD_EXIT_BIOMES[exit_index] # Reads the region anchor connected to this world exit.
        var start: Vector2 = BIOME_CENTERS[biome_kind] # Starts the extension at its owning biome anchor.
        var finish: Vector2 = WORLD_EXIT_POINTS[exit_index] # Ends the extension at the configured world boundary point.
        _rasterize_route(_create_route_polyline(start, finish, edge_index)) # Rasterizes the curved world-edge route into the same influence field.
        edge_index += 1 # Advances the route identity for any later extension.

func _create_route_polyline(start: Vector2, finish: Vector2, edge_index: int) -> PackedVector2Array: # Samples one smooth seed-driven route curve between two fixed endpoints.
    var points: PackedVector2Array = PackedVector2Array() # Stores sampled local cell-space positions along the generated curve.
    var direction: Vector2 = finish - start # Measures the straight baseline connecting the route endpoints.
    var edge_length: float = direction.length() # Stores route length for sample density and curvature amplitude.
    if edge_length <= 0.001: # Guards accidental zero-length topology edges.
        points.append(start) # Returns the single valid endpoint as a degenerate route.
        return points # Stops before normalizing a zero-length direction.
    var normal: Vector2 = Vector2(-direction.y, direction.x).normalized() # Builds a stable lateral axis used to bend the route without moving endpoints.
    var segment_count: int = maxi(8, int(ceil(edge_length / 2.25))) # Samples long routes densely enough for smooth rasterization without excessive startup work.
    for sample_index: int in range(segment_count + 1): # Samples the complete curve including both exact endpoints.
        var progress: float = float(sample_index) / float(segment_count) # Converts sample index into normalized route progress.
        var baseline: Vector2 = start.lerp(finish, progress) # Finds the straight baseline point at this progress.
        var lateral_offset: float = field_sampler.sample_route_offset(edge_index, progress, edge_length) # Reads smooth deterministic curvature from an independent route field.
        points.append(baseline + normal * lateral_offset) # Stores the curved route sample in local generation coordinates.
    return points # Returns a dense smooth polyline ready for distance-field rasterization.

func _rasterize_route(points: PackedVector2Array) -> void: # Paints approximate distance to one smooth route into nearby logical cells.
    if points.size() < 2: # Rejects degenerate route curves that cannot define a corridor.
        return # Leaves the existing route field unchanged.
    var influence_radius: float = PATH_SHOULDER + 2.5 # Extends beyond the visible path for vegetation clearance and shoulder blending.
    var influence_cells: int = int(ceil(influence_radius)) # Converts the local-space influence radius into integer paint bounds.
    for segment_index: int in range(points.size() - 1): # Rasterizes each smooth polyline segment independently.
        var start: Vector2 = points[segment_index] # Reads the current sampled curve point.
        var finish: Vector2 = points[segment_index + 1] # Reads the next sampled curve point.
        var segment_length: float = start.distance_to(finish) # Measures segment length for stable sub-sampling density.
        var sample_count: int = maxi(1, int(ceil(segment_length / ROUTE_SAMPLE_SPACING))) # Prevents gaps between painted influence disks.
        for sample_index: int in range(sample_count + 1): # Paints the full segment including its endpoints.
            var progress: float = float(sample_index) / float(sample_count) # Converts sub-sample index into normalized segment progress.
            var point: Vector2 = start.lerp(finish, progress) # Finds one continuous position on the curved route.
            var center_cell: Vector2i = _local_to_cell(point) # Converts that route position into the nearest logical cell.
            for offset_z: int in range(-influence_cells, influence_cells + 1): # Traverses nearby rows inside the route influence square.
                for offset_x: int in range(-influence_cells, influence_cells + 1): # Traverses nearby columns inside the route influence square.
                    var cell: Vector2i = center_cell + Vector2i(offset_x, offset_z) # Builds one candidate influence cell.
                    if not _is_cell_in_bounds(cell): # Skips route influence outside generated world bounds.
                        continue # Avoids useless dictionary entries for off-map coordinates.
                    var cell_local: Vector2 = _cell_to_local_2d(cell) # Reads the local center of the candidate logical cell.
                    var distance: float = cell_local.distance_to(point) # Measures approximate distance to this dense route sample.
                    if distance > influence_radius: # Rejects cells outside the desired route shoulder field.
                        continue # Keeps the sparse route-distance cache compact.
                    var previous_distance: float = float(route_distance_cache.get(cell, INF)) # Reads any closer route influence painted by an earlier sample or edge.
                    if distance < previous_distance: # Detects an improved nearest-route estimate.
                        route_distance_cache[cell] = distance # Stores the smallest sampled distance for later path, color, and vegetation rules.

func _prepare_height_cache() -> void: # Generates one deterministic continuous height value for every terrain-grid vertex.
    var vertex_width: int = WORLD_WIDTH + 1 # Includes both outer X edges of the cell grid.
    var vertex_depth: int = WORLD_DEPTH + 1 # Includes both outer Z edges of the cell grid.
    height_vertices.resize(vertex_width * vertex_depth) # Allocates the complete packed heightmap once for cache-friendly access.
    for vertex_z: int in range(vertex_depth): # Generates every heightmap row.
        for vertex_x: int in range(vertex_width): # Generates every heightmap column.
            var local: Vector2 = Vector2(float(vertex_x) - float(WORLD_WIDTH) * 0.5, float(vertex_z) - float(WORLD_DEPTH) * 0.5) # Converts the vertex into centered field coordinates.
            height_vertices[_height_index(vertex_x, vertex_z)] = field_sampler.sample_height(local) # Samples layered domain-warped terrain once and caches the result.

func _grade_route_heights() -> void: # Smooths generated terrain beneath and around routes while preserving the large-scale heightmap.
    for pass_index: int in range(3): # Repeats a local low-pass operation enough to remove harsh route-scale steps through noisy terrain.
        var source: PackedFloat32Array = height_vertices.duplicate() # Freezes the previous pass so smoothing remains spatially unbiased.
        for vertex_z: int in range(WORLD_DEPTH + 1): # Traverses every heightmap vertex row.
            for vertex_x: int in range(WORLD_WIDTH + 1): # Traverses every heightmap vertex column.
                var route_distance: float = _route_distance_for_vertex(vertex_x, vertex_z) # Measures approximate proximity to the generated curved route field.
                if route_distance >= PATH_SHOULDER: # Leaves terrain outside the route shoulder completely untouched.
                    continue # Avoids needless averaging work on most world vertices.
                var average_height: float = _average_source_height(source, vertex_x, vertex_z, 2) # Computes a broader local terrain target that removes sharp route-scale variation.
                var core_weight: float = clampf(1.0 - route_distance / PATH_SHOULDER, 0.0, 1.0) # Increases smoothing toward the route centerline.
                var blend_weight: float = core_weight * core_weight * 0.72 # Shapes a strong core grade with a softer natural shoulder transition.
                var index: int = _height_index(vertex_x, vertex_z) # Resolves the packed heightmap index once for this vertex.
                height_vertices[index] = lerpf(source[index], average_height, blend_weight) # Blends toward local grade while retaining broader elevation changes along the route.

func _average_source_height(source: PackedFloat32Array, vertex_x: int, vertex_z: int, radius: int) -> float: # Computes a bounded square average from a frozen heightmap pass.
    var total: float = 0.0 # Accumulates neighboring height values.
    var count: int = 0 # Counts valid neighboring vertices included in the average.
    for offset_z: int in range(-radius, radius + 1): # Traverses rows inside the requested smoothing window.
        var sample_z: int = clampi(vertex_z + offset_z, 0, WORLD_DEPTH) # Clamps samples to the generated heightmap boundary.
        for offset_x: int in range(-radius, radius + 1): # Traverses columns inside the smoothing window.
            var sample_x: int = clampi(vertex_x + offset_x, 0, WORLD_WIDTH) # Clamps samples to the generated heightmap boundary.
            total += source[_height_index(sample_x, sample_z)] # Adds the frozen neighboring height to the running average.
            count += 1 # Records one included sample.
    return total / float(maxi(count, 1)) # Returns the stable local average without risking division by zero.

func _prepare_layout_cache() -> void: # Converts continuous fields and the route raster into final logical terrain, biome, slope, water, and tree caches.
    terrain_cache.clear() # Removes stale terrain classifications from any previous generation.
    biome_cache.clear() # Removes stale biome classifications from any previous generation.
    slope_cache.clear() # Removes stale slope data from any previous generation.
    underlying_water_cache.clear() # Removes stale underlying water markers from any previous generation.
    blocked_cells.clear() # Removes stale generated tree blockers from any previous generation.
    unreachable_cells.clear() # Removes stale connectivity results before the later flood fill.
    tree_cells.clear() # Removes stale tree visual locations before calculating the active seed.
    for cell_z: int in range(WORLD_DEPTH): # Classifies every logical world row once.
        for cell_x: int in range(WORLD_WIDTH): # Classifies every logical world column once.
            var cell: Vector2i = Vector2i(cell_x, cell_z) # Builds the stable logical cell identifier.
            var local: Vector2 = _cell_to_local_2d(cell) # Converts the cell center into field-sampling coordinates.
            var biome_kind: int = field_sampler.sample_biome(local) # Resolves warped biome ownership from continuous field competition.
            var terrain_height: float = _sample_height(local.x, local.y) # Samples the already-cached graded heightmap at the cell center.
            var slope: float = _calculate_cell_slope(cell) # Measures local geometric steepness from cached cell corners.
            var water_feature: bool = field_sampler.is_water(local, biome_kind, terrain_height, WATER_LEVEL) # Resolves terrain-driven lakes, marsh pools, and carved stream channels.
            var route_distance: float = _route_distance_for_cell(cell) # Reads approximate distance to the nearest curved generated route.
            var terrain: TerrainKind = _calculate_terrain_kind(biome_kind, slope, water_feature, route_distance) # Resolves final logical terrain with routes overriding water as bridges.
            biome_cache[cell] = biome_kind # Caches warped region ownership for habitats, materials, and map-related queries.
            slope_cache[cell] = slope # Caches slope so navigation and object placement never need to resample geometry.
            terrain_cache[cell] = terrain # Caches final logical terrain category for rendering and gameplay.
            if water_feature: # Remembers water under routes as well as ordinary visible water cells.
                underlying_water_cache[cell] = true # Lets bridge generation detect route-water crossings after route override.
            if _calculate_tree_for_cell(cell, local, biome_kind, terrain, slope, route_distance): # Applies clustered vegetation, slope, route-clearance, and deterministic sampling rules.
                blocked_cells[cell] = true # Removes this tree-occupied logical cell from navigation and habitat selection.
                tree_cells.append(cell) # Stores the same location for batched trunk and canopy rendering.

func _calculate_terrain_kind(biome_kind: int, slope: float, water_feature: bool, route_distance: float) -> TerrainKind: # Resolves one logical terrain category from continuous generated fields.
    if route_distance <= PATH_WIDTH: # Gives generated routes highest priority so they can cross water and harsh natural terrain.
        return TerrainKind.PATH # Marks the route core as deliberately traversable path terrain.
    if water_feature: # Detects generated low terrain selected by the coherent water field.
        return TerrainKind.WATER # Marks the cell as non-walkable visible water.
    if slope > 0.62 or biome_kind in [BiomeKind.ROCK, BiomeKind.DRAGON, BiomeKind.GROUND, BiomeKind.ICE, BiomeKind.FLYING, BiomeKind.STEEL]: # Detects exposed or geologically hard terrain.
        return TerrainKind.STONE # Uses stone presentation while later slope rules independently decide walkability.
    return TerrainKind.LAND # Uses soft-ground presentation for remaining natural terrain.

func _calculate_tree_for_cell(cell: Vector2i, local: Vector2, biome_kind: int, terrain: TerrainKind, slope: float, route_distance: float) -> bool: # Chooses tree blockers from continuous clustered density rather than independent uniform cell randomness.
    if terrain == TerrainKind.WATER or terrain == TerrainKind.PATH or terrain == TerrainKind.STONE: # Keeps trees off water, routes, and exposed hard terrain.
        return false # Rejects unsuitable terrain immediately.
    if route_distance < PATH_SHOULDER: # Preserves readable route shoulders and intentional sightlines through dense forests.
        return false # Rejects tree placement inside the generated route-clearance band.
    if slope > 0.58: # Prevents trees from appearing awkwardly on severe local slopes.
        return false # Leaves steep terrain to rock objects and exposed ground instead.
    var density: float = field_sampler.sample_tree_density(local, biome_kind) # Reads broad clustered forest mass, local breakup, and moisture influence.
    var placement_probability: float = density * 0.24 # Converts continuous density into sparse logical tree blockers suitable for character navigation.
    return _hash01(cell, 17) < placement_probability # Uses a deterministic hash only as the final sample against the continuous density field.

func _prune_isolated_walkable_regions() -> void: # Marks disconnected terrain as unavailable to gameplay without generating visible fake blocker geometry.
    unreachable_cells.clear() # Starts connectivity analysis from an empty rejection cache.
    var start: Vector2i = _local_to_cell(BIOME_CENTERS[BiomeKind.NORMAL]) # Uses the central Normal anchor as the main connected landmass seed.
    if not _is_basic_walkable(start): # Guards an unexpectedly blocked central anchor before flood filling.
        start = world_to_cell(_find_nearest_basic_walkable_world_position(Vector3.ZERO)) # Attempts to recover a nearby generated walkable cell around world center.
    if not _is_basic_walkable(start): # Stops if generation somehow produced no usable central terrain.
        return # Leaves connectivity cache empty rather than failing startup.
    var reachable: Dictionary = {start: true} # Stores flood-filled logical cells reachable from the central landmass.
    var queue: Array[Vector2i] = [start] # Uses an indexed array as an allocation-light breadth-first traversal queue.
    var queue_index: int = 0 # Tracks the next queue element without repeatedly removing from the front.
    while queue_index < queue.size(): # Continues until every reachable logical cell has been expanded.
        var cell: Vector2i = queue[queue_index] # Reads the next reachable cell.
        queue_index += 1 # Advances the queue cursor before examining neighbors.
        for neighbour: Vector2i in [cell + Vector2i.RIGHT, cell + Vector2i.LEFT, cell + Vector2i.UP, cell + Vector2i.DOWN]: # Tests four-way connectivity matching shared AStarGrid2D navigation.
            if reachable.has(neighbour) or not _is_basic_walkable(neighbour): # Skips already visited and inherently unusable neighbors.
                continue # Avoids duplicate queue work and crossing generated blockers.
            reachable[neighbour] = true # Marks the neighbor as connected to the central world.
            queue.append(neighbour) # Schedules the connected neighbor for later expansion.
    for cell_z: int in range(WORLD_DEPTH): # Scans every logical row to identify disconnected usable-looking terrain.
        for cell_x: int in range(WORLD_WIDTH): # Scans every logical column once after the flood fill.
            var cell: Vector2i = Vector2i(cell_x, cell_z) # Builds one logical cell identifier.
            if _is_basic_walkable(cell) and not reachable.has(cell): # Detects terrain that looks walkable locally but is disconnected from the playable landmass.
                unreachable_cells[cell] = true # Excludes the pocket from A*, habitats, and safe-position queries without adding visible walls.

func _find_nearest_basic_walkable_world_position(world_position: Vector3) -> Vector3: # Finds a local walkable fallback before global connectivity data exists.
    var centre_cell: Vector2i = world_to_cell(world_position) # Converts the supplied world position into logical grid coordinates.
    for radius_cells: int in range(0, 48): # Expands a bounded square search around the starting cell.
        for offset_x: int in range(-radius_cells, radius_cells + 1): # Traverses candidate columns within the current search radius.
            for offset_z: int in range(-radius_cells, radius_cells + 1): # Traverses candidate rows within the current search radius.
                var candidate: Vector2i = centre_cell + Vector2i(offset_x, offset_z) # Builds one logical candidate cell.
                if _is_basic_walkable(candidate): # Accepts local terrain before unreachable-cell pruning is available.
                    return cell_to_world(candidate) # Returns the first suitable generated terrain position.
    return Vector3.ZERO # Returns a deterministic fallback when the generated world contains no basic walkable cell nearby.

func _is_basic_walkable(cell: Vector2i) -> bool: # Reports local terrain walkability before global connectivity is applied.
    if not _is_cell_in_bounds(cell): # Rejects cells outside generated map bounds.
        return false # Prevents flood fill from escaping the logical world.
    if blocked_cells.has(cell): # Rejects generated tree blockers.
        return false # Keeps connectivity analysis consistent with final obstacle placement.
    var terrain: TerrainKind = _terrain_for_cell(cell) # Reads cached logical terrain.
    if terrain == TerrainKind.WATER: # Rejects visible water surfaces.
        return false # Leaves only generated route bridges traversable over water.
    if terrain != TerrainKind.PATH and float(slope_cache.get(cell, 0.0)) > MAX_WALKABLE_SLOPE: # Rejects severe natural slopes while keeping routes deliberately traversable.
        return false # Matches the final navigation slope policy without consulting connectivity itself.
    return true # Accepts locally traversable generated terrain.

func _rebuild_biome_spawn_cache() -> void: # Builds reachable interior habitat pools and curved-route biome boundary cells for wild Pokémon.
    biome_spawn_cells.clear() # Removes stale habitat pools from any prior generation.
    biome_entry_cells.clear() # Removes stale biome-boundary route pools from any prior generation.
    for biome_kind: int in range(BiomeKind.size()): # Creates empty arrays for all seventeen type regions.
        biome_spawn_cells[biome_kind] = [] # Initializes one reachable interior habitat pool.
        biome_entry_cells[biome_kind] = [] # Initializes one route-boundary entry pool.
    for cell_z: int in range(WORLD_DEPTH): # Scans every final logical world row once.
        for cell_x: int in range(WORLD_WIDTH): # Scans every final logical world column once.
            var cell: Vector2i = Vector2i(cell_x, cell_z) # Builds one logical cell coordinate.
            if not is_cell_walkable(cell): # Rejects water, severe slopes, trees, and disconnected pockets.
                continue # Keeps spawn and boundary caches restricted to actual playable terrain.
            var biome_kind: int = int(_biome_for_cell(cell)) # Reads warped biome ownership from the final cache.
            var terrain: TerrainKind = _terrain_for_cell(cell) # Reads the final logical terrain category.
            if terrain != TerrainKind.PATH: # Uses ordinary non-route terrain as habitat interior.
                var spawn_cells: Array = biome_spawn_cells[biome_kind] # Reads the untyped dictionary-backed array for this biome.
                spawn_cells.append(cell) # Adds the reachable cell to the type habitat pool.
                biome_spawn_cells[biome_kind] = spawn_cells # Writes the updated array back to the dictionary for stable Variant semantics.
            elif _is_biome_boundary_cell(cell, biome_kind): # Uses route cells touching a neighboring warped region as entry and exit points.
                var entry_cells: Array = biome_entry_cells[biome_kind] # Reads the untyped boundary array for this biome.
                entry_cells.append(cell) # Adds this curved-route border cell to the habitat boundary pool.
                biome_entry_cells[biome_kind] = entry_cells # Writes the updated boundary array back to the dictionary.

func _is_biome_boundary_cell(cell: Vector2i, biome_kind: int) -> bool: # Detects whether a route cell touches another warped biome in four-way logical space.
    for neighbour: Vector2i in [cell + Vector2i.RIGHT, cell + Vector2i.LEFT, cell + Vector2i.UP, cell + Vector2i.DOWN]: # Tests neighbors consistent with grid navigation.
        if _is_cell_in_bounds(neighbour) and int(_biome_for_cell(neighbour)) != biome_kind: # Detects a valid adjacent cell owned by another region.
            return true # Marks this route cell as a biome entry and exit candidate.
    return false # Reports that the route cell remains fully inside one warped region.

func _prepare_environment_scatter() -> void: # Samples continuous object-density fields into deterministic batched scenery locations.
    grass_cells.clear() # Removes stale ground-cover locations from any previous generation.
    shrub_cells.clear() # Removes stale shrub locations from any previous generation.
    rock_cells.clear() # Removes stale rock locations from any previous generation.
    bridge_cells.clear() # Removes stale bridge locations from any previous generation.
    accent_cells_by_biome.clear() # Removes stale type-specific accent groups from any previous generation.
    for biome_kind: int in range(BiomeKind.size()): # Creates one sparse accent array per type region.
        accent_cells_by_biome[biome_kind] = [] # Initializes the dictionary-backed array used by accent rendering.
    for cell_z: int in range(WORLD_DEPTH): # Samples every logical row once for all non-tree environment objects.
        for cell_x: int in range(WORLD_WIDTH): # Samples every logical column once for all environment density fields.
            var cell: Vector2i = Vector2i(cell_x, cell_z) # Builds one stable logical object-placement coordinate.
            var terrain: TerrainKind = _terrain_for_cell(cell) # Reads final terrain classification.
            var biome_kind: int = int(_biome_for_cell(cell)) # Reads final warped biome ownership.
            var route_distance: float = _route_distance_for_cell(cell) # Reads route proximity for shoulder and sightline rules.
            if terrain == TerrainKind.PATH and underlying_water_cache.has(cell): # Detects generated route crossings over water.
                bridge_cells.append(cell) # Stores the crossing for one batched wooden deck instance.
            if terrain == TerrainKind.WATER or terrain == TerrainKind.PATH or unreachable_cells.has(cell): # Rejects water, route cores, and disconnected pockets from ordinary scenery scatter.
                continue # Leaves those cells to water, bridge, or no visual detail.
            var local: Vector2 = _cell_to_local_2d(cell) # Converts the cell into continuous field coordinates.
            var slope: float = float(slope_cache.get(cell, 0.0)) # Reads cached geometric slope without resampling height.
            var grass_density: float = field_sampler.sample_grass_density(local, biome_kind) # Reads broad patchy ground-cover density.
            if route_distance > PATH_WIDTH + 0.7 and slope < 0.62 and _hash01(cell, 53) < grass_density * 0.58: # Applies route clearance, slope suitability, and deterministic sampling.
                grass_cells.append(cell) # Stores one location for a batched multi-blade grass clump.
            var tree_density: float = field_sampler.sample_tree_density(local, biome_kind) # Reuses clustered forest density for lower shrubs around woodland masses.
            if route_distance > PATH_WIDTH + 1.4 and slope < 0.72 and _hash01(cell, 67) < tree_density * 0.11: # Samples sparse shrubs independently from tree blockers.
                shrub_cells.append(cell) # Stores one location for a batched low shrub object.
            var rock_density: float = field_sampler.sample_rock_density(local, biome_kind) # Reads clustered geological outcrop density.
            var slope_bonus: float = clampf(slope * 0.15, 0.0, 0.18) # Favors rocks on steeper exposed terrain without covering cliffs uniformly.
            if route_distance > PATH_WIDTH + 0.5 and _hash01(cell, 79) < rock_density * 0.12 + slope_bonus: # Samples grouped rocks while keeping route cores clear.
                rock_cells.append(cell) # Stores one location for a batched low-poly boulder.
            if route_distance > PATH_SHOULDER + 1.0 and _hash01(cell, 101 + biome_kind * 7) < _accent_probability(biome_kind): # Samples sparse type accents away from route clutter.
                var accent_cells: Array = accent_cells_by_biome[biome_kind] # Reads the dictionary-backed accent array for this biome.
                accent_cells.append(cell) # Adds one deterministic type-specific accent location.
                accent_cells_by_biome[biome_kind] = accent_cells # Writes the updated array back to the dictionary.

func _build_terrain_geometry() -> void: # Builds vertex-colored terrain, transparent water, water depth, and one combined static collision mesh.
    var ground_tool: SurfaceTool = SurfaceTool.new() # Collects all non-water terrain into one low-draw-call mesh.
    ground_tool.begin(Mesh.PRIMITIVE_TRIANGLES) # Starts triangle construction for generated ground surfaces.
    ground_tool.set_material(_create_vertex_ground_material()) # Uses per-vertex albedo so one material can represent every biome and route.
    var water_tool: SurfaceTool = SurfaceTool.new() # Collects visible water surfaces into one transparent mesh.
    water_tool.begin(Mesh.PRIMITIVE_TRIANGLES) # Starts triangle construction for generated water surfaces.
    water_tool.set_material(_create_water_material()) # Uses a dedicated transparent water material.
    var depth_tool: SurfaceTool = SurfaceTool.new() # Collects dark geometry beneath water for visible depth without textures.
    depth_tool.begin(Mesh.PRIMITIVE_TRIANGLES) # Starts triangle construction for generated water-depth surfaces.
    depth_tool.set_material(_create_ground_material(WATER_DEPTH_COLOR, 0.92)) # Uses a dark opaque rough material below transparent water.
    var collision_faces: PackedVector3Array = PackedVector3Array() # Collects all ground and trunk collision triangles for one static body.
    var ground_vertex_count: int = 0 # Tracks whether the ground SurfaceTool contains geometry before commit.
    var water_vertex_count: int = 0 # Tracks whether the water SurfaceTool contains geometry before commit.
    var depth_vertex_count: int = 0 # Tracks whether the depth SurfaceTool contains geometry before commit.
    for cell_z: int in range(WORLD_DEPTH): # Builds geometry for every logical terrain row.
        for cell_x: int in range(WORLD_WIDTH): # Builds geometry for every logical terrain column.
            var cell: Vector2i = Vector2i(cell_x, cell_z) # Creates one stable logical cell coordinate.
            var terrain: TerrainKind = _terrain_for_cell(cell) # Reads cached logical terrain classification.
            var corners: Array[Vector3] = _get_cell_corners(cell, terrain) # Builds final world-space corners including bridge elevation when required.
            if terrain == TerrainKind.WATER: # Routes visible water cells into the transparent water mesh.
                _append_flat_quad_to_surface(water_tool, corners, Vector3.UP) # Adds the level water surface with upward lighting normal.
                water_vertex_count += 6 # Records one two-triangle water quad.
                var depth_corners: Array[Vector3] = corners.duplicate() # Copies water surface geometry for the darker depth layer.
                for corner_index: int in range(depth_corners.size()): # Lowers every copied water corner by the same amount.
                    depth_corners[corner_index].y = WATER_LEVEL - 1.25 # Places the visible depth floor beneath the transparent surface.
                _append_flat_quad_to_surface(depth_tool, depth_corners, Vector3.UP) # Adds the dark depth floor quad.
                depth_vertex_count += 6 # Records one two-triangle depth quad.
                continue # Skips ordinary ground collision because water is intentionally non-walkable.
            _append_ground_cell_to_surface(ground_tool, cell, corners, terrain) # Adds smooth-normal vertex-colored terrain for this non-water cell.
            ground_vertex_count += 6 # Records one two-triangle ground quad.
            _append_quad_faces(collision_faces, corners) # Adds the exact same terrain surface to the combined physics collision mesh.
            _append_water_boundary_faces(cell, corners, collision_faces) # Adds vertical shoreline walls where traversable ground borders generated water.
    for tree_cell: Vector2i in tree_cells: # Adds physical trunk collision only for actual generated trees.
        _append_tree_collision_faces(tree_cell, collision_faces) # Uses a small hexagonal trunk rather than blocking the whole logical cell in physics.
    if ground_vertex_count > 0: # Commits the generated terrain only when at least one non-water cell exists.
        var ground_instance: MeshInstance3D = MeshInstance3D.new() # Creates the visible generated ground node.
        ground_instance.name = "generated_terrain" # Gives the runtime node a stable diagnostic name.
        ground_instance.mesh = ground_tool.commit() # Commits the complete one-material vertex-colored terrain mesh.
        ground_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # Avoids expensive self-shadow casting from the entire terrain mesh.
        add_child(ground_instance) # Adds generated terrain to the world scene.
    if water_vertex_count > 0: # Commits visible water only when generation produced water cells.
        var water_instance: MeshInstance3D = MeshInstance3D.new() # Creates the visible generated water node.
        water_instance.name = "generated_water" # Gives the runtime water mesh a stable diagnostic name.
        water_instance.mesh = water_tool.commit() # Commits all generated lake, marsh, and stream surfaces in one mesh.
        water_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # Prevents transparent water from casting unnecessary shadows.
        add_child(water_instance) # Adds generated water to the world scene.
    if depth_vertex_count > 0: # Commits the dark water floor only when visible water exists.
        var depth_instance: MeshInstance3D = MeshInstance3D.new() # Creates the generated water-depth node.
        depth_instance.name = "generated_water_depth" # Gives the runtime depth mesh a stable diagnostic name.
        depth_instance.mesh = depth_tool.commit() # Commits all dark water floors into one mesh.
        depth_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # Avoids unnecessary shadows from submerged geometry.
        add_child(depth_instance) # Adds generated water depth beneath the transparent surface.
    var world_body: StaticBody3D = StaticBody3D.new() # Creates one static physics owner for terrain, shore walls, and generated tree trunks.
    world_body.name = "generated_world_collision" # Gives the combined collision body a stable diagnostic name.
    world_body.collision_layer = 1 # Keeps compatibility with the existing player and wild Pokémon collision masks.
    world_body.collision_mask = 0 # Prevents the static world body from querying other collision layers itself.
    var collision_shape: CollisionShape3D = CollisionShape3D.new() # Creates the collision-shape node owned by the generated static body.
    var concave_shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new() # Uses one concave triangle soup suitable for a static generated world.
    concave_shape.backface_collision = true # Keeps ground and shoreline collision robust from either triangle orientation.
    concave_shape.set_faces(collision_faces) # Uploads all generated terrain and trunk collision triangles at once.
    collision_shape.shape = concave_shape # Assigns the completed generated shape to the collision node.
    world_body.add_child(collision_shape) # Parents the shape under its static physics body.
    add_child(world_body) # Adds final generated collision to the world scene.

func _append_ground_cell_to_surface(surface_tool: SurfaceTool, cell: Vector2i, corners: Array[Vector3], terrain: TerrainKind) -> void: # Adds one terrain quad with cached smooth normals and continuous vertex-color breakup.
    var biome_kind: int = int(_biome_for_cell(cell)) # Reads the warped biome controlling the broad material palette.
    var base_color: Color = _terrain_color_for_cell(cell, biome_kind, terrain) # Resolves slope, route shoulder, and biome color blending once for this cell.
    var vertex_coords: Array[Vector2i] = [Vector2i(cell.x, cell.y), Vector2i(cell.x + 1, cell.y), Vector2i(cell.x + 1, cell.y + 1), Vector2i(cell.x, cell.y + 1)] # Maps each corner to its heightmap vertex for smooth normals.
    var triangle_indices: PackedInt32Array = PackedInt32Array([0, 2, 1, 0, 3, 2]) # Preserves the established triangle winding used by generated collision.
    for corner_index: int in triangle_indices: # Emits both terrain triangles with independent per-vertex attributes.
        var vertex_coord: Vector2i = vertex_coords[corner_index] # Reads the corresponding heightmap vertex coordinate.
        var local: Vector2 = Vector2(float(vertex_coord.x) - float(WORLD_WIDTH) * 0.5, float(vertex_coord.y) - float(WORLD_DEPTH) * 0.5) # Converts the vertex to continuous field coordinates.
        var variation: float = field_sampler.sample_color_variation(local) # Samples subtle procedural material breakup at the actual vertex position.
        surface_tool.set_color(_vary_color(base_color, variation)) # Supplies per-vertex albedo before adding the vertex.
        surface_tool.set_normal(_normal_at_vertex(vertex_coord.x, vertex_coord.y)) # Supplies a heightmap-derived smooth lighting normal even though geometry is emitted per cell.
        surface_tool.add_vertex(corners[corner_index]) # Adds the fully attributed terrain vertex to the SurfaceTool.

func _append_flat_quad_to_surface(surface_tool: SurfaceTool, corners: Array[Vector3], normal: Vector3) -> void: # Adds one flat two-triangle quad with a supplied constant normal.
    surface_tool.set_normal(normal) # Supplies the same lighting normal for every following vertex in this flat surface.
    surface_tool.add_vertex(corners[0]) # Adds the first vertex of the first triangle.
    surface_tool.add_vertex(corners[2]) # Adds the second vertex of the first triangle.
    surface_tool.add_vertex(corners[1]) # Adds the third vertex of the first triangle.
    surface_tool.add_vertex(corners[0]) # Adds the first vertex of the second triangle.
    surface_tool.add_vertex(corners[3]) # Adds the second vertex of the second triangle.
    surface_tool.add_vertex(corners[2]) # Adds the third vertex of the second triangle.

func _build_environment_visuals() -> void: # Builds all high-count scenery through MultiMesh batches so richer procedural detail remains inexpensive.
    _build_tree_visuals() # Builds trunks and layered canopies from clustered generated tree positions.
    _build_ground_cover_visuals() # Builds patchy grass clumps and shrubs from continuous vegetation density fields.
    _build_rock_visuals() # Builds clustered low-poly boulders driven by geology and slope.
    _build_bridge_visuals() # Builds wooden decks wherever curved routes cross generated water fields.
    _build_type_accent_visuals() # Builds sparse mathematically placed type-specific objects without authored scene chunks.

func _build_tree_visuals() -> void: # Builds generated forest masses as a few batched trunk and canopy draw calls.
    if tree_cells.is_empty(): # Skips mesh creation when the active seed generated no trees.
        return # Avoids empty MultiMesh resources.
    var grass_tree_cells: Array[Vector2i] = [] # Stores ordinary, Normal, and Grass forest tree cells.
    var bug_tree_cells: Array[Vector2i] = [] # Stores Bug woodland tree cells for a distinct canopy tone.
    var dark_tree_cells: Array[Vector2i] = [] # Stores Dark and Ghost woodland cells for a dense muted canopy tone.
    var wet_tree_cells: Array[Vector2i] = [] # Stores Water and Poison bank trees for a cooler canopy tone.
    for cell: Vector2i in tree_cells: # Groups every generated tree by its warped biome identity.
        match _biome_for_cell(cell): # Selects one canopy palette while all trees continue sharing the same trunk batch.
            BiomeKind.BUG: # Detects Bug woodland trees.
                bug_tree_cells.append(cell) # Adds the tree to the lighter yellow-green canopy group.
            BiomeKind.DARK, BiomeKind.GHOST: # Detects darker woodland regions.
                dark_tree_cells.append(cell) # Adds the tree to the dark canopy group.
            BiomeKind.WATER, BiomeKind.POISON: # Detects wetland and shoreline trees.
                wet_tree_cells.append(cell) # Adds the tree to the cooler wet canopy group.
            _: # Uses the ordinary green canopy for remaining tree-bearing regions.
                grass_tree_cells.append(cell) # Adds the tree to the default canopy group.
    var trunk_mesh: CylinderMesh = CylinderMesh.new() # Creates one reusable low-poly trunk mesh for every generated tree.
    trunk_mesh.top_radius = 0.18 # Tapers trunks naturally toward the canopy.
    trunk_mesh.bottom_radius = 0.30 # Gives trunks a wider grounded base.
    trunk_mesh.height = 1.85 # Produces readable tree height at the current character scale.
    trunk_mesh.radial_segments = 7 # Keeps trunks faceted and inexpensive while avoiding square prototype silhouettes.
    trunk_mesh.rings = 1 # Uses the minimum vertical subdivisions needed for a straight trunk.
    trunk_mesh.material = _create_ground_material(TREE_TRUNK_COLOR, 0.96) # Applies the shared dark natural trunk material.
    _create_cell_multimesh("tree_trunks", trunk_mesh, tree_cells, 0.93, 0.88, 1.20, 211, 0.24) # Batches all trunks with deterministic scale, yaw, and small position jitter.
    _build_canopy_group("grass_canopy", grass_tree_cells, GRASS_CANOPY_COLOR, 223) # Builds layered ordinary green canopies.
    _build_canopy_group("bug_canopy", bug_tree_cells, BUG_CANOPY_COLOR, 227) # Builds layered Bug woodland canopies.
    _build_canopy_group("dark_canopy", dark_tree_cells, DARK_CANOPY_COLOR, 229) # Builds layered dark woodland canopies.
    _build_canopy_group("wet_canopy", wet_tree_cells, WET_CANOPY_COLOR, 233) # Builds layered wetland canopies.

func _build_canopy_group(node_prefix: String, cells: Array[Vector2i], color: Color, salt: int) -> void: # Builds two offset low-poly canopy layers for one generated forest palette.
    if cells.is_empty(): # Skips this palette when no generated trees belong to it.
        return # Avoids empty canopy MultiMesh resources.
    var lower_mesh: SphereMesh = SphereMesh.new() # Creates a broad faceted lower canopy mass.
    lower_mesh.radius = 0.93 # Sets horizontal canopy spread around the trunk.
    lower_mesh.height = 1.42 # Flattens the lower canopy vertically for a stylized natural silhouette.
    lower_mesh.radial_segments = 8 # Uses enough facets to read as organic without high polygon cost.
    lower_mesh.rings = 4 # Uses a few vertical rings for low-poly canopy shape.
    lower_mesh.material = _create_ground_material(color.darkened(0.12), 0.94) # Gives the lower canopy slightly darker self-layering.
    var upper_mesh: SphereMesh = SphereMesh.new() # Creates a smaller upper canopy mass.
    upper_mesh.radius = 0.68 # Narrows the upper canopy above the broader lower layer.
    upper_mesh.height = 1.04 # Keeps the upper canopy compact vertically.
    upper_mesh.radial_segments = 8 # Matches lower canopy facet density.
    upper_mesh.rings = 4 # Matches lower canopy ring count for stable performance.
    upper_mesh.material = _create_ground_material(color, 0.94) # Uses the main palette color on the upper canopy.
    _create_cell_multimesh(node_prefix + "_lower", lower_mesh, cells, 2.05, 0.90, 1.18, salt, 0.24) # Batches broad lower canopy masses with deterministic variation.
    _create_cell_multimesh(node_prefix + "_upper", upper_mesh, cells, 2.77, 0.90, 1.18, salt + 1, 0.24) # Batches smaller upper canopy masses above the same generated tree locations.

func _build_ground_cover_visuals() -> void: # Builds inexpensive small-scale vegetation that fills the missing visual layer between terrain and trees.
    if not grass_cells.is_empty(): # Builds grass only when density-field sampling produced eligible cells.
        var grass_mesh: Mesh = _create_grass_clump_mesh(GRASS_DETAIL_COLOR) # Creates one reusable crossed-blade clump from generated geometry.
        _create_cell_multimesh("grass_clumps", grass_mesh, grass_cells, 0.02, 0.72, 1.28, 251, 0.34) # Batches patchy grass with deterministic position, yaw, and scale variation.
    if not shrub_cells.is_empty(): # Builds shrubs only when clustered forest density produced eligible cells.
        var shrub_mesh: SphereMesh = SphereMesh.new() # Creates one reusable faceted shrub mesh.
        shrub_mesh.radius = 0.42 # Sets shrub horizontal footprint below tree-canopy scale.
        shrub_mesh.height = 0.68 # Flattens shrubs into low ground-level masses.
        shrub_mesh.radial_segments = 7 # Keeps shrubs inexpensive and visibly low-poly.
        shrub_mesh.rings = 3 # Uses few vertical rings for compact batched geometry.
        shrub_mesh.material = _create_ground_material(SHRUB_COLOR, 0.96) # Applies a dark natural shrub material.
        _create_cell_multimesh("shrubs", shrub_mesh, shrub_cells, 0.34, 0.72, 1.25, 263, 0.32) # Batches deterministic shrub clusters across suitable generated terrain.

func _build_rock_visuals() -> void: # Builds clustered exposed boulders from geology and slope density fields.
    if rock_cells.is_empty(): # Skips rock mesh creation when no cells were selected.
        return # Avoids an empty MultiMesh resource.
    var rock_mesh: SphereMesh = SphereMesh.new() # Creates one faceted boulder source mesh reused across all selected cells.
    rock_mesh.radius = 0.46 # Sets a readable small boulder footprint.
    rock_mesh.height = 0.64 # Flattens the sphere into a grounded rock shape.
    rock_mesh.radial_segments = 6 # Uses strong facets for cheap natural variation under random yaw.
    rock_mesh.rings = 3 # Keeps each boulder low polygon for large instance counts.
    rock_mesh.material = _create_ground_material(ROCK_DETAIL_COLOR, 0.99) # Applies a very rough neutral stone material.
    _create_cell_multimesh("rock_outcrops", rock_mesh, rock_cells, 0.30, 0.65, 1.55, 277, 0.31) # Batches boulders with broad deterministic scale and position variation.

func _build_bridge_visuals() -> void: # Builds wooden deck objects exactly where generated curved routes cross generated water.
    if bridge_cells.is_empty(): # Skips bridge mesh creation when no route-water intersections exist.
        return # Avoids an empty MultiMesh resource.
    var deck_mesh: BoxMesh = BoxMesh.new() # Creates one reusable square deck section for each logical bridge cell.
    deck_mesh.size = Vector3(TILE_SIZE * 0.98, 0.14, TILE_SIZE * 0.98) # Slightly overlaps adjacent sections so curved rasterized bridges read as continuous.
    deck_mesh.material = _create_ground_material(BRIDGE_COLOR, 0.90) # Applies a dark rough wooden deck material.
    var multi_mesh: MultiMesh = MultiMesh.new() # Creates one batched bridge resource for all route-water crossing cells.
    multi_mesh.transform_format = MultiMesh.TRANSFORM_3D # Stores full 3D transforms for every deck section.
    multi_mesh.instance_count = bridge_cells.size() # Allocates exactly one deck instance per crossing cell.
    multi_mesh.mesh = deck_mesh # Assigns the shared deck mesh to the batch.
    for index: int in range(bridge_cells.size()): # Configures every generated bridge section transform.
        var cell: Vector2i = bridge_cells[index] # Reads one crossing cell.
        var world_position: Vector3 = cell_to_world(cell) # Uses the same raised bridge height returned to gameplay systems.
        world_position.y += 0.015 # Places the visible deck just above the route collision surface to avoid z fighting.
        multi_mesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, world_position)) # Stores an axis-aligned deck section at the generated crossing position.
    var instance: MultiMeshInstance3D = MultiMeshInstance3D.new() # Creates the scene node that renders the batched bridge resource.
    instance.name = "generated_bridges" # Gives the runtime batch a stable diagnostic name.
    instance.multimesh = multi_mesh # Assigns the completed generated deck transforms.
    add_child(instance) # Adds all bridge sections to the generated world in one draw-call-oriented node.

func _build_type_accent_visuals() -> void: # Builds sparse mathematical object accents so biome identity is not expressed only through ground color.
    for biome_kind: int in range(BiomeKind.size()): # Processes each type region independently for one source mesh and palette.
        var values: Array = accent_cells_by_biome.get(biome_kind, []) # Reads generated accent locations for this biome.
        if values.is_empty(): # Skips regions whose density rule produced no accents.
            continue # Avoids creating empty source meshes and MultiMeshes.
        var cells: Array[Vector2i] = [] # Converts dictionary-backed Variant values into a strongly typed cell array.
        for value: Variant in values: # Iterates every generated accent location.
            cells.append(value as Vector2i) # Appends the typed cell coordinate for rendering.
        var accent_mesh: Mesh = _create_accent_mesh(biome_kind) # Creates one simple object shape derived from the biome's procedural identity.
        _create_cell_multimesh("%s_accents" % _biome_slug(biome_kind), accent_mesh, cells, _accent_height_offset(biome_kind), 0.70, 1.35, 307 + biome_kind * 13, 0.26) # Batches sparse type accents with deterministic transforms.

func _create_accent_mesh(biome_kind: int) -> Mesh: # Creates one primitive-derived object family for sparse type-specific environment accents.
    var color: Color = _accent_color(biome_kind) # Resolves a restrained type-related palette distinct from ground color.
    var material: StandardMaterial3D = _create_ground_material(color, 0.83) # Creates one rough physical material for the accent source mesh.
    if biome_kind in [BiomeKind.ICE, BiomeKind.PSYCHIC, BiomeKind.GHOST, BiomeKind.ELECTRIC]: # Uses tapered crystal-like geometry for luminous or crystalline regions.
        var crystal: CylinderMesh = CylinderMesh.new() # Creates a faceted tapered monolith from built-in mesh geometry.
        crystal.top_radius = 0.05 # Narrows the top into a near-pointed tip.
        crystal.bottom_radius = 0.34 # Gives the generated crystal a stable grounded base.
        crystal.height = 1.55 # Makes the accent readable above grass and low rocks.
        crystal.radial_segments = 5 # Uses a strong faceted silhouette rather than a smooth cylinder.
        crystal.rings = 1 # Keeps the source geometry minimal for many instances.
        crystal.material = material # Applies the region-specific accent material.
        return crystal # Returns the generated crystal family mesh.
    if biome_kind in [BiomeKind.FIRE, BiomeKind.DRAGON, BiomeKind.STEEL, BiomeKind.FLYING]: # Uses narrow pillars or vents in harsh and constructed-looking regions.
        var pillar: CylinderMesh = CylinderMesh.new() # Creates a simple faceted vertical accent.
        pillar.top_radius = 0.16 # Slightly tapers the top for less manufactured repetition.
        pillar.bottom_radius = 0.27 # Gives the accent a wider grounded base.
        pillar.height = 1.45 # Keeps it below landmark scale while visible from the route.
        pillar.radial_segments = 6 # Uses low facet count for inexpensive repeated geometry.
        pillar.rings = 1 # Keeps the source object minimal.
        pillar.material = material # Applies the region-specific material.
        return pillar # Returns the generated pillar accent mesh.
    var boulder: SphereMesh = SphereMesh.new() # Uses a low faceted organic mound for softer remaining regions.
    boulder.radius = 0.38 # Sets the accent footprint below ordinary large boulder scale.
    boulder.height = 0.58 # Flattens the mound into a grounded natural object.
    boulder.radial_segments = 6 # Keeps the object visibly faceted and cheap.
    boulder.rings = 3 # Uses minimal vertical geometry.
    boulder.material = material # Applies the region-specific accent material.
    return boulder # Returns the generated organic accent mesh.

func _create_grass_clump_mesh(color: Color) -> Mesh: # Creates one reusable crossed-quad grass clump entirely from procedural geometry.
    var tool: SurfaceTool = SurfaceTool.new() # Collects two intersecting vertical blade planes into one source mesh.
    tool.begin(Mesh.PRIMITIVE_TRIANGLES) # Starts triangle construction for the generated grass object.
    tool.set_material(_create_double_sided_material(color, 0.98)) # Applies a double-sided rough vegetation material so both planes remain visible from the orbit camera.
    var half_width: float = 0.27 # Defines clump half-width around its local origin.
    var height: float = 0.46 # Defines clump blade height above generated terrain.
    _append_simple_vertical_quad(tool, Vector3(-half_width, 0.0, 0.0), Vector3(half_width, 0.0, 0.0), Vector3(half_width * 0.72, height, 0.0), Vector3(-half_width * 0.72, height, 0.0), Vector3(0.0, 0.0, 1.0)) # Adds the first vertical blade plane.
    _append_simple_vertical_quad(tool, Vector3(0.0, 0.0, -half_width), Vector3(0.0, 0.0, half_width), Vector3(0.0, height, half_width * 0.72), Vector3(0.0, height, -half_width * 0.72), Vector3(1.0, 0.0, 0.0)) # Adds the perpendicular blade plane for all-angle readability.
    return tool.commit() # Returns the generated crossed-plane clump mesh for MultiMesh instancing.

func _append_simple_vertical_quad(tool: SurfaceTool, bottom_left: Vector3, bottom_right: Vector3, top_right: Vector3, top_left: Vector3, normal: Vector3) -> void: # Adds one two-triangle vertical quad to a small generated object mesh.
    tool.set_normal(normal) # Supplies a stable face normal before adding the quad vertices.
    tool.add_vertex(bottom_left) # Adds the first vertex of the first triangle.
    tool.add_vertex(top_right) # Adds the second vertex of the first triangle.
    tool.add_vertex(bottom_right) # Adds the third vertex of the first triangle.
    tool.add_vertex(bottom_left) # Adds the first vertex of the second triangle.
    tool.add_vertex(top_left) # Adds the second vertex of the second triangle.
    tool.add_vertex(top_right) # Adds the third vertex of the second triangle.

func _create_cell_multimesh(node_name: String, source_mesh: Mesh, cells: Array[Vector2i], height_offset: float, min_scale: float, max_scale: float, salt: int, jitter_fraction: float) -> void: # Batches one generated object family with deterministic spatial variation.
    if cells.is_empty(): # Rejects empty object sets before allocating a MultiMesh.
        return # Avoids useless runtime resources.
    var multi_mesh: MultiMesh = MultiMesh.new() # Creates the GPU-friendly repeated-instance resource.
    multi_mesh.transform_format = MultiMesh.TRANSFORM_3D # Stores complete transforms including deterministic yaw and scale.
    multi_mesh.instance_count = cells.size() # Allocates exactly one instance per generated object location.
    multi_mesh.mesh = source_mesh # Assigns the shared procedural source mesh.
    for index: int in range(cells.size()): # Configures every generated object transform exactly once at startup.
        var cell: Vector2i = cells[index] # Reads the logical source cell for this object.
        var scale_value: float = lerpf(min_scale, max_scale, _hash01(cell, salt)) # Derives deterministic size variation from an independent hash salt.
        var yaw: float = _hash01(cell, salt + 1) * TAU # Derives deterministic unrestricted horizontal rotation.
        var jitter_x: float = (_hash01(cell, salt + 2) - 0.5) * TILE_SIZE * jitter_fraction # Offsets the object inside its logical cell to hide the underlying generation grid.
        var jitter_z: float = (_hash01(cell, salt + 3) - 0.5) * TILE_SIZE * jitter_fraction # Uses an independent deterministic offset on the second horizontal axis.
        var world_position: Vector3 = cell_to_world(cell) + Vector3(jitter_x, 0.0, jitter_z) # Starts from the generated cell and applies sub-cell visual jitter.
        world_position.y = _sample_height(world_position.x / TILE_SIZE, world_position.z / TILE_SIZE) + height_offset * scale_value # Re-samples the cached heightmap at the jittered object position so it remains grounded.
        var basis: Basis = Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_value) # Combines deterministic yaw and uniform scale into one instance basis.
        multi_mesh.set_instance_transform(index, Transform3D(basis, world_position)) # Stores the completed generated object transform.
    var instance: MultiMeshInstance3D = MultiMeshInstance3D.new() # Creates the scene node that renders the complete batch.
    instance.name = node_name # Gives the generated batch a stable diagnostic name.
    instance.multimesh = multi_mesh # Assigns all generated transforms and the shared source mesh.
    add_child(instance) # Adds the complete object family to the world in one node.

func _get_cell_corners(cell: Vector2i, terrain: TerrainKind) -> Array[Vector3]: # Returns final world-space quad corners for one generated logical cell.
    if terrain == TerrainKind.WATER: # Uses one level surface for visible water cells.
        return _water_corners_for_cell(cell) # Returns shared-water-level corners instead of terrain heights.
    var x0: float = (float(cell.x) - float(WORLD_WIDTH) * 0.5) * TILE_SIZE # Converts the cell's left edge into world X.
    var x1: float = x0 + TILE_SIZE # Converts the cell's right edge into world X.
    var z0: float = (float(cell.y) - float(WORLD_DEPTH) * 0.5) * TILE_SIZE # Converts the cell's near edge into world Z.
    var z1: float = z0 + TILE_SIZE # Converts the cell's far edge into world Z.
    var corners: Array[Vector3] = [Vector3(x0, _height_at_vertex(cell.x, cell.y), z0), Vector3(x1, _height_at_vertex(cell.x + 1, cell.y), z0), Vector3(x1, _height_at_vertex(cell.x + 1, cell.y + 1), z1), Vector3(x0, _height_at_vertex(cell.x, cell.y + 1), z1)] # Reads the four cached heightmap vertices without resampling noise.
    if terrain == TerrainKind.PATH and underlying_water_cache.has(cell): # Detects bridge terrain where path logically overrides generated water.
        for corner_index: int in range(corners.size()): # Raises every bridge corner to a consistent safe deck level.
            corners[corner_index].y = maxf(corners[corner_index].y, WATER_LEVEL + 0.22) # Prevents bridge collision and visuals from dipping under the water surface.
    return corners # Returns the completed generated terrain or bridge corners.

func _water_corners_for_cell(cell: Vector2i) -> Array[Vector3]: # Returns one level water quad at the shared generated water surface.
    var x0: float = (float(cell.x) - float(WORLD_WIDTH) * 0.5) * TILE_SIZE # Converts the cell's left edge into world X.
    var x1: float = x0 + TILE_SIZE # Converts the cell's right edge into world X.
    var z0: float = (float(cell.y) - float(WORLD_DEPTH) * 0.5) * TILE_SIZE # Converts the cell's near edge into world Z.
    var z1: float = z0 + TILE_SIZE # Converts the cell's far edge into world Z.
    return [Vector3(x0, WATER_LEVEL, z0), Vector3(x1, WATER_LEVEL, z0), Vector3(x1, WATER_LEVEL, z1), Vector3(x0, WATER_LEVEL, z1)] # Returns four flat corners shared by lake, marsh, and stream cells.

func _append_quad_faces(faces: PackedVector3Array, corners: Array[Vector3]) -> void: # Adds one two-triangle quad to the combined static collision face array.
    faces.append(corners[0]) # Adds the first vertex of the first collision triangle.
    faces.append(corners[2]) # Adds the second vertex of the first collision triangle.
    faces.append(corners[1]) # Adds the third vertex of the first collision triangle.
    faces.append(corners[0]) # Adds the first vertex of the second collision triangle.
    faces.append(corners[3]) # Adds the second vertex of the second collision triangle.
    faces.append(corners[2]) # Adds the third vertex of the second collision triangle.

func _append_water_boundary_faces(cell: Vector2i, corners: Array[Vector3], faces: PackedVector3Array) -> void: # Adds shoreline walls so CharacterBody3D cannot walk into generated water gaps.
    var neighbours: Array[Vector2i] = [cell + Vector2i.UP, cell + Vector2i.RIGHT, cell + Vector2i.DOWN, cell + Vector2i.LEFT] # Lists logical neighbors in the same order as terrain quad edges.
    var edge_pairs: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 0)] # Maps each logical neighbor direction to the matching quad edge corners.
    for edge_index: int in range(4): # Tests all four terrain edges for adjacency to generated water or world boundary.
        var neighbour: Vector2i = neighbours[edge_index] # Reads the neighboring logical cell on this edge.
        if _is_cell_in_bounds(neighbour) and _terrain_for_cell(neighbour) != TerrainKind.WATER: # Skips ordinary ground-to-ground edges.
            continue # Avoids unnecessary internal vertical collision faces.
        var pair: Vector2i = edge_pairs[edge_index] # Reads the matching top edge corner indices.
        var top_a: Vector3 = corners[pair.x] # Reads the first top shoreline edge point.
        var top_b: Vector3 = corners[pair.y] # Reads the second top shoreline edge point.
        var bottom_a: Vector3 = Vector3(top_a.x, WATER_LEVEL - 2.2, top_a.z) # Extends the first shoreline point below visible water.
        var bottom_b: Vector3 = Vector3(top_b.x, WATER_LEVEL - 2.2, top_b.z) # Extends the second shoreline point below visible water.
        _append_wall_quad(faces, top_a, top_b, bottom_b, bottom_a) # Adds an invisible vertical collision wall along the shoreline edge.

func _append_tree_collision_faces(cell: Vector2i, faces: PackedVector3Array) -> void: # Adds a small hexagonal trunk collision prism centered on one generated tree.
    var center: Vector3 = cell_to_world(cell) # Resolves the generated terrain position beneath the tree.
    center.y -= 0.04 # Sinks the collision prism slightly into the ground to avoid a lower gap.
    var scale_value: float = lerpf(0.88, 1.20, _hash01(cell, 211)) # Matches the deterministic trunk visual scale used by the MultiMesh batch.
    var radius: float = TREE_COLLISION_RADIUS * scale_value # Scales physical trunk radius with the matching visual instance.
    var height: float = TREE_COLLISION_HEIGHT * scale_value # Scales physical trunk height with the matching visual instance.
    var sides: int = 6 # Uses a cheap hexagonal prism that closely approximates the low-poly visible trunk.
    for side_index: int in range(sides): # Builds one vertical collision wall for each prism side.
        var angle_a: float = TAU * float(side_index) / float(sides) # Computes the first radial direction around the trunk.
        var angle_b: float = TAU * float(side_index + 1) / float(sides) # Computes the next radial direction around the trunk.
        var bottom_a: Vector3 = center + Vector3(cos(angle_a) * radius, 0.0, sin(angle_a) * radius) # Builds the first bottom prism point.
        var bottom_b: Vector3 = center + Vector3(cos(angle_b) * radius, 0.0, sin(angle_b) * radius) # Builds the second bottom prism point.
        var top_a: Vector3 = bottom_a + Vector3.UP * height # Builds the matching first top prism point.
        var top_b: Vector3 = bottom_b + Vector3.UP * height # Builds the matching second top prism point.
        _append_wall_quad(faces, top_a, top_b, bottom_b, bottom_a) # Adds the side as two collision triangles.

func _append_wall_quad(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void: # Adds one vertical or arbitrary wall quad to the collision triangle array.
    faces.append(a) # Adds the first vertex of the first wall triangle.
    faces.append(b) # Adds the second vertex of the first wall triangle.
    faces.append(c) # Adds the third vertex of the first wall triangle.
    faces.append(a) # Adds the first vertex of the second wall triangle.
    faces.append(c) # Adds the second vertex of the second wall triangle.
    faces.append(d) # Adds the third vertex of the second wall triangle.

func _calculate_cell_slope(cell: Vector2i) -> float: # Measures maximum local rise across one terrain cell relative to its world-space width.
    var h0: float = _height_at_vertex(cell.x, cell.y) # Reads the first cached corner height.
    var h1: float = _height_at_vertex(cell.x + 1, cell.y) # Reads the second cached corner height.
    var h2: float = _height_at_vertex(cell.x + 1, cell.y + 1) # Reads the third cached corner height.
    var h3: float = _height_at_vertex(cell.x, cell.y + 1) # Reads the fourth cached corner height.
    var minimum_height: float = minf(minf(h0, h1), minf(h2, h3)) # Finds the lowest cell corner.
    var maximum_height: float = maxf(maxf(h0, h1), maxf(h2, h3)) # Finds the highest cell corner.
    return (maximum_height - minimum_height) / TILE_SIZE # Normalizes height difference by horizontal cell size for a useful steepness metric.

func _normal_at_vertex(vertex_x: int, vertex_z: int) -> Vector3: # Computes a smooth lighting normal directly from neighboring cached heightmap samples.
    var left_x: int = maxi(vertex_x - 1, 0) # Clamps the left sample to the heightmap edge.
    var right_x: int = mini(vertex_x + 1, WORLD_WIDTH) # Clamps the right sample to the heightmap edge.
    var near_z: int = maxi(vertex_z - 1, 0) # Clamps the near sample to the heightmap edge.
    var far_z: int = mini(vertex_z + 1, WORLD_DEPTH) # Clamps the far sample to the heightmap edge.
    var dx_span: float = float(maxi(right_x - left_x, 1)) * TILE_SIZE # Measures actual world-space horizontal span used by the X derivative.
    var dz_span: float = float(maxi(far_z - near_z, 1)) * TILE_SIZE # Measures actual world-space horizontal span used by the Z derivative.
    var dx: float = (_height_at_vertex(right_x, vertex_z) - _height_at_vertex(left_x, vertex_z)) / dx_span # Estimates the X height derivative from cached neighbors.
    var dz: float = (_height_at_vertex(vertex_x, far_z) - _height_at_vertex(vertex_x, near_z)) / dz_span # Estimates the Z height derivative from cached neighbors.
    return Vector3(-dx, 1.0, -dz).normalized() # Converts the height derivatives into a smooth upward-facing terrain normal.

func _sample_height(local_x: float, local_z: float) -> float: # Bilinearly samples the cached generated heightmap at arbitrary local cell-space coordinates.
    var grid_x: float = clampf(local_x + float(WORLD_WIDTH) * 0.5, 0.0, float(WORLD_WIDTH)) # Converts centered local X into heightmap vertex space.
    var grid_z: float = clampf(local_z + float(WORLD_DEPTH) * 0.5, 0.0, float(WORLD_DEPTH)) # Converts centered local Z into heightmap vertex space.
    var x0: int = int(floor(grid_x)) # Finds the left heightmap vertex index.
    var z0: int = int(floor(grid_z)) # Finds the near heightmap vertex index.
    var x1: int = mini(x0 + 1, WORLD_WIDTH) # Finds the right heightmap vertex index within bounds.
    var z1: int = mini(z0 + 1, WORLD_DEPTH) # Finds the far heightmap vertex index within bounds.
    var tx: float = grid_x - float(x0) # Computes horizontal interpolation progress between neighboring vertices.
    var tz: float = grid_z - float(z0) # Computes vertical interpolation progress between neighboring vertices.
    var near_height: float = lerpf(_height_at_vertex(x0, z0), _height_at_vertex(x1, z0), tx) # Interpolates along the near heightmap edge.
    var far_height: float = lerpf(_height_at_vertex(x0, z1), _height_at_vertex(x1, z1), tx) # Interpolates along the far heightmap edge.
    return lerpf(near_height, far_height, tz) # Interpolates between the two edges for the final continuous cached height.

func _height_at_vertex(vertex_x: int, vertex_z: int) -> float: # Reads one cached heightmap vertex with safe boundary clamping.
    var safe_x: int = clampi(vertex_x, 0, WORLD_WIDTH) # Keeps X inside the allocated heightmap vertex range.
    var safe_z: int = clampi(vertex_z, 0, WORLD_DEPTH) # Keeps Z inside the allocated heightmap vertex range.
    return height_vertices[_height_index(safe_x, safe_z)] # Returns the packed cached elevation value.

func _height_index(vertex_x: int, vertex_z: int) -> int: # Converts a heightmap vertex coordinate into one packed-array index.
    return vertex_z * (WORLD_WIDTH + 1) + vertex_x # Uses row-major storage for cache-friendly generation and geometry traversal.

func _route_distance_for_cell(cell: Vector2i) -> float: # Reads sparse approximate distance to the nearest generated curved route.
    return float(route_distance_cache.get(cell, INF)) # Returns infinity outside the painted route influence band.

func _route_distance_for_vertex(vertex_x: int, vertex_z: int) -> float: # Approximates route distance at a heightmap vertex from its four adjacent logical cells.
    var best_distance: float = INF # Starts above every painted route distance.
    for cell: Vector2i in [Vector2i(vertex_x - 1, vertex_z - 1), Vector2i(vertex_x, vertex_z - 1), Vector2i(vertex_x - 1, vertex_z), Vector2i(vertex_x, vertex_z)]: # Tests all cells sharing this vertex.
        if _is_cell_in_bounds(cell): # Ignores off-map adjacent cells at world edges.
            best_distance = minf(best_distance, _route_distance_for_cell(cell)) # Keeps the closest route influence around this vertex.
    return best_distance # Returns the approximate distance used by route terrain grading.

func _terrain_color_for_cell(cell: Vector2i, biome_kind: int, terrain: TerrainKind) -> Color: # Resolves continuous-looking procedural ground color from biome, geology, slope, and route shoulder fields.
    if terrain == TerrainKind.PATH: # Gives route cores a distinct dirt surface.
        return PATH_COLOR # Uses a restrained shared path color before per-vertex noise variation.
    var color: Color = _biome_ground_color(biome_kind) # Starts from the broad warped biome palette.
    var slope: float = float(slope_cache.get(cell, 0.0)) # Reads cached geometric steepness for exposed-stone blending.
    var stone_blend: float = clampf((slope - 0.25) / 0.75, 0.0, 0.72) # Gradually exposes rock as generated terrain gets steeper.
    if terrain == TerrainKind.STONE: # Ensures hard-terrain regions retain visible geology even on moderate slopes.
        stone_blend = maxf(stone_blend, 0.42) # Applies a minimum exposed-stone amount to logical STONE cells.
    color = color.lerp(STONE_COLOR, stone_blend) # Blends broad biome palette toward shared geology instead of hard color blocks.
    var route_distance: float = _route_distance_for_cell(cell) # Reads generated route proximity for natural dirt shoulders.
    if route_distance < PATH_SHOULDER: # Detects terrain inside the procedural route transition band.
        var shoulder_weight: float = clampf(1.0 - (route_distance - PATH_WIDTH) / maxf(PATH_SHOULDER - PATH_WIDTH, 0.01), 0.0, 1.0) # Produces a smooth dirt influence outside the route core.
        color = color.lerp(PATH_COLOR.darkened(0.12), shoulder_weight * 0.34) # Adds subtle worn ground around routes without changing terrain category.
    return color # Returns the base cell color before smaller per-vertex noise breakup.

func _vary_color(color: Color, variation: float) -> Color: # Applies restrained signed brightness breakup while preserving the source hue and alpha.
    var amount: float = clampf(variation * 0.075, -0.075, 0.075) # Caps noise influence so terrain never becomes speckled or high contrast.
    if amount >= 0.0: # Detects a positive brightness variation.
        return color.lightened(amount) # Lightens the base palette slightly at this vertex.
    return color.darkened(-amount) # Darkens the base palette slightly for negative field values.

func _create_vertex_ground_material() -> StandardMaterial3D: # Creates one terrain material that takes its albedo entirely from generated vertex colors.
    var material: StandardMaterial3D = StandardMaterial3D.new() # Creates a built-in physically based material without external textures.
    material.albedo_color = Color.WHITE # Leaves vertex colors un-tinted at the material level.
    material.vertex_color_use_as_albedo = true # Enables the SurfaceTool colors as terrain albedo according to Godot's BaseMaterial3D behavior.
    material.roughness = 0.96 # Keeps natural terrain broad and non-plastic under the global directional light.
    material.metallic = 0.0 # Keeps the shared terrain surface non-metallic across all generated biomes.
    material.cull_mode = BaseMaterial3D.CULL_DISABLED # Keeps generated terrain visible from both sides around steep edges and camera extremes.
    return material # Returns the shared generated terrain material.

func _create_ground_material(color: Color, roughness: float) -> StandardMaterial3D: # Creates a simple built-in material for generated object and depth meshes.
    var material: StandardMaterial3D = StandardMaterial3D.new() # Creates one physically based material resource.
    material.albedo_color = color # Applies the requested procedural palette color.
    material.roughness = roughness # Applies the requested surface roughness.
    material.cull_mode = BaseMaterial3D.CULL_DISABLED # Keeps low-poly procedural objects readable from all camera angles.
    return material # Returns the configured generated material.

func _create_double_sided_material(color: Color, roughness: float) -> StandardMaterial3D: # Creates a double-sided material for thin generated grass planes.
    var material: StandardMaterial3D = _create_ground_material(color, roughness) # Reuses the common simple material configuration.
    material.cull_mode = BaseMaterial3D.CULL_DISABLED # Explicitly preserves both sides of crossed vertical planes.
    return material # Returns the thin-geometry material.

func _create_water_material() -> StandardMaterial3D: # Creates the shared transparent material for all generated water fields.
    var material: StandardMaterial3D = StandardMaterial3D.new() # Creates one built-in physically based transparent material.
    material.albedo_color = WATER_COLOR # Applies the deeper shared water tone and alpha.
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA # Enables ordinary alpha transparency for the Compatibility renderer.
    material.roughness = 0.18 # Keeps water highlights tighter than surrounding rough terrain.
    material.metallic = 0.04 # Adds a restrained reflective response without making the water look metallic.
    material.cull_mode = BaseMaterial3D.CULL_DISABLED # Keeps water surfaces visible from camera extremes and shore transitions.
    return material # Returns the generated water material.

func _biome_ground_color(biome_kind: int) -> Color: # Returns restrained broad palettes used as inputs to continuous slope and route blending.
    match biome_kind: # Maps every Generation IV type region to a less saturated natural ground family.
        BiomeKind.NORMAL: # Defines meadow soil and grass color.
            return Color(0.36, 0.48, 0.27, 1.0) # Uses muted olive grass for the central region.
        BiomeKind.FIRE: # Defines volcanic soil color.
            return Color(0.33, 0.16, 0.11, 1.0) # Uses dark iron-rich brown-red ground.
        BiomeKind.WATER: # Defines lake-district bank color.
            return Color(0.25, 0.43, 0.35, 1.0) # Uses damp blue-green shoreline ground.
        BiomeKind.ELECTRIC: # Defines dry open plains color.
            return Color(0.48, 0.45, 0.20, 1.0) # Uses subdued yellow-olive grass rather than neon yellow.
        BiomeKind.GRASS: # Defines deep forest ground color.
            return Color(0.17, 0.39, 0.18, 1.0) # Uses rich dark green forest floor.
        BiomeKind.ICE: # Defines glacial stone and snow-base color.
            return Color(0.60, 0.72, 0.73, 1.0) # Uses cold desaturated blue-grey terrain.
        BiomeKind.FIGHTING: # Defines warm plateau earth color.
            return Color(0.43, 0.28, 0.21, 1.0) # Uses compact red-brown soil.
        BiomeKind.POISON: # Defines marsh soil color.
            return Color(0.31, 0.25, 0.33, 1.0) # Uses dark muted violet-brown ground.
        BiomeKind.GROUND: # Defines dry badlands color.
            return Color(0.49, 0.34, 0.18, 1.0) # Uses ochre-brown eroded earth.
        BiomeKind.FLYING: # Defines exposed wind plateau color.
            return Color(0.43, 0.52, 0.49, 1.0) # Uses cool desaturated highland ground.
        BiomeKind.PSYCHIC: # Defines unusual garden soil color.
            return Color(0.45, 0.31, 0.42, 1.0) # Uses restrained mauve terrain rather than bright type coding.
        BiomeKind.BUG: # Defines woodland floor color.
            return Color(0.33, 0.40, 0.16, 1.0) # Uses mossy yellow-green ground.
        BiomeKind.ROCK: # Defines mountain terrain color.
            return Color(0.36, 0.34, 0.29, 1.0) # Uses warm weathered stone.
        BiomeKind.GHOST: # Defines hollow terrain color.
            return Color(0.22, 0.23, 0.29, 1.0) # Uses cold dark slate ground.
        BiomeKind.DRAGON: # Defines high peak terrain color.
            return Color(0.27, 0.25, 0.34, 1.0) # Uses muted violet-grey stone.
        BiomeKind.DARK: # Defines dense forest floor color.
            return Color(0.16, 0.18, 0.17, 1.0) # Uses near-charcoal green-brown ground.
        BiomeKind.STEEL: # Defines industrial plateau terrain color.
            return Color(0.43, 0.45, 0.44, 1.0) # Uses neutral cool grey earth and exposed stone.
        _: # Handles unexpected biome indices defensively.
            return Color(0.35, 0.40, 0.30, 1.0) # Returns a neutral muted natural fallback.

func _accent_probability(biome_kind: int) -> float: # Returns sparse type-object probability for one generated biome.
    if biome_kind in [BiomeKind.ICE, BiomeKind.PSYCHIC, BiomeKind.GHOST, BiomeKind.ELECTRIC, BiomeKind.FIRE, BiomeKind.DRAGON, BiomeKind.STEEL]: # Detects regions where vertical accents materially improve silhouette.
        return 0.016 # Places recognizable but sparse accent objects away from routes.
    if biome_kind in [BiomeKind.ROCK, BiomeKind.GROUND, BiomeKind.POISON, BiomeKind.BUG]: # Detects regions where low natural accents add useful secondary detail.
        return 0.010 # Keeps accents quieter than the rock and vegetation systems already active there.
    return 0.005 # Gives remaining regions occasional minor objects without cluttering open areas.

func _accent_color(biome_kind: int) -> Color: # Returns restrained object colors that support type identity without painting the entire biome literally.
    match biome_kind: # Selects one palette family per type accent mesh.
        BiomeKind.FIRE: # Defines volcanic vent accent color.
            return Color(0.46, 0.16, 0.07, 1.0) # Uses dark burnt orange-red.
        BiomeKind.WATER: # Defines shoreline stone accent color.
            return Color(0.23, 0.43, 0.49, 1.0) # Uses muted wet blue-grey.
        BiomeKind.ELECTRIC: # Defines electrical crystal accent color.
            return Color(0.72, 0.61, 0.12, 1.0) # Uses subdued gold rather than neon yellow.
        BiomeKind.GRASS: # Defines forest-floor accent color.
            return Color(0.18, 0.42, 0.18, 1.0) # Uses strong natural green.
        BiomeKind.ICE: # Defines ice crystal accent color.
            return Color(0.64, 0.84, 0.88, 1.0) # Uses pale blue ice.
        BiomeKind.FIGHTING: # Defines training-stone accent color.
            return Color(0.48, 0.22, 0.16, 1.0) # Uses muted brick red.
        BiomeKind.POISON: # Defines marsh mineral accent color.
            return Color(0.47, 0.27, 0.50, 1.0) # Uses restrained purple.
        BiomeKind.GROUND: # Defines badland accent color.
            return Color(0.53, 0.36, 0.18, 1.0) # Uses weathered ochre.
        BiomeKind.FLYING: # Defines wind marker accent color.
            return Color(0.63, 0.72, 0.72, 1.0) # Uses pale highland grey-blue.
        BiomeKind.PSYCHIC: # Defines crystal garden accent color.
            return Color(0.67, 0.32, 0.57, 1.0) # Uses muted magenta-violet.
        BiomeKind.BUG: # Defines woodland mound accent color.
            return Color(0.47, 0.55, 0.14, 1.0) # Uses mossy yellow-green.
        BiomeKind.ROCK: # Defines mountain accent color.
            return Color(0.42, 0.39, 0.31, 1.0) # Uses warm natural rock.
        BiomeKind.GHOST: # Defines ghost crystal accent color.
            return Color(0.38, 0.31, 0.48, 1.0) # Uses dark desaturated violet.
        BiomeKind.DRAGON: # Defines peak pillar accent color.
            return Color(0.38, 0.28, 0.49, 1.0) # Uses muted deep violet.
        BiomeKind.DARK: # Defines dark forest mound accent color.
            return Color(0.18, 0.17, 0.20, 1.0) # Uses near-black violet-grey.
        BiomeKind.STEEL: # Defines industrial pillar accent color.
            return Color(0.53, 0.57, 0.58, 1.0) # Uses neutral steel grey.
        _: # Handles Normal and any unexpected biome index.
            return Color(0.55, 0.49, 0.32, 1.0) # Uses subdued warm stone for the central meadow.

func _accent_height_offset(biome_kind: int) -> float: # Returns the local grounding offset appropriate to each procedural accent source mesh.
    if biome_kind in [BiomeKind.ICE, BiomeKind.PSYCHIC, BiomeKind.GHOST, BiomeKind.ELECTRIC, BiomeKind.FIRE, BiomeKind.DRAGON, BiomeKind.STEEL, BiomeKind.FLYING]: # Detects tall cylinder-derived accents.
        return 0.78 # Raises tapered crystals and pillars by half their approximate source height.
    return 0.28 # Raises low sphere-derived accents by roughly half their flattened source height.

func _biome_slug(biome_kind: int) -> String: # Returns a stable snake-case diagnostic name for generated biome batches.
    match biome_kind: # Maps every biome enum to one runtime node-name fragment.
        BiomeKind.NORMAL: # Handles the Normal biome.
            return "normal" # Names Normal-region generated nodes.
        BiomeKind.FIRE: # Handles the Fire biome.
            return "fire" # Names Fire-region generated nodes.
        BiomeKind.WATER: # Handles the Water biome.
            return "water" # Names Water-region generated nodes.
        BiomeKind.ELECTRIC: # Handles the Electric biome.
            return "electric" # Names Electric-region generated nodes.
        BiomeKind.GRASS: # Handles the Grass biome.
            return "grass" # Names Grass-region generated nodes.
        BiomeKind.ICE: # Handles the Ice biome.
            return "ice" # Names Ice-region generated nodes.
        BiomeKind.FIGHTING: # Handles the Fighting biome.
            return "fighting" # Names Fighting-region generated nodes.
        BiomeKind.POISON: # Handles the Poison biome.
            return "poison" # Names Poison-region generated nodes.
        BiomeKind.GROUND: # Handles the Ground biome.
            return "ground" # Names Ground-region generated nodes.
        BiomeKind.FLYING: # Handles the Flying biome.
            return "flying" # Names Flying-region generated nodes.
        BiomeKind.PSYCHIC: # Handles the Psychic biome.
            return "psychic" # Names Psychic-region generated nodes.
        BiomeKind.BUG: # Handles the Bug biome.
            return "bug" # Names Bug-region generated nodes.
        BiomeKind.ROCK: # Handles the Rock biome.
            return "rock" # Names Rock-region generated nodes.
        BiomeKind.GHOST: # Handles the Ghost biome.
            return "ghost" # Names Ghost-region generated nodes.
        BiomeKind.DRAGON: # Handles the Dragon biome.
            return "dragon" # Names Dragon-region generated nodes.
        BiomeKind.DARK: # Handles the Dark biome.
            return "dark" # Names Dark-region generated nodes.
        BiomeKind.STEEL: # Handles the Steel biome.
            return "steel" # Names Steel-region generated nodes.
        _: # Handles unexpected biome values.
            return "unknown" # Names unexpected biome values defensively.

func _prepare_entry_points() -> void: # Rebuilds four deterministic world-edge entry pairs aligned with generated route extensions.
    entry_spawn_positions.clear() # Removes any stale global entry positions.
    entry_target_positions.clear() # Removes any stale global first-target positions.
    _append_entry(_local_to_cell(WORLD_EXIT_POINTS[0]), Vector3(0.0, 0.0, -TILE_SIZE * 4.0)) # Creates the southern Rock-region entrance.
    _append_entry(_local_to_cell(WORLD_EXIT_POINTS[1]), Vector3(0.0, 0.0, TILE_SIZE * 4.0)) # Creates the northern Electric-region entrance.
    _append_entry(_local_to_cell(WORLD_EXIT_POINTS[2]), Vector3(-TILE_SIZE * 4.0, 0.0, 0.0)) # Creates the western Bug-region entrance.
    _append_entry(_local_to_cell(WORLD_EXIT_POINTS[3]), Vector3(TILE_SIZE * 4.0, 0.0, 0.0)) # Creates the eastern Ghost-region entrance.

func _append_entry(cell: Vector2i, outward_offset: Vector3) -> void: # Adds one global edge spawn position and its first generated in-world target.
    var target_position: Vector3 = cell_to_world(cell) # Resolves the generated terrain position at the world-edge route cell.
    var spawn_position: Vector3 = target_position + outward_offset # Moves the spawn point a short distance outside the playable world.
    spawn_position.y = target_position.y + 0.10 # Keeps the outside spawn point vertically aligned with the generated route edge.
    entry_spawn_positions.append(spawn_position) # Stores the outside spawn position.
    entry_target_positions.append(target_position) # Stores the matching first in-world target position.

func _terrain_for_cell(cell: Vector2i) -> TerrainKind: # Reads cached logical terrain with water as the safe out-of-bounds fallback.
    if not _is_cell_in_bounds(cell): # Detects coordinates beyond the generated world rectangle.
        return TerrainKind.WATER # Treats outside space as non-walkable water-like terrain.
    return terrain_cache.get(cell, TerrainKind.LAND) as TerrainKind # Returns cached terrain or a soft-ground fallback during defensive queries.

func _biome_for_cell(cell: Vector2i) -> BiomeKind: # Reads cached warped biome ownership with Normal as the safe out-of-bounds fallback.
    if not _is_cell_in_bounds(cell): # Detects coordinates beyond the generated world rectangle.
        return BiomeKind.NORMAL # Returns the central neutral region for defensive off-map queries.
    return biome_cache.get(cell, BiomeKind.NORMAL) as BiomeKind # Returns cached warped biome ownership.

func _cell_to_local_2d(cell: Vector2i) -> Vector2: # Converts one logical cell center into centered generation-field coordinates.
    return Vector2(float(cell.x) - float(WORLD_WIDTH) * 0.5 + 0.5, float(cell.y) - float(WORLD_DEPTH) * 0.5 + 0.5) # Returns cell-space coordinates independent from world TILE_SIZE scaling.

func _local_to_cell(local: Vector2) -> Vector2i: # Converts centered generation-field coordinates into one logical cell index.
    return Vector2i(int(floor(local.x + float(WORLD_WIDTH) * 0.5)), int(floor(local.y + float(WORLD_DEPTH) * 0.5))) # Returns the containing logical cell.

func _is_cell_in_bounds(cell: Vector2i) -> bool: # Reports whether one logical coordinate lies inside the generated world rectangle.
    return cell.x >= 0 and cell.y >= 0 and cell.x < WORLD_WIDTH and cell.y < WORLD_DEPTH # Performs branch-light integer bounds checks.

func _hash01(cell: Vector2i, salt: int) -> float: # Returns a deterministic zero-to-one sample used only after continuous fields establish spatial density.
    var value: float = sin(float(cell.x) * 12.9898 + float(cell.y) * 78.233 + float(world_seed + salt) * 0.0137) * 43758.5453123 # Mixes cell coordinates, seed, and independent salt without mutable RNG state.
    return value - floor(value) # Keeps only the fractional component as a stable zero-to-one sample.
