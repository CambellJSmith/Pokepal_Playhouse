class_name HgssWorldBuilder # Owns the procedural world layout, visuals, collision, and navigation queries.
extends Node3D # Keeps generated world geometry beneath one scene node.

enum TerrainKind { GRASS, PATH, TALL_GRASS, WATER, STONE } # Shared semantic terrain categories for rendering and gameplay.

const WORLD_WIDTH: int = 96 # Number of terrain cells from west to east.
const WORLD_DEPTH: int = 80 # Number of terrain cells from north to south.
const TILE_SIZE: float = 1.5 # World-space size of one terrain cell.
const WATER_LEVEL: float = -0.28 # Water surface height beneath ordinary ground.
const TREE_BLOCKER_HEIGHT: float = 2.8 # Collision height used by tree-occupied cells.

const GRASS_COLOR: Color = Color(0.36, 0.64, 0.39, 1.0) # Ordinary meadow grass.
const PATH_COLOR: Color = Color(0.78, 0.68, 0.46, 1.0) # Dirt routes and plazas.
const TALL_GRASS_COLOR: Color = Color(0.22, 0.50, 0.27, 1.0) # Encounter grass.
const WATER_COLOR: Color = Color(0.24, 0.56, 0.78, 0.82) # Semi-transparent surface water.
const WATER_DEPTH_COLOR: Color = Color(0.10, 0.31, 0.46, 1.0) # Opaque depth layer beneath water.
const STONE_COLOR: Color = Color(0.53, 0.55, 0.52, 1.0) # Stone plazas and highland ground.
const TREE_TRUNK_COLOR: Color = Color(0.31, 0.19, 0.10, 1.0) # Tree trunks.
const TREE_LEAF_DARK_COLOR: Color = Color(0.14, 0.36, 0.17, 1.0) # Lower canopy.
const TREE_LEAF_LIGHT_COLOR: Color = Color(0.23, 0.49, 0.23, 1.0) # Upper canopy.
const BRIDGE_COLOR: Color = Color(0.46, 0.29, 0.14, 1.0) # Wooden bridge decks.
const ROCK_COLOR: Color = Color(0.42, 0.44, 0.42, 1.0) # Shoreline and highland rocks.
const SHRUB_COLOR: Color = Color(0.18, 0.42, 0.20, 1.0) # Small decorative shrubs.

var blocked_cells: Dictionary = {} # Cells occupied by hard tree obstacles.
var terrain_cache: Dictionary = {} # Cached terrain classification shared by rendering and AI.
var entry_spawn_positions: Array[Vector3] = [] # Off-map positions used by roaming Pokémon.
var entry_target_positions: Array[Vector3] = [] # Matching walkable positions inside each entrance.

func _ready() -> void: # Builds the complete procedural world with no external world-art assets.
    add_to_group(&"world_builder") # Exposes this component without coupling systems to a scene path.
    _prepare_layout_cache() # Classifies terrain and blockers once before geometry is created.
    _prune_isolated_walkable_regions() # Folds tiny unreachable pockets into surrounding woodland before physics/navigation are built.
    _build_terrain_geometry() # Creates terrain visuals and the combined static collision mesh.
    _build_environment_visuals() # Adds trees, bridge decks, rocks, shrubs, and water depth.
    _prepare_entry_points() # Creates route gates for temporary roaming Pokémon.

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
    for radius_cells: int in range(0, 16):
        for offset_x: int in range(-radius_cells, radius_cells + 1):
            for offset_z: int in range(-radius_cells, radius_cells + 1):
                var candidate: Vector2i = centre_cell + Vector2i(offset_x, offset_z)
                if is_cell_walkable(candidate):
                    return cell_to_world(candidate)
    return Vector3.ZERO

func is_cell_walkable(cell: Vector2i) -> bool: # Reports whether a grid cell can be used by ground movement.
    if not _is_cell_in_bounds(cell):
        return false
    if blocked_cells.has(cell):
        return false
    return _terrain_for_cell(cell) != TerrainKind.WATER

func cell_to_world(cell: Vector2i) -> Vector3: # Converts one grid-cell centre into world coordinates at generated elevation.
    var local_x: float = (float(cell.x) - float(WORLD_WIDTH) * 0.5 + 0.5) * TILE_SIZE
    var local_z: float = (float(cell.y) - float(WORLD_DEPTH) * 0.5 + 0.5) * TILE_SIZE
    var local_y: float = _sample_height(local_x, local_z)
    return Vector3(local_x, local_y + 0.06, local_z)

func world_to_cell(world_position: Vector3) -> Vector2i: # Converts world coordinates back into an integer terrain cell.
    var cell_x: int = int(floor(world_position.x / TILE_SIZE + float(WORLD_WIDTH) * 0.5))
    var cell_z: int = int(floor(world_position.z / TILE_SIZE + float(WORLD_DEPTH) * 0.5))
    return Vector2i(cell_x, cell_z)

func _prepare_layout_cache() -> void: # Classifies every cell so rendering, collision, and AI use exactly the same map.
    blocked_cells.clear()
    terrain_cache.clear()
    for cell_z: int in range(WORLD_DEPTH):
        for cell_x: int in range(WORLD_WIDTH):
            var cell: Vector2i = Vector2i(cell_x, cell_z)
            var terrain_kind: TerrainKind = _calculate_terrain_for_cell(cell)
            terrain_cache[cell] = terrain_kind
            if _calculate_tree_for_cell(cell, terrain_kind):
                blocked_cells[cell] = true

func _prune_isolated_walkable_regions() -> void: # Ensures every visible open region belongs to the main explorable landmass.
    var start_cell: Vector2i = Vector2i(WORLD_WIDTH / 2, WORLD_DEPTH / 2)
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
            terrain_cache[cell] = TerrainKind.GRASS
            blocked_cells[cell] = true

func _build_terrain_geometry() -> void: # Builds batched shaded terrain surfaces and one static collision body.
    var materials: Dictionary = _create_terrain_materials()
    var tools: Dictionary = {}
    var vertex_counts: Dictionary = {}
    for terrain_kind: int in range(TerrainKind.size()):
        var surface_tool: SurfaceTool = SurfaceTool.new()
        surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
        surface_tool.set_material(materials[terrain_kind] as Material)
        tools[terrain_kind] = surface_tool
        vertex_counts[terrain_kind] = 0
    var collision_faces: PackedVector3Array = PackedVector3Array()
    for cell_z: int in range(WORLD_DEPTH):
        for cell_x: int in range(WORLD_WIDTH):
            var cell: Vector2i = Vector2i(cell_x, cell_z)
            var terrain_kind: TerrainKind = _terrain_for_cell(cell)
            var corners: Array[Vector3] = _get_cell_corners(cell, terrain_kind)
            var surface_tool: SurfaceTool = tools[terrain_kind] as SurfaceTool
            _append_quad_to_surface(surface_tool, corners)
            vertex_counts[terrain_kind] = int(vertex_counts[terrain_kind]) + 6
            if terrain_kind != TerrainKind.WATER:
                _append_quad_faces(collision_faces, corners)
                _append_water_boundary_faces(cell, corners, collision_faces)
            if blocked_cells.has(cell):
                _append_blocker_faces(corners, collision_faces)
    for terrain_kind: int in range(TerrainKind.size()):
        if int(vertex_counts[terrain_kind]) <= 0:
            continue
        var surface_tool: SurfaceTool = tools[terrain_kind] as SurfaceTool
        surface_tool.generate_normals()
        var mesh: ArrayMesh = surface_tool.commit()
        var mesh_instance: MeshInstance3D = MeshInstance3D.new()
        mesh_instance.name = "terrain_" + str(terrain_kind)
        mesh_instance.mesh = mesh
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

func _build_environment_visuals() -> void: # Adds lightweight generated scenery without changing navigation rules.
    _build_water_depth_visual()
    _build_tree_visuals()
    _build_bridge_visuals()
    _build_rock_visuals()
    _build_shrub_visuals()

func _build_water_depth_visual() -> void: # Gives water visible depth and keeps the river visually continuous beneath bridges.
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
            var water_cell: bool = _terrain_for_cell(cell) == TerrainKind.WATER
            var bridge_cell: bool = _is_bridge(local)
            if not water_cell and not bridge_cell:
                continue
            var surface_corners: Array[Vector3] = _get_cell_corners(cell, TerrainKind.WATER)
            var depth_corners: Array[Vector3] = surface_corners.duplicate()
            for corner_index: int in range(depth_corners.size()):
                depth_corners[corner_index].y = WATER_LEVEL - 0.55
            _append_quad_to_surface(depth_tool, depth_corners)
            depth_vertex_count += 6
            if bridge_cell:
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

func _build_tree_visuals() -> void: # Replaces blocker boxes with low-poly trunk and canopy tree models.
    var tree_cells: Array[Vector2i] = []
    for key: Variant in blocked_cells.keys():
        var tree_cell: Vector2i = key
        tree_cells.append(tree_cell)
    if tree_cells.is_empty():
        return
    var trunk_mesh: CylinderMesh = CylinderMesh.new()
    trunk_mesh.top_radius = 0.18
    trunk_mesh.bottom_radius = 0.25
    trunk_mesh.height = 1.35
    trunk_mesh.radial_segments = 7
    trunk_mesh.rings = 1
    trunk_mesh.material = _create_ground_material(TREE_TRUNK_COLOR, 0.95)
    var lower_canopy_mesh: SphereMesh = SphereMesh.new()
    lower_canopy_mesh.radius = 0.78
    lower_canopy_mesh.height = 1.25
    lower_canopy_mesh.radial_segments = 8
    lower_canopy_mesh.rings = 4
    lower_canopy_mesh.material = _create_ground_material(TREE_LEAF_DARK_COLOR, 0.9)
    var upper_canopy_mesh: SphereMesh = SphereMesh.new()
    upper_canopy_mesh.radius = 0.58
    upper_canopy_mesh.height = 0.95
    upper_canopy_mesh.radial_segments = 8
    upper_canopy_mesh.rings = 4
    upper_canopy_mesh.material = _create_ground_material(TREE_LEAF_LIGHT_COLOR, 0.9)
    _create_cell_multimesh("tree_trunks", trunk_mesh, tree_cells, 0.72, 0.92, 1.08, 11)
    _create_cell_multimesh("tree_lower_canopy", lower_canopy_mesh, tree_cells, 1.70, 0.92, 1.08, 11)
    _create_cell_multimesh("tree_upper_canopy", upper_canopy_mesh, tree_cells, 2.30, 0.92, 1.08, 11)

func _build_bridge_visuals() -> void: # Places wooden deck geometry over every river crossing.
    var bridge_cells: Array[Vector2i] = []
    for cell_z: int in range(WORLD_DEPTH):
        for cell_x: int in range(WORLD_WIDTH):
            var cell: Vector2i = Vector2i(cell_x, cell_z)
            if _is_bridge(_cell_to_local_2d(cell)):
                bridge_cells.append(cell)
    if bridge_cells.is_empty():
        return
    var deck_mesh: BoxMesh = BoxMesh.new()
    deck_mesh.size = Vector3(TILE_SIZE * 0.96, 0.14, TILE_SIZE * 0.96)
    deck_mesh.material = _create_ground_material(BRIDGE_COLOR, 0.82)
    _create_cell_multimesh("bridge_decks", deck_mesh, bridge_cells, 0.10, 1.0, 1.0, 19)

func _build_rock_visuals() -> void: # Adds sparse low-poly rocks along shores and across stone terrain.
    var rock_cells: Array[Vector2i] = []
    for cell_z: int in range(WORLD_DEPTH):
        for cell_x: int in range(WORLD_WIDTH):
            var cell: Vector2i = Vector2i(cell_x, cell_z)
            if blocked_cells.has(cell):
                continue
            var terrain_kind: TerrainKind = _terrain_for_cell(cell)
            if terrain_kind == TerrainKind.PATH or terrain_kind == TerrainKind.WATER:
                continue
            var shore_rock: bool = _is_shore_cell(cell) and _hash01(cell, 23) > 0.82
            var highland_rock: bool = terrain_kind == TerrainKind.STONE and _hash01(cell, 29) > 0.91
            if shore_rock or highland_rock:
                rock_cells.append(cell)
    if rock_cells.is_empty():
        return
    var rock_mesh: SphereMesh = SphereMesh.new()
    rock_mesh.radius = 0.27
    rock_mesh.height = 0.38
    rock_mesh.radial_segments = 6
    rock_mesh.rings = 3
    rock_mesh.material = _create_ground_material(ROCK_COLOR, 1.0)
    _create_cell_multimesh("environment_rocks", rock_mesh, rock_cells, 0.18, 0.72, 1.28, 31)

func _build_shrub_visuals() -> void: # Adds a few non-blocking shrubs to open grass so large meadows do not look empty.
    var shrub_cells: Array[Vector2i] = []
    for cell_z: int in range(WORLD_DEPTH):
        for cell_x: int in range(WORLD_WIDTH):
            var cell: Vector2i = Vector2i(cell_x, cell_z)
            if blocked_cells.has(cell) or _terrain_for_cell(cell) != TerrainKind.GRASS:
                continue
            var local: Vector2 = _cell_to_local_2d(cell)
            if _is_near_route(local):
                continue
            if _hash01(cell, 37) > 0.975:
                shrub_cells.append(cell)
    if shrub_cells.is_empty():
        return
    var shrub_mesh: SphereMesh = SphereMesh.new()
    shrub_mesh.radius = 0.32
    shrub_mesh.height = 0.44
    shrub_mesh.radial_segments = 7
    shrub_mesh.rings = 3
    shrub_mesh.material = _create_ground_material(SHRUB_COLOR, 0.95)
    _create_cell_multimesh("meadow_shrubs", shrub_mesh, shrub_cells, 0.22, 0.75, 1.20, 41)

func _create_cell_multimesh(node_name: String, source_mesh: Mesh, cells: Array[Vector2i], height_offset: float, min_scale: float, max_scale: float, salt: int) -> void: # Batches repeated scenery with deterministic scale variation.
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

func _create_terrain_materials() -> Dictionary: # Creates one shaded material for each semantic terrain type.
    var materials: Dictionary = {}
    materials[TerrainKind.GRASS] = _create_ground_material(GRASS_COLOR, 0.95)
    materials[TerrainKind.PATH] = _create_ground_material(PATH_COLOR, 1.0)
    materials[TerrainKind.TALL_GRASS] = _create_ground_material(TALL_GRASS_COLOR, 0.92)
    materials[TerrainKind.WATER] = _create_water_material()
    materials[TerrainKind.STONE] = _create_ground_material(STONE_COLOR, 0.88)
    return materials

func _create_ground_material(color: Color, roughness: float) -> StandardMaterial3D: # Creates an opaque shaded material without textures.
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material

func _create_water_material() -> StandardMaterial3D: # Creates translucent water that still responds to world lighting.
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = WATER_COLOR
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.roughness = 0.18
    material.metallic = 0.04
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material

func _get_cell_corners(cell: Vector2i, terrain_kind: TerrainKind) -> Array[Vector3]: # Returns four world-space corners for one generated terrain cell.
    var x0: float = (float(cell.x) - float(WORLD_WIDTH) * 0.5) * TILE_SIZE
    var x1: float = x0 + TILE_SIZE
    var z0: float = (float(cell.y) - float(WORLD_DEPTH) * 0.5) * TILE_SIZE
    var z1: float = z0 + TILE_SIZE
    if terrain_kind == TerrainKind.WATER:
        return [Vector3(x0, WATER_LEVEL, z0), Vector3(x1, WATER_LEVEL, z0), Vector3(x1, WATER_LEVEL, z1), Vector3(x0, WATER_LEVEL, z1)]
    return [Vector3(x0, _sample_height(x0, z0), z0), Vector3(x1, _sample_height(x1, z0), z0), Vector3(x1, _sample_height(x1, z1), z1), Vector3(x0, _sample_height(x0, z1), z1)]

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

func _append_water_boundary_faces(cell: Vector2i, corners: Array[Vector3], faces: PackedVector3Array) -> void: # Adds retaining collision beside water and the world edge.
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
        var bottom_a: Vector3 = Vector3(top_a.x, WATER_LEVEL - 1.4, top_a.z)
        var bottom_b: Vector3 = Vector3(top_b.x, WATER_LEVEL - 1.4, top_b.z)
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

func _terrain_for_cell(cell: Vector2i) -> TerrainKind: # Reads cached terrain or treats out-of-bounds space as water.
    if not _is_cell_in_bounds(cell):
        return TerrainKind.WATER
    return terrain_cache.get(cell, TerrainKind.GRASS) as TerrainKind

func _calculate_terrain_for_cell(cell: Vector2i) -> TerrainKind: # Generates terrain from broad connected regions instead of isolated patches.
    var local: Vector2 = _cell_to_local_2d(cell)
    if _is_bridge(local):
        return TerrainKind.PATH
    if _is_water(local):
        return TerrainKind.WATER
    if _is_stone_area(local):
        return TerrainKind.STONE
    if _is_path(local):
        return TerrainKind.PATH
    if _is_tall_grass(local):
        return TerrainKind.TALL_GRASS
    return TerrainKind.GRASS

func _calculate_tree_for_cell(cell: Vector2i, terrain_kind: TerrainKind) -> bool: # Creates recognizable woods while preserving broad clearings and route shoulders.
    if terrain_kind == TerrainKind.WATER or terrain_kind == TerrainKind.PATH or terrain_kind == TerrainKind.STONE:
        return false
    var local: Vector2 = _cell_to_local_2d(cell)
    if _is_near_gateway(local) or _is_near_route(local):
        return false
    var west_clearing: bool = Vector2((local.x + 29.0) / 5.0, (local.y + 2.0) / 5.5).length_squared() < 1.0
    var northeast_clearing: bool = Vector2((local.x - 30.0) / 5.0, (local.y + 24.0) / 4.5).length_squared() < 1.0
    if west_clearing or northeast_clearing:
        return false
    var edge_forest: bool = absf(local.x) > 43.0 or absf(local.y) > 35.0
    var west_zone: bool = Vector2((local.x + 30.0) / 11.0, (local.y + 2.0) / 14.0).length_squared() < 1.0
    var northeast_zone: bool = Vector2((local.x - 30.0) / 10.0, (local.y + 24.0) / 9.0).length_squared() < 1.0
    var southeast_zone: bool = Vector2((local.x - 17.0) / 9.0, (local.y - 28.0) / 7.0).length_squared() < 1.0
    var density: float = _hash01(cell, 7)
    var woodland_tree: bool = west_zone and density > 0.46
    var highland_tree: bool = northeast_zone and density > 0.50
    var grove_tree: bool = southeast_zone and density > 0.58
    return edge_forest or woodland_tree or highland_tree or grove_tree

func _is_water(local: Vector2) -> bool: # Defines one narrower river plus two contained bodies of water.
    var river_centre_x: float = 10.5 + sin(local.y * 0.17) * 4.4
    var river: bool = absf(local.x - river_centre_x) < 1.9
    var lake_offset: Vector2 = Vector2((local.x - 28.0) / 9.0, (local.y - 20.0) / 6.5)
    var lake: bool = lake_offset.length_squared() < 1.0
    var pond_offset: Vector2 = Vector2((local.x + 28.0) / 4.6, (local.y - 19.0) / 3.8)
    var pond: bool = pond_offset.length_squared() < 1.0
    return river or lake or pond

func _is_bridge(local: Vector2) -> bool: # Provides three crossings so the river no longer divides major route regions.
    var central_bridge: bool = absf(local.y - 7.0) < 1.7 and local.x > 5.0 and local.x < 17.0
    var north_bridge: bool = absf(local.y + 28.0) < 1.8 and local.x > 5.0 and local.x < 18.0
    var south_curve_y: float = 22.0 + sin(local.x * 0.15) * 4.0
    var south_bridge: bool = absf(local.y - south_curve_y) < 1.9 and local.x > 5.0 and local.x < 18.0
    return central_bridge or north_bridge or south_bridge

func _is_path(local: Vector2) -> bool: # Forms a connected route network with loops instead of isolated branches.
    var main_route: bool = absf(local.x) < 2.7
    var east_route: bool = absf(local.y - 7.0) < 2.2 and local.x > -6.0 and local.x < 39.0
    var west_route: bool = absf(local.y + 6.0) < 2.1 and local.x > -39.0 and local.x < 5.0
    var south_curve_y: float = 22.0 + sin(local.x * 0.15) * 4.0
    var south_curve: bool = absf(local.y - south_curve_y) < 1.9 and local.x > -35.0 and local.x < 35.0
    var north_curve_y: float = -28.0 + sin(local.x * 0.20) * 3.2
    var north_curve: bool = absf(local.y - north_curve_y) < 1.8 and local.x > -25.0 and local.x < 35.0
    var west_loop_link: bool = absf(local.x + 20.0) < 1.8 and local.y > -7.0 and local.y < 23.0
    var east_uplink: bool = absf(local.x - 22.0) < 1.8 and local.y > -29.0 and local.y < 8.0
    return main_route or east_route or west_route or south_curve or north_curve or west_loop_link or east_uplink

func _is_stone_area(local: Vector2) -> bool: # Defines a softer eastern plaza and northern highland destination.
    var east_plaza: bool = local.x > 26.0 and local.x < 38.0 and local.y > -8.0 and local.y < 12.0
    var northern_pass: bool = local.y < -35.0 and absf(local.x) < 14.0
    return east_plaza or northern_pass

func _is_tall_grass(local: Vector2) -> bool: # Creates broad organic meadow patches instead of one hard rectangular field.
    var field_pattern: float = sin(local.x * 0.28) + cos(local.y * 0.24) + sin((local.x + local.y) * 0.14)
    var south_meadow: bool = Vector2(local.x / 24.0, (local.y - 21.0) / 12.0).length_squared() < 1.0 and field_pattern > 0.35
    var west_meadow: bool = Vector2((local.x + 13.0) / 15.0, (local.y - 3.0) / 10.0).length_squared() < 1.0 and field_pattern > 0.85
    var scattered_patch: bool = field_pattern > 1.55 and absf(local.x) < 38.0 and absf(local.y) < 32.0
    return south_meadow or west_meadow or scattered_patch

func _sample_height(local_x: float, local_z: float) -> float: # Uses gentle broad elevation so regions read as one landscape.
    var north_rise: float = clampf((-local_z - 15.0) / 27.0, 0.0, 1.0) * 3.4
    var east_distance: float = maxf(absf(local_x - 31.0) - 8.0, 0.0) + maxf(absf(local_z) - 13.0, 0.0)
    var east_rise: float = clampf(1.0 - east_distance / 8.0, 0.0, 1.0) * 1.25
    var hill_dx: float = (local_x + 25.0) / 16.0
    var hill_dz: float = (local_z + 15.0) / 13.0
    var west_hill: float = exp(-(hill_dx * hill_dx + hill_dz * hill_dz)) * 1.35
    var meadow_roll: float = sin(local_x * 0.055) * cos(local_z * 0.06) * 0.16
    return north_rise + east_rise + west_hill + meadow_roll

func _prepare_entry_points() -> void: # Defines four route gates around the world.
    entry_spawn_positions.clear()
    entry_target_positions.clear()
    var south_cell: Vector2i = Vector2i(WORLD_WIDTH / 2, WORLD_DEPTH - 2)
    var north_cell: Vector2i = Vector2i(WORLD_WIDTH / 2, 1)
    var west_cell: Vector2i = Vector2i(1, WORLD_DEPTH / 2 - 4)
    var east_cell: Vector2i = Vector2i(WORLD_WIDTH - 2, WORLD_DEPTH / 2 + 5)
    _append_entry(south_cell, Vector3(0.0, 0.0, TILE_SIZE * 4.0))
    _append_entry(north_cell, Vector3(0.0, 0.0, -TILE_SIZE * 4.0))
    _append_entry(west_cell, Vector3(-TILE_SIZE * 4.0, 0.0, 0.0))
    _append_entry(east_cell, Vector3(TILE_SIZE * 4.0, 0.0, 0.0))

func _append_entry(edge_cell: Vector2i, outward_offset: Vector3) -> void: # Adds one route gate pair.
    var target_position: Vector3 = cell_to_world(edge_cell)
    var spawn_position: Vector3 = target_position + outward_offset
    spawn_position.y = target_position.y + 0.1
    entry_spawn_positions.append(spawn_position)
    entry_target_positions.append(target_position)

func _is_shore_cell(cell: Vector2i) -> bool: # Detects solid cells immediately beside water for sparse shoreline props.
    if not _is_cell_in_bounds(cell) or _terrain_for_cell(cell) == TerrainKind.WATER:
        return false
    var neighbours: Array[Vector2i] = [cell + Vector2i(1, 0), cell + Vector2i(-1, 0), cell + Vector2i(0, 1), cell + Vector2i(0, -1)]
    for neighbour: Vector2i in neighbours:
        if _is_cell_in_bounds(neighbour) and _terrain_for_cell(neighbour) == TerrainKind.WATER:
            return true
    return false

func _is_near_route(local: Vector2) -> bool: # Keeps tree blockers and shrubs off generous route shoulders.
    var clearance: float = 2.4
    return _is_path(local) or _is_bridge(local) or _is_path(local + Vector2(clearance, 0.0)) or _is_path(local + Vector2(-clearance, 0.0)) or _is_path(local + Vector2(0.0, clearance)) or _is_path(local + Vector2(0.0, -clearance))

func _hash01(cell: Vector2i, salt: int) -> float: # Produces deterministic pseudo-random variation without mutable RNG state.
    var value: float = sin(float(cell.x * 127 + cell.y * 311 + salt * 71)) * 43758.5453
    return value - floor(value)

func _cell_to_local_2d(cell: Vector2i) -> Vector2: # Converts a cell index into centred coordinates measured in cells.
    return Vector2(float(cell.x) - float(WORLD_WIDTH) * 0.5 + 0.5, float(cell.y) - float(WORLD_DEPTH) * 0.5 + 0.5)

func _is_near_gateway(local: Vector2) -> bool: # Keeps forest blockers away from route entrances.
    var south_gate: bool = absf(local.x) < 4.0 and local.y > 32.0
    var north_gate: bool = absf(local.x) < 4.0 and local.y < -32.0
    var west_gate: bool = local.x < -40.0 and absf(local.y + 4.0) < 4.0
    var east_gate: bool = local.x > 40.0 and absf(local.y - 5.0) < 4.0
    return south_gate or north_gate or west_gate or east_gate

func _is_cell_in_bounds(cell: Vector2i) -> bool: # Tests whether a cell lies inside generated world dimensions.
    return cell.x >= 0 and cell.x < WORLD_WIDTH and cell.y >= 0 and cell.y < WORLD_DEPTH
