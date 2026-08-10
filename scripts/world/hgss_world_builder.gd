class_name HgssWorldBuilder # Owns the procedural world layout, flat-color visuals, collision, and navigation queries.
extends Node3D # Keeps all generated world geometry beneath one scene node.

enum TerrainKind { GRASS, PATH, TALL_GRASS, WATER, STONE } # Defines the small semantic terrain vocabulary used by gameplay and rendering.

const WORLD_WIDTH: int = 96 # Defines the number of terrain cells from west to east.
const WORLD_DEPTH: int = 80 # Defines the number of terrain cells from north to south.
const TILE_SIZE: float = 1.5 # Defines the world-space width and depth of one terrain cell.
const WATER_LEVEL: float = -0.28 # Places water slightly below adjacent walkable terrain.
const TREE_BLOCKER_HEIGHT: float = 2.8 # Defines the height of forest blocker collision and debug objects.

const GRASS_COLOR: Color = Color(0.34, 0.62, 0.36, 1.0) # Represents ordinary walkable grass.
const PATH_COLOR: Color = Color(0.76, 0.66, 0.43, 1.0) # Represents paths and bridge surfaces.
const TALL_GRASS_COLOR: Color = Color(0.19, 0.46, 0.24, 1.0) # Represents encounter grass.
const WATER_COLOR: Color = Color(0.22, 0.50, 0.76, 1.0) # Represents non-walkable water.
const STONE_COLOR: Color = Color(0.50, 0.52, 0.50, 1.0) # Represents stone and raised plaza terrain.
const FOREST_COLOR: Color = Color(0.12, 0.31, 0.16, 1.0) # Represents tree/forest blockers.

var blocked_cells: Dictionary = {} # Stores cells occupied by hard forest obstacles.
var terrain_cache: Dictionary = {} # Stores terrain classification so all systems share one deterministic layout.
var entry_spawn_positions: Array[Vector3] = [] # Stores off-map positions used by roaming Pokémon.
var entry_target_positions: Array[Vector3] = [] # Stores matching walkable positions just inside each map entrance.

func _ready() -> void: # Builds the complete procedural world with no external world-art dependencies.
    add_to_group(&"world_builder") # Exposes this component to navigation and roaming systems without a scene-path dependency.
    _prepare_layout_cache() # Classifies terrain and blockers once before any geometry is created.
    _build_terrain_geometry() # Creates flat-color terrain plus one combined static collision mesh.
    _build_forest_visuals() # Represents forest blockers with simple built-in box primitives.
    _prepare_entry_points() # Creates the four route gates used by temporary roaming Pokémon.

func get_random_entry_pair(random: RandomNumberGenerator) -> Array[Vector3]: # Returns one spawn point and its corresponding walkable interior target.
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

func cell_to_world(cell: Vector2i) -> Vector3: # Converts one grid-cell centre into world coordinates at the generated elevation.
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

func _build_terrain_geometry() -> void: # Builds batched flat-color surfaces and a single static collision body.
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

func _build_forest_visuals() -> void: # Represents every forest blocker with one simple flat-color box.
    var tree_cells: Array[Vector2i] = []
    for key: Variant in blocked_cells.keys():
        var tree_cell: Vector2i = key
        tree_cells.append(tree_cell)
    if tree_cells.is_empty():
        return
    var forest_mesh: BoxMesh = BoxMesh.new()
    forest_mesh.size = Vector3(TILE_SIZE * 0.72, TREE_BLOCKER_HEIGHT, TILE_SIZE * 0.72)
    forest_mesh.material = _create_flat_material(FOREST_COLOR)
    _create_tree_multimesh("forest_blocks", forest_mesh, tree_cells, TREE_BLOCKER_HEIGHT * 0.5)

func _create_tree_multimesh(node_name: String, source_mesh: Mesh, tree_cells: Array[Vector2i], height_offset: float) -> void: # Batches repeated object markers into one renderer.
    var multi_mesh: MultiMesh = MultiMesh.new()
    multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
    multi_mesh.instance_count = tree_cells.size()
    multi_mesh.mesh = source_mesh
    for index: int in range(tree_cells.size()):
        var world_position: Vector3 = cell_to_world(tree_cells[index])
        world_position.y += height_offset
        multi_mesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, world_position))
    var multi_mesh_instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
    multi_mesh_instance.name = node_name
    multi_mesh_instance.multimesh = multi_mesh
    add_child(multi_mesh_instance)

func _create_terrain_materials() -> Dictionary: # Creates one untextured material for each semantic terrain type.
    var materials: Dictionary = {}
    materials[TerrainKind.GRASS] = _create_flat_material(GRASS_COLOR)
    materials[TerrainKind.PATH] = _create_flat_material(PATH_COLOR)
    materials[TerrainKind.TALL_GRASS] = _create_flat_material(TALL_GRASS_COLOR)
    materials[TerrainKind.WATER] = _create_flat_material(WATER_COLOR)
    materials[TerrainKind.STONE] = _create_flat_material(STONE_COLOR)
    return materials

func _create_flat_material(color: Color) -> StandardMaterial3D: # Creates an opaque untextured debug material.
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = color
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material

func _get_cell_corners(cell: Vector2i, terrain_kind: TerrainKind) -> Array[Vector3]: # Returns the four world-space corners for one generated terrain cell.
    var x0: float = (float(cell.x) - float(WORLD_WIDTH) * 0.5) * TILE_SIZE
    var x1: float = x0 + TILE_SIZE
    var z0: float = (float(cell.y) - float(WORLD_DEPTH) * 0.5) * TILE_SIZE
    var z1: float = z0 + TILE_SIZE
    if terrain_kind == TerrainKind.WATER:
        return [Vector3(x0, WATER_LEVEL, z0), Vector3(x1, WATER_LEVEL, z0), Vector3(x1, WATER_LEVEL, z1), Vector3(x0, WATER_LEVEL, z1)]
    return [Vector3(x0, _sample_height(x0, z0), z0), Vector3(x1, _sample_height(x1, z0), z0), Vector3(x1, _sample_height(x1, z1), z1), Vector3(x0, _sample_height(x0, z1), z1)]

func _append_quad_to_surface(surface_tool: SurfaceTool, corners: Array[Vector3]) -> void: # Adds one terrain quad as two triangles with no UV or texture data.
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

func _append_water_boundary_faces(cell: Vector2i, corners: Array[Vector3], faces: PackedVector3Array) -> void: # Adds vertical collision walls beside water and the world edge.
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

func _append_blocker_faces(corners: Array[Vector3], faces: PackedVector3Array) -> void: # Adds vertical collision around one forest-blocker cell.
    for edge_index: int in range(4):
        var next_index: int = (edge_index + 1) % 4
        var bottom_a: Vector3 = corners[edge_index]
        var bottom_b: Vector3 = corners[next_index]
        var top_a: Vector3 = bottom_a + Vector3.UP * TREE_BLOCKER_HEIGHT
        var top_b: Vector3 = bottom_b + Vector3.UP * TREE_BLOCKER_HEIGHT
        _append_wall_quad(faces, top_a, top_b, bottom_b, bottom_a)

func _append_wall_quad(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void: # Adds an arbitrary four-corner wall as two collision triangles.
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

func _calculate_terrain_for_cell(cell: Vector2i) -> TerrainKind: # Generates the terrain category for one cell from the established layout rules.
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

func _calculate_tree_for_cell(cell: Vector2i, terrain_kind: TerrainKind) -> bool: # Determines whether a solid terrain cell contains a forest obstacle.
    if terrain_kind == TerrainKind.WATER or terrain_kind == TerrainKind.PATH or terrain_kind == TerrainKind.STONE:
        return false
    var local: Vector2 = _cell_to_local_2d(cell)
    if _is_near_gateway(local):
        return false
    var edge_forest: bool = absf(local.x) > 40.0 or absf(local.y) > 33.0
    var west_wood: bool = local.x < -22.0 and local.y < 10.0 and sin(local.x * 0.55 + local.y * 0.37) > -0.15
    var northeast_wood: bool = local.x > 22.0 and local.y < -15.0 and cos(local.x * 0.45 - local.y * 0.33) > 0.15
    var grove: bool = local.x > 8.0 and local.x < 22.0 and local.y > 18.0 and sin(local.x * 0.8) + cos(local.y * 0.7) > 0.55
    return edge_forest or west_wood or northeast_wood or grove

func _is_water(local: Vector2) -> bool: # Defines the existing river, lake, and pond.
    var river_centre_x: float = 11.0 + sin(local.y * 0.18) * 5.0
    var river: bool = absf(local.x - river_centre_x) < 2.4
    var lake_offset: Vector2 = Vector2((local.x - 27.0) / 10.0, (local.y - 20.0) / 7.0)
    var lake: bool = lake_offset.length_squared() < 1.0
    var pond_offset: Vector2 = Vector2((local.x + 27.0) / 5.0, (local.y - 19.0) / 4.0)
    var pond: bool = pond_offset.length_squared() < 1.0
    return river or lake or pond

func _is_bridge(local: Vector2) -> bool: # Defines the two existing route crossings over the river.
    var first_bridge: bool = absf(local.y - 7.0) < 1.6 and local.x > 6.0 and local.x < 18.0
    var second_bridge: bool = absf(local.y + 29.0) < 1.6 and local.x > 5.0 and local.x < 20.0
    return first_bridge or second_bridge

func _is_path(local: Vector2) -> bool: # Defines the existing connected route network.
    var main_route: bool = absf(local.x) < 2.5
    var east_route: bool = absf(local.y - 7.0) < 2.1 and local.x > -6.0 and local.x < 39.0
    var west_route: bool = absf(local.y + 6.0) < 2.0 and local.x > -39.0 and local.x < 5.0
    var south_curve_y: float = 22.0 + sin(local.x * 0.15) * 5.0
    var south_curve: bool = absf(local.y - south_curve_y) < 1.8 and local.x > -34.0 and local.x < 34.0
    var north_curve_y: float = -28.0 + sin(local.x * 0.20) * 4.0
    var north_curve: bool = absf(local.y - north_curve_y) < 1.7 and local.x > -24.0 and local.x < 34.0
    return main_route or east_route or west_route or south_curve or north_curve

func _is_stone_area(local: Vector2) -> bool: # Defines the existing raised plaza and northern pass.
    var east_plaza: bool = local.x > 24.0 and local.x < 38.0 and local.y > -11.0 and local.y < 11.0
    var northern_pass: bool = local.y < -34.0 and absf(local.x) < 15.0
    return east_plaza or northern_pass

func _is_tall_grass(local: Vector2) -> bool: # Defines deterministic encounter-grass patches.
    var field_pattern: float = sin(local.x * 0.31) + cos(local.y * 0.27) + sin((local.x + local.y) * 0.17)
    var broad_field: bool = field_pattern > 1.05
    var route_patch: bool = local.x > -18.0 and local.x < 18.0 and local.y > 10.0 and local.y < 31.0
    return broad_field or route_patch

func _sample_height(local_x: float, local_z: float) -> float: # Defines the unchanged continuous 3D elevation field.
    var north_rise: float = clampf((-local_z - 15.0) / 26.0, 0.0, 1.0) * 4.0
    var east_distance: float = maxf(absf(local_x - 31.0) - 8.0, 0.0) + maxf(absf(local_z) - 13.0, 0.0)
    var east_rise: float = clampf(1.0 - east_distance / 7.0, 0.0, 1.0) * 1.5
    var hill_dx: float = (local_x + 24.0) / 14.0
    var hill_dz: float = (local_z + 16.0) / 11.0
    var west_hill: float = exp(-(hill_dx * hill_dx + hill_dz * hill_dz)) * 1.8
    return north_rise + east_rise + west_hill

func _prepare_entry_points() -> void: # Defines the same four route gates around the world.
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

func _cell_to_local_2d(cell: Vector2i) -> Vector2: # Converts a cell index into centred coordinates measured in cells.
    return Vector2(float(cell.x) - float(WORLD_WIDTH) * 0.5 + 0.5, float(cell.y) - float(WORLD_DEPTH) * 0.5 + 0.5)

func _is_near_gateway(local: Vector2) -> bool: # Keeps generated forest blockers away from route entrances.
    var south_gate: bool = absf(local.x) < 4.0 and local.y > 32.0
    var north_gate: bool = absf(local.x) < 4.0 and local.y < -32.0
    var west_gate: bool = local.x < -40.0 and absf(local.y + 4.0) < 4.0
    var east_gate: bool = local.x > 40.0 and absf(local.y - 5.0) < 4.0
    return south_gate or north_gate or west_gate or east_gate

func _is_cell_in_bounds(cell: Vector2i) -> bool: # Tests whether a cell lies inside the generated world dimensions.
    return cell.x >= 0 and cell.x < WORLD_WIDTH and cell.y >= 0 and cell.y < WORLD_DEPTH
