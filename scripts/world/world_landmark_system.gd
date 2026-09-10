class_name WorldLandmarkSystem # Builds one large signature destination for every Generation IV type biome and exposes safe fast-travel arrivals.
extends Node3D # Keeps landmark composition separate from the procedural terrain generator.

const REGION_NAMES: Array[String] = [
	"Central Meadow", "Volcanic Basin", "Lake District", "Electric Plains", "Deep Forest", "Snowfield", "Training Plateau", "Poison Marsh", "Badlands", "Wind Plateau", "Psychic Garden", "Bug Woods", "Mountain Range", "Ghost Hollow", "Dragon Peaks", "Dark Forest", "Steel District",
] # Matches HgssWorldBuilder.BiomeKind order.

const LANDMARK_NAMES: Array[String] = [
	"Heartstone Plaza", "Ember Crater", "Tide Shrine", "Volt Substation", "Ancient Grove", "Crystal Sanctum", "Red Belt Dojo", "Toxic Wells", "Dust Gate", "Skywatch Tower", "Mind Crystal Garden", "Grand Hive", "Summit Cairn", "Haunted Ruins", "Dragon Shrine", "Eclipse Obelisk", "Iron Forge",
] # Gives every biome a memorable named destination for navigation and fast travel.

const LANDMARK_COLORS: Array[Color] = [
	Color(0.79, 0.70, 0.50, 1.0), Color(0.93, 0.30, 0.08, 1.0), Color(0.22, 0.62, 0.84, 1.0), Color(0.96, 0.80, 0.12, 1.0), Color(0.23, 0.62, 0.25, 1.0), Color(0.74, 0.94, 0.98, 1.0), Color(0.68, 0.22, 0.16, 1.0), Color(0.64, 0.26, 0.70, 1.0), Color(0.72, 0.50, 0.22, 1.0), Color(0.80, 0.89, 0.91, 1.0), Color(0.87, 0.40, 0.73, 1.0), Color(0.64, 0.74, 0.18, 1.0), Color(0.46, 0.43, 0.35, 1.0), Color(0.43, 0.33, 0.57, 1.0), Color(0.49, 0.30, 0.68, 1.0), Color(0.18, 0.17, 0.23, 1.0), Color(0.70, 0.76, 0.80, 1.0),
] # Reuses the world type palette so map markers and physical landmarks correspond visually.

var world_builder: HgssWorldBuilder # Resolved generated-world dependency used to place landmarks on safe ground.
var destinations: Array[Dictionary] = [] # Stores biome metadata and verified walkable arrival positions for the map UI.

func _ready() -> void: # Defers until the procedural world has classified terrain and blockers.
	add_to_group(&"world_landmarks")
	call_deferred("_initialize_landmarks")

func get_destinations() -> Array[Dictionary]: # Returns travel metadata without exposing the mutable internal array.
	return destinations.duplicate(true)

func _initialize_landmarks() -> void: # Creates one landmark at each biome center and a separate safe arrival point facing it.
	if not destinations.is_empty():
		return
	world_builder = get_tree().get_first_node_in_group(&"world_builder") as HgssWorldBuilder
	if world_builder == null:
		push_error("WorldLandmarkSystem could not find HgssWorldBuilder.")
		return
	var normal_center: Vector2 = HgssWorldBuilder.BIOME_CENTERS[HgssWorldBuilder.BiomeKind.NORMAL]
	for biome_kind: int in range(HgssWorldBuilder.BiomeKind.size()):
		var center: Vector2 = HgssWorldBuilder.BIOME_CENTERS[biome_kind]
		var landmark_position: Vector3 = world_builder.get_nearest_walkable_world_position(_local_to_world_hint(center))
		var arrival_direction: Vector2 = normal_center - center
		if arrival_direction.length_squared() <= 0.0001:
			arrival_direction = Vector2(0.0, 1.0)
		else:
			arrival_direction = arrival_direction.normalized()
		var arrival_local: Vector2 = center + arrival_direction * 6.0
		var arrival_position: Vector3 = world_builder.get_nearest_walkable_world_position(_local_to_world_hint(arrival_local))
		var landmark_root: Node3D = Node3D.new()
		landmark_root.name = LANDMARK_NAMES[biome_kind].to_snake_case()
		landmark_root.position = landmark_position
		add_child(landmark_root)
		_build_landmark(landmark_root, biome_kind)
		_build_arrival_marker(arrival_position, biome_kind)
		destinations.append({
			"biome": biome_kind,
			"region_name": REGION_NAMES[biome_kind],
			"landmark_name": LANDMARK_NAMES[biome_kind],
			"position": arrival_position,
			"map_position": center,
			"color": LANDMARK_COLORS[biome_kind],
		})

func _build_landmark(root: Node3D, biome_kind: int) -> void: # Composes a unique large silhouette for each destination from built-in Godot primitives.
	match biome_kind:
		HgssWorldBuilder.BiomeKind.NORMAL:
			_build_heartstone_plaza(root)
		HgssWorldBuilder.BiomeKind.FIRE:
			_build_ember_crater(root)
		HgssWorldBuilder.BiomeKind.WATER:
			_build_tide_shrine(root)
		HgssWorldBuilder.BiomeKind.ELECTRIC:
			_build_volt_substation(root)
		HgssWorldBuilder.BiomeKind.GRASS:
			_build_ancient_grove(root)
		HgssWorldBuilder.BiomeKind.ICE:
			_build_crystal_sanctum(root)
		HgssWorldBuilder.BiomeKind.FIGHTING:
			_build_red_belt_dojo(root)
		HgssWorldBuilder.BiomeKind.POISON:
			_build_toxic_wells(root)
		HgssWorldBuilder.BiomeKind.GROUND:
			_build_dust_gate(root)
		HgssWorldBuilder.BiomeKind.FLYING:
			_build_skywatch_tower(root)
		HgssWorldBuilder.BiomeKind.PSYCHIC:
			_build_mind_crystal_garden(root)
		HgssWorldBuilder.BiomeKind.BUG:
			_build_grand_hive(root)
		HgssWorldBuilder.BiomeKind.ROCK:
			_build_summit_cairn(root)
		HgssWorldBuilder.BiomeKind.GHOST:
			_build_haunted_ruins(root)
		HgssWorldBuilder.BiomeKind.DRAGON:
			_build_dragon_shrine(root)
		HgssWorldBuilder.BiomeKind.DARK:
			_build_eclipse_obelisk(root)
		HgssWorldBuilder.BiomeKind.STEEL:
			_build_iron_forge(root)

func _build_heartstone_plaza(root: Node3D) -> void: # Creates a calm central stone monument surrounded by four marker stones.
	var color: Color = LANDMARK_COLORS[HgssWorldBuilder.BiomeKind.NORMAL]
	_add_cylinder(root, "plaza", 3.0, 3.0, 0.28, Vector3(0.0, 0.14, 0.0), Color(0.47, 0.45, 0.38, 1.0), 20)
	_add_cylinder(root, "heartstone", 0.65, 0.82, 3.3, Vector3(0.0, 1.8, 0.0), color, 8)
	for offset: Vector3 in [Vector3(2.0, 0.55, 0.0), Vector3(-2.0, 0.55, 0.0), Vector3(0.0, 0.55, 2.0), Vector3(0.0, 0.55, -2.0)]:
		_add_sphere(root, "marker", 0.48, 0.85, offset, color.darkened(0.18), 7, 3)

func _build_ember_crater(root: Node3D) -> void: # Creates a broad volcanic crater with a glowing inner vent.
	_add_cylinder(root, "crater_rim", 3.5, 3.5, 0.8, Vector3(0.0, 0.4, 0.0), Color(0.24, 0.16, 0.13, 1.0), 18)
	_add_cylinder(root, "magma", 2.35, 2.35, 0.22, Vector3(0.0, 0.82, 0.0), LANDMARK_COLORS[HgssWorldBuilder.BiomeKind.FIRE], 18)
	for angle_index: int in range(6):
		var angle: float = TAU * float(angle_index) / 6.0
		var offset: Vector3 = Vector3(cos(angle) * 2.8, 1.5, sin(angle) * 2.8)
		_add_cylinder(root, "vent", 0.12, 0.46, 2.2, offset, Color(0.33, 0.22, 0.18, 1.0), 6)

func _build_tide_shrine(root: Node3D) -> void: # Creates a stone gateway and raised water orb that reads clearly from the shoreline.
	var stone: Color = Color(0.60, 0.67, 0.68, 1.0)
	_add_cylinder(root, "shrine_base", 2.9, 2.9, 0.35, Vector3(0.0, 0.18, 0.0), stone.darkened(0.18), 16)
	_add_box(root, "left_pillar", Vector3(0.5, 3.3, 0.55), Vector3(-1.5, 1.95, 0.0), stone)
	_add_box(root, "right_pillar", Vector3(0.5, 3.3, 0.55), Vector3(1.5, 1.95, 0.0), stone)
	_add_box(root, "lintel", Vector3(3.8, 0.48, 0.65), Vector3(0.0, 3.45, 0.0), stone)
	_add_sphere(root, "tide_orb", 0.72, 1.2, Vector3(0.0, 2.0, 0.0), LANDMARK_COLORS[HgssWorldBuilder.BiomeKind.WATER], 12, 6)

func _build_volt_substation(root: Node3D) -> void: # Creates a four-pylon electrical landmark with transformer blocks.
	var metal: Color = Color(0.43, 0.47, 0.49, 1.0)
	var electric: Color = LANDMARK_COLORS[HgssWorldBuilder.BiomeKind.ELECTRIC]
	for x_sign: float in [-1.0, 1.0]:
		for z_sign: float in [-1.0, 1.0]:
			var offset: Vector3 = Vector3(x_sign * 2.0, 2.4, z_sign * 1.4)
			_add_cylinder(root, "pylon", 0.16, 0.28, 4.8, offset, metal, 6)
	_add_box(root, "crossbeam_front", Vector3(5.0, 0.22, 0.28), Vector3(0.0, 4.1, -1.4), metal)
	_add_box(root, "crossbeam_back", Vector3(5.0, 0.22, 0.28), Vector3(0.0, 4.1, 1.4), metal)
	_add_box(root, "transformer_left", Vector3(1.3, 1.35, 1.2), Vector3(-0.9, 0.68, 0.0), electric)
	_add_box(root, "transformer_right", Vector3(1.3, 1.35, 1.2), Vector3(0.9, 0.68, 0.0), electric.darkened(0.12))

func _build_ancient_grove(root: Node3D) -> void: # Builds a mature rooted tree using the same organic woodland art system.
	var tree: MeshInstance3D = MeshInstance3D.new() # Composes the grove's signature tree into its landmark scene.
	tree.name = "ancient_tree" # Gives the signature tree a readable inspector name.
	tree.mesh = WorldSceneryMeshes.tree(0, 1) # Uses a branched tree with a coherent irregular crown.
	tree.scale = Vector3.ONE * 2.35 # Makes this mature landmark larger than the surrounding young woodland.
	root.add_child(tree) # Anchors the complete trunk and crown at the landmark's ground position.

func _build_crystal_sanctum(root: Node3D) -> void: # Creates a cluster of tall ice crystals around a low platform.
	var ice: Color = LANDMARK_COLORS[HgssWorldBuilder.BiomeKind.ICE]
	_add_cylinder(root, "ice_plinth", 2.8, 2.8, 0.35, Vector3(0.0, 0.18, 0.0), Color(0.66, 0.78, 0.82, 1.0), 12)
	_add_crystal(root, Vector3(0.0, 2.5, 0.0), 5.0, 0.7, ice)
	_add_crystal(root, Vector3(-1.6, 1.8, 0.8), 3.6, 0.5, ice.darkened(0.08))
	_add_crystal(root, Vector3(1.6, 1.6, -0.7), 3.2, 0.48, ice.lightened(0.05))

func _build_red_belt_dojo(root: Node3D) -> void: # Creates a compact open dojo with a red roof and training floor.
	var wood: Color = Color(0.38, 0.23, 0.13, 1.0)
	var red: Color = LANDMARK_COLORS[HgssWorldBuilder.BiomeKind.FIGHTING]
	_add_box(root, "dojo_floor", Vector3(5.4, 0.32, 4.4), Vector3(0.0, 0.16, 0.0), Color(0.62, 0.51, 0.34, 1.0))
	for x_sign: float in [-1.0, 1.0]:
		for z_sign: float in [-1.0, 1.0]:
			_add_cylinder(root, "dojo_post", 0.18, 0.22, 3.2, Vector3(x_sign * 2.2, 1.75, z_sign * 1.7), wood, 8)
	_add_box(root, "dojo_roof", Vector3(6.0, 0.42, 5.0), Vector3(0.0, 3.35, 0.0), red)

func _build_toxic_wells(root: Node3D) -> void: # Creates three large toxic vats with a central pipe stack.
	var poison: Color = LANDMARK_COLORS[HgssWorldBuilder.BiomeKind.POISON]
	for offset: Vector3 in [Vector3(-1.8, 0.85, 0.8), Vector3(1.8, 0.85, 0.8), Vector3(0.0, 0.85, -1.4)]:
		_add_cylinder(root, "toxic_vat", 0.95, 0.95, 1.7, offset, poison, 12)
		_add_cylinder(root, "vat_rim", 1.05, 1.05, 0.16, offset + Vector3(0.0, 0.88, 0.0), Color(0.28, 0.25, 0.30, 1.0), 12)
	_add_cylinder(root, "pipe_stack", 0.28, 0.38, 4.2, Vector3(0.0, 2.1, 0.4), Color(0.31, 0.33, 0.32, 1.0), 8)

func _build_dust_gate(root: Node3D) -> void: # Creates a monumental badlands gate from two sandstone towers and a lintel.
	var ground: Color = LANDMARK_COLORS[HgssWorldBuilder.BiomeKind.GROUND]
	_add_box(root, "left_tower", Vector3(1.5, 4.2, 1.8), Vector3(-2.0, 2.1, 0.0), ground)
	_add_box(root, "right_tower", Vector3(1.5, 4.2, 1.8), Vector3(2.0, 2.1, 0.0), ground.darkened(0.08))
	_add_box(root, "gate_lintel", Vector3(5.5, 1.0, 1.8), Vector3(0.0, 4.0, 0.0), ground.lightened(0.06))

func _build_skywatch_tower(root: Node3D) -> void: # Creates a tall observation tower with broad wind-catching crossarms.
	var pale: Color = LANDMARK_COLORS[HgssWorldBuilder.BiomeKind.FLYING]
	_add_cylinder(root, "tower", 0.42, 0.70, 6.2, Vector3(0.0, 3.1, 0.0), Color(0.56, 0.63, 0.64, 1.0), 8)
	_add_sphere(root, "watch_orb", 0.95, 1.25, Vector3(0.0, 6.4, 0.0), pale, 10, 5)
	_add_box(root, "wind_arm_x", Vector3(5.6, 0.22, 0.30), Vector3(0.0, 5.3, 0.0), pale)
	_add_box(root, "wind_arm_z", Vector3(0.30, 0.22, 5.6), Vector3(0.0, 5.3, 0.0), pale)

func _build_mind_crystal_garden(root: Node3D) -> void: # Creates a raised psychic orb surrounded by four geometric monoliths.
	var psychic: Color = LANDMARK_COLORS[HgssWorldBuilder.BiomeKind.PSYCHIC]
	_add_sphere(root, "mind_orb", 1.15, 1.5, Vector3(0.0, 3.2, 0.0), psychic, 12, 6)
	for offset: Vector3 in [Vector3(2.2, 1.4, 0.0), Vector3(-2.2, 1.4, 0.0), Vector3(0.0, 1.4, 2.2), Vector3(0.0, 1.4, -2.2)]:
		_add_box(root, "psychic_monolith", Vector3(0.55, 2.8, 0.55), offset, psychic.darkened(0.12))

func _build_grand_hive(root: Node3D) -> void: # Creates an oversized hive body elevated on a short organic trunk.
	var bug: Color = LANDMARK_COLORS[HgssWorldBuilder.BiomeKind.BUG]
	_add_cylinder(root, "hive_trunk", 0.48, 0.65, 2.2, Vector3(0.0, 1.1, 0.0), Color(0.33, 0.23, 0.12, 1.0), 8)
	_add_sphere(root, "hive_body", 2.0, 3.0, Vector3(0.0, 3.1, 0.0), bug, 10, 6)
	_add_sphere(root, "hive_cap", 1.45, 1.8, Vector3(0.0, 4.8, 0.0), bug.lightened(0.08), 10, 5)
	_add_cylinder(root, "hive_entrance", 0.45, 0.45, 0.38, Vector3(0.0, 2.8, -1.85), Color(0.16, 0.13, 0.08, 1.0), 10, Vector3(90.0, 0.0, 0.0))

func _build_summit_cairn(root: Node3D) -> void: # Creates a heavy stacked stone summit marker visible against the mountain skyline.
	var rock: Color = LANDMARK_COLORS[HgssWorldBuilder.BiomeKind.ROCK]
	_add_sphere(root, "cairn_base", 2.1, 1.5, Vector3(0.0, 0.75, 0.0), rock, 8, 4)
	_add_sphere(root, "cairn_mid", 1.5, 1.6, Vector3(0.0, 1.9, 0.0), rock.lightened(0.04), 8, 4)
	_add_sphere(root, "cairn_top", 0.85, 1.2, Vector3(0.0, 3.0, 0.0), rock.darkened(0.08), 8, 4)

func _build_haunted_ruins(root: Node3D) -> void: # Creates a broken stone arch framed by grave-like markers.
	var ghost: Color = LANDMARK_COLORS[HgssWorldBuilder.BiomeKind.GHOST]
	_add_box(root, "ruin_left", Vector3(0.8, 4.0, 0.9), Vector3(-1.7, 2.0, 0.0), ghost.darkened(0.18))
	_add_box(root, "ruin_right", Vector3(0.8, 3.3, 0.9), Vector3(1.7, 1.65, 0.0), ghost.darkened(0.12))
	_add_box(root, "ruin_lintel", Vector3(4.2, 0.72, 0.9), Vector3(0.0, 3.8, 0.0), ghost)
	for x: float in [-3.0, 3.0]:
		_add_box(root, "grave", Vector3(0.65, 1.35, 0.35), Vector3(x, 0.68, 1.5), ghost.lightened(0.08))

func _build_dragon_shrine(root: Node3D) -> void: # Creates an altar guarded by two tall tapered dragon spires.
	var dragon: Color = LANDMARK_COLORS[HgssWorldBuilder.BiomeKind.DRAGON]
	_add_box(root, "dragon_altar", Vector3(3.4, 1.0, 2.5), Vector3(0.0, 0.5, 0.0), dragon.darkened(0.18))
	_add_cylinder(root, "left_spire", 0.05, 0.72, 5.8, Vector3(-2.2, 2.9, 0.0), dragon, 7)
	_add_cylinder(root, "right_spire", 0.05, 0.72, 5.8, Vector3(2.2, 2.9, 0.0), dragon.lightened(0.06), 7)
	_add_sphere(root, "dragon_core", 0.72, 1.0, Vector3(0.0, 2.0, 0.0), dragon.lightened(0.12), 10, 5)

func _build_eclipse_obelisk(root: Node3D) -> void: # Creates a tall dark four-sided obelisk with a pale eclipse disc.
	var dark: Color = LANDMARK_COLORS[HgssWorldBuilder.BiomeKind.DARK]
	_add_cylinder(root, "obelisk", 0.14, 0.82, 6.4, Vector3(0.0, 3.2, 0.0), dark, 4)
	_add_sphere(root, "eclipse_disc", 1.25, 0.35, Vector3(0.0, 6.2, 0.0), Color(0.63, 0.59, 0.67, 1.0), 16, 4)

func _build_iron_forge(root: Node3D) -> void: # Creates a squat metallic forge building with twin smokestacks.
	var steel: Color = LANDMARK_COLORS[HgssWorldBuilder.BiomeKind.STEEL]
	_add_box(root, "forge_body", Vector3(5.2, 2.7, 4.2), Vector3(0.0, 1.35, 0.0), steel, 0.55)
	_add_box(root, "forge_roof", Vector3(5.8, 0.55, 4.8), Vector3(0.0, 2.95, 0.0), steel.darkened(0.18), 0.65)
	_add_cylinder(root, "left_stack", 0.38, 0.52, 4.4, Vector3(-1.6, 4.2, 0.7), steel.darkened(0.26), 8)
	_add_cylinder(root, "right_stack", 0.38, 0.52, 4.4, Vector3(1.6, 4.2, 0.7), steel.darkened(0.26), 8)
	_add_box(root, "forge_door", Vector3(1.5, 1.8, 0.18), Vector3(0.0, 0.9, -2.18), Color(0.22, 0.23, 0.24, 1.0), 0.45)

func _build_arrival_marker(arrival_position: Vector3, biome_kind: int) -> void: # Marks the safe fast-travel landing point without blocking movement.
	var marker: MeshInstance3D = MeshInstance3D.new()
	marker.name = "%s_travel_marker" % REGION_NAMES[biome_kind].to_snake_case()
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = 0.78
	mesh.bottom_radius = 0.78
	mesh.height = 0.05
	mesh.radial_segments = 18
	mesh.rings = 1
	mesh.material = _create_material(LANDMARK_COLORS[biome_kind].darkened(0.12), 0.72)
	marker.mesh = mesh
	marker.position = arrival_position + Vector3(0.0, 0.025, 0.0)
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)

func _add_crystal(root: Node3D, position: Vector3, height: float, radius: float, color: Color) -> void: # Uses a six-sided cone-like cylinder as a readable crystal silhouette.
	_add_cylinder(root, "crystal", 0.04, radius, height, position, color, 6)

func _add_box(root: Node3D, node_name: String, size: Vector3, position: Vector3, color: Color, metallic: float = 0.0) -> void: # Adds one colored box primitive to a landmark composition.
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	mesh.material = _create_material(color, 0.82, metallic)
	instance.mesh = mesh
	instance.position = position
	root.add_child(instance)

func _add_cylinder(root: Node3D, node_name: String, top_radius: float, bottom_radius: float, height: float, position: Vector3, color: Color, radial_segments: int, rotation_degrees: Vector3 = Vector3.ZERO) -> void: # Adds a cylinder or cone primitive with optional rotation.
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = radial_segments
	mesh.rings = 1
	mesh.material = _create_material(color, 0.84)
	instance.mesh = mesh
	instance.position = position
	instance.rotation_degrees = rotation_degrees
	root.add_child(instance)

func _add_sphere(root: Node3D, node_name: String, radius: float, height: float, position: Vector3, color: Color, radial_segments: int, rings: int) -> void: # Adds a low-poly ellipsoid-like sphere primitive.
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = radial_segments
	mesh.rings = rings
	mesh.material = _create_material(color, 0.86)
	instance.mesh = mesh
	instance.position = position
	root.add_child(instance)

func _create_material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D: # Creates one shaded untextured landmark material.
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func _local_to_world_hint(local: Vector2) -> Vector3: # Converts biome-layout coordinates into an approximate world position for safe-cell lookup.
	return Vector3(local.x * HgssWorldBuilder.TILE_SIZE, 0.0, local.y * HgssWorldBuilder.TILE_SIZE)
