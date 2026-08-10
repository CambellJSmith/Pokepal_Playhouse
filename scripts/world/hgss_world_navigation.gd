class_name HgssWorldNavigation # Provides shared grid pathfinding over the procedural HGSS world.
extends RefCounted # Keeps navigation data outside the scene tree because it has no transform or frame processing.

static var navigation_grid: AStarGrid2D # Stores one reusable A* grid for every roaming Pokémon in the active world.
static var world_instance_id: int = 0 # Tracks which generated world the cached pathfinding grid represents.

static func get_world_path(world_builder: HgssWorldBuilder, from_world: Vector3, to_world: Vector3) -> Array[Vector3]: # Converts two 3D positions into a shared walkable-cell path.
    _ensure_grid(world_builder) # Lazily builds or refreshes the pathfinding grid for the active generated world.
    if navigation_grid == null: # Guards an invalid world reference without allowing callers to crash.
        return [] # Reports that no safe path can be produced.
    var from_cell: Vector2i = world_builder.world_to_cell(from_world) # Converts the moving character's position into a grid identifier.
    var to_cell: Vector2i = world_builder.world_to_cell(to_world) # Converts the requested destination into a grid identifier.
    if not world_builder.is_cell_walkable(from_cell): # Recovers if physics left the character slightly outside a valid cell.
        from_cell = world_builder.world_to_cell(world_builder.get_nearest_walkable_world_position(from_world)) # Snaps pathfinding intent to the nearest usable generated cell.
    if not world_builder.is_cell_walkable(to_cell): # Recovers if a requested destination lies just beyond a valid route edge.
        to_cell = world_builder.world_to_cell(world_builder.get_nearest_walkable_world_position(to_world)) # Converts the target to the nearest usable generated cell.
    if navigation_grid.is_point_solid(from_cell) or navigation_grid.is_point_solid(to_cell): # Rejects endpoints that remain blocked after nearest-cell recovery.
        return [] # Prevents A* from spending time on an impossible request.
    var cell_path: Array[Vector2i] = navigation_grid.get_id_path(from_cell, to_cell, false) # Finds the shortest orthogonal path through water-free, tree-free cells.
    if cell_path.is_empty(): # Detects disconnected terrain regions or an unexpectedly blocked route.
        return [] # Lets the roaming controller keep a direct fallback rather than freezing.
    return _compress_cell_path(world_builder, cell_path) # Converts the full cell route into a much smaller list of 3D turning-point waypoints.

static func _ensure_grid(world_builder: HgssWorldBuilder) -> void: # Builds one AStarGrid2D and reuses it until a different world instance is supplied.
    if world_builder == null: # Guards callers during scene teardown or malformed setup.
        navigation_grid = null # Clears the cached grid because it no longer has a valid geometry source.
        world_instance_id = 0 # Clears the owner identifier together with the grid.
        return # Stops before dereferencing an invalid node.
    var current_instance_id: int = int(world_builder.get_instance_id()) # Reads the stable runtime identity of the active generated-world node.
    if navigation_grid != null and world_instance_id == current_instance_id: # Detects a cache that already represents this exact world instance.
        return # Reuses the existing grid without rebuilding thousands of point flags.
    navigation_grid = AStarGrid2D.new() # Creates the shared partial-grid A* resource.
    navigation_grid.region = Rect2i(0, 0, HgssWorldBuilder.WORLD_WIDTH, HgssWorldBuilder.WORLD_DEPTH) # Matches the generated terrain's integer cell bounds exactly.
    navigation_grid.cell_size = Vector2.ONE # Keeps path costs measured in cells because conversion back to 3D is handled by the world builder.
    navigation_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER # Uses four-way paths so Pokémon cannot cut diagonally through tree or water corners.
    navigation_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN # Uses the heuristic intended for orthogonal grid movement.
    navigation_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN # Keeps route estimates consistent with four-way movement costs.
    navigation_grid.update() # Allocates every grid point before individual solid flags are assigned.
    for cell_z: int in range(HgssWorldBuilder.WORLD_DEPTH): # Traverses every generated map row once during cache construction.
        for cell_x: int in range(HgssWorldBuilder.WORLD_WIDTH): # Traverses every generated map column once during cache construction.
            var cell: Vector2i = Vector2i(cell_x, cell_z) # Creates the stable grid identifier for this map cell.
            if not world_builder.is_cell_walkable(cell): # Detects water and cells occupied by hard forest blockers.
                navigation_grid.set_point_solid(cell, true) # Removes the blocked cell from all future path searches.
    world_instance_id = current_instance_id # Marks the completed grid as belonging to the active generated world.

static func _compress_cell_path(world_builder: HgssWorldBuilder, cell_path: Array[Vector2i]) -> Array[Vector3]: # Reduces cell-by-cell A* output to route corners so movement remains smooth and inexpensive.
    var world_path: Array[Vector3] = [] # Stores only 3D waypoints where route direction changes or the path ends.
    if cell_path.size() <= 1: # Handles a destination in the same grid cell as the moving character.
        if not cell_path.is_empty(): # Confirms there is at least one valid endpoint to return.
            world_path.append(world_builder.cell_to_world(cell_path[0])) # Returns the current cell centre as the sole waypoint.
        return world_path # Avoids direction-compression logic for a one-point route.
    var previous_direction: Vector2i = cell_path[1] - cell_path[0] # Initializes direction tracking from the first A* segment.
    for index: int in range(1, cell_path.size() - 1): # Examines each interior cell for a change in travel direction.
        var next_direction: Vector2i = cell_path[index + 1] - cell_path[index] # Measures the direction leaving this interior cell.
        if next_direction != previous_direction: # Detects a route corner that the CharacterBody3D must explicitly turn through.
            world_path.append(world_builder.cell_to_world(cell_path[index])) # Preserves this cell as a 3D waypoint at generated terrain height.
            previous_direction = next_direction # Starts tracking the new straight route segment.
    world_path.append(world_builder.cell_to_world(cell_path[cell_path.size() - 1])) # Always preserves the final destination cell after compression.
    return world_path # Returns a compact 3D route suitable for direct CharacterBody3D steering.
