class_name HgssWorldBuilder # Owns the procedural type-biome world, visuals, collision, and navigation queries.
extends Node3D # Keeps generated world geometry beneath one scene node.

enum TerrainKind { LAND, PATH, WATER, STONE } # Separates traversal surfaces from the type-biome identity.
enum BiomeKind { NORMAL, FIRE, WATER, ELECTRIC, GRASS, ICE, FIGHTING, POISON, GROUND, FLYING, PSYCHIC, BUG, ROCK, GHOST, DRAGON, DARK, STEEL } # Matches every Pokémon type available in Generation IV.

const WORLD_WIDTH: int = 168 # Gives every type enough room to read as a destination rather than a patch.
const WORLD_DEPTH: int = 136 # Keeps the world broad enough for a connected multi-region route network.
const TILE_SIZE: float = 1.5 # Preserves the existing player/world scale while greatly enlarging the map.
const WATER_LEVEL: float = -0.45 # Keeps lakes and swamp pools visibly below nearby walkable ground.
const TREE_BLOCKER_HEIGHT: float = 3.0 # Matches collision height to the generated low-poly trees.
const PATH_WIDTH: float = 2.0 # Keeps primary routes readable without dominating each biome.
const PATH_SHOULDER: float = 4.6 # Protects generous clear space around routes from blocking scenery.

const PATH_COLOR: Color = Color(0.73, 0.63, 0.43, 1.0) # Warm neutral route color shared across all regions.
const WATER_COLOR: Color = Color(0.20, 0.52, 0.78, 0.80) # Semi-transparent surface water.
const WATER_DEPTH_COLOR: Color = Color(0.07, 0.24, 0.38, 1.0) # Gives lakes visible depth beneath the transparent surface.
const STONE_COLOR: Color = Color(0.48, 0.49, 0.48, 1.0) # Neutral base used to tint rocky terrain toward its biome.
const TREE_TRUNK_COLOR: Color = Color(0.30, 0.18, 0.09, 1.0) # Shared tree-trunk material.
const GRASS_CANOPY_COLOR: Color = Color(0.18, 0.46, 0.20, 1.0) # Bright forest canopy for the Grass region.
const BUG_CANOPY_COLOR: Color = Color(0.42, 0.55, 0.16, 1.0) # Yellow-green canopy distinguishes the Bug woods.
const DARK_CANOPY_COLOR: Color = Color(0.16, 0.16, 0.25, 1.0) # Muted purple canopy gives the Dark forest a separate silhouette.
const BRIDGE_COLOR: Color = Color(0.45, 0.28, 0.13, 1.0) # Wooden causeways remain readable over water.

const BIOME_CENTERS: Array[Vector2] = [
    Vector2(0.0, 8.0), # Normal meadow forms the central hub.
    Vector2(58.0, -20.0), # Fire volcanic basin.
    Vector2(52.0, 38.0), # Water lake district.
    Vector2(18.0, 38.0), # Electric plains.
    Vector2(-28.0, 8.0), # Grass forest.
    Vector2(-18.0, -48.0), # Ice snowfield.
    Vector2(-28.0, -20.0), # Fighting training plateau.
    Vector2(-52.0, 38.0), # Poison marsh.
    Vector2(-58.0, -20.0), # Ground badlands.
    Vector2(18.0, -48.0), # Flying high plateau.
    Vector2(28.0, 8.0), # Psychic garden.
    Vector2(-56.0, 8.0), # Bug woodland.
    Vector2(-52.0, -48.0), # Rock mountain range.
    Vector2(56.0, 8.0), # Ghost hollow.
    Vector2(52.0, -48.0), # Dragon peaks.
    Vector2(-18.0, 38.0), # Dark forest.
    Vector2(30.0, -20.0), # Steel works/plain.
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

var blocked_cells: Dictionary = {} # Hard tree obstacles shared by physics and A*.
var terrain_cache: Dictionary = {} # Traversal surface classification for each grid cell.
var biome_cache: Dictionary = {} # Type-biome identity for each grid cell.
var entry_spawn_positions: Array[Vector3] = [] # Off-map positions used by roaming Pokémon.
var entry_target_positions: Array[Vector3] = [] # Matching walkable positions inside each entrance.

func _ready() -> void: # Builds the complete asset-free world from deterministic type-biome rules.
    add_to_group(&"world_builder")
    _prepare_layout_cache()
    _prune_isolated_walkable_regions()
    _build_terrain_geometry()
    _build_environment_visuals()
    _prepare_entry_points()

func get_random_entry_pair(random: RandomNumberGenerator) -> Array[Vector3]: # Returns one spawn point and matching interior target.
    if entry_spawn_positions.is_empty():
        _prepare_entry_points()
    var entry_index: int = random.randi_range(0, entry_spawn_positions.size() - 1)
    return [entry_spawn_positions[entry_index], entry_target_positions[entry_index]]

func get_exit_target_from(world_position: Vector3) -> Vector3: # Returns the nearest route gate for a departing roaming Pokémon.
    if entry_spawn_positions.is_empty():
        _prepare_entry_points()
    var best_position: Vector3 = entry_spawn_positions[0]
    var best_distance_squared: float = world_position.distance_squared_to(best_position)
    for candidate: Vector3 in entry_spawn_positions:
        var distance_squared: float = world_position.distance_squared_to(candidate)
        if distance_squared < best_distance_squared:
            best_distance_squared = distance_squared
            best_position = candidate
    return best_position

func get_random_walkable_world_position_near(world_position: Vector3, radius: float, random: RandomNumberGenerator) -> Vector3: # Finds a nearby cell suitable for roaming movement.
    var centre_cell: Vector2i = world_to_cell(world_position)
    var radius_cells: int = maxi(1, int(ceil(radius / TILE_SIZE)))
    for attempt: int in range(32):
        var candidate: Vector2i = centre_cell + Vector2i(random.randi_range(-radius_cells, radius_cells), random.randi_range(-radius_cells, radius_cells))
        if is_cell_walkable(candidate):
            return cell_to_world(candidate)
    if is_cell_walkable(centre_cell):
        return cell_to_world(centre_cell)
    return get_nearest_walkable_world_position(world_position)

func get_nearest_walkable_world_position(world_position: Vector3) -> Vector3: # Finds the closest usable terrain cell around an arbitrary point.
    var centre_cell: Vector2i = world_to_cell(world_position)
    for radius_cells: int in range(0, 24):
        for offset_x: int in range(-radius_cells, radius_cells + 1):
            for offset_z: int in range(-radius_cells, radius_cells + 1):
                var candidate: Vector2i = centre_cell + Vector2i(offset_x, offset_z)
                if is_cell_walkable(candidate):
                    return cell_to_world(candidate)
    return Vector3.ZERO

func is_cell_walkable(cell: Vector2i) -> bool: # Reports whether a grid cell can be used by ground movement.
    if not _is_cell_in_bounds(cell) or blocked_cells.has(cell):
        return false
    return _terrain_for_cell(cell) != TerrainKind.WATER

func cell_to_world(cell: Vector2i) -> Vector3: # Converts one grid-cell centre into world coordinates at generated elevation.
    var local_x: float = (float(cell.x) - float(WORLD_WIDTH) * 0.5 + 0.5) * TILE_SIZE
    var local_z: float = (float(cell.y) - float(WORLD_DEPTH) * 0.5 + 0.5) * TILE_SIZE
    var local_y: float = _sample_height(local_x / TILE_SIZE, local_z / TILE_SIZE)
    return Vector3(local_x, local_y + 0.06, local_z)

func world_to_cell(world_position: Vector3) -> Vector2i: # Converts world coordinates back into an integer terrain cell.
    var cell_x: int = int(floor(world_position.x / TILE_SIZE + float(WORLD_WIDTH) * 0.5))
    var cell_z: int = int(floor(world_position.z / TILE_SIZE + float(WORLD_DEPTH) * 0.5))
    return Vector2i(cell_x, cell_z)

func _prepare_layout_cache() -> void: # Gives every cell one contiguous type region before deriving traversal and blockers.
    blocked_cells.clear()
    terrain_cache.clear()
    biome_cache.clear()
    for cell_z: int in range(WORLD_DEPTH):
        for cell_x: int in range(WORLD_WIDTH):
            var cell: Vector2i = Vector2i(cell_x, cell_z)
            var local: Vector2 = _cell_to_local_2d(cell)
            var biome_kind: BiomeKind = _calculate_biome_for_local(local)
            var terrain_kind: TerrainKind = _calculate_terrain_for_local(local, biome_kind)
            biome_cache[cell] = biome_kind
            terrain_cache[cell] = terrain_kind
            if _calculate_tree_for_cell(cell, local, biome_kind, terrain_kind):
                blocked_cells[cell] = true

func _prune_isolated_walkable_regions() -> void: # Converts tiny unreachable pockets into scenery so the exposed landmass remains coherent.
    var start_cell: Vector2i = _local_to_cell(BIOME_CENTERS[BiomeKind.NORMAL])
    if not is_cell_walkable(start_cell):
        return
    var reachable: Dictionary = {start_cell: true}
    var queue: Array[Vector2i] = [start_cell]
    var queue_index: int = 0
    while queue_index < queue.size():
        var cell: Vector2i = queue[queue_index]
        queue_index += 1
        var neighbours: Array[Vector2i] = [cell + Vector2i(1, 0), cell + Vector2i(-1, 0), cell + Vector2i(0, 1), cell + Vector2i(0, -1)]
        for neighbour: Vector2i in neighbours:
            if reachable.has(neighbour) or not is_cell_walkable(neighbour):
                continue
            reachable[neighbour] = true
            queue.append(neighbour)
    for cell_z: int in range(WORLD_DEPTH):
        for cell_x: int in range(WORLD_WIDTH):
            var cell: Vector2i = Vector2i(cell_x, cell_z)
            if _terrain_for_cell(cell) == TerrainKind.WATER or reachable.has(cell) or blocked_cells.has(cell):
                continue
            blocked_cells[cell] = true

func _build_terrain_geometry() -> void: # Batches biome-tinted ground while keeping physics in one static collision mesh.
    var tools: Dictionary = {}
    var vertex_counts: Dictionary = {}
    for biome_kind: int in range(BiomeKind.size()):
        for terrain_kind: int in range(TerrainKind.size()):
            var surface_key: int = _surface_key(biome_kind, terrain_kind)
            var surface_tool: SurfaceTool = SurfaceTool.new()
            surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
            surface_tool.set_material(_create_terrain_material(biome_kind, terrain_kind))
            tools[surface_key] = surface_tool
            vertex_counts[surface_key] = 0
    var collision_faces: PackedVector3Array = PackedVector3Array()
    for cell_z: int in range(WORLD_DEPTH):
        for cell_x: int in range(WORLD_WIDTH):
            var cell: Vector2i = Vector2i(cell_x, cell_z)
            var biome_kind: BiomeKind = _biome_for_cell(cell)
            var terrain_kind: TerrainKind = _terrain_for_cell(cell)
            var corners: Array[Vector3] = _get_cell_corners(cell, terrain_kind)
            var surface_key: int = _surface_key(biome_kind, terrain_kind)
            var surface_tool: SurfaceTool = tools[surface_key] as SurfaceTool
            _append_quad_to_surface(surface_tool, corners)
            vertex_counts[surface_key] = int(vertex_counts[surface_key]) + 6
            if terrain_kind != TerrainKind.WATER:
                _append_quad_faces(collision_faces, corners)
                _append_water_boundary_faces(cell, corners, collision_faces)
            if blocked_cells.has(cell):
                _append_blocker_faces(corners, collision_faces)
    for biome_kind: int in range(BiomeKind.size()):
        for terrain_kind: int in range(TerrainKind.size()):
            var surface_key: int = _surface_key(biome_kind, terrain_kind)
            if int(vertex_counts[surface_key]) <= 0:
                continue
            var surface_tool: SurfaceTool = tools[surface_key] as SurfaceTool
            surface_tool.generate_normals()
            var mesh_instance: MeshInstance3D = MeshInstance3D.new()
            mesh_instance.name = "terrain_%s_%s" % [_biome_slug(biome_kind), str(terrain_kind)]
            mesh_instance.mesh = surface_tool.commit()
            mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            add_child(mesh_instance)
    var world_body: StaticBody3D = StaticBody3D.new()
    world_body.name = "generated_world_collision"
    world_body.collision_layer = 1
    world_body.collision_mask = 0
    var collision_shape: CollisionShape3D = CollisionShape3D.new()
    var concave_shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
    concave_shape.backface_collision = true
    concave_shape.set_faces(collision_faces)
    collision_shape.shape = concave_shape
    world_body.add_child(collision_shape)
    add_child(world_body)

func _build_environment_visuals() -> void: # Adds distinct generated scenery for the seventeen type regions.
    _build_water_depth_visual()
    _build_tree_visuals()
    _build_bridge_visuals()
    _build_type_landmarks()

func _build_water_depth_visual() -> void: # Gives Water and Poison liquids visible depth and keeps them beneath bridge paths.
    var depth_tool: SurfaceTool = SurfaceTool.new()
    depth_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    depth_tool.set_material(_create_ground_material(WATER_DEPTH_COLOR, 1.0))
    var bridge_water_tool: SurfaceTool = SurfaceTool.new()
    bridge_water_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    bridge_water_tool.set_material(_create_water_material())
    var depth_vertex_count: int = 0
    var bridge_water_vertex_count: int = 0
    for cell_z: int in range(WORLD_DEPTH):
        for cell_x: int in range(WORLD_WIDTH):
            var cell: Vector2i = Vector2i(cell_x, cell_z)
            var local: Vector2 = _cell_to_local_2d(cell)
            var biome_kind: BiomeKind = _biome_for_cell(cell)
            if not _is_water_feature(local, biome_kind):
                continue
            var surface_corners: Array[Vector3] = _water_corners_for_cell(cell)
            var depth_corners: Array[Vector3] = surface_corners.duplicate()
            for corner_index: int in range(depth_corners.size()):
                depth_corners[corner_index].y = WATER_LEVEL - 0.62
            _append_quad_to_surface(depth_tool, depth_corners)
            depth_vertex_count += 6
            if _terrain_for_cell(cell) == TerrainKind.PATH:
                _append_quad_to_surface(bridge_water_tool, surface_corners)
                bridge_water_vertex_count += 6
    if depth_vertex_count > 0:
        depth_tool.generate_normals()
        var depth_instance: MeshInstance3D = MeshInstance3D.new()
        depth_instance.name = "water_depth"
        depth_instance.mesh = depth_tool.commit()
        depth_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        add_child(depth_instance)
    if bridge_water_vertex_count > 0:
        bridge_water_tool.generate_normals()
        var bridge_water_instance: MeshInstance3D = MeshInstance3D.new()
        bridge_water_instance.name = "water_under_bridges"
        bridge_water_instance.mesh = bridge_water_tool.commit()
        bridge_water_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        add_child(bridge_water_instance)

func _build_tree_visuals() -> void: # Builds trunk-and-layered-canopy models for the forest-oriented regions.
    var all_tree_cells: Array[Vector2i] = []
    var grass_tree_cells: Array[Vector2i] = []
    var bug_tree_cells: Array[Vector2i] = []
    var dark_tree_cells: Array[Vector2i] = []
    for key: Variant in blocked_cells.keys():
        var cell: Vector2i = key
        all_tree_cells.append(cell)
        match _biome_for_cell(cell):
            BiomeKind.BUG:
                bug_tree_cells.append(cell)
            BiomeKind.DARK, BiomeKind.GHOST:
                dark_tree_cells.append(cell)
            _:
                grass_tree_cells.append(cell)
    if all_tree_cells.is_empty():
        return
    var trunk_mesh: CylinderMesh = CylinderMesh.new()
    trunk_mesh.top_radius = 0.18
    trunk_mesh.bottom_radius = 0.27
    trunk_mesh.height = 1.45
    trunk_mesh.radial_segments = 7
    trunk_mesh.rings = 1
    trunk_mesh.material = _create_ground_material(TREE_TRUNK_COLOR, 0.98)
    _create_cell_multimesh("tree_trunks", trunk_mesh, all_tree_cells, 0.76, 0.90, 1.10, 11)
    _build_canopy_group("grass_canopy", grass_tree_cells, GRASS_CANOPY_COLOR, 13)
    _build_canopy_group("bug_canopy", bug_tree_cells, BUG_CANOPY_COLOR, 17)
    _build_canopy_group("dark_canopy", dark_tree_cells, DARK_CANOPY_COLOR, 23)

func _build_canopy_group(node_prefix: String, cells: Array[Vector2i], color: Color, salt: int) -> void: # Uses two overlapping low-poly spheres so trees read as actual trees at game distance.
    if cells.is_empty():
        return
    var lower_mesh: SphereMesh = SphereMesh.new()
    lower_mesh.radius = 0.80
    lower_mesh.height = 1.28
    lower_mesh.radial_segments = 8
    lower_mesh.rings = 4
    lower_mesh.material = _create_ground_material(color.darkened(0.12), 0.92)
    var upper_mesh: SphereMesh = SphereMesh.new()
    upper_mesh.radius = 0.60
    upper_mesh.height = 0.98
    upper_mesh.radial_segments = 8
    upper_mesh.rings = 4
    upper_mesh.material = _create_ground_material(color, 0.92)
    _create_cell_multimesh(node_prefix + "_lower", lower_mesh, cells, 1.76, 0.90, 1.10, salt)
    _create_cell_multimesh(node_prefix + "_upper", upper_mesh, cells, 2.38, 0.90, 1.10, salt)

func _build_bridge_visuals() -> void: # Adds wooden decks only where the route network crosses a liquid feature.
    var bridge_cells: Array[Vector2i] = []
    for cell_z: int in range(WORLD_DEPTH):
        for cell_x: int in range(WORLD_WIDTH):
            var cell: Vector2i = Vector2i(cell_x, cell_z)
            var local: Vector2 = _cell_to_local_2d(cell)
            if _terrain_for_cell(cell) == TerrainKind.PATH and _is_water_feature(local, _biome_for_cell(cell)):
                bridge_cells.append(cell)
    if bridge_cells.is_empty():
        return
    var deck_mesh: BoxMesh = BoxMesh.new()
    deck_mesh.size = Vector3(TILE_SIZE * 0.96, 0.14, TILE_SIZE * 0.96)
    deck_mesh.material = _create_ground_material(BRIDGE_COLOR, 0.84)
    _create_cell_multimesh("bridge_decks", deck_mesh, bridge_cells, 0.10, 1.0, 1.0, 29)

func _build_type_landmarks() -> void: # Gives every type a repeated visual motif without imported models or textures.
    for biome_kind: int in range(BiomeKind.size()):
        var cells: Array[Vector2i] = []
        for cell_z: int in range(WORLD_DEPTH):
            for cell_x: int in range(WORLD_WIDTH):
                var cell: Vector2i = Vector2i(cell_x, cell_z)
                if _biome_for_cell(cell) != biome_kind or blocked_cells.has(cell):
                    continue
                var terrain_kind: TerrainKind = _terrain_for_cell(cell)
                if terrain_kind == TerrainKind.PATH or terrain_kind == TerrainKind.WATER:
                    continue
                var local: Vector2 = _cell_to_local_2d(cell)
                if _path_distance(local) < PATH_SHOULDER + 1.5:
                    continue
                if _hash01(cell, 101 + biome_kind * 13) > _landmark_threshold(biome_kind):
                    cells.append(cell)
        if cells.is_empty():
            continue
        var mesh: Mesh = _create_landmark_mesh(biome_kind)
        _create_cell_multimesh("%s_landmarks" % _biome_slug(biome_kind), mesh, cells, _landmark_height_offset(biome_kind), 0.82, 1.22, 151 + biome_kind)

func _create_landmark_mesh(biome_kind: int) -> Mesh: # Uses primitive silhouettes so each type has an immediately different landscape language.
    var material: StandardMaterial3D = _create_ground_material(_landmark_color(biome_kind), _landmark_roughness(biome_kind))
    match biome_kind:
        BiomeKind.FIRE, BiomeKind.FIGHTING, BiomeKind.FLYING, BiomeKind.DRAGON, BiomeKind.STEEL, BiomeKind.ELECTRIC:
            var pillar: CylinderMesh = CylinderMesh.new()
            pillar.top_radius = 0.12 if biome_kind == BiomeKind.DRAGON else 0.24
            pillar.bottom_radius = 0.36
            pillar.height = 1.8 if biome_kind != BiomeKind.ELECTRIC else 2.3
            pillar.radial_segments = 6
            pillar.rings = 1
            pillar.material = material
            return pillar
        BiomeKind.ICE, BiomeKind.PSYCHIC, BiomeKind.GHOST:
            var monolith: BoxMesh = BoxMesh.new()
            monolith.size = Vector3(0.48, 1.65, 0.48)
            monolith.material = material
            return monolith
        BiomeKind.WATER, BiomeKind.GROUND, BiomeKind.ROCK, BiomeKind.POISON, BiomeKind.BUG, BiomeKind.NORMAL, BiomeKind.GRASS, BiomeKind.DARK:
            var boulder: SphereMesh = SphereMesh.new()
            boulder.radius = 0.42
            boulder.height = 0.62
            boulder.radial_segments = 6
            boulder.rings = 3
            boulder.material = material
            return boulder
        _:
            var fallback: BoxMesh = BoxMesh.new()
            fallback.size = Vector3(0.6, 0.8, 0.6)
            fallback.material = material
            return fallback

func _create_terrain_material(biome_kind: int, terrain_kind: int) -> StandardMaterial3D: # Keeps routes/liquids consistent while tinting natural ground by Pokémon type.
    if terrain_kind == TerrainKind.PATH:
        return _create_ground_material(PATH_COLOR, 1.0)
    if terrain_kind == TerrainKind.WATER:
        return _create_water_material()
    var biome_color: Color = _biome_ground_color(biome_kind)
    if terrain_kind == TerrainKind.STONE:
        biome_color = biome_color.lerp(STONE_COLOR, 0.58)
    var material: StandardMaterial3D = _create_ground_material(biome_color, 0.94)
    if biome_kind == BiomeKind.STEEL:
        material.metallic = 0.35
        material.roughness = 0.55
    elif biome_kind == BiomeKind.ICE:
        material.metallic = 0.08
        material.roughness = 0.42
    return material

func _create_ground_material(color: Color, roughness: float) -> StandardMaterial3D: # Creates a shaded untextured world material.
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material

func _create_water_material() -> StandardMaterial3D: # Creates simple translucent water that responds to the world lighting.
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = WATER_COLOR
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.roughness = 0.16
    material.metallic = 0.05
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material

func _get_cell_corners(cell: Vector2i, terrain_kind: TerrainKind) -> Array[Vector3]: # Returns four world-space corners for one generated terrain cell.
    if terrain_kind == TerrainKind.WATER:
        return _water_corners_for_cell(cell)
    var x0: float = (float(cell.x) - float(WORLD_WIDTH) * 0.5) * TILE_SIZE
    var x1: float = x0 + TILE_SIZE
    var z0: float = (float(cell.y) - float(WORLD_DEPTH) * 0.5) * TILE_SIZE
    var z1: float = z0 + TILE_SIZE
    return [
        Vector3(x0, _sample_height(x0 / TILE_SIZE, z0 / TILE_SIZE), z0),
        Vector3(x1, _sample_height(x1 / TILE_SIZE, z0 / TILE_SIZE), z0),
        Vector3(x1, _sample_height(x1 / TILE_SIZE, z1 / TILE_SIZE), z1),
        Vector3(x0, _sample_height(x0 / TILE_SIZE, z1 / TILE_SIZE), z1),
    ]

func _water_corners_for_cell(cell: Vector2i) -> Array[Vector3]: # Keeps all liquid surfaces level so lakes read cleanly against rolling terrain.
    var x0: float = (float(cell.x) - float(WORLD_WIDTH) * 0.5) * TILE_SIZE
    var x1: float = x0 + TILE_SIZE
    var z0: float = (float(cell.y) - float(WORLD_DEPTH) * 0.5) * TILE_SIZE
    var z1: float = z0 + TILE_SIZE
    return [Vector3(x0, WATER_LEVEL, z0), Vector3(x1, WATER_LEVEL, z0), Vector3(x1, WATER_LEVEL, z1), Vector3(x0, WATER_LEVEL, z1)]

func _append_quad_to_surface(surface_tool: SurfaceTool, corners: Array[Vector3]) -> void: # Adds one terrain quad as two upward-facing triangles.
    surface_tool.add_vertex(corners[0])
    surface_tool.add_vertex(corners[2])
    surface_tool.add_vertex(corners[1])
    surface_tool.add_vertex(corners[0])
    surface_tool.add_vertex(corners[3])
    surface_tool.add_vertex(corners[2])

func _append_quad_faces(faces: PackedVector3Array, corners: Array[Vector3]) -> void: # Adds one terrain quad to the static collision triangle list.
    faces.append(corners[0])
    faces.append(corners[2])
    faces.append(corners[1])
    faces.append(corners[0])
    faces.append(corners[3])
    faces.append(corners[2])

func _append_water_boundary_faces(cell: Vector2i, corners: Array[Vector3], faces: PackedVector3Array) -> void: # Adds retaining collision beside liquid and the outer world edge.
    var neighbours: Array[Vector2i] = [cell + Vector2i(0, -1), cell + Vector2i(1, 0), cell + Vector2i(0, 1), cell + Vector2i(-1, 0)]
    var edge_pairs: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 0)]
    for edge_index: int in range(4):
        var neighbour: Vector2i = neighbours[edge_index]
        var needs_wall: bool = not _is_cell_in_bounds(neighbour) or _terrain_for_cell(neighbour) == TerrainKind.WATER
        if not needs_wall:
            continue
        var pair: Vector2i = edge_pairs[edge_index]
        var top_a: Vector3 = corners[pair.x]
        var top_b: Vector3 = corners[pair.y]
        var bottom_a: Vector3 = Vector3(top_a.x, WATER_LEVEL - 1.8, top_a.z)
        var bottom_b: Vector3 = Vector3(top_b.x, WATER_LEVEL - 1.8, top_b.z)
        _append_wall_quad(faces, top_a, top_b, bottom_b, bottom_a)

func _append_blocker_faces(corners: Array[Vector3], faces: PackedVector3Array) -> void: # Adds vertical collision around one tree-occupied cell.
    for edge_index: int in range(4):
        var next_index: int = (edge_index + 1) % 4
        var bottom_a: Vector3 = corners[edge_index]
        var bottom_b: Vector3 = corners[next_index]
        var top_a: Vector3 = bottom_a + Vector3.UP * TREE_BLOCKER_HEIGHT
        var top_b: Vector3 = bottom_b + Vector3.UP * TREE_BLOCKER_HEIGHT
        _append_wall_quad(faces, top_a, top_b, bottom_b, bottom_a)

func _append_wall_quad(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void: # Adds a four-corner wall as two collision triangles.
    faces.append(a)
    faces.append(b)
    faces.append(c)
    faces.append(a)
    faces.append(c)
    faces.append(d)

func _calculate_biome_for_local(local: Vector2) -> BiomeKind: # Uses a Voronoi-style partition so every type region is contiguous and shares borders naturally.
    var best_biome: int = BiomeKind.NORMAL
    var best_distance: float = INF
    for biome_kind: int in range(BiomeKind.size()):
        var distance: float = local.distance_squared_to(BIOME_CENTERS[biome_kind])
        if distance < best_distance:
            best_distance = distance
            best_biome = biome_kind
    return best_biome as BiomeKind

func _calculate_terrain_for_local(local: Vector2, biome_kind: BiomeKind) -> TerrainKind: # Routes override hazards so every region remains connected by walkable corridors.
    if _is_path(local):
        return TerrainKind.PATH
    if _is_water_feature(local, biome_kind):
        return TerrainKind.WATER
    if biome_kind == BiomeKind.ROCK or biome_kind == BiomeKind.ICE or biome_kind == BiomeKind.DRAGON or biome_kind == BiomeKind.GROUND or biome_kind == BiomeKind.STEEL:
        return TerrainKind.STONE
    return TerrainKind.LAND

func _calculate_tree_for_cell(cell: Vector2i, local: Vector2, biome_kind: BiomeKind, terrain_kind: TerrainKind) -> bool: # Concentrates real tree obstacles inside the forest-oriented type areas.
    if terrain_kind != TerrainKind.LAND or _path_distance(local) < PATH_SHOULDER:
        return false
    var center: Vector2 = BIOME_CENTERS[biome_kind]
    var distance_to_center: float = local.distance_to(center)
    var density: float = _hash01(cell, 7)
    match biome_kind:
        BiomeKind.GRASS:
            if distance_to_center < 5.0:
                return false
            return distance_to_center < 17.0 and density > 0.38
        BiomeKind.BUG:
            if distance_to_center < 4.5:
                return false
            return distance_to_center < 15.5 and density > 0.44
        BiomeKind.DARK:
            if distance_to_center < 5.5:
                return false
            return distance_to_center < 17.0 and density > 0.42
        BiomeKind.GHOST:
            return distance_to_center > 8.0 and distance_to_center < 15.0 and density > 0.72
        _:
            return false

func _is_water_feature(local: Vector2, biome_kind: BiomeKind) -> bool: # Keeps major water contained within its intended regions instead of slicing the whole map apart.
    if biome_kind == BiomeKind.WATER:
        var main_lake: Vector2 = Vector2((local.x - 52.0) / 17.0, (local.y - 38.0) / 12.0)
        var north_cove: Vector2 = Vector2((local.x - 47.0) / 8.0, (local.y - 29.0) / 6.0)
        return main_lake.length_squared() < 1.0 or north_cove.length_squared() < 1.0
    if biome_kind == BiomeKind.POISON:
        var poison_center: Vector2 = BIOME_CENTERS[BiomeKind.POISON]
        var relative: Vector2 = local - poison_center
        var inside_marsh: bool = Vector2(relative.x / 15.0, relative.y / 12.0).length_squared() < 1.0
        var pool_pattern: float = sin(local.x * 0.48) + cos(local.y * 0.43)
        return inside_marsh and pool_pattern > 1.22
    return false

func _is_path(local: Vector2) -> bool: # Connects every type region with a redundant grid/ring network rather than isolated spokes.
    return _path_distance(local) <= PATH_WIDTH

func _path_distance(local: Vector2) -> float: # Measures the nearest designed route segment, including four world-entry corridors.
    var best_distance: float = INF
    for edge: Vector2i in PATH_EDGES:
        best_distance = minf(best_distance, _distance_to_segment(local, BIOME_CENTERS[edge.x], BIOME_CENTERS[edge.y]))
    best_distance = minf(best_distance, _distance_to_segment(local, BIOME_CENTERS[BiomeKind.ROCK], Vector2(-52.0, -68.0)))
    best_distance = minf(best_distance, _distance_to_segment(local, BIOME_CENTERS[BiomeKind.ELECTRIC], Vector2(18.0, 68.0)))
    best_distance = minf(best_distance, _distance_to_segment(local, BIOME_CENTERS[BiomeKind.BUG], Vector2(-84.0, 8.0)))
    best_distance = minf(best_distance, _distance_to_segment(local, BIOME_CENTERS[BiomeKind.GHOST], Vector2(84.0, 8.0)))
    return best_distance

func _distance_to_segment(point: Vector2, start: Vector2, finish: Vector2) -> float: # Keeps route construction smooth between arbitrary biome centers.
    var segment: Vector2 = finish - start
    var length_squared: float = segment.length_squared()
    if length_squared <= 0.0001:
        return point.distance_to(start)
    var progress: float = clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
    return point.distance_to(start + segment * progress)

func _sample_height(local_x: float, local_z: float) -> float: # Shapes type destinations while blending them into one continuous traversable landscape.
    var local: Vector2 = Vector2(local_x, local_z)
    var height: float = sin(local_x * 0.055) * cos(local_z * 0.05) * 0.20
    height += _gaussian_height(local, BIOME_CENTERS[BiomeKind.ROCK], 19.0, 5.6)
    height += _gaussian_height(local, BIOME_CENTERS[BiomeKind.ICE], 17.0, 3.7)
    height += _gaussian_height(local, BIOME_CENTERS[BiomeKind.FLYING], 18.0, 3.0)
    height += _gaussian_height(local, BIOME_CENTERS[BiomeKind.DRAGON], 18.0, 6.2)
    height += _gaussian_height(local, BIOME_CENTERS[BiomeKind.FIRE], 18.0, 3.4)
    height -= _gaussian_height(local, BIOME_CENTERS[BiomeKind.FIRE], 6.0, 1.2)
    height += _gaussian_height(local, BIOME_CENTERS[BiomeKind.GROUND], 20.0, 1.9)
    height += _gaussian_height(local, BIOME_CENTERS[BiomeKind.STEEL], 17.0, 1.0)
    height -= _gaussian_height(local, BIOME_CENTERS[BiomeKind.WATER], 18.0, 0.42)
    height -= _gaussian_height(local, BIOME_CENTERS[BiomeKind.POISON], 17.0, 0.25)
    return height

func _gaussian_height(local: Vector2, center: Vector2, radius: float, amplitude: float) -> float: # Creates broad hills without hard elevation seams at biome borders.
    var offset: Vector2 = (local - center) / radius
    return exp(-offset.length_squared() * 2.0) * amplitude

func _prepare_entry_points() -> void: # Places four roaming entrances directly on the extended route network.
    entry_spawn_positions.clear()
    entry_target_positions.clear()
    _append_entry(_local_to_cell(Vector2(-52.0, -66.0)), Vector3(0.0, 0.0, -TILE_SIZE * 4.0))
    _append_entry(_local_to_cell(Vector2(18.0, 66.0)), Vector3(0.0, 0.0, TILE_SIZE * 4.0))
    _append_entry(_local_to_cell(Vector2(-82.0, 8.0)), Vector3(-TILE_SIZE * 4.0, 0.0, 0.0))
    _append_entry(_local_to_cell(Vector2(82.0, 8.0)), Vector3(TILE_SIZE * 4.0, 0.0, 0.0))

func _append_entry(edge_cell: Vector2i, outward_offset: Vector3) -> void: # Adds one route gate pair using generated terrain height.
    var target_position: Vector3 = cell_to_world(edge_cell)
    var spawn_position: Vector3 = target_position + outward_offset
    spawn_position.y = target_position.y + 0.1
    entry_spawn_positions.append(spawn_position)
    entry_target_positions.append(target_position)

func _create_cell_multimesh(node_name: String, source_mesh: Mesh, cells: Array[Vector2i], height_offset: float, min_scale: float, max_scale: float, salt: int) -> void: # Batches repeated scenery with deterministic scale variation.
    if cells.is_empty():
        return
    var multi_mesh: MultiMesh = MultiMesh.new()
    multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
    multi_mesh.instance_count = cells.size()
    multi_mesh.mesh = source_mesh
    for index: int in range(cells.size()):
        var cell: Vector2i = cells[index]
        var scale_value: float = lerpf(min_scale, max_scale, _hash01(cell, salt))
        var basis: Basis = Basis.IDENTITY.scaled(Vector3(scale_value, scale_value, scale_value))
        var world_position: Vector3 = cell_to_world(cell)
        world_position.y += height_offset * scale_value
        multi_mesh.set_instance_transform(index, Transform3D(basis, world_position))
    var multi_mesh_instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
    multi_mesh_instance.name = node_name
    multi_mesh_instance.multimesh = multi_mesh
    add_child(multi_mesh_instance)

func _terrain_for_cell(cell: Vector2i) -> TerrainKind: # Reads cached terrain or treats outside space as water for boundary collision.
    if not _is_cell_in_bounds(cell):
        return TerrainKind.WATER
    return terrain_cache.get(cell, TerrainKind.LAND) as TerrainKind

func _biome_for_cell(cell: Vector2i) -> BiomeKind: # Reads the cached type identity used by rendering and scenery generation.
    if not _is_cell_in_bounds(cell):
        return BiomeKind.NORMAL
    return biome_cache.get(cell, BiomeKind.NORMAL) as BiomeKind

func _surface_key(biome_kind: int, terrain_kind: int) -> int: # Packs two small enum values into one dictionary key for batching.
    return biome_kind * TerrainKind.size() + terrain_kind

func _biome_ground_color(biome_kind: int) -> Color: # Gives every Generation IV type a distinct ground palette.
    match biome_kind:
        BiomeKind.NORMAL: return Color(0.55, 0.67, 0.42, 1.0)
        BiomeKind.FIRE: return Color(0.48, 0.24, 0.16, 1.0)
        BiomeKind.WATER: return Color(0.36, 0.62, 0.57, 1.0)
        BiomeKind.ELECTRIC: return Color(0.72, 0.68, 0.28, 1.0)
        BiomeKind.GRASS: return Color(0.24, 0.55, 0.27, 1.0)
        BiomeKind.ICE: return Color(0.70, 0.84, 0.86, 1.0)
        BiomeKind.FIGHTING: return Color(0.56, 0.37, 0.28, 1.0)
        BiomeKind.POISON: return Color(0.42, 0.31, 0.48, 1.0)
        BiomeKind.GROUND: return Color(0.65, 0.50, 0.29, 1.0)
        BiomeKind.FLYING: return Color(0.60, 0.72, 0.70, 1.0)
        BiomeKind.PSYCHIC: return Color(0.64, 0.42, 0.61, 1.0)
        BiomeKind.BUG: return Color(0.48, 0.58, 0.22, 1.0)
        BiomeKind.ROCK: return Color(0.48, 0.45, 0.36, 1.0)
        BiomeKind.GHOST: return Color(0.30, 0.31, 0.42, 1.0)
        BiomeKind.DRAGON: return Color(0.34, 0.33, 0.48, 1.0)
        BiomeKind.DARK: return Color(0.24, 0.25, 0.27, 1.0)
        BiomeKind.STEEL: return Color(0.52, 0.58, 0.61, 1.0)
        _: return Color(0.45, 0.55, 0.40, 1.0)

func _landmark_color(biome_kind: int) -> Color: # Pushes each area's prop silhouette toward the associated type without textures.
    match biome_kind:
        BiomeKind.NORMAL: return Color(0.75, 0.68, 0.50, 1.0)
        BiomeKind.FIRE: return Color(0.86, 0.31, 0.10, 1.0)
        BiomeKind.WATER: return Color(0.22, 0.58, 0.70, 1.0)
        BiomeKind.ELECTRIC: return Color(0.92, 0.78, 0.16, 1.0)
        BiomeKind.GRASS: return Color(0.25, 0.62, 0.24, 1.0)
        BiomeKind.ICE: return Color(0.72, 0.92, 0.96, 1.0)
        BiomeKind.FIGHTING: return Color(0.63, 0.24, 0.18, 1.0)
        BiomeKind.POISON: return Color(0.60, 0.26, 0.66, 1.0)
        BiomeKind.GROUND: return Color(0.69, 0.49, 0.22, 1.0)
        BiomeKind.FLYING: return Color(0.82, 0.88, 0.86, 1.0)
        BiomeKind.PSYCHIC: return Color(0.82, 0.38, 0.68, 1.0)
        BiomeKind.BUG: return Color(0.60, 0.70, 0.18, 1.0)
        BiomeKind.ROCK: return Color(0.42, 0.40, 0.34, 1.0)
        BiomeKind.GHOST: return Color(0.38, 0.30, 0.50, 1.0)
        BiomeKind.DRAGON: return Color(0.45, 0.28, 0.62, 1.0)
        BiomeKind.DARK: return Color(0.18, 0.16, 0.22, 1.0)
        BiomeKind.STEEL: return Color(0.68, 0.72, 0.75, 1.0)
        _: return Color.WHITE

func _landmark_threshold(biome_kind: int) -> float: # Keeps props sparse enough that the expanded regions remain readable and performant.
    match biome_kind:
        BiomeKind.GRASS, BiomeKind.BUG, BiomeKind.DARK: return 0.988
        BiomeKind.ROCK, BiomeKind.GROUND, BiomeKind.ICE: return 0.978
        BiomeKind.ELECTRIC, BiomeKind.STEEL, BiomeKind.FIRE: return 0.986
        _: return 0.982

func _landmark_height_offset(biome_kind: int) -> float: # Places each primitive around its visual base rather than its geometric centre.
    match biome_kind:
        BiomeKind.FIRE, BiomeKind.FIGHTING, BiomeKind.FLYING, BiomeKind.DRAGON, BiomeKind.STEEL: return 0.90
        BiomeKind.ELECTRIC: return 1.15
        BiomeKind.ICE, BiomeKind.PSYCHIC, BiomeKind.GHOST: return 0.82
        _: return 0.30

func _landmark_roughness(biome_kind: int) -> float: # Lets ice/steel/electric props catch more light than natural stone and vegetation.
    match biome_kind:
        BiomeKind.ICE: return 0.28
        BiomeKind.STEEL: return 0.38
        BiomeKind.ELECTRIC: return 0.45
        _: return 0.90

func _biome_slug(biome_kind: int) -> String: # Produces stable generated-node names for debugger inspection.
    match biome_kind:
        BiomeKind.NORMAL: return "normal"
        BiomeKind.FIRE: return "fire"
        BiomeKind.WATER: return "water"
        BiomeKind.ELECTRIC: return "electric"
        BiomeKind.GRASS: return "grass"
        BiomeKind.ICE: return "ice"
        BiomeKind.FIGHTING: return "fighting"
        BiomeKind.POISON: return "poison"
        BiomeKind.GROUND: return "ground"
        BiomeKind.FLYING: return "flying"
        BiomeKind.PSYCHIC: return "psychic"
        BiomeKind.BUG: return "bug"
        BiomeKind.ROCK: return "rock"
        BiomeKind.GHOST: return "ghost"
        BiomeKind.DRAGON: return "dragon"
        BiomeKind.DARK: return "dark"
        BiomeKind.STEEL: return "steel"
        _: return "unknown"

func _hash01(cell: Vector2i, salt: int) -> float: # Produces deterministic pseudo-random variation without mutable RNG state.
    var value: float = sin(float(cell.x * 127 + cell.y * 311 + salt * 71)) * 43758.5453
    return value - floor(value)

func _cell_to_local_2d(cell: Vector2i) -> Vector2: # Converts a cell index into centred coordinates measured in cells.
    return Vector2(float(cell.x) - float(WORLD_WIDTH) * 0.5 + 0.5, float(cell.y) - float(WORLD_DEPTH) * 0.5 + 0.5)

func _local_to_cell(local: Vector2) -> Vector2i: # Converts type-layout coordinates back into a clamped grid cell.
    var cell_x: int = clampi(int(floor(local.x + float(WORLD_WIDTH) * 0.5)), 0, WORLD_WIDTH - 1)
    var cell_z: int = clampi(int(floor(local.y + float(WORLD_DEPTH) * 0.5)), 0, WORLD_DEPTH - 1)
    return Vector2i(cell_x, cell_z)

func _is_cell_in_bounds(cell: Vector2i) -> bool: # Tests whether a cell lies inside generated world dimensions.
    return cell.x >= 0 and cell.x < WORLD_WIDTH and cell.y >= 0 and cell.y < WORLD_DEPTH
