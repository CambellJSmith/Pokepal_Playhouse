class_name WorldSceneryMeshes # Creates reusable organic scenery with coherent silhouettes and grounded proportions.
extends RefCounted # Builds meshes once without adding per-object scene processing.

const VEGETATION_SHADER: Shader = preload("res://resources/shaders/vegetation.gdshader") # Shares GPU wind and organic surface shading.

static func tree(style: int, variant: int) -> ArrayMesh: # Composes a complete tree into one reusable root-anchored mesh.
    var random: RandomNumberGenerator = RandomNumberGenerator.new() # Keeps mesh variation deterministic and independent of placement.
    random.seed = 7109 + style * 97 + variant * 311 # Gives each reusable silhouette a stable geometry seed.
    var tool: SurfaceTool = _begin() # Starts a merged bark-and-foliage surface.
    var trunk: CylinderMesh = CylinderMesh.new() # Forms the tree's tapered central trunk.
    trunk.bottom_radius = 0.29 # Matches the existing physical tree footprint.
    trunk.top_radius = 0.09 # Narrows the trunk naturally toward the branches.
    trunk.height = 3.25 if style == 1 else 3.2 # Fits the trunk to the selected tree silhouette.
    trunk.radial_segments = 7 # Keeps background branch geometry economical.
    trunk.rings = 1 # Avoids unnecessary subdivisions along straight wood.
    _append(tool, trunk, Transform3D(Basis.IDENTITY, Vector3.UP * (trunk.height * 0.5 - 0.12)), Color(0.22, 0.145, 0.08), 0.0, random) # Roots the trunk into the terrain with a consistent bark colour.
    if style == 1: # Builds a tiered evergreen crown for the northern woodland.
        for tier: int in range(5): # Layers overlapping conifer boughs into a continuous silhouette.
            var crown: CylinderMesh = CylinderMesh.new() # Forms one tapered tier of needles.
            crown.bottom_radius = 1.28 - float(tier) * 0.19 # Narrows the canopy progressively toward the treetop.
            crown.top_radius = 0.10 # Keeps the tip of each tier softly pointed.
            crown.height = 1.62 # Overlaps adjacent tiers without exposed gaps.
            crown.radial_segments = 9 # Retains a readable faceted evergreen profile.
            crown.rings = 2 # Provides enough vertices for subtle organic variation.
            var position: Vector3 = Vector3(0.0, 1.8 + float(tier) * 0.65, 0.0) # Stacks the crown along the same rooted trunk.
            _append(tool, crown, Transform3D(Basis(Vector3.UP, float(tier) * 0.45), position), Color(0.105, 0.255 + float(tier) * 0.014, 0.17), 0.65, random) # Adds dark evergreen boughs with restrained wind.
    else: # Builds a branched broadleaf or wetland crown.
        for branch_index: int in range(5): # Places irregular branch-and-leaf groups around the trunk.
            var angle: float = float(branch_index) * 2.39996 + random.randf_range(-0.22, 0.22) # Avoids a rigid radial arrangement.
            var reach: float = random.randf_range(0.9, 1.35) # Varies the reach of each branch.
            var tip: Vector3 = Vector3(cos(angle) * reach, random.randf_range(3.0, 4.1), sin(angle) * reach) # Places each crown lobe at a believable branch endpoint.
            _branch(tool, Vector3(0.0, 1.65, 0.0), tip, random) # Connects visible foliage back to the central trunk.
            var crown: SphereMesh = SphereMesh.new() # Forms a rounded foliage cluster around the branch tip.
            crown.radius = random.randf_range(0.92, 1.25) # Varies lobe size within one coherent tree scale.
            crown.height = 2.0 if style == 0 else 2.5 # Gives wetland trees a more drooping crown.
            crown.radial_segments = 9 # Keeps rounded foliage economical enough for woodland batches.
            crown.rings = 5 # Gives silhouette irregularity enough vertices to read naturally.
            var color: Color = Color(0.17, 0.35, 0.105) if style == 0 else Color(0.15, 0.31, 0.22) # Selects foliage suited to the habitat.
            _append(tool, crown, Transform3D(Basis.IDENTITY, tip), color.lightened(random.randf_range(0.0, 0.08)), 0.75, random) # Adds subtly varied leaf clusters to the same tree mesh.
    return tool.commit() # Returns the entire tree as one batched mesh.

static func grass() -> ArrayMesh: # Builds tapered bent grass blades instead of solid crossed rectangles.
    var tool: SurfaceTool = _begin() # Starts one reusable clump of grass.
    for blade: int in range(9): # Distributes small blade silhouettes around the clump root.
        var angle: float = float(blade) * 2.39996 # Separates blade directions without a visible cross pattern.
        var root: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * (0.09 + float(blade % 3) * 0.07) # Spreads the blade roots over a small patch of soil.
        var side: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * 0.042 # Defines the narrow width of the blade.
        var bend: Vector3 = Vector3(-sin(angle), 0.0, cos(angle)) * 0.16 # Bends the blade away from its root.
        var height: float = 0.24 + float(blade % 4) * 0.085 # Varies blade height within a restrained ground-cover scale.
        var middle: Vector3 = root + Vector3.UP * height * 0.65 + bend * 0.3 # Defines the curved blade's middle section.
        var tip: Vector3 = root + Vector3.UP * height + bend # Defines its tapered upper tip.
        _blade_triangle(tool, root - side, middle + side * 0.55, root + side) # Builds the lower half of the blade.
        _blade_triangle(tool, root - side, middle - side * 0.55, middle + side * 0.55) # Completes the flexible lower section.
        _blade_triangle(tool, middle - side * 0.55, tip, middle + side * 0.55) # Tapers the upper section into a fine tip.
    return tool.commit() # Returns a reusable root-anchored grass clump.

static func shrub() -> ArrayMesh: # Builds low irregular shrub clusters for woodland edges.
    var random: RandomNumberGenerator = RandomNumberGenerator.new() # Keeps the reusable shrub shape deterministic.
    random.seed = 2917 # Selects a stable shrub silhouette.
    var tool: SurfaceTool = _begin() # Starts a merged undergrowth surface.
    for index: int in range(3): # Composes overlapping leaf lobes into a compact shrub.
        var lobe: SphereMesh = SphereMesh.new() # Forms one irregular mass of small foliage.
        lobe.radius = 0.34 # Keeps the shrub lower and narrower than character sprites.
        lobe.height = 0.58 # Gives the undergrowth a compact natural silhouette.
        lobe.radial_segments = 7 # Limits geometry cost for repeated ground detail.
        lobe.rings = 4 # Allows subtle crown deformation without excessive vertices.
        var offset: Vector3 = Vector3(cos(float(index) * 2.4) * 0.20, 0.22, sin(float(index) * 2.4) * 0.20) # Overlaps lobes around the same ground contact.
        _append(tool, lobe, Transform3D(Basis.IDENTITY, offset), Color(0.18, 0.32, 0.13), 0.55, random) # Adds varied foliage to the same rooted shrub mesh.
    return tool.commit() # Returns the reusable low shrub.

static func rock() -> ArrayMesh: # Creates a low irregular outcrop that remains compatible with open-cell navigation.
    var random: RandomNumberGenerator = RandomNumberGenerator.new() # Keeps the weathered outcrop repeatable across launches.
    random.seed = 3571 # Selects a stable irregular stone shape.
    var tool: SurfaceTool = _begin() # Uses the shared vertex-colour surface builder.
    var stone: SphereMesh = SphereMesh.new() # Starts from a compact rounded stone volume.
    stone.radius = 0.48 # Keeps stones within their accepted scenery cell.
    stone.height = 0.34 # Leaves scattered stones as low ground detail rather than invisible navigation obstacles.
    stone.radial_segments = 7 # Gives weathered rock a restrained faceted silhouette.
    stone.rings = 4 # Provides vertices for irregular natural deformation.
    _append(tool, stone, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.15, 0.0)), Color(0.35, 0.34, 0.29), 0.0, random) # Seats the stone near the root with no wind deformation.
    return tool.commit() # Returns the reusable weathered outcrop.

static func _begin() -> SurfaceTool: # Initializes one vertex-coloured organic mesh surface.
    var tool: SurfaceTool = SurfaceTool.new() # Creates the temporary mesh assembler.
    tool.begin(Mesh.PRIMITIVE_TRIANGLES) # Uses ordinary triangle geometry for compatibility rendering.
    var material: ShaderMaterial = ShaderMaterial.new() # Assigns a shared shader program to this mesh.
    material.shader = VEGETATION_SHADER # Enables vertex-coloured bark, foliage, and wind weights.
    tool.set_material(material) # Attaches the material before committing geometry.
    return tool # Returns the configured assembler.

static func _append(tool: SurfaceTool, source: PrimitiveMesh, transform: Transform3D, color: Color, wind_weight: float, random: RandomNumberGenerator) -> void: # Merges transformed primitive geometry with continuous deterministic deformation.
    var arrays: Array = source.get_mesh_arrays() # Reads the source's indexed vertex attributes.
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] # Reads local primitive positions.
    var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] # Reads local primitive normals.
    var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] # Reads the primitive's triangle winding.
    var phase: float = random.randf_range(-PI, PI) # Gives each composed part its own smooth irregularity.
    for index: int in indices: # Expands the small reusable part into the combined mesh.
        var local: Vector3 = vertices[index] # Reads this primitive vertex before deformation.
        var variation: float = sin(local.x * 5.3 + local.y * 3.7 + local.z * 4.1 + phase) * (0.20 if wind_weight > 0.0 else 0.04) # Applies continuous shape variation without cracks between duplicate vertices.
        var point: Vector3 = transform * (local * (1.0 + variation)) # Places the deformed vertex inside the whole object.
        tool.set_normal((transform.basis * normals[index]).normalized()) # Preserves smooth lighting through the merged geometry.
        tool.set_color(color.lightened(maxf(variation, 0.0) * 0.5)) # Adds subdued local organic colour variation.
        tool.set_uv(Vector2(0.0, wind_weight)) # Marks foliage while anchoring wood and stone.
        tool.add_vertex(point) # Adds the final shared-root object vertex.

static func _branch(tool: SurfaceTool, start: Vector3, finish: Vector3, random: RandomNumberGenerator) -> void: # Connects the central trunk to a foliage lobe with visible wood.
    var direction: Vector3 = finish - start # Measures the branch axis and required length.
    var branch: CylinderMesh = CylinderMesh.new() # Creates an inexpensive tapered wooden branch.
    branch.bottom_radius = 0.105 # Fits the branch base naturally against the trunk.
    branch.top_radius = 0.035 # Tapers the branch toward its leaf cluster.
    branch.height = direction.length() # Connects the two authored branch endpoints exactly.
    branch.radial_segments = 5 # Limits geometry on small background branches.
    branch.rings = 1 # Avoids redundant subdivisions along the branch.
    var basis: Basis = Basis(Quaternion(Vector3.UP, direction.normalized())) # Rotates the branch cylinder onto the endpoint direction.
    _append(tool, branch, Transform3D(basis, (start + finish) * 0.5), Color(0.24, 0.16, 0.085), 0.0, random) # Adds rooted wooden structure with no detached moving parts.

static func _blade_triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void: # Adds one shaded flexible triangle to a grass blade.
    var normal: Vector3 = (b - a).cross(c - a).normalized() # Computes the thin blade's geometric normal.
    for point: Vector3 in [a, b, c]: # Emits the blade triangle in its authored winding order.
        tool.set_normal(normal) # Gives each blade a consistent response to sunlight.
        tool.set_color(Color(0.22, 0.38, 0.12).lerp(Color(0.42, 0.49, 0.21), clampf(point.y * 1.5, 0.0, 1.0))) # Grades the blade from shaded root to sunlit tip.
        tool.set_uv(Vector2(0.0, point.y)) # Weights the wind by height so roots remain fixed.
        tool.add_vertex(point) # Adds the root-relative blade vertex.
