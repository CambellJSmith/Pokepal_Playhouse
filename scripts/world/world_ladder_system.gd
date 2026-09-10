class_name WorldLadderSystem # Creates a single climb route only for isolated walkable land pockets.
extends Node3D # Keeps ladder analysis and rendering separate from terrain generation.

const ANALYSIS_RADIUS_CELLS: int = 52 # Examines a broad local terrain window around the player for isolated flat regions.
const MIN_REGION_CELLS: int = 6 # Ignores tiny isolated fragments that are not meaningful explorable land.
const MAX_REGION_HEIGHT_RANGE: float = 2.2 # Requires an isolated component to remain broadly flat before it qualifies for a ladder.
const MAX_WALK_STEP_HEIGHT: float = 1.15 # Treats adjacent walkable cells within this vertical change as ordinary walking connectivity.
const MIN_LADDER_HEIGHT: float = 1.75 # Requires a genuine inaccessible vertical transition before adding a ladder.
const REBUILD_CHUNK_DISTANCE: int = 1 # Reanalyzes only after the player crosses into another terrain chunk.

var world_builder: RadialWorldBuilder # References the active infinite terrain service.
var player_reference: Node3D # Tracks the main character used to center local accessibility analysis.
var last_analysis_chunk: Vector2i = Vector2i(2147483647, 2147483647) # Forces one initial analysis after dependencies resolve.
var ladder_root: Node3D # Owns the currently generated ladder markers and batched visuals.
var ladder_mesh: BoxMesh # Reuses one unit box for all rail and rung instances.
var ladder_material: StandardMaterial3D # Reuses one simple wood material across every generated ladder piece.

func _ready() -> void: # Prepares shared ladder resources and resolves runtime dependencies after scene startup.
    ladder_mesh = BoxMesh.new() # Creates one reusable primitive for rails and rungs.
    ladder_mesh.size = Vector3.ONE # Keeps the source mesh normalized so transforms control dimensions.
    ladder_material = StandardMaterial3D.new() # Creates one shared ladder material.
    ladder_material.albedo_color = Color(0.38, 0.24, 0.12, 1.0) # Gives ladder geometry a readable timber appearance.
    ladder_material.roughness = 0.86 # Keeps ladder surfaces matte against terrain.
    ladder_mesh.material = ladder_material # Applies the shared material directly to the reusable primitive.
    call_deferred("_resolve_dependencies") # Waits for sibling world and player nodes to finish entering the tree.

func _process(_delta: float) -> void: # Rebuilds sparse ladder access only after meaningful player movement between chunks.
    if world_builder == null or player_reference == null: # Waits until both required dependencies are available.
        return # Avoids analysis while scene construction is incomplete.
    var current_chunk: Vector2i = world_builder.world_to_chunk(player_reference.global_position) # Resolves the player's current streamed terrain chunk.
    if current_chunk == last_analysis_chunk: # Keeps ladder placement stable while the player remains in the same chunk.
        return # Avoids repeated flood-fill analysis every rendered frame.
    _rebuild_ladders(current_chunk) # Reanalyzes accessibility around the player's new chunk.

func _resolve_dependencies() -> void: # Resolves the radial world and player through semantic groups.
    world_builder = get_tree().get_first_node_in_group(&"world_builder") as RadialWorldBuilder # Finds the active radial world without a hard-coded NodePath.
    player_reference = get_tree().get_first_node_in_group(&"player") as Node3D # Finds the main character through its semantic group.
    if world_builder == null or player_reference == null: # Detects malformed scene composition.
        push_error("WorldLadderSystem requires RadialWorldBuilder and a player node.") # Reports the missing dependency directly.
        return # Stops before attempting terrain analysis.
    _rebuild_ladders(world_builder.world_to_chunk(player_reference.global_position)) # Builds the first sparse ladder set around the player.

func _rebuild_ladders(center_chunk: Vector2i) -> void: # Finds isolated walkable land regions and gives each qualifying region one ladder only.
    last_analysis_chunk = center_chunk # Stores the chunk that owns this accessibility snapshot.
    if ladder_root != null and is_instance_valid(ladder_root): # Detects a previous sparse ladder set.
        ladder_root.queue_free() # Removes old markers and visuals before rebuilding the local accessibility graph.
    ladder_root = Node3D.new() # Creates one root for the complete current ladder set.
    ladder_root.name = "sparse_access_ladders" # Gives the generated ladder collection a stable diagnostic name.
    add_child(ladder_root) # Parents the root before adding markers and render batches.
    var rail_transforms: Array[Transform3D] = [] # Collects rail pieces for one batched render submission.
    var rung_transforms: Array[Transform3D] = [] # Collects rung pieces for one batched render submission.
    var center_cell: Vector2i = world_builder.world_to_cell(player_reference.global_position) # Converts the player position into the logical terrain grid.
    var minimum_cell: Vector2i = center_cell - Vector2i(ANALYSIS_RADIUS_CELLS, ANALYSIS_RADIUS_CELLS) # Defines the local analysis window minimum coordinate.
    var maximum_cell: Vector2i = center_cell + Vector2i(ANALYSIS_RADIUS_CELLS, ANALYSIS_RADIUS_CELLS) # Defines the local analysis window maximum coordinate.
    var visited: Dictionary[Vector2i, bool] = {} # Tracks cells already assigned to a walking-connected component.
    for y: int in range(minimum_cell.y, maximum_cell.y + 1): # Traverses every logical row inside the bounded analysis window.
        for x: int in range(minimum_cell.x, maximum_cell.x + 1): # Traverses every logical cell in the current row.
            var start_cell: Vector2i = Vector2i(x, y) # Resolves this global terrain-cell coordinate.
            if visited.has(start_cell): # Skips cells already consumed by an earlier component flood fill.
                continue # Preserves linear component traversal across the analysis window.
            if not world_builder.is_cell_walkable(start_cell): # Rejects steep surface cells that do not themselves form usable land.
                visited[start_cell] = true # Marks the unusable cell so it is not reconsidered later.
                continue # Moves directly to the next candidate cell.
            var region: Array[Vector2i] = [] # Collects one walking-connected component of usable terrain.
            var touches_window_edge: bool = _collect_walkable_region(start_cell, minimum_cell, maximum_cell, visited, region) # Flood-fills ordinary walking links and reports whether the component exits the known window.
            if touches_window_edge: # Treats components continuing beyond the analysis window as potentially accessible elsewhere.
                continue # Refuses to add speculative ladders to large or incomplete land masses.
            if region.size() < MIN_REGION_CELLS: # Rejects tiny isolated ledges that are not meaningful explorable spaces.
                continue # Leaves decorative fragments without ladders.
            if not _is_region_flat_enough(region): # Requires the enclosed component to read as usable flat land rather than a mountain face.
                continue # Avoids ladders on irregular steep terrain masses.
            var ladder_edge: Array[Vector2i] = _find_best_ladder_edge(region) # Finds one deterministic boundary crossing into the isolated land.
            if ladder_edge.size() != 2: # Detects isolated regions without a practical neighboring landing cell.
                continue # Leaves impossible geometry without generating a nonsensical ladder.
            _add_ladder(ladder_root, rail_transforms, rung_transforms, ladder_edge[0], ladder_edge[1]) # Creates exactly one ladder for this otherwise inaccessible region.
    _build_batch(ladder_root, "ladder_rails", rail_transforms) # Uploads all rails through one MultiMesh batch.
    _build_batch(ladder_root, "ladder_rungs", rung_transforms) # Uploads all rungs through one MultiMesh batch.

func _collect_walkable_region(start_cell: Vector2i, minimum_cell: Vector2i, maximum_cell: Vector2i, visited: Dictionary[Vector2i, bool], region: Array[Vector2i]) -> bool: # Flood-fills cells reachable from one another by ordinary walking only.
    var queue: Array[Vector2i] = [start_cell] # Starts breadth-first traversal from the first usable cell.
    visited[start_cell] = true # Marks the seed immediately so neighbors cannot enqueue it twice.
    var touches_window_edge: bool = false # Tracks whether this component continues beyond the analysis window.
    while not queue.is_empty(): # Processes every walking-connected cell in the current component.
        var cell: Vector2i = queue.pop_front() # Takes the next breadth-first cell.
        region.append(cell) # Adds the cell to this component's final membership list.
        if cell.x == minimum_cell.x or cell.x == maximum_cell.x or cell.y == minimum_cell.y or cell.y == maximum_cell.y: # Detects components touching the unknown outside world.
            touches_window_edge = true # Marks the region as incomplete for conservative ladder decisions.
        for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]: # Tests four-cardinal walking adjacency only.
            var neighbor: Vector2i = cell + direction # Resolves the neighboring terrain cell.
            if neighbor.x < minimum_cell.x or neighbor.x > maximum_cell.x or neighbor.y < minimum_cell.y or neighbor.y > maximum_cell.y: # Rejects neighbors outside the bounded analysis window.
                continue # Leaves unknown terrain for a later analysis centered closer to it.
            if visited.has(neighbor): # Skips cells already classified by this or another traversal.
                continue # Prevents duplicate queue entries.
            if not world_builder.is_cell_walkable(neighbor): # Rejects steep neighbor surfaces as ordinary walking destinations.
                continue # Leaves the cell available for later classification as non-walkable terrain.
            if not _cells_connect_by_walking(cell, neighbor): # Rejects excessive vertical steps between otherwise flat neighboring cells.
                continue # Preserves true cliff separation between plateaus and pits.
            visited[neighbor] = true # Claims the valid walking neighbor for this component.
            queue.append(neighbor) # Continues breadth-first traversal through ordinary walking links.
    return touches_window_edge # Reports whether the component is fully enclosed inside the known terrain window.

func _cells_connect_by_walking(cell_a: Vector2i, cell_b: Vector2i) -> bool: # Tests whether two neighboring usable cells can be crossed without a ladder.
    var position_a: Vector3 = world_builder.cell_to_world(cell_a) # Reads the first cell's grounded center position.
    var position_b: Vector3 = world_builder.cell_to_world(cell_b) # Reads the second cell's grounded center position.
    return absf(position_b.y - position_a.y) <= MAX_WALK_STEP_HEIGHT # Accepts only modest height changes as ordinary walking connectivity.

func _is_region_flat_enough(region: Array[Vector2i]) -> bool: # Rejects enclosed components whose surface varies too much to count as a flat explorable pocket.
    var minimum_height: float = INF # Starts above all valid terrain heights for minimum tracking.
    var maximum_height: float = -INF # Starts below all valid terrain heights for maximum tracking.
    for cell: Vector2i in region: # Samples each walking-connected cell once.
        var height: float = world_builder.cell_to_world(cell).y # Reads the deterministic terrain center height.
        minimum_height = minf(minimum_height, height) # Updates the region's lowest usable point.
        maximum_height = maxf(maximum_height, height) # Updates the region's highest usable point.
        if maximum_height - minimum_height > MAX_REGION_HEIGHT_RANGE: # Detects a component that has become too vertically varied.
            return false # Rejects mountain-like or heavily sloped regions early.
    return true # Confirms the isolated component is broadly flat enough to deserve access.

func _find_best_ladder_edge(region: Array[Vector2i]) -> Array[Vector2i]: # Chooses one deterministic practical cliff edge for the entire isolated region.
    var membership: Dictionary[Vector2i, bool] = {} # Creates constant-time membership lookup for boundary testing.
    for cell: Vector2i in region: # Indexes every cell in the isolated component.
        membership[cell] = true # Marks the cell as belonging to this flat land pocket.
    var best_inside: Vector2i = Vector2i.ZERO # Stores the isolated-side cell of the preferred ladder edge.
    var best_outside: Vector2i = Vector2i.ZERO # Stores the surrounding-side cell of the preferred ladder edge.
    var best_score: float = INF # Prefers the shortest viable ladder, then uses deterministic coordinate bias for ties.
    for inside_cell: Vector2i in region: # Examines every boundary opportunity around the isolated land.
        var inside_position: Vector3 = world_builder.cell_to_world(inside_cell) # Grounds the isolated-side landing position once.
        for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]: # Tests each cardinal boundary edge.
            var outside_cell: Vector2i = inside_cell + direction # Resolves the neighboring cell across this component boundary.
            if membership.has(outside_cell): # Rejects internal edges that remain inside the same land pocket.
                continue # Continues searching for a true boundary crossing.
            if not world_builder.is_cell_walkable(outside_cell): # Requires a usable landing surface on both ends of the ladder.
                continue # Avoids ladders terminating on steep or broken terrain.
            var outside_position: Vector3 = world_builder.cell_to_world(outside_cell) # Grounds the surrounding-side landing position.
            var height_difference: float = absf(outside_position.y - inside_position.y) # Measures the required ladder span.
            if height_difference < MIN_LADDER_HEIGHT: # Rejects transitions that should not need a ladder.
                continue # Leaves ordinary walking-scale changes unmodified.
            var coordinate_bias: float = float(absi(inside_cell.x * 31 + inside_cell.y * 17 + outside_cell.x * 13 + outside_cell.y * 7) % 1000) * 0.000001 # Makes equal-height choices deterministic without materially changing ladder-length preference.
            var score: float = height_difference + coordinate_bias # Prefers the least extreme valid crossing into the region.
            if score >= best_score: # Rejects candidates no better than the current preferred edge.
                continue # Preserves deterministic best-edge selection.
            best_score = score # Stores the improved ladder cost.
            best_inside = inside_cell # Records the isolated-side landing cell.
            best_outside = outside_cell # Records the surrounding-side landing cell.
    if best_score == INF: # Detects a region with no usable flat landing on the other side of its cliff boundary.
        return [] # Reports that no ladder should be generated.
    return [best_outside, best_inside] # Returns exactly one surrounding-to-isolated boundary edge for this region.

func _add_ladder(root: Node3D, rail_transforms: Array[Transform3D], rung_transforms: Array[Transform3D], cell_a: Vector2i, cell_b: Vector2i) -> void: # Creates one climbable ladder between two selected flat landing cells.
    var position_a: Vector3 = world_builder.cell_to_world(cell_a) # Grounds the first landing cell on deterministic terrain.
    var position_b: Vector3 = world_builder.cell_to_world(cell_b) # Grounds the second landing cell on deterministic terrain.
    var height_difference: float = absf(position_b.y - position_a.y) # Measures the complete climb span.
    if height_difference < MIN_LADDER_HEIGHT: # Revalidates the selected edge before constructing geometry.
        return # Refuses to create a ladder for a now-walkable transition.
    var lower_position: Vector3 = position_a if position_a.y < position_b.y else position_b # Identifies the lower landing point.
    var upper_position: Vector3 = position_b if position_b.y > position_a.y else position_a # Identifies the upper landing point.
    var edge_direction: Vector3 = position_b - position_a # Measures the horizontal direction crossing the cliff face.
    edge_direction.y = 0.0 # Removes vertical difference before orientation calculations.
    if edge_direction.length_squared() <= 0.0001: # Guards degenerate adjacency data.
        return # Avoids constructing an invalid basis from a zero direction.
    edge_direction = edge_direction.normalized() # Produces a stable unit normal across the cliff transition.
    var ladder_center: Vector3 = (lower_position + upper_position) * 0.5 # Centers ladder geometry vertically between both terrain levels.
    ladder_center.x = (position_a.x + position_b.x) * 0.5 # Places the ladder on the shared boundary along world X.
    ladder_center.z = (position_a.z + position_b.z) * 0.5 # Places the ladder on the shared boundary along world Z.
    var marker: Node3D = Node3D.new() # Creates one lightweight gameplay marker for player ladder detection.
    marker.name = "ladder" # Gives the climbable marker a predictable semantic name.
    marker.global_position = ladder_center # Places the marker at the center of the climbable span.
    marker.add_to_group(&"world_ladder") # Exposes the ladder through the existing signal-free semantic group.
    marker.set_meta(&"bottom_position", lower_position + edge_direction * 0.28 + Vector3.UP * 0.1) # Stores the lower safe walk-off position clear of the cliff face.
    marker.set_meta(&"top_position", upper_position - edge_direction * 0.28 + Vector3.UP * 0.1) # Stores the upper safe walk-off position on the isolated flat land.
    marker.set_meta(&"climb_height", height_difference) # Stores the usable vertical span for player proximity checks.
    root.add_child(marker) # Parents the gameplay marker under the current sparse ladder root.
    var tangent: Vector3 = Vector3(-edge_direction.z, 0.0, edge_direction.x) # Builds the horizontal axis running across the ladder face.
    var ladder_basis: Basis = Basis(tangent, Vector3.UP, edge_direction).orthonormalized() # Aligns local X across the ladder and local Y vertically.
    var rail_offset: float = 0.42 # Separates the two rails for clear visual readability.
    for side: float in [-1.0, 1.0]: # Creates both vertical rail instances.
        var rail_origin: Vector3 = ladder_center + tangent * rail_offset * side # Offsets one rail laterally across the cliff face.
        var rail_basis: Basis = ladder_basis.scaled(Vector3(0.10, height_difference + 0.55, 0.10)) # Scales the unit box into a narrow vertical timber rail.
        rail_transforms.append(Transform3D(rail_basis, rail_origin - global_position)) # Stores the rail transform in ladder-system local space.
    var rung_count: int = maxi(3, int(floor(height_difference / 0.45))) # Chooses evenly spaced rungs across the complete climb span.
    for rung_index: int in range(rung_count + 1): # Creates each horizontal rung from bottom to top.
        var rung_fraction: float = float(rung_index) / float(rung_count) # Converts the rung index into normalized ladder height.
        var rung_origin: Vector3 = ladder_center # Starts the rung on the ladder center line.
        rung_origin.y = lerpf(lower_position.y, upper_position.y, rung_fraction) # Places this rung at its evenly distributed vertical height.
        var rung_basis: Basis = ladder_basis.scaled(Vector3(0.96, 0.08, 0.10)) # Scales the unit box into one horizontal rung.
        rung_transforms.append(Transform3D(rung_basis, rung_origin - global_position)) # Stores the rung transform in ladder-system local space.

func _build_batch(root: Node3D, node_name: String, transforms: Array[Transform3D]) -> void: # Builds one MultiMesh batch for repeated ladder pieces.
    if transforms.is_empty(): # Avoids creating empty render resources when no ladders are required.
        return # Leaves the root marker-only or empty as appropriate.
    var multi_mesh: MultiMesh = MultiMesh.new() # Allocates one GPU-friendly repeated-instance buffer.
    multi_mesh.transform_format = MultiMesh.TRANSFORM_3D # Stores complete 3D transforms for each ladder piece.
    multi_mesh.mesh = ladder_mesh # Reuses the shared unit box geometry for every rail or rung.
    multi_mesh.instance_count = transforms.size() # Allocates exactly the required instance count.
    for index: int in range(transforms.size()): # Uploads each generated transform once.
        multi_mesh.set_instance_transform(index, transforms[index]) # Writes the transform into the MultiMesh buffer.
    var instance: MultiMeshInstance3D = MultiMeshInstance3D.new() # Creates the render node owning the repeated-instance resource.
    instance.name = node_name # Gives rails and rungs separate readable scene-tree names.
    instance.multimesh = multi_mesh # Attaches the completed repeated-instance resource.
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON # Lets sparse ladders cast grounding shadows against cliffs.
    root.add_child(instance) # Parents the batch beneath the current sparse ladder root.
