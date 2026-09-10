class_name WorldTerrainRenderer # Builds continuous terrain and clipped water in independently culled chunks.
extends RefCounted # Keeps mesh construction separate from world layout and habitat policy.

const CHUNK_CELLS: int = 32 # Sets the terrain chunk granularity for rendering and physics.
const LAND_SHADER: Shader = preload("res://resources/shaders/landscape.gdshader") # Shares the world-space terrain material program.
const WATER_SHADER: Shader = preload("res://resources/shaders/river_water.gdshader") # Shares the animated lake and river material program.

static func build(parent: Node3D, heights: PackedFloat32Array, cell_colors: PackedColorArray, routes: PackedFloat32Array, dimensions: Vector2i, spacing: float, water_level: float) -> void: # Builds matching visible and physical surfaces from one height field.
    var land_material: ShaderMaterial = ShaderMaterial.new() # Shares one ground material across all chunks.
    land_material.shader = LAND_SHADER # Enables natural soil and rock shading.
    land_material.set_shader_parameter(&"water_level", water_level) # Aligns damp bank shading to the actual water.
    var water_material: ShaderMaterial = ShaderMaterial.new() # Shares one ripple material across all water chunks.
    water_material.shader = WATER_SHADER # Enables moving water without per-frame scripts.
    var colors: PackedColorArray = _smooth_colors(cell_colors, dimensions) # Computes common vertex colours once to prevent seams.
    var normals: PackedVector3Array = _build_normals(heights, dimensions, spacing) # Computes common normals once to prevent lighting seams.
    for start_z: int in range(0, dimensions.y, CHUNK_CELLS): # Traverses the terrain's spatial rows.
        for start_x: int in range(0, dimensions.x, CHUNK_CELLS): # Traverses the terrain's spatial columns.
            var extent: Vector2i = Vector2i(mini(CHUNK_CELLS, dimensions.x - start_x), mini(CHUNK_CELLS, dimensions.y - start_z)) # Fits partial chunks to the outer world boundary.
            _build_chunk(parent, Vector2i(start_x, start_z), extent, heights, colors, normals, routes, dimensions, spacing, water_level, land_material, water_material) # Emits one bounded terrain section.

static func _build_chunk(parent: Node3D, start: Vector2i, extent: Vector2i, heights: PackedFloat32Array, colors: PackedColorArray, normals: PackedVector3Array, routes: PackedFloat32Array, dimensions: Vector2i, spacing: float, water_level: float, land_material: Material, water_material: Material) -> void: # Emits indexed terrain, exact triangle collision, and contour-clipped water.
    var vertices: PackedVector3Array = PackedVector3Array() # Stores shared terrain vertices for this chunk.
    var vertex_normals: PackedVector3Array = PackedVector3Array() # Stores seam-free terrain normals.
    var vertex_colors: PackedColorArray = PackedColorArray() # Stores seam-free biome colour blends.
    var route_uv: PackedVector2Array = PackedVector2Array() # Stores continuous route distance for the ground shader.
    var indices: PackedInt32Array = PackedInt32Array() # Reuses grid vertices across neighboring triangles.
    var faces: PackedVector3Array = PackedVector3Array() # Stores the exact rendered triangles for physics.
    var water: SurfaceTool = SurfaceTool.new() # Collects only triangles below the shared water plane.
    water.begin(Mesh.PRIMITIVE_TRIANGLES) # Starts the chunk's water surface.
    water.set_material(water_material) # Attaches the shared ripple shader.
    var water_count: int = 0 # Tracks whether this chunk needs a water render object.
    var origin: Vector3 = Vector3((float(start.x) - float(dimensions.x) * 0.5) * spacing, 0.0, (float(start.y) - float(dimensions.y) * 0.5) * spacing) # Places mesh data in local chunk coordinates.
    for z: int in range(extent.y + 1): # Traverses every shared vertex row.
        for x: int in range(extent.x + 1): # Traverses every shared vertex column.
            var index: int = (start.y + z) * (dimensions.x + 1) + start.x + x # Addresses the authoritative global height field.
            vertices.append(Vector3(float(x) * spacing, heights[index], float(z) * spacing)) # Adds the terrain vertex in local coordinates.
            vertex_normals.append(normals[index]) # Reuses the global smooth normal at this vertex.
            vertex_colors.append(colors[index]) # Reuses the global blended biome colour.
            route_uv.append(Vector2(routes[index], 0.0)) # Supplies the distance to the closest route.
    for z: int in range(extent.y): # Traverses the chunk's logical cell rows.
        for x: int in range(extent.x): # Traverses the chunk's logical cell columns.
            var a: int = z * (extent.x + 1) + x # Addresses the near-left cell corner.
            var b: int = a + 1 # Addresses the near-right cell corner.
            var d: int = a + extent.x + 1 # Addresses the far-left cell corner.
            var c: int = d + 1 # Addresses the far-right cell corner.
            indices.append_array(PackedInt32Array([a, b, c, a, c, d])) # Uses a consistent upward-facing diagonal.
            faces.append_array(PackedVector3Array([vertices[a], vertices[b], vertices[c], vertices[a], vertices[c], vertices[d]])) # Gives physics precisely the same terrain triangles.
            water_count += _clip_water(water, [vertices[a], vertices[b], vertices[c]], water_level) # Clips the first triangle to the true shoreline.
            water_count += _clip_water(water, [vertices[a], vertices[c], vertices[d]], water_level) # Clips the second triangle to the true shoreline.
    var arrays: Array = [] # Collects the typed mesh buffers using Godot's mesh array layout.
    arrays.resize(Mesh.ARRAY_MAX) # Allocates slots for all supported vertex attributes.
    arrays[Mesh.ARRAY_VERTEX] = vertices # Supplies the indexed terrain positions.
    arrays[Mesh.ARRAY_NORMAL] = vertex_normals # Supplies continuous terrain lighting normals.
    arrays[Mesh.ARRAY_COLOR] = vertex_colors # Supplies blended biome surface colours.
    arrays[Mesh.ARRAY_TEX_UV2] = route_uv # Supplies the continuous route field.
    arrays[Mesh.ARRAY_INDEX] = indices # Supplies shared-vertex triangle topology.
    var mesh: ArrayMesh = ArrayMesh.new() # Creates the chunk's terrain geometry.
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays) # Uploads the completed indexed surface.
    mesh.surface_set_material(0, land_material) # Shares the same ground shader across all chunks.
    var chunk: MeshInstance3D = MeshInstance3D.new() # Creates an independently culled terrain object.
    chunk.name = "terrain_%s_%s" % [start.x, start.y] # Gives the generated chunk a stable inspector name.
    chunk.position = origin # Positions local mesh coordinates inside the world.
    chunk.mesh = mesh # Attaches the completed geometry.
    parent.add_child(chunk) # Adds the terrain to the world scene.
    var body: StaticBody3D = StaticBody3D.new() # Gives each terrain chunk a matching static collider.
    body.collision_layer = 1 # Keeps ordinary player, wildlife, and camera collision compatibility.
    body.collision_mask = 0 # Avoids unnecessary collision querying by static geometry.
    var shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new() # Uses exact triangle collision on static terrain.
    shape.set_faces(faces) # Supplies the same triangle positions as the render mesh.
    var collider: CollisionShape3D = CollisionShape3D.new() # Composes the collision resource into the chunk scene.
    collider.shape = shape # Attaches the prepared terrain collider.
    body.add_child(collider) # Adds the shape to its owning physics body.
    chunk.add_child(body) # Shares the chunk transform between rendering and physics.
    if water_count > 0: # Avoids allocating empty water surfaces on dry terrain.
        var surface: MeshInstance3D = MeshInstance3D.new() # Creates the local water render object.
        surface.name = "water" # Keeps the generated hierarchy readable.
        surface.mesh = water.commit() # Uploads the clipped water surface.
        surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # Prevents water from darkening its own banks.
        chunk.add_child(surface) # Shares the terrain chunk's exact world transform.

static func _clip_water(tool: SurfaceTool, triangle: Array[Vector3], level: float) -> int: # Clips terrain triangles to a level water plane so shorelines follow real contours.
    var polygon: Array[Vector3] = [] # Stores the submerged part of the terrain triangle.
    for index: int in range(3): # Examines every oriented triangle edge.
        var a: Vector3 = triangle[index] # Reads the current edge's starting bed vertex.
        var b: Vector3 = triangle[(index + 1) % 3] # Reads the current edge's ending bed vertex.
        if a.y < level: # Retains vertices beneath the water surface.
            polygon.append(a) # Carries bed height into shallow-water shading.
        if (a.y < level) != (b.y < level): # Detects an edge crossing the shoreline contour.
            var ratio: float = (level - a.y) / (b.y - a.y) # Finds the exact intersection along that edge.
            polygon.append(a.lerp(b, ratio)) # Inserts the shoreline intersection without grid-shaped steps.
    if polygon.size() < 3: # Rejects dry triangles and degenerate shoreline slivers.
        return 0 # Reports no emitted water geometry.
    for index: int in range(1, polygon.size() - 1): # Triangulates the clipped convex polygon as a fan.
        for point: Vector3 in [polygon[0], polygon[index], polygon[index + 1]]: # Emits each fan triangle in the terrain's winding order.
            tool.set_normal(Vector3.UP) # Keeps the physical water surface level.
            tool.set_tangent(Plane(Vector3.RIGHT, 1.0)) # Supplies a stable basis for ripple normal shading.
            tool.set_uv2(Vector2(0.0, maxf(level - point.y, 0.0))) # Encodes actual bed depth for shoreline colour.
            tool.add_vertex(Vector3(point.x, level, point.z)) # Projects the bed polygon onto the shared water level.
    return (polygon.size() - 2) * 3 # Reports the number of emitted water vertices.

static func _smooth_colors(cell_colors: PackedColorArray, dimensions: Vector2i) -> PackedColorArray: # Filters biome colours once before creating shared chunk vertices.
    var horizontal: PackedColorArray = PackedColorArray() # Stores the first pass of the separable surface filter.
    horizontal.resize(cell_colors.size()) # Allocates one intermediate colour for each terrain cell.
    for z: int in range(dimensions.y): # Traverses every cell row.
        for x: int in range(dimensions.x): # Traverses each cell in that row.
            var color: Color = Color(0.0, 0.0, 0.0, 0.0) # Starts the horizontal neighbourhood sum.
            for offset: int in range(-4, 5): # Samples nearby biome colours through a soft transition band.
                color += cell_colors[z * dimensions.x + clampi(x + offset, 0, dimensions.x - 1)] # Extends edge colours consistently beyond the border.
            horizontal[z * dimensions.x + x] = color / 9.0 # Stores the averaged horizontal colour.
    var result: PackedColorArray = PackedColorArray() # Stores one seam-free colour for every terrain vertex.
    result.resize((dimensions.x + 1) * (dimensions.y + 1)) # Matches the authoritative height field dimensions.
    for z: int in range(dimensions.y + 1): # Traverses every final vertex row.
        for x: int in range(dimensions.x + 1): # Traverses every final vertex column.
            var color: Color = Color(0.0, 0.0, 0.0, 0.0) # Starts the vertical neighbourhood sum.
            for offset: int in range(-4, 5): # Completes the separable biome colour filter.
                color += horizontal[clampi(z + offset, 0, dimensions.y - 1) * dimensions.x + mini(x, dimensions.x - 1)] # Reuses the horizontally filtered colours.
            result[z * (dimensions.x + 1) + x] = color / 9.0 # Stores a common colour at every shared vertex.
    return result # Returns the precomputed transition field.

static func _build_normals(heights: PackedFloat32Array, dimensions: Vector2i, spacing: float) -> PackedVector3Array: # Derives smooth normals from the complete height field rather than separate chunks.
    var normals: PackedVector3Array = PackedVector3Array() # Stores one normal for each authoritative vertex.
    normals.resize(heights.size()) # Allocates exactly the required normal count.
    var width: int = dimensions.x + 1 # Stores the global height-array row stride.
    for z: int in range(dimensions.y + 1): # Traverses every shared vertex row.
        for x: int in range(dimensions.x + 1): # Traverses every shared vertex column.
            var left: int = maxi(x - 1, 0) # Clamps the left derivative sample to the world.
            var right: int = mini(x + 1, dimensions.x) # Clamps the right derivative sample to the world.
            var near_z: int = maxi(z - 1, 0) # Clamps the near derivative sample to the world.
            var far_z: int = mini(z + 1, dimensions.y) # Clamps the far derivative sample to the world.
            var dx: float = (heights[z * width + right] - heights[z * width + left]) / (float(right - left) * spacing) # Computes the horizontal surface gradient.
            var dz: float = (heights[far_z * width + x] - heights[near_z * width + x]) / (float(far_z - near_z) * spacing) # Computes the depth surface gradient.
            normals[z * width + x] = Vector3(-dx, 1.0, -dz).normalized() # Stores the normalized global surface normal.
    return normals # Returns reusable seam-free lighting data.
