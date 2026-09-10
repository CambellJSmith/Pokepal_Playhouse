class_name RadialWorldLandmarkSystem # Places the existing named landmarks on the neutral hub and evenly spaced outer type ring.
extends WorldLandmarkSystem # Reuses the established landmark geometry and destination metadata contract.

func _initialize_landmarks() -> void: # Creates the central landmark plus one landmark near the inner edge of every infinite outer type world.
    if not destinations.is_empty(): # Prevents duplicate landmark construction after deferred initialization.
        return # Keeps one stable destination entry per supported biome.
    world_builder = get_tree().get_first_node_in_group(&"world_builder") as HgssWorldBuilder # Resolves the streamed world through the established semantic group.
    var radial_world: RadialWorldBuilder = world_builder as RadialWorldBuilder # Narrows the dependency to the radial topology service used by this placement policy.
    if radial_world == null: # Detects an incompatible world scene instead of placing landmarks with obsolete finite coordinates.
        push_error("RadialWorldLandmarkSystem requires RadialWorldBuilder.") # Reports the scene-composition error directly.
        return # Stops before generating mismatched destinations.
    for biome_kind: int in range(HgssWorldBuilder.BiomeKind.size()): # Creates one destination for the neutral hub and every non-Normal type world.
        var landmark_cell: Vector2 = radial_world.get_biome_landmark_cell(biome_kind) # Reads the authoritative radial landmark coordinate from world topology.
        var landmark_hint: Vector3 = _cell_to_world_hint(landmark_cell) # Converts the logical radial coordinate into world-space X/Z.
        var landmark_position: Vector3 = radial_world.get_nearest_walkable_world_position(landmark_hint) # Grounds the landmark on practical streamed terrain.
        var arrival_cell: Vector2 = _get_arrival_cell(landmark_cell, biome_kind) # Places fast travel separately from the visible landmark geometry.
        var arrival_position: Vector3 = radial_world.get_nearest_walkable_world_position(_cell_to_world_hint(arrival_cell)) # Grounds the arrival marker on nearby traversable terrain.
        var landmark_root: Node3D = Node3D.new() # Creates one transform root for the inherited landmark composition.
        landmark_root.name = LANDMARK_NAMES[biome_kind].to_snake_case() # Uses the established readable landmark scene name.
        landmark_root.position = landmark_position # Places the landmark at its radial inner-world destination.
        add_child(landmark_root) # Adds the landmark before composing its child geometry.
        _build_landmark(landmark_root, biome_kind) # Reuses the existing unique landmark art for this type.
        _build_arrival_marker(arrival_position, biome_kind) # Reuses the existing visible fast-travel marker policy.
        destinations.append({ # Stores the same dictionary contract consumed by WorldMapOverlay.
            "biome": biome_kind, # Records the Generation IV biome index.
            "region_name": REGION_NAMES[biome_kind], # Preserves the established human-readable region name.
            "landmark_name": LANDMARK_NAMES[biome_kind], # Preserves the established destination name.
            "position": arrival_position, # Supplies the grounded fast-travel world position.
            "map_position": landmark_cell, # Supplies radial logical coordinates for the schematic map.
            "color": LANDMARK_COLORS[biome_kind], # Preserves the established type-related map marker colour.
        }) # Completes one destination entry.

func _get_arrival_cell(landmark_cell: Vector2, biome_kind: int) -> Vector2: # Places arrivals toward the neutral hub while keeping them outside landmark geometry.
    if biome_kind == HgssWorldBuilder.BiomeKind.NORMAL: # Handles the central neutral destination independently from radial sectors.
        return Vector2(0.0, 7.0) # Places the central arrival a short walk from Heartstone Plaza.
    var direction_to_center: Vector2 = -landmark_cell.normalized() # Points from the outer landmark back toward the neutral hub.
    return landmark_cell + direction_to_center * 7.0 # Keeps the player in the same sector but clear of the landmark footprint.

func _cell_to_world_hint(cell_position: Vector2) -> Vector3: # Converts radial logical-cell coordinates into world-space X/Z without finite-map offsets.
    return Vector3(cell_position.x * HgssWorldBuilder.TILE_SIZE, 0.0, cell_position.y * HgssWorldBuilder.TILE_SIZE) # Leaves Y for the world builder's deterministic terrain grounding step.
