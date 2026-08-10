class_name HgssWorldBuilder # Builds the large tile-driven 3D overworld and exposes walkable positions to roaming Pokémon.
extends Node3D # Keeps generated level geometry composed beneath one scene node.

enum TerrainKind { GRASS, PATH, TALL_GRASS, WATER, STONE } # Defines the small material vocabulary used to construct the overworld.

const WORLD_WIDTH: int = 96 # Defines the number of terrain cells from west to east.
const WORLD_DEPTH: int = 80 # Defines the number of terrain cells from north to south.
const TILE_SIZE: float = 1.5 # Defines the world-space width and depth represented by one source-map tile sample.
const WATER_LEVEL: float = -0.28 # Places water slightly below adjacent walkable terrain.
const TREE_BLOCKER_HEIGHT: float = 2.8 # Defines the vertical collision height around occupied forest cells.
const SOURCE_ROUTE_29: String = "res://assets/world/hgss/source_maps/route_29.png" # Supplies HGSS grass, path, and tall-grass pixels.
const SOURCE_ROUTE_6: String = "res://assets/world/hgss/source_maps/route_6.png" # Supplies HGSS water pixels.
const SOURCE_ROUTE_5: String = "res://assets/world/hgss/source_maps/route_5.png" # Supplies HGSS rocky and terrace pixels.

var blocked_cells: Dictionary = {} # Stores cells occupied by trees or other hard obstacles.
var terrain_cache: Dictionary = {} # Stores terrain classification so repeated gameplay queries avoid regenerating layout decisions.
var entry_spawn_positions: Array[Vector3] = [] # Stores off-map locations from which roaming Pokémon enter.
var entry_target_positions: Array[Vector3] = [] # Stores matching walkable positions just inside each map entrance.

func _ready() -> void: # Builds the procedural world before the player and spawner begin normal gameplay.
    add_to_group(&"world_builder") # Exposes this component semantically without coupling other systems to a scene path.
    _prepare_layout_cache() # Classifies every world cell before rendering or physics generation begins.
    _build_terrain_geometry() # Creates textured terrain meshes plus one static collision mesh.
    _build_forest_visuals() # Batches repeated tree geometry with MultiMesh instances.
    _prepare_entry_points() # Creates the four route gates used by temporary roaming Pokémon.
    if not ResourceLoader.exists(SOURCE_ROUTE_29, "Texture2D"): # Detects a clone where the optional HGSS map source images have not been downloaded yet.
        push_warning("HGSS map source images are missing. Run: bash download_hgss_world_tiles.sh") # Explains how to replace fallback colors with the actual game-map tiles.

func get_random_entry_pair(random: RandomNumberGenerator) -> Array[Vector3]: # Returns one off-map spawn point and its corresponding walkable interior destination.
    if entry_spawn_positions.is_empty(): # Guards unexpectedly early calls before entry points are prepared.
        _prepare_entry_points() # Reconstructs deterministic entry points on demand.
    var entry_index: int = random.randi_range(0, entry_spawn_positions.size() - 1) # Chooses one route gate uniformly.
    return [entry_spawn_positions[entry_index], entry_target_positions[entry_index]] # Returns spawn then arrival target in a compact typed pair.

func get_exit_target_from(world_position: Vector3) -> Vector3: # Returns the nearest off-map route gate for a departing roaming Pokémon.
    if entry_spawn_positions.is_empty(): # Guards unexpectedly early calls before entry points are prepared.
        _prepare_entry_points() # Reconstructs deterministic entry points on demand.
    var best_position: Vector3 = entry_spawn_positions[0] # Starts with the first gateway as the current nearest candidate.
    var best_distance_squared: float = world_position.distance_squared_to(best_position) # Measures the first gateway without an unnecessary square root.
    for candidate: Vector3 in entry_spawn_positions: # Compares every deterministic gateway against the Pokémon's current position.
        var distance_squared: float = world_position.distance_squared_to(candidate) # Measures this candidate in world space.
        if distance_squared < best_distance_squared: # Detects a shorter route out of the world.
            best_distance_squared = distance_squared # Stores the improved distance for later comparisons.
            best_position = candidate # Stores the matching off-map exit location.
    return best_position # Sends the Pokémon toward the nearest route gate.

func get_random_walkable_world_position_near(world_position: Vector3, radius: float, random: RandomNumberGenerator) -> Vector3: # Finds a nearby terrain cell that is safe for wandering movement.
    var centre_cell: Vector2i = world_to_cell(world_position) # Converts the current world location into map-grid coordinates.
    var radius_cells: int = maxi(1, int(ceil(radius / TILE_SIZE))) # Converts the requested world-space radius into an integer search radius.
    for attempt: int in range(32): # Tries several inexpensive random candidates before falling back to the current cell.
        var candidate: Vector2i = centre_cell + Vector2i(random.randi_range(-radius_cells, radius_cells), random.randi_range(-radius_cells, radius_cells)) # Chooses a local offset around the character.
        if is_cell_walkable(candidate): # Accepts only cells containing solid traversable terrain without a blocker.
            return cell_to_world(candidate) # Returns the terrain-aware world-space centre of the selected cell.
    if is_cell_walkable(centre_cell): # Checks whether remaining in the current cell is a valid fallback.
        return cell_to_world(centre_cell) # Keeps the Pokémon in place rather than sending it into invalid terrain.
    return get_nearest_walkable_world_position(world_position) # Recovers from an invalid current position by searching outward deterministically.

func get_nearest_walkable_world_position(world_position: Vector3) -> Vector3: # Finds the closest valid cell around an arbitrary world position.
    var centre_cell: Vector2i = world_to_cell(world_position) # Converts the query point to map-grid coordinates.
    for radius_cells: int in range(0, 16): # Expands outward until at least one walkable cell can be found.
        for offset_x: int in range(-radius_cells, radius_cells + 1): # Scans the current square ring horizontally.
            for offset_z: int in range(-radius_cells, radius_cells + 1): # Scans the current square ring vertically.
                var candidate: Vector2i = centre_cell + Vector2i(offset_x, offset_z) # Builds the candidate cell from the current ring offset.
                if is_cell_walkable(candidate): # Accepts the first valid terrain cell encountered at this radius.
                    return cell_to_world(candidate) # Returns its centre with the correct generated terrain elevation.
    return Vector3.ZERO # Provides a safe final fallback if the generated layout is unexpectedly invalid.

func is_cell_walkable(cell: Vector2i) -> bool: # Reports whether a grid cell can be used by player-like ground movement.
    if not _is_cell_in_bounds(cell): # Rejects cells beyond the generated world boundary.
        return false # Prevents roaming targets outside the playable map except explicit entry and exit points.
    if blocked_cells.has(cell): # Rejects cells occupied by forest geometry.
        return false # Keeps wandering logic from choosing locations inside tree collision.
    return _terrain_for_cell(cell) != TerrainKind.WATER # Treats every non-water surface as potentially walkable terrain.

func cell_to_world(cell: Vector2i) -> Vector3: # Converts one grid-cell centre into the generated world coordinate system.
    var local_x: float = (float(cell.x) - float(WORLD_WIDTH) * 0.5 + 0.5) * TILE_SIZE # Centres the finite grid around world-space X zero.
    var local_z: float = (float(cell.y) - float(WORLD_DEPTH) * 0.5 + 0.5) * TILE_SIZE # Centres the finite grid around world-space Z zero.
    var local_y: float = _sample_height(local_x, local_z) # Samples the same continuous height function used by the terrain mesh.
    return Vector3(local_x, local_y + 0.06, local_z) # Places characters slightly above the terrain to allow stable floor snapping.

func world_to_cell(world_position: Vector3) -> Vector2i: # Converts a world-space position back into integer terrain-grid coordinates.
    var cell_x: int = int(floor(world_position.x / TILE_SIZE + float(WORLD_WIDTH) * 0.5)) # Reverses the centred X conversion.
    var cell_z: int = int(floor(world_position.z / TILE_SIZE + float(WORLD_DEPTH) * 0.5)) # Reverses the centred Z conversion.
    return Vector2i(cell_x, cell_z) # Returns the matching terrain cell identifier.

func _prepare_layout_cache() -> void: # Classifies terrain and blockers once so rendering, collision, and AI all share exactly the same map.
    blocked_cells.clear() # Removes stale blocker data before rebuilding the deterministic layout.
    terrain_cache.clear() # Removes stale terrain classifications before rebuilding.
    for cell_z: int in range(WORLD_DEPTH): # Traverses every terrain row.
        for cell_x: int in range(WORLD_WIDTH): # Traverses every terrain column.
            var cell: Vector2i = Vector2i(cell_x, cell_z) # Creates the stable dictionary key for this map location.
            var terrain_kind: TerrainKind = _calculate_terrain_for_cell(cell) # Evaluates route, water, grass, and plaza rules once.
            terrain_cache[cell] = terrain_kind # Reuses the result throughout the rest of the session.
            if _calculate_tree_for_cell(cell, terrain_kind): # Determines whether this otherwise-solid cell is occupied by forest.
                blocked_cells[cell] = true # Records the hard obstacle for collision and roaming target selection.

func _build_terrain_geometry() -> void: # Builds batched visual surfaces and a single static collision body for the complete world.
    var materials: Dictionary = _create_terrain_materials() # Loads HGSS source-map crops or their deterministic fallback colors.
    var tools: Dictionary = {} # Stores one SurfaceTool per terrain material so each kind becomes one draw surface.
    var vertex_counts: Dictionary = {} # Tracks which SurfaceTools actually received geometry before commit.
    for terrain_kind: int in range(TerrainKind.size()): # Creates one batched procedural surface for each terrain category.
        var surface_tool: SurfaceTool = SurfaceTool.new() # Allocates the builder for this material group.
        surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES) # Uses triangles so generated normals and ordinary 3D rendering work correctly.
        surface_tool.set_material(materials[terrain_kind] as Material) # Applies the matching HGSS-derived terrain material.
        tools[terrain_kind] = surface_tool # Stores the prepared builder by terrain enum value.
        vertex_counts[terrain_kind] = 0 # Starts the geometry count for this material at zero.
    var collision_faces: PackedVector3Array = PackedVector3Array() # Accumulates top surfaces, water boundaries, and tree blockers into one static level shape.
    for cell_z: int in range(WORLD_DEPTH): # Traverses every terrain row while building geometry.
        for cell_x: int in range(WORLD_WIDTH): # Traverses every terrain column while building geometry.
            var cell: Vector2i = Vector2i(cell_x, cell_z) # Identifies the current source-map tile location.
            var terrain_kind: TerrainKind = _terrain_for_cell(cell) # Reads the cached terrain classification.
            var corners: Array[Vector3] = _get_cell_corners(cell, terrain_kind) # Samples the four 3D corners for the visible tile surface.
            var surface_tool: SurfaceTool = tools[terrain_kind] as SurfaceTool # Selects the batching surface for this terrain type.
            _append_quad_to_surface(surface_tool, corners) # Adds a source-tile-textured quad with local UVs from zero to one.
            vertex_counts[terrain_kind] = int(vertex_counts[terrain_kind]) + 6 # Records the two triangles added to this material surface.
            if terrain_kind != TerrainKind.WATER: # Adds physical floor collision only for solid terrain.
                _append_quad_faces(collision_faces, corners) # Uses exactly the same top geometry for physics as for rendering.
                _append_water_boundary_faces(cell, corners, collision_faces) # Adds retaining walls beside water and beyond the world edge.
            if blocked_cells.has(cell): # Adds hard vertical collision around cells visually occupied by trees.
                _append_blocker_faces(corners, collision_faces) # Prevents the player and roaming Pokémon from walking through forest cells.
    for terrain_kind: int in range(TerrainKind.size()): # Finalizes one MeshInstance3D for every terrain type that contains vertices.
        if int(vertex_counts[terrain_kind]) <= 0: # Skips unused terrain categories without committing an empty ArrayMesh.
            continue # Moves directly to the next material group.
        var surface_tool: SurfaceTool = tools[terrain_kind] as SurfaceTool # Retrieves the complete surface builder.
        surface_tool.generate_normals() # Generates ordinary lighting normals after all triangles have been supplied.
        var mesh: ArrayMesh = surface_tool.commit() # Compiles the generated vertex stream into a GPU-ready mesh resource.
        var mesh_instance: MeshInstance3D = MeshInstance3D.new() # Creates the scene node that renders this batched terrain surface.
        mesh_instance.name = "terrain_" + str(terrain_kind) # Gives the generated surface a stable debug-friendly name.
        mesh_instance.mesh = mesh # Assigns the committed procedural mesh.
        mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # Avoids expensive self-shadowing across thousands of tiny ground tiles.
        add_child(mesh_instance) # Adds the batched surface to the generated world.
    var world_body: StaticBody3D = StaticBody3D.new() # Creates the single physics body representing all static generated terrain.
    world_body.name = "generated_world_collision" # Gives the generated collision body a clear debugger name.
    world_body.collision_layer = 1 # Keeps level geometry on the existing world collision layer.
    world_body.collision_mask = 0 # Static world geometry does not need to scan for other bodies.
    var collision_shape: CollisionShape3D = CollisionShape3D.new() # Wraps the generated triangle mesh for StaticBody3D physics.
    var concave_shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new() # Uses one concave trimesh because this is static level geometry.
    concave_shape.backface_collision = true # Makes cliff and blocker walls robust regardless of generated triangle winding.
    concave_shape.set_faces(collision_faces) # Supplies all level triangles in one allocation.
    collision_shape.shape = concave_shape # Assigns the finished static collision resource.
    world_body.add_child(collision_shape) # Parents the collision shape beneath its StaticBody3D owner.
    add_child(world_body) # Adds the finished physics geometry to the generated world.

func _build_forest_visuals() -> void: # Creates inexpensive repeated tree trunks and crowns over every blocked forest cell.
    var tree_cells: Array[Vector2i] = [] # Collects tree positions before allocating fixed-size MultiMeshes.
    for key: Variant in blocked_cells.keys(): # Traverses every hard forest cell stored during layout generation.
        tree_cells.append(key as Vector2i) # Preserves the typed map coordinate for transform creation.
    if tree_cells.is_empty(): # Guards a future layout variant without trees.
        return # Avoids creating zero-instance MultiMeshes.
    var trunk_material: StandardMaterial3D = StandardMaterial3D.new() # Creates a simple trunk material that remains subordinate to the HGSS ground tiles.
    trunk_material.albedo_color = Color(0.28, 0.16, 0.08, 1.0) # Uses a restrained DS-era brown for repeated trunks.
    trunk_material.roughness = 1.0 # Keeps the low-poly trunks matte.
    var crown_material: StandardMaterial3D = StandardMaterial3D.new() # Creates a simple crown material for the batched forest canopy.
    crown_material.albedo_color = Color(0.20, 0.43, 0.20, 1.0) # Uses a muted green close to the HGSS route palette.
    crown_material.roughness = 1.0 # Keeps the canopy diffuse rather than glossy.
    var trunk_mesh: CylinderMesh = CylinderMesh.new() # Uses a low-sided cylinder as an inexpensive 3D trunk proxy.
    trunk_mesh.top_radius = 0.18 # Keeps the upper trunk narrow beneath the crown.
    trunk_mesh.bottom_radius = 0.25 # Gives the trunk a slight natural taper.
    trunk_mesh.height = 1.25 # Sets tree height relative to the tile-sized world scale.
    trunk_mesh.radial_segments = 6 # Preserves a deliberately simple low-poly silhouette.
    trunk_mesh.material = trunk_material # Applies the shared trunk material once for every instance.
    var crown_mesh: SphereMesh = SphereMesh.new() # Uses a compact low-poly sphere as the repeated leafy crown.
    crown_mesh.radius = 0.72 # Makes neighbouring forest crowns overlap visually like HGSS tree walls.
    crown_mesh.height = 1.25 # Keeps the crown vertically compact.
    crown_mesh.radial_segments = 8 # Limits geometry while retaining a readable rounded silhouette.
    crown_mesh.rings = 4 # Limits vertical tessellation for repeated rendering.
    crown_mesh.material = crown_material # Applies one shared canopy material to every instance.
    _create_tree_multimesh("tree_trunks", trunk_mesh, tree_cells, 0.68) # Batches all trunks into one draw-efficient object.
    _create_tree_multimesh("tree_crowns", crown_mesh, tree_cells, 1.65) # Batches all crowns separately so their vertical offsets differ.

func _create_tree_multimesh(node_name: String, source_mesh: Mesh, tree_cells: Array[Vector2i], height_offset: float) -> void: # Creates one MultiMesh layer at the requested vertical offset.
    var multi_mesh: MultiMesh = MultiMesh.new() # Allocates the instancing resource shared by this tree layer.
    multi_mesh.transform_format = MultiMesh.TRANSFORM_3D # Stores full 3D transforms for every tree instance.
    multi_mesh.instance_count = tree_cells.size() # Allocates exactly one instance for every blocked forest cell.
    multi_mesh.mesh = source_mesh # Assigns the trunk or crown mesh that will be repeated.
    for index: int in range(tree_cells.size()): # Writes one transform per deterministic tree position.
        var world_position: Vector3 = cell_to_world(tree_cells[index]) # Reads the generated terrain height at this forest cell.
        world_position.y += height_offset # Moves the requested tree component above the terrain surface.
        multi_mesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, world_position)) # Places the repeated mesh without allocating one scene node per tree.
    var multi_mesh_instance: MultiMeshInstance3D = MultiMeshInstance3D.new() # Creates the renderer for this batched tree layer.
    multi_mesh_instance.name = node_name # Preserves a useful generated-scene label.
    multi_mesh_instance.multimesh = multi_mesh # Assigns the complete instancing resource.
    add_child(multi_mesh_instance) # Adds the batched forest layer to the world.

func _create_terrain_materials() -> Dictionary: # Creates one material per terrain type using crops from real HGSS route-map images when available.
    var materials: Dictionary = {} # Stores materials by TerrainKind enum value.
    materials[TerrainKind.GRASS] = _create_tile_material(SOURCE_ROUTE_29, Rect2(0.56, 0.28, 0.0625, 0.0625), Color(0.34, 0.67, 0.49, 1.0)) # Samples open Route 29 grass.
    materials[TerrainKind.PATH] = _create_tile_material(SOURCE_ROUTE_29, Rect2(0.12, 0.46, 0.0625, 0.0625), Color(0.77, 0.67, 0.45, 1.0)) # Samples the pale Route 29 dirt path.
    materials[TerrainKind.TALL_GRASS] = _create_tile_material(SOURCE_ROUTE_29, Rect2(0.40, 0.35, 0.0625, 0.0625), Color(0.19, 0.52, 0.35, 1.0)) # Samples the darker HGSS encounter grass.
    materials[TerrainKind.WATER] = _create_tile_material(SOURCE_ROUTE_6, Rect2(0.40, 0.67, 0.0625, 0.0625), Color(0.22, 0.62, 0.78, 1.0)) # Samples the Route 6 pond surface.
    materials[TerrainKind.STONE] = _create_tile_material(SOURCE_ROUTE_5, Rect2(0.43, 0.42, 0.0625, 0.0625), Color(0.48, 0.47, 0.42, 1.0)) # Samples raised Route 5 terrain and stone detail.
    return materials # Returns the complete terrain-material lookup table.

func _create_tile_material(source_path: String, normalized_region: Rect2, fallback_color: Color) -> StandardMaterial3D: # Creates a nearest-filtered terrain material from one source-map tile crop.
    var material: StandardMaterial3D = StandardMaterial3D.new() # Allocates a conventional 3D material for this terrain surface.
    material.albedo_color = fallback_color # Ensures the map remains readable before optional source images are downloaded.
    material.roughness = 0.95 # Keeps DS-style terrain mostly diffuse under the world lighting.
    material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST # Preserves hard source pixels instead of smoothing the HGSS artwork.
    if ResourceLoader.exists(source_path, "Texture2D"): # Checks whether Godot has imported the optional route-map source image.
        var source_texture: Texture2D = ResourceLoader.load(source_path, "Texture2D") as Texture2D # Loads the source image through Godot's resource cache.
        if source_texture != null: # Guards an incomplete import without preventing the world from loading.
            var atlas_texture: AtlasTexture = AtlasTexture.new() # Creates a lightweight subregion view without copying source pixels.
            atlas_texture.atlas = source_texture # Points the cropped tile at the complete HGSS route image.
            atlas_texture.region = Rect2(normalized_region.position.x * float(source_texture.get_width()), normalized_region.position.y * float(source_texture.get_height()), normalized_region.size.x * float(source_texture.get_width()), normalized_region.size.y * float(source_texture.get_height())) # Converts normalized crop coordinates into source-image pixels at whatever resolution the host serves.
            material.albedo_texture = atlas_texture # Uses the original HGSS pixels as the terrain surface.
            material.albedo_color = Color.WHITE # Prevents fallback tinting once the real source artwork is available.
    return material # Returns either the HGSS-textured material or its deterministic fallback.

func _get_cell_corners(cell: Vector2i, terrain_kind: TerrainKind) -> Array[Vector3]: # Returns the four world-space corners for one generated terrain tile.
    var x0: float = (float(cell.x) - float(WORLD_WIDTH) * 0.5) * TILE_SIZE # Calculates the western tile edge.
    var x1: float = x0 + TILE_SIZE # Calculates the eastern tile edge.
    var z0: float = (float(cell.y) - float(WORLD_DEPTH) * 0.5) * TILE_SIZE # Calculates the northern tile edge.
    var z1: float = z0 + TILE_SIZE # Calculates the southern tile edge.
    if terrain_kind == TerrainKind.WATER: # Keeps water level independent of the surrounding hillside function.
        return [Vector3(x0, WATER_LEVEL, z0), Vector3(x1, WATER_LEVEL, z0), Vector3(x1, WATER_LEVEL, z1), Vector3(x0, WATER_LEVEL, z1)] # Returns a flat lower water quad.
    return [Vector3(x0, _sample_height(x0, z0), z0), Vector3(x1, _sample_height(x1, z0), z0), Vector3(x1, _sample_height(x1, z1), z1), Vector3(x0, _sample_height(x0, z1), z1)] # Returns terrain corners sampled from the continuous height field.

func _append_quad_to_surface(surface_tool: SurfaceTool, corners: Array[Vector3]) -> void: # Adds one upward-facing textured tile as two triangles.
    _add_surface_vertex(surface_tool, corners[0], Vector2(0.0, 0.0)) # Adds the northwest corner of the first triangle.
    _add_surface_vertex(surface_tool, corners[2], Vector2(1.0, 1.0)) # Adds the southeast corner of the first triangle.
    _add_surface_vertex(surface_tool, corners[1], Vector2(1.0, 0.0)) # Adds the northeast corner of the first triangle with upward winding.
    _add_surface_vertex(surface_tool, corners[0], Vector2(0.0, 0.0)) # Reuses the northwest corner for the second triangle.
    _add_surface_vertex(surface_tool, corners[3], Vector2(0.0, 1.0)) # Adds the southwest corner of the second triangle.
    _add_surface_vertex(surface_tool, corners[2], Vector2(1.0, 1.0)) # Adds the southeast corner of the second triangle.

func _add_surface_vertex(surface_tool: SurfaceTool, position: Vector3, uv: Vector2) -> void: # Supplies one UV and vertex pair to SurfaceTool in the required attribute order.
    surface_tool.set_uv(uv) # Stores the source-tile coordinate for the next vertex.
    surface_tool.add_vertex(position) # Captures the UV together with the world-space vertex position.

func _append_quad_faces(faces: PackedVector3Array, corners: Array[Vector3]) -> void: # Adds one upward-facing terrain quad to the static collision triangle list.
    faces.append(corners[0]) # Adds triangle one vertex A.
    faces.append(corners[2]) # Adds triangle one vertex B.
    faces.append(corners[1]) # Adds triangle one vertex C.
    faces.append(corners[0]) # Adds triangle two vertex A.
    faces.append(corners[3]) # Adds triangle two vertex B.
    faces.append(corners[2]) # Adds triangle two vertex C.

func _append_water_boundary_faces(cell: Vector2i, corners: Array[Vector3], faces: PackedVector3Array) -> void: # Adds vertical retaining walls wherever solid terrain borders water or the world edge.
    var neighbours: Array[Vector2i] = [cell + Vector2i(0, -1), cell + Vector2i(1, 0), cell + Vector2i(0, 1), cell + Vector2i(-1, 0)] # Lists north, east, south, and west neighbours in corner order.
    var edge_pairs: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 0)] # Maps each neighbour to the matching two top corners.
    for edge_index: int in range(4): # Examines every side of the current solid terrain cell.
        var neighbour: Vector2i = neighbours[edge_index] # Reads the adjacent map cell for this side.
        var needs_wall: bool = not _is_cell_in_bounds(neighbour) or _terrain_for_cell(neighbour) == TerrainKind.WATER # Detects exposed terrain next to water or beyond the generated world.
        if not needs_wall: # Leaves continuous solid terrain without an unnecessary internal wall.
            continue # Moves to the next side.
        var pair: Vector2i = edge_pairs[edge_index] # Selects the two matching top edge vertices.
        var top_a: Vector3 = corners[pair.x] # Reads the first top edge point.
        var top_b: Vector3 = corners[pair.y] # Reads the second top edge point.
        var bottom_a: Vector3 = Vector3(top_a.x, WATER_LEVEL - 1.4, top_a.z) # Drops the first point below visible water level.
        var bottom_b: Vector3 = Vector3(top_b.x, WATER_LEVEL - 1.4, top_b.z) # Drops the second point below visible water level.
        _append_wall_quad(faces, top_a, top_b, bottom_b, bottom_a) # Adds a two-triangle retaining wall to the collision mesh.

func _append_blocker_faces(corners: Array[Vector3], faces: PackedVector3Array) -> void: # Adds four vertical collision walls around one tree-occupied cell.
    for edge_index: int in range(4): # Builds one wall for each side of the occupied tile.
        var next_index: int = (edge_index + 1) % 4 # Selects the next corner around the tile perimeter.
        var bottom_a: Vector3 = corners[edge_index] # Uses the generated terrain edge as the bottom of the blocker.
        var bottom_b: Vector3 = corners[next_index] # Uses the neighbouring terrain corner as the other blocker bottom.
        var top_a: Vector3 = bottom_a + Vector3.UP * TREE_BLOCKER_HEIGHT # Raises the first blocker point above character height.
        var top_b: Vector3 = bottom_b + Vector3.UP * TREE_BLOCKER_HEIGHT # Raises the second blocker point above character height.
        _append_wall_quad(faces, top_a, top_b, bottom_b, bottom_a) # Adds the solid side wall to the shared static collision mesh.

func _append_wall_quad(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void: # Adds an arbitrary four-corner vertical wall as two triangles.
    faces.append(a) # Adds triangle one vertex A.
    faces.append(b) # Adds triangle one vertex B.
    faces.append(c) # Adds triangle one vertex C.
    faces.append(a) # Adds triangle two vertex A.
    faces.append(c) # Adds triangle two vertex B.
    faces.append(d) # Adds triangle two vertex C.

func _terrain_for_cell(cell: Vector2i) -> TerrainKind: # Reads the cached terrain kind for a valid cell or treats out-of-bounds space as water.
    if not _is_cell_in_bounds(cell): # Detects coordinates outside the finite generated map.
        return TerrainKind.WATER # Allows edge-wall logic to treat the exterior like non-walkable low terrain.
    return terrain_cache.get(cell, TerrainKind.GRASS) as TerrainKind # Returns the deterministic classification generated at startup.

func _calculate_terrain_for_cell(cell: Vector2i) -> TerrainKind: # Generates the terrain category for one map cell from route-like procedural rules.
    var local: Vector2 = _cell_to_local_2d(cell) # Converts the integer grid coordinate into centred tile-space coordinates.
    if _is_bridge(local): # Lets explicit route bridges override river water beneath them.
        return TerrainKind.PATH # Keeps bridge crossings visually connected to the road network.
    if _is_water(local): # Detects the winding river, lake, and smaller pond.
        return TerrainKind.WATER # Marks these cells non-walkable until surfing is implemented.
    if _is_stone_area(local): # Detects the raised eastern plaza and northern mountain pass.
        return TerrainKind.STONE # Gives elevated landmarks a distinct HGSS-derived rocky surface.
    if _is_path(local): # Detects the connected road network threading through the large map.
        return TerrainKind.PATH # Uses the pale dirt-route source tile.
    if _is_tall_grass(local): # Detects deterministic encounter-grass patches away from roads and water.
        return TerrainKind.TALL_GRASS # Uses the darker HGSS tall-grass source tile.
    return TerrainKind.GRASS # Fills remaining terrain with ordinary route grass.

func _calculate_tree_for_cell(cell: Vector2i, terrain_kind: TerrainKind) -> bool: # Determines whether one solid terrain cell contains a hard forest obstacle.
    if terrain_kind == TerrainKind.WATER or terrain_kind == TerrainKind.PATH or terrain_kind == TerrainKind.STONE: # Keeps water, roads, bridges, and plazas clear of tree blockers.
        return false # Leaves these traversal corridors unobstructed.
    var local: Vector2 = _cell_to_local_2d(cell) # Reads centred tile-space coordinates for shape rules.
    if _is_near_gateway(local): # Keeps all four world entrances visibly open.
        return false # Prevents forest generation from sealing a route gate.
    var edge_forest: bool = absf(local.x) > 40.0 or absf(local.y) > 33.0 # Builds a dense tree wall around much of the world perimeter.
    var west_wood: bool = local.x < -22.0 and local.y < 10.0 and sin(local.x * 0.55 + local.y * 0.37) > -0.15 # Creates an irregular western woodland interior.
    var northeast_wood: bool = local.x > 22.0 and local.y < -15.0 and cos(local.x * 0.45 - local.y * 0.33) > 0.15 # Creates a second forest around the highlands.
    var grove: bool = local.x > 8.0 and local.x < 22.0 and local.y > 18.0 and sin(local.x * 0.8) + cos(local.y * 0.7) > 0.55 # Creates a smaller southeast grove near the lake.
    return edge_forest or west_wood or northeast_wood or grove # Combines the forest regions into one deterministic blocker decision.

func _is_water(local: Vector2) -> bool: # Defines a winding river plus two bodies of water across the expanded map.
    var river_centre_x: float = 11.0 + sin(local.y * 0.18) * 5.0 # Bends the north-south river instead of using a mechanical straight channel.
    var river: bool = absf(local.x - river_centre_x) < 2.4 # Gives the river a width of several map cells.
    var lake_offset: Vector2 = Vector2((local.x - 27.0) / 10.0, (local.y - 20.0) / 7.0) # Normalizes the southeast lake to an ellipse.
    var lake: bool = lake_offset.length_squared() < 1.0 # Fills the elliptical lake footprint.
    var pond_offset: Vector2 = Vector2((local.x + 27.0) / 5.0, (local.y - 19.0) / 4.0) # Normalizes a smaller southwest pond.
    var pond: bool = pond_offset.length_squared() < 1.0 # Fills the smaller pond footprint.
    return river or lake or pond # Combines every water feature into one classification.

func _is_bridge(local: Vector2) -> bool: # Defines two road crossings over the winding river.
    var first_bridge: bool = absf(local.y - 7.0) < 1.6 and local.x > 6.0 and local.x < 18.0 # Creates the central east-west bridge.
    var second_bridge: bool = absf(local.y + 29.0) < 1.6 and local.x > 5.0 and local.x < 20.0 # Creates a northern highland crossing.
    return first_bridge or second_bridge # Keeps both bridge strips solid and path-textured.

func _is_path(local: Vector2) -> bool: # Defines a connected network of primary and secondary HGSS-style routes.
    var main_route: bool = absf(local.x) < 2.5 # Creates the main north-south road from one world edge to the other.
    var east_route: bool = absf(local.y - 7.0) < 2.1 and local.x > -6.0 and local.x < 39.0 # Connects the central route to the eastern plateau.
    var west_route: bool = absf(local.y + 6.0) < 2.0 and local.x > -39.0 and local.x < 5.0 # Connects the central route through the western woodland.
    var south_curve_y: float = 22.0 + sin(local.x * 0.15) * 5.0 # Generates a curved southern scenic route.
    var south_curve: bool = absf(local.y - south_curve_y) < 1.8 and local.x > -34.0 and local.x < 34.0 # Applies the curved path across the lower map.
    var north_curve_y: float = -28.0 + sin(local.x * 0.20) * 4.0 # Generates a separate highland route.
    var north_curve: bool = absf(local.y - north_curve_y) < 1.7 and local.x > -24.0 and local.x < 34.0 # Connects the northern slope to the eastern side.
    return main_route or east_route or west_route or south_curve or north_curve # Produces one connected route network rather than isolated test strips.

func _is_stone_area(local: Vector2) -> bool: # Defines visually distinct elevated landmarks and mountain terrain.
    var east_plaza: bool = local.x > 24.0 and local.x < 38.0 and local.y > -11.0 and local.y < 11.0 # Creates a raised town-like stone plaza beside the eastern route.
    var northern_pass: bool = local.y < -34.0 and absf(local.x) < 15.0 # Creates a rocky mountain approach at the north end of the main road.
    return east_plaza or northern_pass # Combines both stone regions.

func _is_tall_grass(local: Vector2) -> bool: # Creates varied but deterministic encounter-grass patches throughout open terrain.
    var field_pattern: float = sin(local.x * 0.31) + cos(local.y * 0.27) + sin((local.x + local.y) * 0.17) # Combines several frequencies so patches do not form a simple checkerboard.
    var broad_field: bool = field_pattern > 1.05 # Selects the denser areas of the procedural field.
    var route_patch: bool = local.x > -18.0 and local.x < 18.0 and local.y > 10.0 and local.y < 31.0 # Guarantees a substantial visible southern encounter field.
    return broad_field or route_patch # Uses both organic scattered patches and one intentional gameplay field.

func _sample_height(local_x: float, local_z: float) -> float: # Defines a continuous 3D height field beneath the 2D HGSS tile surfaces.
    var north_rise: float = clampf((-local_z - 15.0) / 26.0, 0.0, 1.0) * 4.0 # Raises the northern third into a broad mountain slope.
    var east_distance: float = maxf(absf(local_x - 31.0) - 8.0, 0.0) + maxf(absf(local_z) - 13.0, 0.0) # Measures distance outside the eastern plateau rectangle.
    var east_rise: float = clampf(1.0 - east_distance / 7.0, 0.0, 1.0) * 1.5 # Blends the eastern plaza smoothly into surrounding terrain.
    var hill_dx: float = (local_x + 24.0) / 14.0 # Normalizes the western hill's horizontal distance.
    var hill_dz: float = (local_z + 16.0) / 11.0 # Normalizes the western hill's depth distance.
    var west_hill: float = exp(-(hill_dx * hill_dx + hill_dz * hill_dz)) * 1.8 # Adds one rounded woodland hill without discontinuous steps.
    return north_rise + east_rise + west_hill # Produces smooth elevation compatible with ordinary CharacterBody3D slope movement.

func _prepare_entry_points() -> void: # Defines four reusable route gates around the expanded world.
    entry_spawn_positions.clear() # Removes stale gateway positions before rebuilding.
    entry_target_positions.clear() # Removes stale arrival destinations before rebuilding.
    var south_cell: Vector2i = Vector2i(WORLD_WIDTH / 2, WORLD_DEPTH - 2) # Selects the southern end of the central route.
    var north_cell: Vector2i = Vector2i(WORLD_WIDTH / 2, 1) # Selects the northern mountain pass.
    var west_cell: Vector2i = Vector2i(1, WORLD_DEPTH / 2 - 4) # Selects the western branch route.
    var east_cell: Vector2i = Vector2i(WORLD_WIDTH - 2, WORLD_DEPTH / 2 + 5) # Selects the eastern branch route.
    _append_entry(south_cell, Vector3(0.0, 0.0, TILE_SIZE * 4.0)) # Creates the southern off-map and interior pair.
    _append_entry(north_cell, Vector3(0.0, 0.0, -TILE_SIZE * 4.0)) # Creates the northern off-map and interior pair.
    _append_entry(west_cell, Vector3(-TILE_SIZE * 4.0, 0.0, 0.0)) # Creates the western off-map and interior pair.
    _append_entry(east_cell, Vector3(TILE_SIZE * 4.0, 0.0, 0.0)) # Creates the eastern off-map and interior pair.

func _append_entry(edge_cell: Vector2i, outward_offset: Vector3) -> void: # Adds one route gate pair using a walkable edge cell and an outward direction.
    var target_position: Vector3 = cell_to_world(edge_cell) # Places the interior target on generated solid terrain.
    var spawn_position: Vector3 = target_position + outward_offset # Places the temporary spawn point clearly beyond the world perimeter.
    spawn_position.y = target_position.y + 0.1 # Keeps the off-map visitor close to the route elevation while gravity takes over.
    entry_spawn_positions.append(spawn_position) # Stores the off-map point for arrival and departure behaviour.
    entry_target_positions.append(target_position) # Stores the matching walkable destination just inside the map.

func _cell_to_local_2d(cell: Vector2i) -> Vector2: # Converts a cell index into centred coordinates measured in cells rather than world units.
    return Vector2(float(cell.x) - float(WORLD_WIDTH) * 0.5 + 0.5, float(cell.y) - float(WORLD_DEPTH) * 0.5 + 0.5) # Centres procedural layout rules around zero for readable region definitions.

func _is_near_gateway(local: Vector2) -> bool: # Keeps route entrances free from generated forest blockers.
    var south_gate: bool = absf(local.x) < 4.0 and local.y > 32.0 # Opens the southern central road.
    var north_gate: bool = absf(local.x) < 4.0 and local.y < -32.0 # Opens the northern mountain road.
    var west_gate: bool = local.x < -40.0 and absf(local.y + 4.0) < 4.0 # Opens the western route gate.
    var east_gate: bool = local.x > 40.0 and absf(local.y - 5.0) < 4.0 # Opens the eastern route gate.
    return south_gate or north_gate or west_gate or east_gate # Returns whether the current cell belongs to any open route boundary.

func _is_cell_in_bounds(cell: Vector2i) -> bool: # Tests whether an integer map cell lies inside the generated world dimensions.
    return cell.x >= 0 and cell.x < WORLD_WIDTH and cell.y >= 0 and cell.y < WORLD_DEPTH # Performs the four inexpensive integer boundary checks.
