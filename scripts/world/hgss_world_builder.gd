class_name HgssWorldBuilder # Owns the enlarged procedural type-biome world, collision, scenery, and habitat queries.
extends Node3D

enum TerrainKind { LAND, PATH, WATER, STONE }
enum BiomeKind { NORMAL, FIRE, WATER, ELECTRIC, GRASS, ICE, FIGHTING, POISON, GROUND, FLYING, PSYCHIC, BUG, ROCK, GHOST, DRAGON, DARK, STEEL }

const WORLD_WIDTH: int = 264 # Produces a world about 396 units wide at the existing gameplay scale.
const WORLD_DEPTH: int = 216 # Produces a world about 324 units deep with room for broad biome interiors.
const TILE_SIZE: float = 1.5
const WATER_LEVEL: float = -0.62
const TREE_BLOCKER_HEIGHT: float = 3.4
const PATH_WIDTH: float = 2.6
const PATH_SHOULDER: float = 6.0

const PATH_COLOR: Color = Color(0.73, 0.63, 0.43, 1.0)
const WATER_COLOR: Color = Color(0.20, 0.52, 0.78, 0.80)
const WATER_DEPTH_COLOR: Color = Color(0.07, 0.24, 0.38, 1.0)
const STONE_COLOR: Color = Color(0.48, 0.49, 0.48, 1.0)
const TREE_TRUNK_COLOR: Color = Color(0.30, 0.18, 0.09, 1.0)
const GRASS_CANOPY_COLOR: Color = Color(0.18, 0.46, 0.20, 1.0)
const BUG_CANOPY_COLOR: Color = Color(0.42, 0.55, 0.16, 1.0)
const DARK_CANOPY_COLOR: Color = Color(0.16, 0.16, 0.25, 1.0)
const BRIDGE_COLOR: Color = Color(0.45, 0.28, 0.13, 1.0)

const BIOME_CENTERS: Array[Vector2] = [
    Vector2(0.0, 20.0), Vector2(100.0, -26.0), Vector2(94.0, 72.0), Vector2(34.0, 72.0), Vector2(-52.0, 20.0),
    Vector2(-31.0, -76.0), Vector2(-50.0, -26.0), Vector2(-90.0, 72.0), Vector2(-100.0, -26.0), Vector2(31.0, -76.0),
    Vector2(54.0, 20.0), Vector2(-102.0, 20.0), Vector2(-92.0, -76.0), Vector2(104.0, 20.0), Vector2(92.0, -76.0),
    Vector2(-30.0, 72.0), Vector2(50.0, -26.0),
]

const PATH_EDGES: Array[Vector2i] = [
    Vector2i(BiomeKind.ROCK, BiomeKind.ICE), Vector2i(BiomeKind.ICE, BiomeKind.FLYING), Vector2i(BiomeKind.FLYING, BiomeKind.DRAGON),
    Vector2i(BiomeKind.GROUND, BiomeKind.FIGHTING), Vector2i(BiomeKind.FIGHTING, BiomeKind.STEEL), Vector2i(BiomeKind.STEEL, BiomeKind.FIRE),
    Vector2i(BiomeKind.BUG, BiomeKind.GRASS), Vector2i(BiomeKind.GRASS, BiomeKind.NORMAL), Vector2i(BiomeKind.NORMAL, BiomeKind.PSYCHIC), Vector2i(BiomeKind.PSYCHIC, BiomeKind.GHOST),
    Vector2i(BiomeKind.POISON, BiomeKind.DARK), Vector2i(BiomeKind.DARK, BiomeKind.ELECTRIC), Vector2i(BiomeKind.ELECTRIC, BiomeKind.WATER),
    Vector2i(BiomeKind.ROCK, BiomeKind.GROUND), Vector2i(BiomeKind.GROUND, BiomeKind.BUG), Vector2i(BiomeKind.BUG, BiomeKind.POISON),
    Vector2i(BiomeKind.ICE, BiomeKind.FIGHTING), Vector2i(BiomeKind.FIGHTING, BiomeKind.GRASS), Vector2i(BiomeKind.GRASS, BiomeKind.DARK),
    Vector2i(BiomeKind.FLYING, BiomeKind.STEEL), Vector2i(BiomeKind.STEEL, BiomeKind.PSYCHIC), Vector2i(BiomeKind.PSYCHIC, BiomeKind.ELECTRIC),
    Vector2i(BiomeKind.DRAGON, BiomeKind.FIRE), Vector2i(BiomeKind.FIRE, BiomeKind.GHOST), Vector2i(BiomeKind.GHOST, BiomeKind.WATER),
    Vector2i(BiomeKind.NORMAL, BiomeKind.FIGHTING), Vector2i(BiomeKind.NORMAL, BiomeKind.STEEL), Vector2i(BiomeKind.NORMAL, BiomeKind.DARK), Vector2i(BiomeKind.NORMAL, BiomeKind.ELECTRIC),
]

var blocked_cells: Dictionary = {}
var terrain_cache: Dictionary = {}
var biome_cache: Dictionary = {}
var biome_spawn_cells: Dictionary = {} # Non-path walkable habitat cells grouped by type.
var biome_entry_cells: Dictionary = {} # Walkable path cells at type-region borders used for entry and departure.
var entry_spawn_positions: Array[Vector3] = []
var entry_target_positions: Array[Vector3] = []

func _ready() -> void:
    add_to_group(&"world_builder")
    _prepare_layout_cache()
    _prune_isolated_walkable_regions()
    _rebuild_biome_spawn_cache()
    _build_terrain_geometry()
    _build_environment_visuals()
    _prepare_entry_points()

func get_random_biome_entry_pair(biome_kind: int, random: RandomNumberGenerator) -> Array[Vector3]: # Starts a Pokémon on a route crossing its habitat boundary and points it inward.
    var entries: Array = biome_entry_cells.get(biome_kind, [])
    if entries.is_empty():
        var fallback: Vector3 = get_random_walkable_world_position_in_biome(biome_kind, random)
        return [fallback, get_random_walkable_world_position_near_in_biome(fallback, 18.0, biome_kind, random)]
    var entry_cell: Vector2i = entries[random.randi_range(0, entries.size() - 1)]
    var entry_position: Vector3 = cell_to_world(entry_cell)
    var target_position: Vector3 = get_random_walkable_world_position_near_in_biome(entry_position, 20.0, biome_kind, random)
    return [entry_position, target_position]

func get_biome_exit_target_from(world_position: Vector3, biome_kind: int) -> Vector3: # Returns the nearest path/border cell belonging to one type region.
    var entries: Array = biome_entry_cells.get(biome_kind, [])
    if entries.is_empty():
        return get_random_walkable_world_position_in_biome(biome_kind, RandomNumberGenerator.new())
    var best_cell: Vector2i = entries[0]
    var best_position: Vector3 = cell_to_world(best_cell)
    var best_distance: float = world_position.distance_squared_to(best_position)
    for value: Variant in entries:
        var cell: Vector2i = value
        var candidate: Vector3 = cell_to_world(cell)
        var distance: float = world_position.distance_squared_to(candidate)
        if distance < best_distance:
            best_distance = distance
            best_position = candidate
    return best_position

func get_random_walkable_world_position_in_biome(biome_kind: int, random: RandomNumberGenerator) -> Vector3: # Picks a cached interior habitat cell without scanning the expanded map per spawn.
    var cells: Array = biome_spawn_cells.get(biome_kind, [])
    if cells.is_empty():
        return get_nearest_walkable_world_position(Vector3(BIOME_CENTERS[biome_kind].x * TILE_SIZE, 0.0, BIOME_CENTERS[biome_kind].y * TILE_SIZE))
    return cell_to_world(cells[random.randi_range(0, cells.size() - 1)])

func get_random_walkable_world_position_near_in_biome(world_position: Vector3, radius: float, biome_kind: int, random: RandomNumberGenerator) -> Vector3: # Keeps local wandering inside the assigned habitat.
    var centre_cell: Vector2i = world_to_cell(world_position)
    var radius_cells: int = maxi(1, int(ceil(radius / TILE_SIZE)))
    for attempt: int in range(64):
        var candidate: Vector2i = centre_cell + Vector2i(random.randi_range(-radius_cells, radius_cells), random.randi_range(-radius_cells, radius_cells))
        if is_cell_walkable(candidate) and _biome_for_cell(candidate) == biome_kind:
            return cell_to_world(candidate)
    if is_cell_walkable(centre_cell) and _biome_for_cell(centre_cell) == biome_kind:
        return cell_to_world(centre_cell)
    return get_random_walkable_world_position_in_biome(biome_kind, random)

func get_random_entry_pair(random: RandomNumberGenerator) -> Array[Vector3]:
    if entry_spawn_positions.is_empty(): _prepare_entry_points()
    var index: int = random.randi_range(0, entry_spawn_positions.size() - 1)
    return [entry_spawn_positions[index], entry_target_positions[index]]

func get_exit_target_from(world_position: Vector3) -> Vector3:
    if entry_spawn_positions.is_empty(): _prepare_entry_points()
    var best: Vector3 = entry_spawn_positions[0]
    var best_distance: float = world_position.distance_squared_to(best)
    for candidate: Vector3 in entry_spawn_positions:
        var distance: float = world_position.distance_squared_to(candidate)
        if distance < best_distance:
            best_distance = distance
            best = candidate
    return best

func get_random_walkable_world_position_near(world_position: Vector3, radius: float, random: RandomNumberGenerator) -> Vector3:
    var centre_cell: Vector2i = world_to_cell(world_position)
    var radius_cells: int = maxi(1, int(ceil(radius / TILE_SIZE)))
    for attempt: int in range(48):
        var candidate: Vector2i = centre_cell + Vector2i(random.randi_range(-radius_cells, radius_cells), random.randi_range(-radius_cells, radius_cells))
        if is_cell_walkable(candidate): return cell_to_world(candidate)
    if is_cell_walkable(centre_cell): return cell_to_world(centre_cell)
    return get_nearest_walkable_world_position(world_position)

func get_nearest_walkable_world_position(world_position: Vector3) -> Vector3:
    var centre_cell: Vector2i = world_to_cell(world_position)
    for radius_cells: int in range(0, 40):
        for offset_x: int in range(-radius_cells, radius_cells + 1):
            for offset_z: int in range(-radius_cells, radius_cells + 1):
                var candidate: Vector2i = centre_cell + Vector2i(offset_x, offset_z)
                if is_cell_walkable(candidate): return cell_to_world(candidate)
    return Vector3.ZERO

func is_cell_walkable(cell: Vector2i) -> bool:
    return _is_cell_in_bounds(cell) and not blocked_cells.has(cell) and _terrain_for_cell(cell) != TerrainKind.WATER

func cell_to_world(cell: Vector2i) -> Vector3:
    var local_x: float = (float(cell.x) - float(WORLD_WIDTH) * 0.5 + 0.5) * TILE_SIZE
    var local_z: float = (float(cell.y) - float(WORLD_DEPTH) * 0.5 + 0.5) * TILE_SIZE
    return Vector3(local_x, _sample_height(local_x / TILE_SIZE, local_z / TILE_SIZE) + 0.06, local_z)

func world_to_cell(world_position: Vector3) -> Vector2i:
    return Vector2i(int(floor(world_position.x / TILE_SIZE + float(WORLD_WIDTH) * 0.5)), int(floor(world_position.z / TILE_SIZE + float(WORLD_DEPTH) * 0.5)))

func _prepare_layout_cache() -> void:
    blocked_cells.clear(); terrain_cache.clear(); biome_cache.clear()
    for z: int in range(WORLD_DEPTH):
        for x: int in range(WORLD_WIDTH):
            var cell := Vector2i(x, z)
            var local := _cell_to_local_2d(cell)
            var biome: BiomeKind = _calculate_biome_for_local(local)
            var terrain: TerrainKind = _calculate_terrain_for_local(local, biome)
            biome_cache[cell] = biome; terrain_cache[cell] = terrain
            if _calculate_tree_for_cell(cell, local, biome, terrain): blocked_cells[cell] = true

func _prune_isolated_walkable_regions() -> void:
    var start := _local_to_cell(BIOME_CENTERS[BiomeKind.NORMAL])
    if not is_cell_walkable(start): return
    var reachable: Dictionary = {start: true}
    var queue: Array[Vector2i] = [start]
    var index := 0
    while index < queue.size():
        var cell := queue[index]; index += 1
        for neighbour: Vector2i in [cell + Vector2i.RIGHT, cell + Vector2i.LEFT, cell + Vector2i.UP, cell + Vector2i.DOWN]:
            if reachable.has(neighbour) or not is_cell_walkable(neighbour): continue
            reachable[neighbour] = true; queue.append(neighbour)
    for z: int in range(WORLD_DEPTH):
        for x: int in range(WORLD_WIDTH):
            var cell := Vector2i(x, z)
            if _terrain_for_cell(cell) != TerrainKind.WATER and not reachable.has(cell) and not blocked_cells.has(cell): blocked_cells[cell] = true

func _rebuild_biome_spawn_cache() -> void:
    biome_spawn_cells.clear(); biome_entry_cells.clear()
    for biome: int in range(BiomeKind.size()):
        biome_spawn_cells[biome] = []; biome_entry_cells[biome] = []
    for z: int in range(WORLD_DEPTH):
        for x: int in range(WORLD_WIDTH):
            var cell := Vector2i(x, z)
            if not is_cell_walkable(cell): continue
            var biome: int = _biome_for_cell(cell)
            var terrain: TerrainKind = _terrain_for_cell(cell)
            if terrain != TerrainKind.PATH:
                var spawn_cells: Array = biome_spawn_cells[biome]; spawn_cells.append(cell); biome_spawn_cells[biome] = spawn_cells
            elif _is_biome_boundary_cell(cell, biome):
                var entry_cells: Array = biome_entry_cells[biome]; entry_cells.append(cell); biome_entry_cells[biome] = entry_cells

func _is_biome_boundary_cell(cell: Vector2i, biome_kind: int) -> bool:
    for neighbour: Vector2i in [cell + Vector2i.RIGHT, cell + Vector2i.LEFT, cell + Vector2i.UP, cell + Vector2i.DOWN]:
        if _is_cell_in_bounds(neighbour) and _biome_for_cell(neighbour) != biome_kind: return true
    return false

func _build_terrain_geometry() -> void:
    var tools: Dictionary = {}; var counts: Dictionary = {}
    for biome: int in range(BiomeKind.size()):
        for terrain: int in range(TerrainKind.size()):
            var key := _surface_key(biome, terrain); var tool := SurfaceTool.new(); tool.begin(Mesh.PRIMITIVE_TRIANGLES); tool.set_material(_create_terrain_material(biome, terrain)); tools[key] = tool; counts[key] = 0
    var faces := PackedVector3Array()
    for z: int in range(WORLD_DEPTH):
        for x: int in range(WORLD_WIDTH):
            var cell := Vector2i(x, z); var biome: BiomeKind = _biome_for_cell(cell); var terrain: TerrainKind = _terrain_for_cell(cell); var corners := _get_cell_corners(cell, terrain); var key := _surface_key(biome, terrain); var tool: SurfaceTool = tools[key]
            _append_quad_to_surface(tool, corners); counts[key] = int(counts[key]) + 6
            if terrain != TerrainKind.WATER: _append_quad_faces(faces, corners); _append_water_boundary_faces(cell, corners, faces)
            if blocked_cells.has(cell): _append_blocker_faces(corners, faces)
    for biome: int in range(BiomeKind.size()):
        for terrain: int in range(TerrainKind.size()):
            var key := _surface_key(biome, terrain)
            if int(counts[key]) == 0: continue
            var tool: SurfaceTool = tools[key]; tool.generate_normals(); var instance := MeshInstance3D.new(); instance.name = "terrain_%s_%s" % [_biome_slug(biome), str(terrain)]; instance.mesh = tool.commit(); instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(instance)
    var body := StaticBody3D.new(); body.name = "generated_world_collision"; body.collision_layer = 1; body.collision_mask = 0
    var collision := CollisionShape3D.new(); var shape := ConcavePolygonShape3D.new(); shape.backface_collision = true; shape.set_faces(faces); collision.shape = shape; body.add_child(collision); add_child(body)

func _build_environment_visuals() -> void:
    _build_water_depth_visual(); _build_tree_visuals(); _build_bridge_visuals(); _build_type_landmarks()

func _build_water_depth_visual() -> void:
    var depth := SurfaceTool.new(); depth.begin(Mesh.PRIMITIVE_TRIANGLES); depth.set_material(_create_ground_material(WATER_DEPTH_COLOR, 1.0))
    var bridge_water := SurfaceTool.new(); bridge_water.begin(Mesh.PRIMITIVE_TRIANGLES); bridge_water.set_material(_create_water_material())
    var depth_count := 0; var bridge_count := 0
    for z: int in range(WORLD_DEPTH):
        for x: int in range(WORLD_WIDTH):
            var cell := Vector2i(x,z); var local := _cell_to_local_2d(cell); var biome: BiomeKind = _biome_for_cell(cell)
            if not _is_water_feature(local, biome): continue
            var surface := _water_corners_for_cell(cell); var lower := surface.duplicate()
            for i: int in range(lower.size()): lower[i].y = WATER_LEVEL - 0.85
            _append_quad_to_surface(depth, lower); depth_count += 6
            if _terrain_for_cell(cell) == TerrainKind.PATH: _append_quad_to_surface(bridge_water, surface); bridge_count += 6
    if depth_count > 0: depth.generate_normals(); var d := MeshInstance3D.new(); d.name = "water_depth"; d.mesh = depth.commit(); d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(d)
    if bridge_count > 0: bridge_water.generate_normals(); var b := MeshInstance3D.new(); b.name = "water_under_bridges"; b.mesh = bridge_water.commit(); b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(b)

func _build_tree_visuals() -> void:
    var all: Array[Vector2i] = []; var grass: Array[Vector2i] = []; var bug: Array[Vector2i] = []; var dark: Array[Vector2i] = []
    for key: Variant in blocked_cells.keys():
        var cell: Vector2i = key; all.append(cell)
        match _biome_for_cell(cell):
            BiomeKind.BUG: bug.append(cell)
            BiomeKind.DARK, BiomeKind.GHOST: dark.append(cell)
            _: grass.append(cell)
    if all.is_empty(): return
    var trunk := CylinderMesh.new(); trunk.top_radius = 0.20; trunk.bottom_radius = 0.31; trunk.height = 1.7; trunk.radial_segments = 7; trunk.rings = 1; trunk.material = _create_ground_material(TREE_TRUNK_COLOR, 0.98)
    _create_cell_multimesh("tree_trunks", trunk, all, 0.88, 0.88, 1.15, 11); _build_canopy_group("grass_canopy", grass, GRASS_CANOPY_COLOR, 13); _build_canopy_group("bug_canopy", bug, BUG_CANOPY_COLOR, 17); _build_canopy_group("dark_canopy", dark, DARK_CANOPY_COLOR, 23)

func _build_canopy_group(prefix: String, cells: Array[Vector2i], color: Color, salt: int) -> void:
    if cells.is_empty(): return
    var lower := SphereMesh.new(); lower.radius = 0.92; lower.height = 1.45; lower.radial_segments = 8; lower.rings = 4; lower.material = _create_ground_material(color.darkened(0.12), 0.92)
    var upper := SphereMesh.new(); upper.radius = 0.68; upper.height = 1.08; upper.radial_segments = 8; upper.rings = 4; upper.material = _create_ground_material(color, 0.92)
    _create_cell_multimesh(prefix + "_lower", lower, cells, 2.02, 0.9, 1.12, salt); _create_cell_multimesh(prefix + "_upper", upper, cells, 2.75, 0.9, 1.12, salt)

func _build_bridge_visuals() -> void:
    var cells: Array[Vector2i] = []
    for z: int in range(WORLD_DEPTH):
        for x: int in range(WORLD_WIDTH):
            var cell := Vector2i(x,z)
            if _terrain_for_cell(cell) == TerrainKind.PATH and _is_water_feature(_cell_to_local_2d(cell), _biome_for_cell(cell)): cells.append(cell)
    if cells.is_empty(): return
    var mesh := BoxMesh.new(); mesh.size = Vector3(TILE_SIZE * 0.96, 0.14, TILE_SIZE * 0.96); mesh.material = _create_ground_material(BRIDGE_COLOR, 0.84); _create_cell_multimesh("bridge_decks", mesh, cells, 0.10, 1.0, 1.0, 29)

func _build_type_landmarks() -> void: # Scatters sparse secondary motifs so the enlarged regions have visual texture between major destinations.
    for biome: int in range(BiomeKind.size()):
        var cells: Array[Vector2i] = []
        for z: int in range(WORLD_DEPTH):
            for x: int in range(WORLD_WIDTH):
                var cell := Vector2i(x,z)
                if _biome_for_cell(cell) != biome or blocked_cells.has(cell): continue
                var terrain: TerrainKind = _terrain_for_cell(cell)
                if terrain == TerrainKind.PATH or terrain == TerrainKind.WATER or _path_distance(_cell_to_local_2d(cell)) < PATH_SHOULDER + 2.0: continue
                if _hash01(cell, 101 + biome * 13) > _landmark_threshold(biome): cells.append(cell)
        if cells.is_empty(): continue
        _create_cell_multimesh("%s_landmarks" % _biome_slug(biome), _create_landmark_mesh(biome), cells, _landmark_height_offset(biome), 0.82, 1.25, 151 + biome)

func _create_landmark_mesh(biome: int) -> Mesh:
    var material := _create_ground_material(_landmark_color(biome), _landmark_roughness(biome))
    if biome in [BiomeKind.FIRE, BiomeKind.FIGHTING, BiomeKind.FLYING, BiomeKind.DRAGON, BiomeKind.STEEL, BiomeKind.ELECTRIC]:
        var pillar := CylinderMesh.new(); pillar.top_radius = 0.12 if biome == BiomeKind.DRAGON else 0.24; pillar.bottom_radius = 0.38; pillar.height = 2.1 if biome != BiomeKind.ELECTRIC else 2.7; pillar.radial_segments = 6; pillar.material = material; return pillar
    if biome in [BiomeKind.ICE, BiomeKind.PSYCHIC, BiomeKind.GHOST]:
        var monolith := BoxMesh.new(); monolith.size = Vector3(0.55, 1.9, 0.55); monolith.material = material; return monolith
    var boulder := SphereMesh.new(); boulder.radius = 0.48; boulder.height = 0.72; boulder.radial_segments = 6; boulder.rings = 3; boulder.material = material; return boulder

func _calculate_biome_for_local(local: Vector2) -> BiomeKind:
    var best := BiomeKind.NORMAL; var best_distance := INF
    for biome: int in range(BiomeKind.size()):
        var distance := local.distance_squared_to(BIOME_CENTERS[biome])
        if distance < best_distance: best_distance = distance; best = biome
    return best as BiomeKind

func _calculate_terrain_for_local(local: Vector2, biome: BiomeKind) -> TerrainKind:
    if _is_path(local): return TerrainKind.PATH
    if _is_water_feature(local, biome): return TerrainKind.WATER
    if biome in [BiomeKind.ROCK, BiomeKind.ICE, BiomeKind.DRAGON, BiomeKind.GROUND, BiomeKind.STEEL, BiomeKind.FLYING]: return TerrainKind.STONE
    return TerrainKind.LAND

func _calculate_tree_for_cell(cell: Vector2i, local: Vector2, biome: BiomeKind, terrain: TerrainKind) -> bool:
    if terrain != TerrainKind.LAND or _path_distance(local) < PATH_SHOULDER: return false
    var distance := local.distance_to(BIOME_CENTERS[biome]); var density := _hash01(cell, 7)
    match biome:
        BiomeKind.GRASS: return distance > 9.0 and distance < 33.0 and density > 0.31
        BiomeKind.BUG: return distance > 8.0 and distance < 29.0 and density > 0.40
        BiomeKind.DARK: return distance > 10.0 and distance < 34.0 and density > 0.35
        BiomeKind.GHOST: return distance > 15.0 and distance < 29.0 and density > 0.69
        _: return false

func _is_water_feature(local: Vector2, biome: BiomeKind) -> bool:
    if biome == BiomeKind.WATER:
        var center := BIOME_CENTERS[BiomeKind.WATER]; var relative := local - center
        var lake := Vector2(relative.x / 29.0, relative.y / 23.0).length_squared() < 1.0
        var cove := Vector2((relative.x + 19.0) / 13.0, (relative.y + 12.0) / 9.0).length_squared() < 1.0
        var inlet := absf(relative.x - 21.0) < 5.0 and relative.y > -18.0 and relative.y < 14.0
        var island := Vector2((relative.x + 2.0) / 7.5, (relative.y - 1.0) / 5.5).length_squared() < 1.0
        return (lake or cove or inlet) and not island
    if biome == BiomeKind.POISON:
        var r := local - BIOME_CENTERS[BiomeKind.POISON]; var marsh := Vector2(r.x / 27.0, r.y / 21.0).length_squared() < 1.0
        return marsh and (sin(local.x * 0.34) + cos(local.y * 0.31) + sin((local.x + local.y) * 0.19)) > 1.35
    return false

func _is_path(local: Vector2) -> bool: return _path_distance(local) <= PATH_WIDTH

func _path_distance(local: Vector2) -> float:
    var best := INF
    for edge: Vector2i in PATH_EDGES: best = minf(best, _distance_to_segment(local, BIOME_CENTERS[edge.x], BIOME_CENTERS[edge.y]))
    best = minf(best, _distance_to_segment(local, BIOME_CENTERS[BiomeKind.ROCK], Vector2(-92.0, -107.0)))
    best = minf(best, _distance_to_segment(local, BIOME_CENTERS[BiomeKind.ELECTRIC], Vector2(34.0, 107.0)))
    best = minf(best, _distance_to_segment(local, BIOME_CENTERS[BiomeKind.BUG], Vector2(-131.0, 20.0)))
    best = minf(best, _distance_to_segment(local, BIOME_CENTERS[BiomeKind.GHOST], Vector2(131.0, 20.0)))
    return best

func _distance_to_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
    var segment := finish - start; var length_squared := segment.length_squared()
    if length_squared <= 0.0001: return point.distance_to(start)
    var progress := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
    return point.distance_to(start + segment * progress)

func _sample_height(x: float, z: float) -> float: # Blends broad terrain forms so each biome has a distinct silhouette without hard border steps.
    var p := Vector2(x,z)
    var height := sin(x * 0.045) * cos(z * 0.041) * 0.28 + sin((x + z) * 0.025) * 0.18
    height += _gaussian_height(p, BIOME_CENTERS[BiomeKind.ROCK], 38.0, 6.4) + _gaussian_height(p, BIOME_CENTERS[BiomeKind.ROCK] + Vector2(-13, 7), 17.0, 3.4) + _gaussian_height(p, BIOME_CENTERS[BiomeKind.ROCK] + Vector2(14, -5), 15.0, 2.8)
    height += _gaussian_height(p, BIOME_CENTERS[BiomeKind.DRAGON], 35.0, 7.0) + _gaussian_height(p, BIOME_CENTERS[BiomeKind.DRAGON] + Vector2(-12, 8), 13.0, 3.0) + _gaussian_height(p, BIOME_CENTERS[BiomeKind.DRAGON] + Vector2(14, 5), 12.0, 3.4)
    height += _gaussian_height(p, BIOME_CENTERS[BiomeKind.ICE], 34.0, 4.6) + _gaussian_height(p, BIOME_CENTERS[BiomeKind.FLYING], 35.0, 4.8)
    height += _gaussian_height(p, BIOME_CENTERS[BiomeKind.FIRE], 34.0, 5.1) - _gaussian_height(p, BIOME_CENTERS[BiomeKind.FIRE], 10.0, 2.5)
    height += _gaussian_height(p, BIOME_CENTERS[BiomeKind.GROUND], 38.0, 2.8) + sin((x + 20.0) * 0.16) * _gaussian_weight(p, BIOME_CENTERS[BiomeKind.GROUND], 34.0) * 0.8
    height += _gaussian_height(p, BIOME_CENTERS[BiomeKind.FIGHTING], 31.0, 2.0) + _gaussian_height(p, BIOME_CENTERS[BiomeKind.STEEL], 30.0, 1.7)
    height += _gaussian_height(p, BIOME_CENTERS[BiomeKind.PSYCHIC], 28.0, 1.3) + _gaussian_height(p, BIOME_CENTERS[BiomeKind.GRASS], 34.0, 1.0)
    height += _gaussian_height(p, BIOME_CENTERS[BiomeKind.GHOST], 34.0, 1.0) - _gaussian_height(p, BIOME_CENTERS[BiomeKind.GHOST], 15.0, 1.8)
    height -= _gaussian_height(p, BIOME_CENTERS[BiomeKind.WATER], 38.0, 1.05) + _gaussian_height(p, BIOME_CENTERS[BiomeKind.POISON], 34.0, 0.65)
    height += sin(x * 0.19) * cos(z * 0.14) * _gaussian_weight(p, BIOME_CENTERS[BiomeKind.ROCK], 34.0) * 0.8
    height += sin((x - z) * 0.18) * _gaussian_weight(p, BIOME_CENTERS[BiomeKind.DRAGON], 31.0) * 0.75
    return height

func _gaussian_weight(local: Vector2, center: Vector2, radius: float) -> float:
    var offset := (local - center) / radius; return exp(-offset.length_squared() * 2.0)
func _gaussian_height(local: Vector2, center: Vector2, radius: float, amplitude: float) -> float: return _gaussian_weight(local, center, radius) * amplitude

func _prepare_entry_points() -> void:
    entry_spawn_positions.clear(); entry_target_positions.clear()
    _append_entry(_local_to_cell(Vector2(-92,-106)), Vector3(0,0,-TILE_SIZE*4)); _append_entry(_local_to_cell(Vector2(34,106)), Vector3(0,0,TILE_SIZE*4)); _append_entry(_local_to_cell(Vector2(-130,20)), Vector3(-TILE_SIZE*4,0,0)); _append_entry(_local_to_cell(Vector2(130,20)), Vector3(TILE_SIZE*4,0,0))
func _append_entry(cell: Vector2i, offset: Vector3) -> void:
    var target := cell_to_world(cell); var spawn := target + offset; spawn.y = target.y + 0.1; entry_spawn_positions.append(spawn); entry_target_positions.append(target)

func _create_cell_multimesh(node_name: String, source_mesh: Mesh, cells: Array[Vector2i], y_offset: float, min_scale: float, max_scale: float, salt: int) -> void:
    if cells.is_empty(): return
    var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.instance_count = cells.size(); mm.mesh = source_mesh
    for i: int in range(cells.size()):
        var scale := lerpf(min_scale, max_scale, _hash01(cells[i], salt)); var basis := Basis.IDENTITY.scaled(Vector3.ONE * scale); var position := cell_to_world(cells[i]); position.y += y_offset * scale; mm.set_instance_transform(i, Transform3D(basis, position))
    var instance := MultiMeshInstance3D.new(); instance.name = node_name; instance.multimesh = mm; add_child(instance)

func _get_cell_corners(cell: Vector2i, terrain: TerrainKind) -> Array[Vector3]:
    if terrain == TerrainKind.WATER: return _water_corners_for_cell(cell)
    var x0 := (float(cell.x) - float(WORLD_WIDTH)*0.5)*TILE_SIZE; var x1 := x0 + TILE_SIZE; var z0 := (float(cell.y)-float(WORLD_DEPTH)*0.5)*TILE_SIZE; var z1 := z0 + TILE_SIZE
    return [Vector3(x0,_sample_height(x0/TILE_SIZE,z0/TILE_SIZE),z0), Vector3(x1,_sample_height(x1/TILE_SIZE,z0/TILE_SIZE),z0), Vector3(x1,_sample_height(x1/TILE_SIZE,z1/TILE_SIZE),z1), Vector3(x0,_sample_height(x0/TILE_SIZE,z1/TILE_SIZE),z1)]
func _water_corners_for_cell(cell: Vector2i) -> Array[Vector3]:
    var x0 := (float(cell.x)-float(WORLD_WIDTH)*0.5)*TILE_SIZE; var x1:=x0+TILE_SIZE; var z0:=(float(cell.y)-float(WORLD_DEPTH)*0.5)*TILE_SIZE; var z1:=z0+TILE_SIZE
    return [Vector3(x0,WATER_LEVEL,z0),Vector3(x1,WATER_LEVEL,z0),Vector3(x1,WATER_LEVEL,z1),Vector3(x0,WATER_LEVEL,z1)]
func _append_quad_to_surface(tool: SurfaceTool, c: Array[Vector3]) -> void:
    tool.add_vertex(c[0]); tool.add_vertex(c[2]); tool.add_vertex(c[1]); tool.add_vertex(c[0]); tool.add_vertex(c[3]); tool.add_vertex(c[2])
func _append_quad_faces(f: PackedVector3Array, c: Array[Vector3]) -> void:
    f.append(c[0]); f.append(c[2]); f.append(c[1]); f.append(c[0]); f.append(c[3]); f.append(c[2])
func _append_water_boundary_faces(cell: Vector2i, c: Array[Vector3], f: PackedVector3Array) -> void:
    var ns: Array[Vector2i] = [cell+Vector2i.UP,cell+Vector2i.RIGHT,cell+Vector2i.DOWN,cell+Vector2i.LEFT]; var pairs: Array[Vector2i] = [Vector2i(0,1),Vector2i(1,2),Vector2i(2,3),Vector2i(3,0)]
    for i: int in range(4):
        if _is_cell_in_bounds(ns[i]) and _terrain_for_cell(ns[i]) != TerrainKind.WATER: continue
        var a:=c[pairs[i].x]; var b:=c[pairs[i].y]; _append_wall_quad(f,a,b,Vector3(b.x,WATER_LEVEL-2.2,b.z),Vector3(a.x,WATER_LEVEL-2.2,a.z))
func _append_blocker_faces(c: Array[Vector3], f: PackedVector3Array) -> void:
    for i: int in range(4): var j:=(i+1)%4; _append_wall_quad(f,c[i]+Vector3.UP*TREE_BLOCKER_HEIGHT,c[j]+Vector3.UP*TREE_BLOCKER_HEIGHT,c[j],c[i])
func _append_wall_quad(f: PackedVector3Array,a:Vector3,b:Vector3,c:Vector3,d:Vector3)->void:
    f.append(a);f.append(b);f.append(c);f.append(a);f.append(c);f.append(d)

func _create_terrain_material(biome: int, terrain: int) -> StandardMaterial3D:
    if terrain == TerrainKind.PATH: return _create_ground_material(PATH_COLOR,1.0)
    if terrain == TerrainKind.WATER: return _create_water_material()
    var color := _biome_ground_color(biome)
    if terrain == TerrainKind.STONE: color = color.lerp(STONE_COLOR,0.58)
    var material := _create_ground_material(color,0.94)
    if biome == BiomeKind.STEEL: material.metallic=0.35; material.roughness=0.55
    elif biome == BiomeKind.ICE: material.metallic=0.08; material.roughness=0.42
    return material
func _create_ground_material(color: Color, roughness: float) -> StandardMaterial3D:
    var m:=StandardMaterial3D.new();m.albedo_color=color;m.roughness=roughness;m.cull_mode=BaseMaterial3D.CULL_DISABLED;return m
func _create_water_material() -> StandardMaterial3D:
    var m:=StandardMaterial3D.new();m.albedo_color=WATER_COLOR;m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;m.roughness=0.16;m.metallic=0.05;m.cull_mode=BaseMaterial3D.CULL_DISABLED;return m

func _terrain_for_cell(cell: Vector2i) -> TerrainKind:
    if not _is_cell_in_bounds(cell): return TerrainKind.WATER
    return terrain_cache.get(cell,TerrainKind.LAND) as TerrainKind
func _biome_for_cell(cell: Vector2i) -> BiomeKind:
    if not _is_cell_in_bounds(cell): return BiomeKind.NORMAL
    return biome_cache.get(cell,BiomeKind.NORMAL) as BiomeKind
func _surface_key(biome:int,terrain:int)->int:return biome*TerrainKind.size()+terrain

func _biome_ground_color(biome:int)->Color:
    match biome:
        BiomeKind.NORMAL:return Color(0.55,0.67,0.42,1); BiomeKind.FIRE:return Color(0.48,0.24,0.16,1); BiomeKind.WATER:return Color(0.36,0.62,0.57,1); BiomeKind.ELECTRIC:return Color(0.72,0.68,0.28,1); BiomeKind.GRASS:return Color(0.24,0.55,0.27,1); BiomeKind.ICE:return Color(0.70,0.84,0.86,1); BiomeKind.FIGHTING:return Color(0.56,0.37,0.28,1); BiomeKind.POISON:return Color(0.42,0.31,0.48,1); BiomeKind.GROUND:return Color(0.65,0.50,0.29,1); BiomeKind.FLYING:return Color(0.60,0.72,0.70,1); BiomeKind.PSYCHIC:return Color(0.64,0.42,0.61,1); BiomeKind.BUG:return Color(0.48,0.58,0.22,1); BiomeKind.ROCK:return Color(0.48,0.45,0.36,1); BiomeKind.GHOST:return Color(0.30,0.31,0.42,1); BiomeKind.DRAGON:return Color(0.34,0.33,0.48,1); BiomeKind.DARK:return Color(0.24,0.25,0.27,1); BiomeKind.STEEL:return Color(0.52,0.58,0.61,1); _:return Color(0.45,0.55,0.40,1)
func _landmark_color(biome:int)->Color:
    return _biome_ground_color(biome).lightened(0.18)
func _landmark_threshold(biome:int)->float:
    if biome in [BiomeKind.GRASS,BiomeKind.BUG,BiomeKind.DARK]: return 0.994
    if biome in [BiomeKind.ROCK,BiomeKind.GROUND,BiomeKind.ICE]: return 0.990
    return 0.993
func _landmark_height_offset(biome:int)->float:
    if biome in [BiomeKind.FIRE,BiomeKind.FIGHTING,BiomeKind.FLYING,BiomeKind.DRAGON,BiomeKind.STEEL]:return 1.05
    if biome==BiomeKind.ELECTRIC:return 1.35
    if biome in [BiomeKind.ICE,BiomeKind.PSYCHIC,BiomeKind.GHOST]:return 0.95
    return 0.36
func _landmark_roughness(biome:int)->float:
    if biome==BiomeKind.ICE:return 0.28
    if biome==BiomeKind.STEEL:return 0.38
    if biome==BiomeKind.ELECTRIC:return 0.45
    return 0.90
func _biome_slug(biome:int)->String:
    return ["normal","fire","water","electric","grass","ice","fighting","poison","ground","flying","psychic","bug","rock","ghost","dragon","dark","steel"][biome]
func _hash01(cell:Vector2i,salt:int)->float:
    var value:=sin(float(cell.x*127+cell.y*311+salt*71))*43758.5453;return value-floor(value)
func _cell_to_local_2d(cell:Vector2i)->Vector2:return Vector2(float(cell.x)-float(WORLD_WIDTH)*0.5+0.5,float(cell.y)-float(WORLD_DEPTH)*0.5+0.5)
func _local_to_cell(local:Vector2)->Vector2i:return Vector2i(clampi(int(floor(local.x+float(WORLD_WIDTH)*0.5)),0,WORLD_WIDTH-1),clampi(int(floor(local.y+float(WORLD_DEPTH)*0.5)),0,WORLD_DEPTH-1))
func _is_cell_in_bounds(cell:Vector2i)->bool:return cell.x>=0 and cell.x<WORLD_WIDTH and cell.y>=0 and cell.y<WORLD_DEPTH
