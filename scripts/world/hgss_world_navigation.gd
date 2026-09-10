class_name HgssWorldNavigation # Provides bounded local pathfinding over finite or streamed procedural worlds.
extends RefCounted # Keeps navigation work outside the scene tree because it has no transform or frame processing.

const PATH_MARGIN_CELLS: int = 10 # Adds local search room around requested endpoints without allocating a world-sized navigation grid.
const DIRECT_LINE_SAMPLE_LIMIT: int = 192 # Caps cheap direct-path sampling before falling back to a local AStarGrid2D.

static func get_world_path(world_builder: HgssWorldBuilder, from_world: Vector3, to_world: Vector3) -> Array[Vector3]: # Finds a practical local route using unbounded signed world cells.
    if world_builder == null: # Guards scene teardown and malformed setup before any path work.
        return [] # Reports that no safe route can be produced without a world service.
    var from_cell: Vector2i = world_builder.world_to_cell(from_world) # Converts the current character position into the world's logical grid.
    var to_cell: Vector2i = world_builder.world_to_cell(to_world) # Converts the requested destination into the same logical coordinate space.
    if not world_builder.is_cell_walkable(from_cell): # Recovers if physics left the character on a locally steep generated cell.
        from_cell = world_builder.world_to_cell(world_builder.get_nearest_walkable_world_position(from_world)) # Snaps the starting point to nearby practical terrain.
    if not world_builder.is_cell_walkable(to_cell): # Recovers if the requested destination lies on locally steep terrain.
        to_cell = world_builder.world_to_cell(world_builder.get_nearest_walkable_world_position(to_world)) # Snaps the destination to nearby practical terrain.
    if from_cell == to_cell: # Handles very short movement without allocating any pathfinding structure.
        return [world_builder.cell_to_world(to_cell)] # Returns the grounded destination cell directly.
    if _has_clear_direct_path(world_builder, from_cell, to_cell): # Prefers a straight route when every sampled cell is practical.
        return [world_builder.cell_to_world(to_cell)] # Avoids AStar allocation for the common open-terrain case.
    return _build_local_astar_path(world_builder, from_cell, to_cell) # Uses a bounded signed-coordinate AStar grid only around obstructed requests.

static func _has_clear_direct_path(world_builder: HgssWorldBuilder, from_cell: Vector2i, to_cell: Vector2i) -> bool: # Tests a rasterized straight line before invoking AStar.
    var delta: Vector2i = to_cell - from_cell # Measures the requested grid displacement.
    var steps: int = maxi(absi(delta.x), absi(delta.y)) # Uses enough samples to visit every crossed logical-cell span.
    if steps > DIRECT_LINE_SAMPLE_LIMIT: # Avoids turning a very long route into hundreds of synchronous slope queries.
        return false # Sends long routes to the bounded AStar path instead.
    if steps <= 0: # Handles a degenerate line defensively.
        return true # Treats an identical-cell request as clear.
    for step: int in range(steps + 1): # Samples the complete line including both endpoints.
        var t: float = float(step) / float(steps) # Converts this raster step into normalized line progress.
        var sample_x: int = roundi(lerpf(float(from_cell.x), float(to_cell.x), t)) # Finds the nearest logical X cell along the line.
        var sample_y: int = roundi(lerpf(float(from_cell.y), float(to_cell.y), t)) # Finds the nearest logical Z cell along the line.
        if not world_builder.is_cell_walkable(Vector2i(sample_x, sample_y)): # Detects terrain that the character should not cross directly.
            return false # Requires local pathfinding as soon as one blocked sample is found.
    return true # Confirms the straight line remains practical across every sampled cell.

static func _build_local_astar_path(world_builder: HgssWorldBuilder, from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector3]: # Allocates one temporary AStarGrid2D tightly around the current route request.
    var minimum_x: int = mini(from_cell.x, to_cell.x) - PATH_MARGIN_CELLS # Expands the local search rectangle beyond the leftmost endpoint.
    var minimum_y: int = mini(from_cell.y, to_cell.y) - PATH_MARGIN_CELLS # Expands the local search rectangle beyond the nearest Z endpoint.
    var maximum_x: int = maxi(from_cell.x, to_cell.x) + PATH_MARGIN_CELLS # Expands the local search rectangle beyond the rightmost endpoint.
    var maximum_y: int = maxi(from_cell.y, to_cell.y) + PATH_MARGIN_CELLS # Expands the local search rectangle beyond the farthest Z endpoint.
    var region: Rect2i = Rect2i(minimum_x, minimum_y, maximum_x - minimum_x + 1, maximum_y - minimum_y + 1) # Creates a signed-coordinate region with no finite-world assumptions.
    var navigation_grid: AStarGrid2D = AStarGrid2D.new() # Creates a temporary path grid for only this route request.
    navigation_grid.region = region # Restricts memory and point setup to the local search rectangle.
    navigation_grid.cell_size = Vector2.ONE # Keeps AStar costs measured in logical terrain cells.
    navigation_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER # Prevents corner-cutting across steep generated terrain.
    navigation_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN # Uses the appropriate heuristic for four-way movement.
    navigation_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN # Keeps estimate behavior consistent with actual movement rules.
    navigation_grid.update() # Allocates the bounded point set before solid flags are assigned.
    for cell_y: int in range(region.position.y, region.end.y): # Traverses each local signed grid row once.
        for cell_x: int in range(region.position.x, region.end.x): # Traverses every local signed grid cell in the current row.
            var cell: Vector2i = Vector2i(cell_x, cell_y) # Builds the logical terrain identifier for slope testing.
            if not world_builder.is_cell_walkable(cell): # Detects locally impractical generated terrain.
                navigation_grid.set_point_solid(cell, true) # Removes the cell from this temporary route search.
    if navigation_grid.is_point_solid(from_cell) or navigation_grid.is_point_solid(to_cell): # Rejects endpoints that somehow remained blocked after nearest-cell recovery.
        return [] # Lets the roaming controller use its direct movement fallback.
    var cell_path: Array[Vector2i] = navigation_grid.get_id_path(from_cell, to_cell, false) # Finds the shortest four-way route through local practical terrain.
    if cell_path.is_empty(): # Detects a locally disconnected generated area.
        return [] # Reports failure without keeping a stale navigation cache.
    return _compress_cell_path(world_builder, cell_path) # Converts the cell route into a compact set of grounded turning points.

static func _compress_cell_path(world_builder: HgssWorldBuilder, cell_path: Array[Vector2i]) -> Array[Vector3]: # Reduces cell-by-cell AStar output to only direction changes and the destination.
    var world_path: Array[Vector3] = [] # Stores compact grounded waypoints for direct CharacterBody3D steering.
    if cell_path.size() <= 1: # Handles a one-cell route defensively.
        if not cell_path.is_empty(): # Confirms a valid endpoint exists before indexing.
            world_path.append(world_builder.cell_to_world(cell_path[0])) # Returns the grounded endpoint as the only waypoint.
        return world_path # Skips direction-compression logic when no interior route exists.
    var previous_direction: Vector2i = cell_path[1] - cell_path[0] # Starts direction tracking from the first path segment.
    for index: int in range(1, cell_path.size() - 1): # Examines each interior cell for a turn.
        var next_direction: Vector2i = cell_path[index + 1] - cell_path[index] # Measures the direction leaving the current interior cell.
        if next_direction != previous_direction: # Detects a path corner requiring an explicit steering waypoint.
            world_path.append(world_builder.cell_to_world(cell_path[index])) # Preserves the grounded turning point.
            previous_direction = next_direction # Starts tracking the new straight path segment.
    world_path.append(world_builder.cell_to_world(cell_path[cell_path.size() - 1])) # Always preserves the final grounded destination.
    return world_path # Returns the compact local route without retaining a finite world-sized cache.
