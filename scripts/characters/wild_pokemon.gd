class_name WildPokemon # Controls one temporary overworld Pokémon as it enters, wanders, idles, leaves, and despawns.
extends CharacterBody3D # Uses ordinary 3D character collision and floor handling for wild overworld movement.

enum BehaviourState { ENTERING, HANGING_OUT, LEAVING } # Defines the three phases of a wild Pokémon's short visit to the area.

@onready var visual: BillboardCharacterVisual = $pokemon_visual as BillboardCharacterVisual # References the reusable billboard renderer owned by this character.

var random: RandomNumberGenerator = RandomNumberGenerator.new() # Gives each Pokémon independent movement and timing choices.
var behaviour_state: BehaviourState = BehaviourState.ENTERING # Starts the character in its edge-to-interior arrival phase.
var area_center: Vector3 = Vector3.ZERO # Stores the world-space centre of the rectangular wandering region.
var area_half_size: Vector2 = Vector2.ONE # Stores the usable X/Z half-extents of the wandering region.
var movement_target: Vector3 = Vector3.ZERO # Stores the current world-space point the Pokémon is walking toward.
var configured: bool = false # Prevents movement processing until the spawner has supplied assets and area information.
var move_speed: float = 1.65 # Controls the relaxed roaming pace used while the Pokémon is visible.
var acceleration: float = 8.0 # Controls how smoothly horizontal movement reaches and leaves its target velocity.
var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity")) # Uses the project's configured 3D gravity.
var hangout_time_remaining: float = 0.0 # Tracks how long this Pokémon remains in the area before deciding to leave.
var idle_time_remaining: float = 0.0 # Tracks short pauses between wandering movements.
var target_reach_distance: float = 0.32 # Defines when a movement destination is close enough to count as reached.

func setup(sprite_directory: String, roaming_center: Vector3, roaming_half_size: Vector2, initial_target: Vector3, random_seed: int) -> void: # Configures a newly spawned Pokémon before its first physics update.
    random.seed = random_seed # Gives this instance deterministic independent random values based on the spawner-provided seed.
    area_center = roaming_center # Stores the world-space wandering region centre for later target selection.
    area_half_size = roaming_half_size # Stores the wandering region extents for later clamping and exit selection.
    movement_target = initial_target # Sends the new arrival toward a point comfortably inside the visible roaming area.
    move_speed = random.randf_range(1.25, 2.0) # Gives individual Pokémon a small amount of natural walking-speed variation.
    hangout_time_remaining = random.randf_range(10.0, 22.0) # Gives each visit a varied but deliberately temporary duration.
    visual.set_sprite_frames(PokemonSpriteLibrary.get_sprite_frames(sprite_directory)) # Assigns the selected species/form animation resource to the shared renderer.
    behaviour_state = BehaviourState.ENTERING # Ensures the first movement phase walks inward from the spawn edge.
    configured = true # Enables physics behaviour now that every required runtime value is available.

func _physics_process(delta: float) -> void: # Advances behaviour, movement, gravity, collision response, and directional animation each physics frame.
    if not configured: # Guards the brief scene-tree period before the spawner finishes configuring this instance.
        return # Avoids moving or animating with incomplete setup data.
    var camera: Camera3D = get_viewport().get_camera_3d() # Reads the active camera for camera-relative HGSS facing selection.
    if camera == null: # Guards startup or scene-transition frames where no active camera exists.
        return # Delays character processing until a camera is available.
    _update_behaviour(delta) # Advances arrival, lingering, wandering, pausing, and departure decisions.
    var desired_velocity: Vector3 = _get_desired_horizontal_velocity() # Converts the current behaviour target into a horizontal travel request.
    velocity.x = move_toward(velocity.x, desired_velocity.x, acceleration * delta) # Smoothly approaches the desired X movement speed.
    velocity.z = move_toward(velocity.z, desired_velocity.z, acceleration * delta) # Smoothly approaches the desired Z movement speed.
    if is_on_floor(): # Keeps roaming Pokémon attached to the walkable ground surface.
        velocity.y = -0.1 # Applies a small downward bias so floor contact remains stable.
    else: # Applies gravity while the character is not supported by a floor.
        velocity.y -= gravity * delta # Integrates the project's gravity into vertical velocity.
    move_and_slide() # Moves the CharacterBody3D while resolving terrain collision and slopes through Godot physics.
    visual.update_motion(get_real_velocity(), camera) # Selects idle or walk animation and camera-relative facing from actual resulting movement.
    if behaviour_state == BehaviourState.LEAVING and _has_reached_target(): # Detects a departing Pokémon reaching its off-area destination.
        queue_free() # Removes the temporary character cleanly after it has wandered back out.

func _update_behaviour(delta: float) -> void: # Advances the finite-state behaviour without coupling it to visual rendering.
    if behaviour_state == BehaviourState.ENTERING: # Handles the initial walk from an edge toward the interior.
        if _has_reached_target(): # Detects when the Pokémon has successfully entered the roaming region.
            behaviour_state = BehaviourState.HANGING_OUT # Switches to the temporary idle-and-wander phase.
            _begin_idle_pause() # Lets the Pokémon settle briefly before choosing its first roaming destination.
        return # Prevents hangout timers from starting before the arrival phase has completed.
    if behaviour_state == BehaviourState.LEAVING: # Keeps the departure target fixed once the Pokémon has decided to go.
        return # Allows normal movement processing to continue toward the selected exit without new behaviour choices.
    hangout_time_remaining -= delta # Counts down the total amount of time this Pokémon will remain in the area.
    if hangout_time_remaining <= 0.0: # Detects when the temporary visit has finished.
        _begin_leaving() # Chooses an outward destination and switches permanently to departure behaviour.
        return # Stops hangout decision processing after departure begins.
    if idle_time_remaining > 0.0: # Checks whether the Pokémon is currently pausing between wander movements.
        idle_time_remaining = maxf(idle_time_remaining - delta, 0.0) # Counts the pause down without allowing a negative value to accumulate.
        if idle_time_remaining <= 0.0: # Detects the end of the current pause.
            movement_target = _choose_wander_target() # Chooses another nearby point inside the roaming region.
        return # Keeps the character stationary for the rest of an active idle pause.
    if _has_reached_target(): # Detects arrival at the current wandering destination.
        _begin_idle_pause() # Stops for a short random interval before wandering again.

func _get_desired_horizontal_velocity() -> Vector3: # Calculates horizontal travel while respecting deliberate idle pauses.
    if behaviour_state == BehaviourState.HANGING_OUT and idle_time_remaining > 0.0: # Detects an intentional stationary hangout moment.
        return Vector3.ZERO # Lets acceleration decelerate the Pokémon smoothly to a stop.
    var to_target: Vector3 = movement_target - global_position # Measures displacement from the Pokémon to its active destination.
    to_target.y = 0.0 # Keeps movement planning on the horizontal ground plane.
    if to_target.length_squared() <= target_reach_distance * target_reach_distance: # Avoids normalizing extremely small target vectors.
        return Vector3.ZERO # Stops horizontal movement once the destination is effectively reached.
    return to_target.normalized() * move_speed # Travels toward the destination at this Pokémon's individual roaming speed.

func _begin_idle_pause() -> void: # Starts a natural stationary period between roaming movements.
    idle_time_remaining = random.randf_range(1.25, 4.0) # Gives the Pokémon enough time to visibly hang out rather than constantly pace.
    movement_target = global_position # Keeps the current position as the active target while the character is deliberately idle.

func _begin_leaving() -> void: # Chooses an edge destination and permanently switches the visit into its departure phase.
    behaviour_state = BehaviourState.LEAVING # Prevents any further idle or wandering decisions after the departure starts.
    idle_time_remaining = 0.0 # Cancels an active pause so departure begins immediately.
    movement_target = _choose_exit_target() # Sends the Pokémon beyond whichever roaming edge is nearest to its current position.

func _choose_wander_target() -> Vector3: # Chooses a nearby destination while keeping the Pokémon comfortably inside the roaming rectangle.
    var roam_step: Vector2 = Vector2(random.randf_range(-3.2, 3.2), random.randf_range(-3.2, 3.2)) # Creates a local wandering offset rather than teleporting intent across the whole area.
    var candidate_x: float = clampf(global_position.x + roam_step.x, area_center.x - area_half_size.x, area_center.x + area_half_size.x) # Restricts the target to the allowed X range.
    var candidate_z: float = clampf(global_position.z + roam_step.y, area_center.z - area_half_size.y, area_center.z + area_half_size.y) # Restricts the target to the allowed Z range.
    return Vector3(candidate_x, area_center.y, candidate_z) # Returns a ground-level world-space roaming destination.

func _choose_exit_target() -> Vector3: # Chooses a point beyond the nearest edge so departure looks like leaving rather than vanishing in place.
    var left_distance: float = absf(global_position.x - (area_center.x - area_half_size.x)) # Measures distance to the western roaming boundary.
    var right_distance: float = absf((area_center.x + area_half_size.x) - global_position.x) # Measures distance to the eastern roaming boundary.
    var top_distance: float = absf(global_position.z - (area_center.z - area_half_size.y)) # Measures distance to the northern roaming boundary.
    var bottom_distance: float = absf((area_center.z + area_half_size.y) - global_position.z) # Measures distance to the southern roaming boundary.
    var nearest_distance: float = minf(minf(left_distance, right_distance), minf(top_distance, bottom_distance)) # Finds the shortest outward route from the current position.
    var exit_margin: float = 1.2 # Places the despawn destination visibly beyond the logical roaming boundary.
    if nearest_distance == left_distance: # Selects the west edge when it is the shortest departure route.
        return Vector3(area_center.x - area_half_size.x - exit_margin, area_center.y, global_position.z) # Returns an off-area target directly beyond the west boundary.
    if nearest_distance == right_distance: # Selects the east edge when it is the shortest departure route.
        return Vector3(area_center.x + area_half_size.x + exit_margin, area_center.y, global_position.z) # Returns an off-area target directly beyond the east boundary.
    if nearest_distance == top_distance: # Selects the north edge when it is the shortest departure route.
        return Vector3(global_position.x, area_center.y, area_center.z - area_half_size.y - exit_margin) # Returns an off-area target directly beyond the north boundary.
    return Vector3(global_position.x, area_center.y, area_center.z + area_half_size.y + exit_margin) # Returns an off-area target directly beyond the south boundary.

func _has_reached_target() -> bool: # Tests destination arrival using horizontal distance only.
    var offset: Vector3 = movement_target - global_position # Measures the remaining displacement to the current destination.
    offset.y = 0.0 # Ignores small vertical differences caused by floor contact and slopes.
    return offset.length_squared() <= target_reach_distance * target_reach_distance # Uses squared distance to avoid a square root in the per-frame arrival test.
