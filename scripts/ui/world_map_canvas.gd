class_name WorldMapCanvas # Draws the neutral hub, infinite radial type sectors, destinations, selection, and player position.
extends Control # Keeps the map lightweight and fully procedural without texture assets.

var destinations: Array[Dictionary] = [] # Stores landmark metadata supplied by the active WorldLandmarkSystem.
var connections: Array[Vector2i] = [] # Retains the existing API parameter even though radial topology no longer uses a finite graph.
var selected_index: int = 0 # Stores the currently highlighted fast-travel destination.
var player_map_position: Vector2 = Vector2.ZERO # Stores the player's unbounded logical X/Z position for map display.

func set_map_data(new_destinations: Array[Dictionary], new_connections: Array[Vector2i], new_selected_index: int, new_player_map_position: Vector2) -> void: # Replaces all map state and redraws once.
    destinations = new_destinations # Copies the current radial destination metadata.
    connections = new_connections # Preserves compatibility with the existing overlay call signature.
    selected_index = new_selected_index # Stores the requested active destination marker.
    player_map_position = new_player_map_position # Stores the player's current unbounded logical position.
    queue_redraw() # Requests one redraw with the replacement map state.

func set_selection(new_selected_index: int) -> void: # Updates only the selected landmark during map navigation.
    selected_index = new_selected_index # Stores the new selected destination index.
    queue_redraw() # Redraws the selection highlight without rebuilding map data.

func set_player_map_position(new_player_map_position: Vector2) -> void: # Moves the player marker when the map opens after exploration.
    player_map_position = new_player_map_position # Stores the latest unbounded logical player position.
    queue_redraw() # Redraws the player marker at the new map location.

func _draw() -> void: # Renders the radial pizza-like topology with a neutral centre and outward type sectors.
    var full_rect: Rect2 = Rect2(Vector2.ZERO, size) # Covers the complete custom map control.
    draw_rect(full_rect, Color(0.055, 0.070, 0.085, 1.0), true) # Draws the outer dark UI background.
    var map_rect: Rect2 = Rect2(Vector2(28.0, 24.0), Vector2(maxf(size.x - 56.0, 1.0), maxf(size.y - 48.0, 1.0))) # Leaves a consistent inset border around the actual map field.
    draw_rect(map_rect, Color(0.10, 0.13, 0.14, 1.0), true) # Draws the map field background beneath the radial sectors.
    if destinations.is_empty(): # Handles opening the overlay before landmark initialization finishes.
        draw_rect(map_rect, Color(0.46, 0.50, 0.48, 1.0), false, 2.0) # Keeps the map frame visible while destination data is unavailable.
        return # Stops before indexing destination metadata.
    var map_extent: float = _get_map_extent() # Chooses a symmetric logical radius large enough to include landmarks and the current player.
    var center_canvas: Vector2 = map_rect.position + map_rect.size * 0.5 # Resolves the visual world origin at the centre of the map field.
    var scale: float = minf(map_rect.size.x, map_rect.size.y) * 0.5 / map_extent # Converts logical cell distance into map pixels uniformly on both axes.
    var neutral_radius_pixels: float = RadialWorldFieldSampler.CENTER_RADIUS_CELLS * scale # Converts the authoritative neutral-hub radius into the current map scale.
    var outer_radius_pixels: float = maxf(map_rect.size.x, map_rect.size.y) * 0.78 # Extends type wedges beyond the visible frame so they read as continuing indefinitely.
    _draw_outer_sectors(center_canvas, neutral_radius_pixels, outer_radius_pixels) # Draws sixteen equal non-Normal type regions around the central hole.
    var neutral_color: Color = destinations[0].get("color", Color(0.79, 0.70, 0.50, 1.0)) # Uses the existing Normal destination palette for the neutral hub marker family.
    draw_circle(center_canvas, neutral_radius_pixels, neutral_color.darkened(0.58)) # Fills the large shared neutral central area distinctly from every type world.
    draw_circle(center_canvas, neutral_radius_pixels, neutral_color.darkened(0.18), false, 3.0, true) # Outlines the organic concept schematically as one clear hub boundary.
    _draw_radial_routes(center_canvas, neutral_radius_pixels, outer_radius_pixels) # Draws the ring route and one outward route through each type sector.
    for index: int in range(destinations.size()): # Draws every named fast-travel destination after the region fills.
        var destination: Dictionary = destinations[index] # Reads one destination's radial metadata.
        var position: Vector2 = _map_to_canvas(destination.get("map_position", Vector2.ZERO), map_rect, map_extent) # Converts its unbounded logical coordinate into the current dynamic map scale.
        var color: Color = destination.get("color", Color.WHITE) # Reads the established type-related marker colour.
        draw_circle(position, 9.0, color) # Draws the outer destination marker body.
        draw_circle(position, 4.0, color.lightened(0.32)) # Adds a small bright centre for readability over dark sector fills.
        if index == selected_index: # Detects the currently selected fast-travel destination.
            var selection_rect: Rect2 = Rect2(position - Vector2(15.0, 15.0), Vector2(30.0, 30.0)) # Builds a compact selection outline around the marker.
            draw_rect(selection_rect, Color(1.0, 0.96, 0.72, 1.0), false, 3.0) # Draws the active selection highlight above the marker.
    var player_position: Vector2 = _map_to_canvas(player_map_position, map_rect, map_extent) # Converts the player's potentially very distant infinite-world position into view.
    draw_circle(player_position, 7.0, Color.WHITE) # Draws the high-contrast player marker.
    draw_circle(player_position, 3.5, Color(0.12, 0.17, 0.20, 1.0)) # Adds a dark centre so the player marker remains readable over pale biomes.
    draw_rect(map_rect, Color(0.46, 0.50, 0.48, 1.0), false, 2.0) # Draws the map frame last so outward sectors appear clipped by the UI boundary.

func _draw_outer_sectors(center_canvas: Vector2, inner_radius: float, outer_radius: float) -> void: # Draws sixteen equal annular wedges that visually continue off the map edge.
    for biome_kind: int in range(1, destinations.size()): # Uses one wedge for every non-Normal Generation IV type destination.
        var map_position: Vector2 = destinations[biome_kind].get("map_position", Vector2.RIGHT) # Reads the landmark axis that defines this type sector.
        var axis_angle: float = atan2(map_position.y, map_position.x) # Resolves the sector centre angle from the same radial placement used in-world.
        var half_angle: float = RadialWorldFieldSampler.SECTOR_ANGLE * 0.5 # Gives every outer type the same mean angular width.
        var start_direction: Vector2 = Vector2(cos(axis_angle - half_angle), sin(axis_angle - half_angle)) # Builds the first radial sector boundary direction.
        var end_direction: Vector2 = Vector2(cos(axis_angle + half_angle), sin(axis_angle + half_angle)) # Builds the second radial sector boundary direction.
        var polygon: PackedVector2Array = PackedVector2Array([center_canvas + start_direction * inner_radius, center_canvas + start_direction * outer_radius, center_canvas + end_direction * outer_radius, center_canvas + end_direction * inner_radius]) # Creates one quadrilateral annular wedge between the hub and map edge.
        var sector_color: Color = destinations[biome_kind].get("color", Color.WHITE).darkened(0.62) # Uses a subdued version of each type's established destination colour.
        draw_colored_polygon(polygon, sector_color) # Fills the complete visible portion of this infinite outward type sector.
        draw_line(center_canvas + start_direction * inner_radius, center_canvas + start_direction * outer_radius, sector_color.lightened(0.20), 1.0, true) # Gives neighboring type worlds a restrained readable boundary.

func _draw_radial_routes(center_canvas: Vector2, neutral_radius: float, outer_radius: float) -> void: # Draws the schematic ring route and infinite outward route centre lines.
    var route_color: Color = Color(0.61, 0.55, 0.39, 0.80) # Uses the established warm route colour from the previous map.
    draw_arc(center_canvas, neutral_radius * 0.84, 0.0, TAU, 96, route_color, 3.0, true) # Draws the circular route around the inside of the neutral hub boundary.
    for biome_kind: int in range(1, destinations.size()): # Draws one outward route through the centre of each type world.
        var map_position: Vector2 = destinations[biome_kind].get("map_position", Vector2.RIGHT) # Reads the radial axis from landmark placement.
        var direction: Vector2 = map_position.normalized() # Converts the landmark coordinate into an outward unit direction.
        var start: Vector2 = center_canvas + direction * neutral_radius * 0.82 # Starts the radial route where it joins the hub ring.
        var finish: Vector2 = center_canvas + direction * outer_radius # Extends the route beyond the visible map field to imply continuation.
        draw_line(start, finish, route_color, 3.0, true) # Draws the schematic infinite route centre line.

func _get_map_extent() -> float: # Chooses a dynamic logical radius so infinite exploration remains visible instead of clamping to old world bounds.
    var landmark_extent: float = RadialWorldFieldSampler.CENTER_RADIUS_CELLS + 42.0 # Keeps the complete landmark ring comfortably inside the map by default.
    for destination: Dictionary in destinations: # Expands the base extent if future radial landmark placement moves farther outward.
        landmark_extent = maxf(landmark_extent, Vector2(destination.get("map_position", Vector2.ZERO)).length() + 18.0) # Preserves margin around every named destination.
    var player_extent: float = player_map_position.length() * 1.16 # Expands the map when the player travels far into an infinite type sector.
    return maxf(landmark_extent, player_extent, 1.0) # Returns a nonzero symmetric logical radius for map scaling.

func _map_to_canvas(map_position: Vector2, map_rect: Rect2, map_extent: float) -> Vector2: # Converts unbounded logical coordinates into a dynamically scaled square map centred on the origin.
    var center_canvas: Vector2 = map_rect.position + map_rect.size * 0.5 # Resolves the central neutral hub position in UI space.
    var scale: float = minf(map_rect.size.x, map_rect.size.y) * 0.5 / maxf(map_extent, 1.0) # Preserves aspect ratio while fitting the chosen radial extent.
    return center_canvas + map_position * scale # Maps signed infinite-world coordinates directly without rectangular clamping.
