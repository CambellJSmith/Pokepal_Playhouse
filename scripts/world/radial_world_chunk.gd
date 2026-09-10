class_name RadialWorldChunk # Builds one bounded visible and physical section of the infinite radial world.
extends Node3D # Lets the world streamer add and remove terrain chunks as the player travels.

const CHUNK_CELLS: int = 24 # Keeps each streamed terrain build small enough to spread generation across frames.
const DETAIL_VISIBILITY_RANGE: float = 95.0 # Hides small procedural scenery before it becomes visually insignificant.

var chunk_coordinate: Vector2i # Stores this chunk's infinite grid coordinate for streaming bookkeeping.
var field_sampler: RadialWorldFieldSampler # References the deterministic world function shared by every chunk.
var terrain_material: Material # Reuses one terrain shader material across all streamed chunks.
var tile_size: float # Stores the world-space size of one logical terrain cell.

func build(coordinate: Vector2i, sampler: RadialWorldFieldSampler, shared_material: Material, spacing: float) -> void: # Builds terrain, collision, and sparse scenery for one infinite-world chunk.
    chunk_coordinate = coordinate # Retains the coordinate used by the owning streamer.
    field_sampler = sampler # Shares deterministic terrain math with every neighboring chunk.
    terrain_material = shared_material # Reuses the same material resource to avoid per-chunk shader duplication.
    tile_size = spacing # Stores the conversion from logical cells to world-space metres.
    name = "radial_chunk_%s_%s" % [chunk_coordinate.x, chunk_coordinate.y] # Gives the streamed chunk a stable diagnostic name.
    position = Vector3(float(chunk_coordinate.x * CHUNK_CELLS) * tile_size, 0.0, float(chunk_coordinate.y * CHUNK_CELLS) * tile_size) # Places local chunk geometry at its global infinite-world origin.
    _build_terrain() # Creates the indexed terrain surface and matching static collision.
    _build_scenery() # Adds inexpensive local MultiMesh scenery without global batching work.

func _build_terrain() -> void: # Creates one indexed grid with seam-free samples from global world coordinates.
    var vertex_count_per_axis: int = CHUNK_CELLS + 1 # Includes the shared outer vertex row and column for exact chunk continuity.
    var vertices: PackedVector3Array = PackedVector3Array() # Stores local terrain positions for the ArrayMesh.
    var normals: PackedVector3Array = PackedVector3Array() # Stores world-consistent lighting normals sampled across chunk boundaries.
    var colors: PackedColorArray = PackedColorArray() # Stores biome colour at every terrain vertex.
    var route_uv: PackedVector2Array = PackedVector2Array() # Stores route distance in UV2 for the existing landscape shader.
    var indices: PackedInt32Array = PackedInt32Array() # Reuses shared grid vertices across terrain triangles.
    var collision_faces: PackedVector3Array = PackedVector3Array() # Stores the exact rendered triangles for static physics.
    vertices.resize(vertex_count_per_axis * vertex_count_per_axis) # Allocates all terrain vertices once before filling them.
    normals.resize(vertices.size()) # Matches the position buffer exactly.
    colors.resize(vertices.size()) # Matches the position buffer exactly.
    route_uv.resize(vertices.size()) # Matches the position buffer exactly.
    var start_cell: Vector2i = chunk_coordinate * CHUNK_CELLS # Resolves this chunk's global logical-cell origin.
    for local_z: int in range(vertex_count_per_axis): # Traverses every shared vertex row in this chunk.
        for local_x: int in range(vertex_count_per_axis): # Traverses every shared vertex column in this row.
            var global_cell: Vector2 = Vector2(float(start_cell.x + local_x), float(start_cell.y + local_z)) # Resolves the authoritative infinite-world sample coordinate.
            var vertex_index: int = local_z * vertex_count_per_axis + local_x # Resolves the packed array index for this local grid vertex.
            var height: float = field_sampler.sample_height(global_cell) # Samples deterministic terrain independent of which chunk requested it.
            vertices[vertex_index] = Vector3(float(local_x) * tile_size, height, float(local_z) * tile_size) # Stores local geometry so large coordinates stay out of vertex buffers.
            normals[vertex_index] = _sample_normal(global_cell) # Uses neighboring global samples so adjacent chunks share lighting normals.
            colors[vertex_index] = field_sampler.get_biome_color(field_sampler.sample_biome(global_cell)) # Colours the terrain from the radial topology.
            route_uv[vertex_index] = Vector2(field_sampler.sample_route_distance(global_cell), 0.0) # Feeds radial and ring route distance into terrain shading.
    for local_z: int in range(CHUNK_CELLS): # Traverses every logical cell row for triangle topology.
        for local_x: int in range(CHUNK_CELLS): # Traverses every logical cell in the current row.
            var a: int = local_z * vertex_count_per_axis + local_x # Addresses the near-left grid corner.
            var b: int = a + 1 # Addresses the near-right grid corner.
            var d: int = a + vertex_count_per_axis # Addresses the far-left grid corner.
            var c: int = d + 1 # Addresses the far-right grid corner.
            indices.append_array(PackedInt32Array([a, b, c, a, c, d])) # Uses one stable diagonal across every chunk for render continuity.
            collision_faces.append_array(PackedVector3Array([vertices[a], vertices[b], vertices[c], vertices[a], vertices[c], vertices[d]])) # Gives physics the exact same triangles as rendering.
    var arrays: Array = [] # Prepares Godot's standard ArrayMesh buffer layout.
    arrays.resize(Mesh.ARRAY_MAX) # Allocates every supported array slot before assigning used attributes.
    arrays[Mesh.ARRAY_VERTEX] = vertices # Supplies terrain positions.
    arrays[Mesh.ARRAY_NORMAL] = normals # Supplies seam-free terrain normals.
    arrays[Mesh.ARRAY_COLOR] = colors # Supplies radial biome colours.
    arrays[Mesh.ARRAY_TEX_UV2] = route_uv # Supplies procedural route distance.
    arrays[Mesh.ARRAY_INDEX] = indices # Supplies indexed terrain topology.
    var mesh: ArrayMesh = ArrayMesh.new() # Creates the GPU terrain mesh resource for this chunk.
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays) # Uploads the completed indexed terrain surface.
    mesh.surface_set_material(0, terrain_material) # Applies the shared landscape shader material.
    var terrain_instance: MeshInstance3D = MeshInstance3D.new() # Creates the visible terrain node for this streamed chunk.
    terrain_instance.name = "terrain" # Gives the visible surface a compact inspector name.
    terrain_instance.mesh = mesh # Attaches the completed terrain mesh.
    terrain_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # Avoids expensive self-shadow submission from every streamed terrain chunk.
    add_child(terrain_instance) # Adds visible terrain beneath the chunk root.
    var static_body: StaticBody3D = StaticBody3D.new() # Creates one static physics owner for this terrain chunk.
    static_body.name = "collision" # Gives the physical surface a compact inspector name.
    static_body.collision_layer = 1 # Preserves the existing player and roaming Pokémon collision layer contract.
    static_body.collision_mask = 0 # Prevents static terrain from querying other bodies unnecessarily.
    var shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new() # Uses triangle collision suited to static procedural terrain.
    shape.backface_collision = true # Keeps terrain collision robust if a character approaches a steep triangle from an unusual angle.
    shape.set_faces(collision_faces) # Uploads the exact local render triangles to physics.
    var collision_shape: CollisionShape3D = CollisionShape3D.new() # Wraps the terrain shape in a scene-tree collision node.
    collision_shape.shape = shape # Attaches the completed concave terrain surface.
    static_body.add_child(collision_shape) # Parents the collision shape under its static owner.
    add_child(static_body) # Adds terrain collision with the same chunk transform as rendering.

func _build_scenery() -> void: # Adds sparse deterministic vegetation and rock detail without global world scans.
    var tree_transforms: Array[Transform3D] = [] # Collects local tree transforms for one chunk-local MultiMesh.
    var grass_transforms: Array[Transform3D] = [] # Collects local grass transforms for one chunk-local MultiMesh.
    var rock_transforms: Array[Transform3D] = [] # Collects local rock transforms for one chunk-local MultiMesh.
    var start_cell: Vector2i = chunk_coordinate * CHUNK_CELLS # Resolves this chunk's global logical-cell origin once.
    for local_z: int in range(1, CHUNK_CELLS, 2): # Samples scenery on a coarser grid to keep generation and instance counts bounded.
        for local_x: int in range(1, CHUNK_CELLS, 2): # Samples alternate cells across each coarse scenery row.
            var global_cell_i: Vector2i = start_cell + Vector2i(local_x, local_z) # Resolves the deterministic integer scenery coordinate.
            var global_cell: Vector2 = Vector2(global_cell_i) # Converts the integer cell into field-sampling coordinates.
            var biome_kind: int = field_sampler.sample_biome(global_cell) # Reads the radial biome controlling scenery character.
            var scatter: float = field_sampler.sample_scatter(global_cell) # Reads broad deterministic density shared across chunk seams.
            var random_value: float = _hash01(global_cell_i, 311) # Adds fine deterministic variation without another noise query.
            var local_position: Vector3 = Vector3(float(local_x) * tile_size, field_sampler.sample_height(global_cell), float(local_z) * tile_size) # Grounds scenery on the same terrain function as the mesh.
            if _biome_supports_trees(biome_kind) and scatter > 0.12 and random_value > 0.70: # Places trees in coherent woodland-like patches only.
                tree_transforms.append(_make_transform(local_position, global_cell_i, 401, 0.88, 1.18)) # Adds one complete tree transform with deterministic variation.
            elif scatter > -0.05 and random_value > 0.58: # Fills ordinary open terrain with sparse low grass instead of trees.
                grass_transforms.append(_make_transform(local_position, global_cell_i, 503, 0.72, 1.22)) # Adds one grounded grass transform.
            if _biome_supports_rocks(biome_kind) and _hash01(global_cell_i, 617) > 0.86: # Adds occasional stones in rougher terrain types.
                rock_transforms.append(_make_transform(local_position + Vector3(0.0, -0.08, 0.0), global_cell_i, 701, 0.72, 1.45)) # Seats the stone slightly into the terrain.
    if not tree_transforms.is_empty(): # Creates a tree batch only when this chunk actually contains trees.
        _build_multimesh("trees", WorldSceneryMeshes.tree(0, abs(chunk_coordinate.x + chunk_coordinate.y) % 3), tree_transforms, 0.0, true) # Reuses the existing coherent procedural tree mesh.
    if not grass_transforms.is_empty(): # Creates a grass batch only when useful detail exists.
        _build_multimesh("grass", WorldSceneryMeshes.grass(), grass_transforms, DETAIL_VISIBILITY_RANGE, false) # Uses short-range batched grass to control fill cost.
    if not rock_transforms.is_empty(): # Creates a rock batch only for chunks with selected outcrops.
        _build_multimesh("rocks", WorldSceneryMeshes.rock(), rock_transforms, DETAIL_VISIBILITY_RANGE, true) # Reuses the existing irregular weathered stone mesh.

func _build_multimesh(node_name: String, source_mesh: Mesh, transforms: Array[Transform3D], visibility_end: float, cast_shadows: bool) -> void: # Creates one chunk-local GPU instance batch.
    var multi_mesh: MultiMesh = MultiMesh.new() # Allocates the repeated-instance resource.
    multi_mesh.transform_format = MultiMesh.TRANSFORM_3D # Stores complete 3D transforms for procedural scenery.
    multi_mesh.mesh = source_mesh # Shares one source mesh across every local instance.
    multi_mesh.instance_count = transforms.size() # Allocates exactly the number of selected placements.
    for index: int in range(transforms.size()): # Uploads each deterministic local transform once.
        multi_mesh.set_instance_transform(index, transforms[index]) # Writes the transform into the GPU-friendly MultiMesh buffer.
    var instance: MultiMeshInstance3D = MultiMeshInstance3D.new() # Creates the render node owning this local MultiMesh.
    instance.name = node_name # Gives the scenery batch a readable scene-tree name.
    instance.multimesh = multi_mesh # Attaches the completed repeated-instance resource.
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # Keeps grass shadow-free while allowing larger scenery to ground itself.
    if visibility_end > 0.0: # Applies range culling only to deliberately short-range detail.
        instance.visibility_range_end = visibility_end # Stops small scenery rendering near the streamed terrain horizon.
        instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF # Softens the disappearance of detail near its visibility limit.
    add_child(instance) # Adds the complete local scenery batch beneath the chunk root.

func _sample_normal(global_cell: Vector2) -> Vector3: # Derives one smooth terrain normal from neighboring infinite-world height samples.
    var left_height: float = field_sampler.sample_height(global_cell + Vector2(-1.0, 0.0)) # Samples the global left neighbor even when it lies in another chunk.
    var right_height: float = field_sampler.sample_height(global_cell + Vector2(1.0, 0.0)) # Samples the global right neighbor for the X derivative.
    var near_height: float = field_sampler.sample_height(global_cell + Vector2(0.0, -1.0)) # Samples the global near neighbor for the Z derivative.
    var far_height: float = field_sampler.sample_height(global_cell + Vector2(0.0, 1.0)) # Samples the global far neighbor even across a chunk edge.
    var dx: float = (right_height - left_height) / (2.0 * tile_size) # Converts the X height difference into a world-space gradient.
    var dz: float = (far_height - near_height) / (2.0 * tile_size) # Converts the Z height difference into a world-space gradient.
    return Vector3(-dx, 1.0, -dz).normalized() # Returns the upward-facing smooth normal used for lighting.

func _make_transform(local_position: Vector3, global_cell: Vector2i, salt: int, minimum_scale: float, maximum_scale: float) -> Transform3D: # Builds one deterministic scenery transform from a global cell.
    var yaw: float = _hash01(global_cell, salt) * TAU # Rotates repeated geometry independently around the vertical axis.
    var scale_value: float = lerpf(minimum_scale, maximum_scale, _hash01(global_cell, salt + 1)) # Varies object size while preserving coherent proportions.
    var jitter_x: float = (_hash01(global_cell, salt + 2) - 0.5) * tile_size * 0.72 # Breaks the coarse scenery grid along X.
    var jitter_z: float = (_hash01(global_cell, salt + 3) - 0.5) * tile_size * 0.72 # Breaks the coarse scenery grid independently along Z.
    var jittered_position: Vector3 = local_position + Vector3(jitter_x, 0.0, jitter_z) # Applies sub-cell variation without changing deterministic ownership.
    return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_value), jittered_position) # Returns the complete local instance transform.

func _biome_supports_trees(biome_kind: int) -> bool: # Identifies outer worlds where dense natural vegetation fits the established art direction.
    return biome_kind in [0, 2, 4, 7, 11, 13, 15] # Keeps trees common in neutral, wetland, woodland, ghost, and dark regions.

func _biome_supports_rocks(biome_kind: int) -> bool: # Identifies outer worlds where exposed stone should be common.
    return biome_kind in [1, 5, 8, 9, 12, 14, 16] # Concentrates rocks in volcanic, frozen, badland, highland, and steel regions.

func _hash01(cell: Vector2i, salt: int) -> float: # Produces one deterministic zero-to-one value from an infinite integer world coordinate.
    var value: int = cell.x * 73856093 ^ cell.y * 19349663 ^ salt * 83492791 # Mixes both signed coordinates and an independent salt into one integer.
    value = (value ^ (value >> 13)) * 1274126177 # Applies an additional integer avalanche step for spatial decorrelation.
    value = value ^ (value >> 16) # Finishes the hash before normalizing its positive magnitude.
    return float(value & 0x7fffffff) / 2147483647.0 # Converts the deterministic integer hash into a stable unit interval.
