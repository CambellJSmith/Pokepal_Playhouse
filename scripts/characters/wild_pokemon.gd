class_name WildPokemon # Controls one temporary overworld Pokémon as it enters, wanders inside its type habitat, leaves, and despawns.
extends CharacterBody3D # Uses ordinary 3D character collision and floor handling for roaming overworld movement.

enum BehaviourState { ENTERING, HANGING_OUT, LEAVING } # Defines the three phases of a temporary Pokémon visit.

@onready var visual: BillboardCharacterVisual = $pokemon_visual as BillboardCharacterVisual # References the reusable billboard renderer owned by this character.

var random: RandomNumberGenerator = RandomNumberGenerator.new() # Gives each Pokémon independent movement and timing choices.
var behaviour_state: BehaviourState = BehaviourState.ENTERING # Starts the character at a biome boundary before it walks inward.
var world_builder: HgssWorldBuilder # References the generated world's habitat-aware walkability service.
var home_biome: int = HgssWorldBuilder.BiomeKind.NORMAL # Keeps wandering and departure constrained to the primary-type region chosen by the spawner.
var destination_position: Vector3 = Vector3.ZERO # Stores the final world-space destination for the current behaviour decision.
var movement_target: Vector3 = Vector3.ZERO # Stores the current A* turning-point waypoint the CharacterBody3D is steering toward.
var movement_path: Array[Vector3] = [] # Stores the compact shared-grid route through walkable cells.
var movement_path_index: int = 0 # Tracks the active waypoint inside the compact movement path.
var configured: bool = false # Prevents processing until the spawner has supplied assets and terrain policy.
var move_speed: float = 1.65 # Controls the relaxed roaming pace used while the Pokémon is visible.
var acceleration: float = 8.0 # Controls how smoothly horizontal movement reaches and leaves its target velocity.
var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity")) # Uses the project's configured 3D gravity.
var hangout_time_remaining: float = 0.0 # Tracks how long this Pokémon remains before deciding to leave.
var idle_time_remaining: float = 0.0 # Tracks short pauses between wandering movements.
var target_reach_distance: float = 0.38 # Defines when a waypoint or destination is close enough to count as reached.
var stalled_time: float = 0.0 # Tracks how long the Pokémon has failed to make meaningful progress toward a waypoint.
var previous_position: Vector3 = Vector3.ZERO # Stores the prior physics-frame position for simple dynamic-obstacle detection.

func setup(sprite_directory: String, generated_world: HgssWorldBuilder, initial_target: Vector3, assigned_biome: int, random_seed: int) -> void: # Configures a newly spawned Pokémon with its visual, home habitat, and first inward route.
    random.seed = random_seed
    world_builder = generated_world
    home_biome = assigned_biome
    move_speed = random.randf_range(1.25, 2.05)
    hangout_time_remaining = random.randf_range(22.0, 48.0) # Gives the enlarged habitats enough time for local roaming to be visible.
    visual.set_sprite_frames(PokemonSpriteLibrary.get_sprite_frames(sprite_directory))
    behaviour_state = BehaviourState.ENTERING
    previous_position = global_position
    configured = world_builder != null
    if configured:
        _set_destination(initial_target)

func _physics_process(delta: float) -> void: # Advances behaviour, route following, gravity, collision response, and directional animation each physics frame.
    if not configured:
        return
    var camera: Camera3D = get_viewport().get_camera_3d()
    if camera == null:
        return
    _update_behaviour(delta)
    _advance_path_if_needed()
    var desired_velocity: Vector3 = _get_desired_horizontal_velocity()
    velocity.x = move_toward(velocity.x, desired_velocity.x, acceleration * delta)
    velocity.z = move_toward(velocity.z, desired_velocity.z, acceleration * delta)
    if is_on_floor():
        velocity.y = -0.1
    else:
        velocity.y -= gravity * delta
    move_and_slide()
    visual.update_motion(get_real_velocity(), camera)
    _update_stall_detection(delta)
    if behaviour_state == BehaviourState.LEAVING and _has_reached_destination():
        queue_free()

func _update_behaviour(delta: float) -> void: # Advances the finite-state behaviour without coupling it to rendering.
    if behaviour_state == BehaviourState.ENTERING:
        if _has_reached_destination():
            behaviour_state = BehaviourState.HANGING_OUT
            _begin_idle_pause()
        return
    if behaviour_state == BehaviourState.LEAVING:
        return
    hangout_time_remaining -= delta
    if hangout_time_remaining <= 0.0:
        _begin_leaving()
        return
    if idle_time_remaining > 0.0:
        idle_time_remaining = maxf(idle_time_remaining - delta, 0.0)
        if idle_time_remaining <= 0.0:
            _set_destination(_choose_wander_target())
        return
    if _has_reached_destination():
        _begin_idle_pause()

func _get_desired_horizontal_velocity() -> Vector3: # Calculates horizontal travel while respecting deliberate idle pauses and the current route waypoint.
    if behaviour_state == BehaviourState.HANGING_OUT and idle_time_remaining > 0.0:
        return Vector3.ZERO
    var to_target: Vector3 = movement_target - global_position
    to_target.y = 0.0
    if to_target.length_squared() <= target_reach_distance * target_reach_distance:
        return Vector3.ZERO
    return to_target.normalized() * move_speed

func _set_destination(destination: Vector3) -> void: # Builds or rebuilds a compact shared-grid route to one final generated-world destination.
    destination_position = destination
    movement_path = HgssWorldNavigation.get_world_path(world_builder, global_position, destination_position)
    movement_path_index = 0
    if movement_path.is_empty():
        movement_target = destination_position
        return
    movement_target = movement_path[0]

func _advance_path_if_needed() -> void: # Moves to the next A* waypoint after the current one has been reached.
    if movement_path.is_empty():
        return
    if not _has_reached_waypoint():
        return
    if movement_path_index >= movement_path.size() - 1:
        movement_target = destination_position
        return
    movement_path_index += 1
    movement_target = movement_path[movement_path_index]

func _begin_idle_pause() -> void: # Starts a natural stationary period between local roaming routes.
    idle_time_remaining = random.randf_range(1.25, 4.5)
    movement_path.clear()
    destination_position = global_position
    movement_target = global_position
    stalled_time = 0.0

func _begin_leaving() -> void: # Routes the Pokémon back to the nearest walkable boundary of its own primary-type habitat.
    behaviour_state = BehaviourState.LEAVING
    idle_time_remaining = 0.0
    var biome_exit: Vector3 = world_builder.get_biome_exit_target_from(global_position, home_biome)
    _set_destination(biome_exit)
    stalled_time = 0.0

func _choose_wander_target() -> Vector3: # Chooses a nearby destination that remains inside the Pokémon's assigned primary-type biome.
    var radius: float = random.randf_range(7.0, 16.0)
    return world_builder.get_random_walkable_world_position_near_in_biome(global_position, radius, home_biome, random)

func _update_stall_detection(delta: float) -> void: # Detects local movement deadlocks caused by the player or other roaming Pokémon.
    if behaviour_state == BehaviourState.HANGING_OUT and idle_time_remaining > 0.0:
        previous_position = global_position
        stalled_time = 0.0
        return
    var moved_squared: float = global_position.distance_squared_to(previous_position)
    if moved_squared < 0.0004 and not _has_reached_waypoint():
        stalled_time += delta
    else:
        stalled_time = 0.0
    previous_position = global_position
    if stalled_time < 1.5:
        return
    stalled_time = 0.0
    if behaviour_state == BehaviourState.HANGING_OUT:
        _set_destination(_choose_wander_target())
        return
    _set_destination(destination_position)

func _has_reached_waypoint() -> bool: # Tests arrival at the current intermediate A* waypoint using horizontal distance only.
    var offset: Vector3 = movement_target - global_position
    offset.y = 0.0
    return offset.length_squared() <= target_reach_distance * target_reach_distance

func _has_reached_destination() -> bool: # Tests whether the final behaviour destination has been reached after route following.
    var offset: Vector3 = destination_position - global_position
    offset.y = 0.0
    return offset.length_squared() <= target_reach_distance * target_reach_distance
