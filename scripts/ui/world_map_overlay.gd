class_name WorldMapOverlay # Owns the openable schematic world map, spatial landmark selection, and fast travel.
extends CanvasLayer # Renders the map above the 3D world without coupling it to camera transforms.

var map_root: Control # Full-screen map container toggled by Button_Start.
var map_canvas: WorldMapCanvas # Custom renderer for routes, landmarks, selection, and player position.
var destination_label: Label # Shows the selected region and landmark name.
var counter_label: Label # Shows the selected landmark index out of the seventeen destinations.
var landmark_system: WorldLandmarkSystem # Provides named destinations and verified safe arrival points.
var player: CharacterBody3D # Player body teleported by fast travel and frozen while the map is open.
var destinations: Array[Dictionary] = [] # Local snapshot of landmark metadata while the map is open.
var selected_index: int = 0 # Selected destination controlled by the four directional actions.
var map_open: bool = false # Prevents gameplay movement while the overlay is active.

func _ready() -> void: # Builds the UI once and resolves world dependencies after scene startup.
    layer = 20
    _build_ui()
    call_deferred("_resolve_dependencies")

func _process(_delta: float) -> void: # Handles map controls through the project's existing named input actions.
    if Input.is_action_just_pressed(&"Button_Start"):
        if map_open:
            _close_map()
        else:
            _open_map()
        return
    if not map_open:
        return
    if Input.is_action_just_pressed(&"StickLeft_North"):
        _move_selection(Vector2(0.0, -1.0))
    elif Input.is_action_just_pressed(&"StickLeft_South"):
        _move_selection(Vector2(0.0, 1.0))
    elif Input.is_action_just_pressed(&"StickLeft_West"):
        _move_selection(Vector2(-1.0, 0.0))
    elif Input.is_action_just_pressed(&"StickLeft_East"):
        _move_selection(Vector2(1.0, 0.0))
    elif Input.is_action_just_pressed(&"Button_A"):
        _fast_travel_to_selected()

func _build_ui() -> void: # Creates a centered map panel entirely from built-in controls and procedural drawing.
    map_root = Control.new()
    map_root.name = "map_root"
    map_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    map_root.mouse_filter = Control.MOUSE_FILTER_STOP
    map_root.visible = false
    add_child(map_root)

    var dimmer: ColorRect = ColorRect.new()
    dimmer.color = Color(0.015, 0.020, 0.025, 0.84)
    dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    map_root.add_child(dimmer)

    var center: CenterContainer = CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    map_root.add_child(center)

    var panel: PanelContainer = PanelContainer.new()
    panel.custom_minimum_size = Vector2(820.0, 650.0)
    var panel_style: StyleBoxFlat = StyleBoxFlat.new()
    panel_style.bg_color = Color(0.035, 0.045, 0.055, 0.98)
    panel_style.border_color = Color(0.38, 0.42, 0.42, 1.0)
    panel_style.set_border_width_all(2)
    panel_style.corner_radius_top_left = 12
    panel_style.corner_radius_top_right = 12
    panel_style.corner_radius_bottom_left = 12
    panel_style.corner_radius_bottom_right = 12
    panel.add_theme_stylebox_override(&"panel", panel_style)
    center.add_child(panel)

    var margin: MarginContainer = MarginContainer.new()
    margin.add_theme_constant_override(&"margin_left", 22)
    margin.add_theme_constant_override(&"margin_top", 18)
    margin.add_theme_constant_override(&"margin_right", 22)
    margin.add_theme_constant_override(&"margin_bottom", 18)
    panel.add_child(margin)

    var column: VBoxContainer = VBoxContainer.new()
    column.add_theme_constant_override(&"separation", 10)
    margin.add_child(column)

    var title: Label = Label.new()
    title.text = "Poképal Region Map"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override(&"font_size", 24)
    column.add_child(title)

    var subtitle: Label = Label.new()
    subtitle.text = "Select a biome landmark to fast travel"
    subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    subtitle.modulate = Color(0.78, 0.82, 0.84, 1.0)
    column.add_child(subtitle)

    map_canvas = WorldMapCanvas.new()
    map_canvas.custom_minimum_size = Vector2(760.0, 465.0)
    map_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    map_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(map_canvas)

    destination_label = Label.new()
    destination_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    destination_label.add_theme_font_size_override(&"font_size", 19)
    column.add_child(destination_label)

    counter_label = Label.new()
    counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    counter_label.modulate = Color(0.76, 0.80, 0.82, 1.0)
    column.add_child(counter_label)

    var controls: Label = Label.new()
    controls.text = "Directions / left stick: select    •    Button A / Space: fast travel    •    Start / Esc: close"
    controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    controls.modulate = Color(0.72, 0.76, 0.78, 1.0)
    column.add_child(controls)

func _resolve_dependencies() -> void: # Resolves semantic scene groups instead of hard-coded node paths.
    landmark_system = get_tree().get_first_node_in_group(&"world_landmarks") as WorldLandmarkSystem
    player = get_tree().get_first_node_in_group(&"player") as CharacterBody3D

func _open_map() -> void: # Freezes the player, selects the nearest destination, and shows the current world position.
    _resolve_dependencies()
    if landmark_system == null:
        push_error("WorldMapOverlay could not find WorldLandmarkSystem.")
        return
    destinations = landmark_system.get_destinations()
    if destinations.is_empty():
        push_warning("WorldMapOverlay opened before landmark destinations were ready.")
        return
    if player == null:
        push_error("WorldMapOverlay could not find the player CharacterBody3D.")
        return
    player.velocity = Vector3.ZERO
    player.set_physics_process(false)
    selected_index = _nearest_destination_index_to_player()
    map_open = true
    map_root.visible = true
    var player_map_position: Vector2 = _player_map_position()
    map_canvas.set_map_data(destinations, HgssWorldBuilder.PATH_EDGES, selected_index, player_map_position)
    _refresh_selection_text()

func _close_map() -> void: # Restores player physics and hides the overlay without changing world state.
    map_open = false
    map_root.visible = false
    if player != null:
        player.velocity = Vector3.ZERO
        player.set_physics_process(true)

func _move_selection(direction: Vector2) -> void: # Picks the closest landmark lying substantially in the requested screen-map direction.
    if destinations.is_empty() or selected_index < 0 or selected_index >= destinations.size():
        return
    var current_position: Vector2 = destinations[selected_index].get("map_position", Vector2.ZERO)
    var normalized_direction: Vector2 = direction.normalized()
    var best_index: int = -1
    var best_score: float = INF
    for index: int in range(destinations.size()):
        if index == selected_index:
            continue
        var candidate_position: Vector2 = destinations[index].get("map_position", Vector2.ZERO)
        var delta: Vector2 = candidate_position - current_position
        var distance: float = delta.length()
        if distance <= 0.0001:
            continue
        var alignment: float = delta.normalized().dot(normalized_direction)
        if alignment <= 0.25:
            continue
        var score: float = distance / (alignment * alignment)
        if score < best_score:
            best_score = score
            best_index = index
    if best_index < 0:
        return
    selected_index = best_index
    map_canvas.set_selection(selected_index)
    _refresh_selection_text()

func _fast_travel_to_selected() -> void: # Teleports to the landmark's precomputed walkable arrival marker and closes the map.
    if player == null or selected_index < 0 or selected_index >= destinations.size():
        return
    var destination: Dictionary = destinations[selected_index]
    var arrival_position: Vector3 = destination.get("position", player.global_position)
    player.global_position = arrival_position
    player.velocity = Vector3.ZERO
    _close_map()

func _nearest_destination_index_to_player() -> int: # Opens the map focused on the region nearest the player's current position.
    var player_position: Vector2 = _player_map_position()
    var best_index: int = 0
    var best_distance_squared: float = INF
    for index: int in range(destinations.size()):
        var map_position: Vector2 = destinations[index].get("map_position", Vector2.ZERO)
        var distance_squared: float = player_position.distance_squared_to(map_position)
        if distance_squared < best_distance_squared:
            best_distance_squared = distance_squared
            best_index = index
    return best_index

func _player_map_position() -> Vector2: # Converts the 3D player's X/Z position into the world builder's centered map coordinate system.
    if player == null:
        return Vector2.ZERO
    return Vector2(player.global_position.x / HgssWorldBuilder.TILE_SIZE, player.global_position.z / HgssWorldBuilder.TILE_SIZE)

func _refresh_selection_text() -> void: # Shows both the biome region and its signature landmark under the map.
    if selected_index < 0 or selected_index >= destinations.size():
        destination_label.text = ""
        counter_label.text = ""
        return
    var destination: Dictionary = destinations[selected_index]
    var region_name: String = destination.get("region_name", "Unknown Region")
    var landmark_name: String = destination.get("landmark_name", "Unknown Landmark")
    destination_label.text = "%s — %s" % [region_name, landmark_name]
    counter_label.text = "%d / %d destinations" % [selected_index + 1, destinations.size()]
