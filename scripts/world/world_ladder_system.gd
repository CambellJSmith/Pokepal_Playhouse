class_name WorldLadderSystem # Streams climbable ladders along otherwise impassable geological height changes.
extends Node3D # Owns ladder markers and batched visuals independently from terrain chunks.

const LADDER_CHUNK_RADIUS: int = 3 # Keeps ladder coverage around the player aligned with nearby streamed terrain.
const LADDER_UNLOAD_RADIUS: int = 4 # Retains one extra ladder ring to avoid churn near chunk boundaries.
const LADDERS_PER_FRAME: int = 1 # Limits ladder-chunk analysis to one bounded chunk each frame.
const MIN_LADDER_HEIGHT: float = 1.75 # Treats vertical changes above ordinary walking capability as ladder candidates.
const MAX_LADDER_HEIGHT: float = 18.0 # Avoids generating impractically long ladders across extreme mountain walls.
const LADDER_SPACING_MODULUS: int = 6 # Spaces ladders along continuous cliff bands instead of covering every metre with rungs.

var world_builder: RadialWorldBuilder # References the active infinite terrain service and deterministic sampler.
var player_reference: Node3D # Tracks the player chunk that drives ladder streaming.
var ladder_chunks: Dictionary[Vector2i, Node3D] = {} # Stores generated ladder roots by infinite terrain chunk coordinate.
var pending_chunks: Array[Vector2i] = [] # Queues nearby chunks whose cliff edges still need ladder analysis.
var stream_center: Vector2i = Vector2i(2147483647, 2147483647) # Forces the first resolved player chunk to populate ladder coverage.
var ladder_mesh: BoxMesh # Reuses one unit box for all rail and rung MultiMesh instances.
var ladder_material: StandardMaterial3D # Reuses one simple wood material across every streamed ladder.

func _ready() -> void: # Resolves world dependencies and prepares shared ladder rendering resources.
    ladder_mesh = BoxMesh.new() # Creates one reusable box primitive for rails and rungs.
    ladder_mesh.size = Vector3.ONE # Keeps geometry normalized so instance transforms control every ladder dimension.
    ladder_material = StandardMaterial3D.new() # Creates one inexpensive material for all ladder pieces.
    ladder_material.albedo_color = Color(0.38, 0.24, 0.12, 1.0) # Gives ladders a readable warm timber appearance against varied geology.
    ladder_material.roughness = 0.86 # Keeps ladder surfaces matte and visually grounded.
    ladder_mesh.material = ladder_material # Applies the shared material directly to the reusable primitive.
    call_deferred("_resolve_dependencies") # Waits for sibling world and player nodes to finish entering the tree.

func _process(_delta: float) -> void: # Incrementally analyzes nearby cliff chunks without adding a large frame spike.
    if world_builder == null or player_reference == null: # Waits until both runtime dependencies are available.
        return # Skips generation while scene construction is incomplete.
    var current_chunk: Vector2i = world_builder.world_to_chunk(player_reference.global_position) # Resolves the player's current infinite terrain chunk.
    if current_chunk != stream_center: # Detects movement into a new chunk.
        _refresh_stream_window(current_chunk) # Rebuilds nearby ladder priorities and unloads distant ladder data.
    var builds_remaining: int = LADDERS_PER_FRAME # Establishes the bounded per-frame analysis budget.
    while builds_remaining > 0 and not pending_chunks.is_empty(): # Processes only the configured number of ladder chunks this frame.
        var coordinate: Vector2i = pending_chunks.pop_front() # Takes the nearest outstanding ladder chunk.
        if not ladder_chunks.has(coordinate): # Avoids rebuilding an already resident ladder root.
            _build_ladder_chunk(coordinate) # Analyzes local terrain edges and creates required ladders.
        builds_remaining -= 1 # Accounts for one completed analysis slot.

func _resolve_dependencies() -> void: # Resolves the radial world and player through semantic groups.
    world_builder = get_tree().get_first_node_in_group(&"world_builder") as RadialWorldBuilder # Narrows the active world service to the radial implementation.
    player_reference = get_tree().get_first_node_in_group(&"player") as Node3D # Resolves the main character without a hard-coded NodePath.
    if world_builder == null or player_reference == null: # Detects malformed scene composition.
        push_error("WorldLadderSystem requires RadialWorldBuilder and a player node.") # Reports the missing dependency clearly.
        return # Stops before attempting coordinate conversion.
    _refresh_stream_window(world_builder.world_to_chunk(player_reference.global_position)) # Populates initial ladder coverage around the player.

func _refresh_stream_window(center_chunk: Vector2i) -> void: # Queues nearby ladder analysis and retires distant ladder chunks.
    stream_center = center_chunk # Stores the current ladder-stream origin.
    pending_chunks.clear() # Removes obsolete priorities after movement or fast travel.
    for radius: int in range(LADDER_CHUNK_RADIUS + 1): # Queues chunks nearest-first using concentric square rings.
        for offset_y: int in range(-radius, radius + 1): # Traverses candidate rows in this priority ring.
            for offset_x: int in range(-radius, radius + 1): # Traverses candidate columns in this priority ring.
                if maxi(absi(offset_x), absi(offset_y)) != radius: # Keeps each coordinate in exactly one ring.
                    continue # Skips interior coordinates already visited by smaller radii.
                var coordinate: Vector2i = center_chunk + Vector2i(offset_x, offset_y) # Resolves one nearby infinite chunk coordinate.
                if not ladder_chunks.has(coordinate): # Queues only chunks not already represented.
                    pending_chunks.append(coordinate) # Defers bounded cliff analysis to the normal process loop.
    var loaded_coordinates: Array[Vector2i] = [] # Takes a stable snapshot before mutating the ladder dictionary.
    for coordinate: Vector2i in ladder_chunks: # Reads each currently resident ladder chunk key.
        loaded_coordinates.append(coordinate) # Copies the key for safe unload iteration.
    for coordinate: Vector2i in loaded_coordinates: # Evaluates resident ladder chunks against the new player centre.
        var distance: int = maxi(absi(coordinate.x - center_chunk.x), absi(coordinate.y - center_chunk.y)) # Measures cheap Chebyshev chunk distance.
        if distance <= LADDER_UNLOAD_RADIUS: # Retains chunks inside the hysteresis ring.
            continue # Avoids load/unload churn near the coverage edge.
        var ladder_root: Node3D = ladder_chunks[coordinate] # Reads the scene root being retired.
        ladder_chunks.erase(coordinate) # Removes bookkeeping before freeing the scene nodes.
        ladder_root.queue_free() # Releases ladder markers and MultiMesh resources safely at frame end.

func _build_ladder_chunk(coordinate: Vector2i) -> void: # Finds steep adjacent cell transitions and builds sparse guaranteed climbing points along them.
    var root: Node3D = Node3D.new() # Creates one owner for every ladder and render batch in this terrain chunk.
    root.name = "ladder_chunk_%s_%s" % [coordinate.x, coordinate.y] # Gives the streamed ladder root a stable diagnostic name.
    add_child(root) # Adds the root before creating markers and visuals beneath it.
    ladder_chunks[coordinate] = root # Records residency immediately so duplicate queue work cannot occur.
    var rail_transforms: Array[Transform3D] = [] # Collects both vertical rails for every ladder in this chunk.
    var rung_transforms: Array[Transform3D] = [] # Collects all horizontal rungs for every ladder in this chunk.
    var start_cell: Vector2i = coordinate * RadialWorldChunk.CHUNK_CELLS # Resolves the chunk's global logical-cell origin.
    for local_y: int in range(RadialWorldChunk.CHUNK_CELLS): # Traverses every logical terrain row in the chunk.
        for local_x: int in range(RadialWorldChunk.CHUNK_CELLS): # Traverses every logical terrain cell in the row.
            var cell: Vector2i = start_cell + Vector2i(local_x, local_y) # Resolves the authoritative global logical cell coordinate.
            _consider_edge(root, rail_transforms, rung_transforms, cell, cell + Vector2i.RIGHT) # Tests the east-west height transition once from its western owner.
            _consider_edge(root, rail_transforms, rung_transforms, cell, cell + Vector2i.DOWN) # Tests the north-south height transition once from its northern owner.
    _build_batch(root, "ladder_rails", rail_transforms) # Uploads all vertical rail pieces as one GPU instance batch.
    _build_batch(root, "ladder_rungs", rung_transforms) # Uploads all rung pieces as one GPU instance batch.

func _consider_edge(root: Node3D, rail_transforms: Array[Transform3D], rung_transforms: Array[Transform3D], cell_a: Vector2i, cell_b: Vector2i) -> void: # Adds one ladder when an adjacent-cell height change cannot be walked normally.
    var position_a: Vector3 = world_builder.cell_to_world(cell_a) # Grounds the first adjacent cell on the deterministic terrain surface.
    var position_b: Vector3 = world_builder.cell_to_world(cell_b) # Grounds the second adjacent cell on the deterministic terrain surface.
    var height_difference: float = absf(position_b.y - position_a.y) # Measures the vertical barrier between the two cell centres.
    if height_difference < MIN_LADDER_HEIGHT or height_difference > MAX_LADDER_HEIGHT: # Rejects ordinary slopes and extreme walls unsuitable for one ladder.
        return # Leaves normally walkable changes alone and avoids absurd ladder lengths.
    var route_midpoint: Vector2 = (Vector2(float(cell_a.x), float(cell_a.y)) + Vector2(float(cell_b.x), float(cell_b.y))) * 0.5 # Resolves the transition midpoint in sampler coordinates.
    var on_route: bool = world_builder.radial_sampler.sample_route_distance(route_midpoint) <= 3.0 # Guarantees ladders wherever a main travel route meets a cliff.
    var spacing_hash: int = absi(cell_a.x * 31 + cell_a.y * 17 + cell_b.x * 13 + cell_b.y * 7) # Produces deterministic spacing along non-route cliff bands.
    if not on_route and spacing_hash % LADDER_SPACING_MODULUS != 0: # Keeps natural cliff ladders useful without covering every edge in repeated props.
        return # Leaves this section of the same climbable cliff band visually clean.
    var lower_position: Vector3 = position_a if position_a.y < position_b.y else position_b # Identifies the walkable lower exit of the ladder.
    var upper_position: Vector3 = position_b if position_b.y > position_a.y else position_a # Identifies the walkable upper exit of the ladder.
    var edge_direction: Vector3 = position_b - position_a # Measures the horizontal direction crossing the cliff face.
    edge_direction.y = 0.0 # Removes vertical difference before orientation calculations.
    edge_direction = edge_direction.normalized() # Produces the unit normal pointing across the cliff transition.
    var ladder_center: Vector3 = (lower_position + upper_position) * 0.5 # Centres ladder geometry vertically between both terrain levels.
    ladder_center.x = (position_a.x + position_b.x) * 0.5 # Places the ladder directly on the shared cliff boundary along X.
    ladder_center.z = (position_a.z + position_b.z) * 0.5 # Places the ladder directly on the shared cliff boundary along Z.
    var marker: Node3D = Node3D.new() # Creates one lightweight gameplay marker for player ladder detection.
    marker.name = "ladder" # Gives every climbable marker one predictable semantic name.
    marker.global_position = ladder_center # Places the marker at the centre of the climbable vertical span.
    marker.add_to_group(&"world_ladder") # Exposes the marker through a signal-free semantic group lookup.
    marker.set_meta(&"bottom_position", lower_position + edge_direction * 0.28 + Vector3.UP * 0.1) # Stores the lower walk-off position clear of the cliff face.
    marker.set_meta(&"top_position", upper_position - edge_direction * 0.28 + Vector3.UP * 0.1) # Stores the upper walk-off position on the high side of the cliff.
    marker.set_meta(&"climb_height", height_difference) # Stores the usable vertical span for proximity checks and player interpolation.
    root.add_child(marker) # Parents the gameplay marker under the streamed ladder chunk root.
    var tangent: Vector3 = Vector3(-edge_direction.z, 0.0, edge_direction.x) # Builds the horizontal axis running across the ladder face.
    var ladder_basis: Basis = Basis(tangent, Vector3.UP, edge_direction).orthonormalized() # Aligns local X across the ladder and local Y vertically.
    var rail_offset: float = 0.42 # Separates the two rails enough for the character sprite to read the ladder clearly.
    for side: float in [-1.0, 1.0]: # Creates the left and right vertical rail instances.
        var rail_origin: Vector3 = ladder_center + tangent * rail_offset * side # Offsets one rail laterally across the cliff face.
        var rail_basis: Basis = ladder_basis.scaled(Vector3(0.10, height_difference + 0.55, 0.10)) # Scales the unit box into one narrow vertical timber rail.
        rail_transforms.append(Transform3D(rail_basis, rail_origin - global_position)) # Stores the rail transform in ladder-system local space.
    var rung_count: int = maxi(3, int(floor(height_difference / 0.45))) # Chooses closely spaced rungs across the complete climb span.
    for rung_index: int in range(rung_count + 1): # Creates all horizontal rungs from bottom to top.
        var rung_fraction: float = float(rung_index) / float(rung_count) # Converts the rung index into normalized ladder height.
        var rung_origin: Vector3 = ladder_center # Starts each rung on the ladder centre line.
        rung_origin.y = lerpf(lower_position.y, upper_position.y, rung_fraction) # Places this rung at its evenly distributed vertical height.
        var rung_basis: Basis = ladder_basis.scaled(Vector3(0.96, 0.08, 0.10)) # Scales the unit box into one horizontal rung across both rails.
        rung_transforms.append(Transform3D(rung_basis, rung_origin - global_position)) # Stores the rung transform in ladder-system local space.

func _build_batch(root: Node3D, node_name: String, transforms: Array[Transform3D]) -> void: # Builds one MultiMesh batch for repeated ladder pieces.
    if transforms.is_empty(): # Avoids creating empty render resources for chunks without ladders.
        return # Leaves the ladder root marker-only when no visual pieces were generated.
    var multi_mesh: MultiMesh = MultiMesh.new() # Allocates one GPU-friendly repeated-instance buffer.
    multi_mesh.transform_format = MultiMesh.TRANSFORM_3D # Stores complete 3D transforms for each ladder piece.
    multi_mesh.mesh = ladder_mesh # Reuses the shared unit box geometry for rails and rungs.
    multi_mesh.instance_count = transforms.size() # Allocates exactly the required number of repeated pieces.
    for index: int in range(transforms.size()): # Uploads each generated rail or rung transform once.
        multi_mesh.set_instance_transform(index, transforms[index]) # Writes the transform into the MultiMesh buffer.
    var instance: MultiMeshInstance3D = MultiMeshInstance3D.new() # Creates the scene renderer for this ladder piece batch.
    instance.name = node_name # Gives rails and rungs separate readable scene-tree entries.
    instance.multimesh = multi_mesh # Attaches the completed repeated-instance resource.
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON # Lets ladders cast simple shadows against cliff faces.
    root.add_child(instance) # Parents the batch beneath its streamed ladder chunk root.
