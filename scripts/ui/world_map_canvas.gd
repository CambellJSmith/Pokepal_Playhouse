class_name WorldMapCanvas # Draws the procedural region network, biome destinations, selection, and player position.
extends Control # Keeps the map lightweight and fully generated without texture assets.

var destinations: Array[Dictionary] = [] # Landmark metadata supplied by WorldLandmarkSystem.
var connections: Array[Vector2i] = [] # Biome graph edges copied from the procedural world route network.
var selected_index: int = 0 # Currently highlighted fast-travel destination.
var player_map_position: Vector2 = Vector2.ZERO # Player position expressed in the world builder's local cell coordinate space.

func set_map_data(new_destinations: Array[Dictionary], new_connections: Array[Vector2i], new_selected_index: int, new_player_map_position: Vector2) -> void: # Replaces all map state and redraws once.
    destinations = new_destinations
    connections = new_connections
    selected_index = new_selected_index
    player_map_position = new_player_map_position
    queue_redraw()

func set_selection(new_selected_index: int) -> void: # Updates only the selected landmark during map navigation.
    selected_index = new_selected_index
    queue_redraw()

func set_player_map_position(new_player_map_position: Vector2) -> void: # Moves the player marker when the map opens after world movement.
    player_map_position = new_player_map_position
    queue_redraw()

func _draw() -> void: # Renders a schematic world map directly from the same region coordinates that generate the 3D world.
    var full_rect: Rect2 = Rect2(Vector2.ZERO, size)
    draw_rect(full_rect, Color(0.055, 0.070, 0.085, 1.0), true)
    var map_rect: Rect2 = Rect2(Vector2(28.0, 24.0), Vector2(maxf(size.x - 56.0, 1.0), maxf(size.y - 48.0, 1.0)))
    draw_rect(map_rect, Color(0.10, 0.13, 0.14, 1.0), true)
    draw_rect(map_rect, Color(0.46, 0.50, 0.48, 1.0), false, 2.0)
    if destinations.is_empty():
        return
    for edge: Vector2i in connections:
        if edge.x < 0 or edge.x >= destinations.size() or edge.y < 0 or edge.y >= destinations.size():
            continue
        var start_position: Vector2 = _destination_canvas_position(destinations[edge.x], map_rect)
        var end_position: Vector2 = _destination_canvas_position(destinations[edge.y], map_rect)
        draw_line(start_position, end_position, Color(0.61, 0.55, 0.39, 0.78), 4.0, true)
    for index: int in range(destinations.size()):
        var destination: Dictionary = destinations[index]
        var position: Vector2 = _destination_canvas_position(destination, map_rect)
        var color: Color = destination.get("color", Color.WHITE)
        draw_circle(position, 9.0, color)
        draw_circle(position, 4.0, color.lightened(0.32))
        if index == selected_index:
            var selection_rect: Rect2 = Rect2(position - Vector2(15.0, 15.0), Vector2(30.0, 30.0))
            draw_rect(selection_rect, Color(1.0, 0.96, 0.72, 1.0), false, 3.0)
    var player_position: Vector2 = _map_to_canvas(player_map_position, map_rect)
    draw_circle(player_position, 7.0, Color.WHITE)
    draw_circle(player_position, 3.5, Color(0.12, 0.17, 0.20, 1.0))

func _destination_canvas_position(destination: Dictionary, map_rect: Rect2) -> Vector2: # Converts a destination's biome-layout coordinate into the visible map rectangle.
    var map_position: Vector2 = destination.get("map_position", Vector2.ZERO)
    return _map_to_canvas(map_position, map_rect)

func _map_to_canvas(map_position: Vector2, map_rect: Rect2) -> Vector2: # Scales the world builder's centered local cell coordinates into UI coordinates.
    var world_min: Vector2 = Vector2(-float(HgssWorldBuilder.WORLD_WIDTH) * 0.5, -float(HgssWorldBuilder.WORLD_DEPTH) * 0.5)
    var world_size: Vector2 = Vector2(float(HgssWorldBuilder.WORLD_WIDTH), float(HgssWorldBuilder.WORLD_DEPTH))
    var normalized: Vector2 = (map_position - world_min) / world_size
    normalized.x = clampf(normalized.x, 0.0, 1.0)
    normalized.y = clampf(normalized.y, 0.0, 1.0)
    return map_rect.position + normalized * map_rect.size
