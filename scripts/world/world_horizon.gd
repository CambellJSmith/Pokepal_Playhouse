class_name WorldHorizon # Extends the landscape into distant hills beyond the playable terrain.
extends Node3D # Keeps the visual horizon independent from gameplay terrain and navigation.

const RING_STEPS: int = 10 # Controls the inexpensive outward silhouette mesh resolution.
const EDGE_STEPS: int = 160 # Controls the distant perimeter's sampling density.
const RING_DISTANCE: float = 42.0 # Sets the spacing of successive distant landscape bands.

func build(heights: PackedFloat32Array, dimensions: Vector2i, spacing: float, seed_value: int) -> void: # Adds continuous distant ground with no changes to playable world bounds.
    var noise: FastNoiseLite = FastNoiseLite.new() # Generates broad stable background hill silhouettes.
    noise.seed = seed_value + 919 # Separates horizon variation from the playable terrain's fields.
    noise.frequency = 0.0042 # Produces large geographic forms in the distance.
    noise.fractal_octaves = 2 # Adds readable secondary ridges without fine detail.
    var tool: SurfaceTool = SurfaceTool.new() # Collects the continuous outer landscape ring.
    tool.begin(Mesh.PRIMITIVE_TRIANGLES) # Uses static triangle geometry for the horizon.
    var material: StandardMaterial3D = StandardMaterial3D.new() # Uses ordinary sun-and-sky lighting for the distant ground.
    material.vertex_color_use_as_albedo = true
    material.vertex_color_is_srgb = true # Converts painted distant colours consistently with the foreground shader. # Allows restrained variation between distant slopes.
    material.roughness = 1.0 # Keeps the far hills free from polished highlights.
    tool.set_material(material) # Shares one material over the entire horizon mesh.
    for side: int in range(4): # Builds every side of the rectangular world perimeter.
        for step: int in range(EDGE_STEPS): # Samples the boundary at evenly spaced positions.
            for ring: int in range(RING_STEPS): # Extends the sampled boundary through successive distant bands.
                var a: Vector3 = _point(side, float(step) / EDGE_STEPS, ring, heights, dimensions, spacing, noise) # Reads the near band's first point.
                var b: Vector3 = _point(side, float(step + 1) / EDGE_STEPS, ring, heights, dimensions, spacing, noise) # Reads the near band's next point.
                var c: Vector3 = _point(side, float(step + 1) / EDGE_STEPS, ring + 1, heights, dimensions, spacing, noise) # Reads the matching outer-band point.
                var d: Vector3 = _point(side, float(step) / EDGE_STEPS, ring + 1, heights, dimensions, spacing, noise) # Reads the outer band's first point.
                for point: Vector3 in [a, b, c, a, c, d]: # Emits the connected perimeter segment.
                    var tint: float = clampf(point.y / 70.0, 0.0, 1.0) # Changes the subdued palette gradually with elevation.
                    tool.set_color(Color(0.27, 0.34, 0.24).lerp(Color(0.36, 0.38, 0.35), tint)) # Gives distant ridges natural vegetation and stone colours.
                    tool.add_vertex(point) # Adds the stable background landscape vertex.
    tool.generate_normals() # Lights the horizon consistently with the directional sun.
    var surface: MeshInstance3D = MeshInstance3D.new() # Creates one inexpensive distant landscape object.
    surface.name = "distant_hills" # Names the visual-only horizon clearly in the scene.
    surface.mesh = tool.commit() # Uploads the completed landscape ring.
    surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # Avoids spending near shadow-map resolution on distant background hills.
    add_child(surface) # Composes the horizon under its dedicated scene component.

func _point(side: int, progress: float, ring: int, heights: PackedFloat32Array, dimensions: Vector2i, spacing: float, noise: FastNoiseLite) -> Vector3: # Samples the outer hill ring while matching the playable boundary elevation.
    var half: Vector2 = Vector2(dimensions) * spacing * 0.5 # Converts playable dimensions into world-space half extents.
    var corners: Array[Vector2] = [Vector2(-half.x, -half.y), Vector2(-half.x, half.y), Vector2(half.x, half.y), Vector2(half.x, -half.y)] # Orders the outer contour consistently.
    var edge: Vector2 = corners[side].lerp(corners[(side + 1) % 4], progress) # Finds a position on the playable boundary.
    var expanded: Vector2 = edge * (Vector2.ONE + Vector2.ONE * float(ring) * RING_DISTANCE / half) # Expands the rectangle into a continuous outward band.
    var grid: Vector2 = (edge + half) / spacing # Converts the boundary position to terrain vertex coordinates.
    var x: int = clampi(int(grid.x), 0, dimensions.x) # Clamps the boundary column to the shared height field.
    var z: int = clampi(int(grid.y), 0, dimensions.y) # Clamps the boundary row to the shared height field.
    var boundary_height: float = heights[z * (dimensions.x + 1) + x] # Matches the nearby terrain elevation at the edge.
    var ridge: float = (noise.get_noise_2d(expanded.x, expanded.y) + 1.0) * 0.5 # Samples broad irregular background hills.
    var distant_height: float = 8.0 + ridge * 55.0 # Builds recognizable mountain silhouettes on the horizon.
    var blend: float = smoothstep(0.0, 3.0, float(ring)) # Ramps gradually away from the playable boundary.
    return Vector3(expanded.x, lerpf(boundary_height - 0.12, distant_height, blend), expanded.y) # Returns the matched boundary or distant hill position.
