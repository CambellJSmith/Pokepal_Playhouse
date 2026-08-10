class_name WildPokemon # Controls one temporary overworld Pokémon as it enters, wanders, idles, leaves, and despawns.
extends CharacterBody3D # Uses ordinary 3D character collision and floor handling for roaming overworld movement.

enum BehaviourState { ENTERING, HANGING_OUT, LEAVING } # Defines the three phases of a temporary Pokémon visit.

@onready var visual: BillboardCharacterVisual = $pokemon_visual as BillboardCharacterVisual # References the reusable billboard renderer owned by this character.

var random: RandomNumberGenerator = RandomNumberGenerator.new() # Gives each Pokémon independent movement and timing choices.
var behaviour_state: BehaviourState = BehaviourState.ENTERING # Starts the character in its route-gate arrival phase.
var world_builder: HgssWorldBuilder # References the generated world's walkability and nearest-exit service.
var movement_target: Vector3 = Vector3.ZERO # Stores the current world-space point the Pokémon is walking toward.
var configured: bool = false # Prevents processing until the spawner has supplied assets and terrain policy.
var move_speed: float = 1.65 # Controls the relaxed roaming pace used while the Pokémon is visible.
var acceleration: float = 8.0 # Controls how smoothly horizontal movement reaches and leaves its target velocity.
var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity")) # Uses the project's configured 3D gravity.
var hangout_time_remaining: float = 0.0 # Tracks how long this Pokémon remains before deciding to leave.
var idle_time_remaining: float = 0.0 # Tracks short pauses between wandering movements.
var target_reach_distance: float = 0.38 # Defines when a movement destination is close enough to count as reached.
var stalled_time: float = 0.0 # Tracks how long the Pokémon has failed to make meaningful progress toward a target.
var previous_position: Vector3 = Vector3.ZERO # Stores the prior physics-frame position for simple stuck detection.

func setup(sprite_directory: String, generated_world: HgssWorldBuilder, initial_target: Vector3, random_seed: int) -> void: # Configures a newly spawned Pokémon before its first physics update.
    random.seed = random_seed # Gives this instance deterministic independent random values based on the spawner-provided seed.
    world_builder = generated_world # Stores the generated terrain service for all future wandering and departure decisions.
    movement_target = initial_target # Sends the new arrival toward a safe point just inside its selected route gate.
    move_speed = random.randf_range(1.25, 2.05) # Gives individual Pokémon a small amount of natural walking-speed variation.
    hangout_time_remaining = random.randf_range(14.0, 32.0) # Gives the larger world longer, more readable temporary visits.
    visual.set_sprite_frames(PokemonSpriteLibrary.get_sprite_frames(sprite_directory)) # Assigns the selected species/form animation resource to the shared renderer.
    behaviour_state = BehaviourState.ENTERING # Ensures the first movement phase walks inward from the map edge.
    previous_position = global_position # Initializes progress tracking from the actual spawn point.
    configured = world_builder != null # Enables physics only when a valid generated-world service exists.

func _physics_process(delta: float) -> void: # Advances behaviour, movement, gravity, collision response, and directional animation each physics frame.
    if not configured: # Guards the brief scene-tree period before setup completes or a structurally invalid spawn.
        return # Avoids moving or animating with incomplete runtime data.
    var camera: Camera3D = get_viewport().get_camera_3d() # Reads the active camera for camera-relative HGSS facing selection.
    if camera == null: # Guards startup or transition frames where no active camera exists.
        return # Delays character processing until a camera is available.
    _update_behaviour(delta) # Advances arrival, lingering, wandering, pausing, and departure decisions.
    var desired_velocity: Vector3 = _get_desired_horizontal_velocity() # Converts the current target into a horizontal travel request.
    velocity.x = move_toward(velocity.x, desired_velocity.x, acceleration * delta) # Smoothly approaches the desired X movement speed.
    velocity.z = move_toward(velocity.z, desired_velocity.z, acceleration * delta) # Smoothly approaches the desired Z movement speed.
    if is_on_floor(): # Keeps roaming Pokémon attached to generated terrain and slopes.
        velocity.y = -0.1 # Applies a small downward bias so floor contact remains stable.
    else: # Applies gravity whenever the character leaves the ground.
        velocity.y -= gravity * delta # Integrates vertical acceleration into the body's velocity.
    move_and_slide() # Moves the CharacterBody3D while resolving generated terrain, player, and Pokémon collision.
    visual.update_motion(get_real_velocity(), camera) # Selects idle or walk animation and camera-relative facing from actual resulting motion.
    _update_stall_detection(delta) # Replans local wandering when collision or terrain geometry prevents useful progress.
    if behaviour_state == BehaviourState.LEAVING and _has_reached_target(): # Detects a departing Pokémon reaching its off-map destination.
        queue_free() # Removes the temporary character cleanly after it has walked out.

func _update_behaviour(delta: float) -> void: # Advances the finite-state behaviour without coupling it to rendering.
    if behaviour_state == BehaviourState.ENTERING: # Handles the initial walk from a route gate toward the interior.
        if _has_reached_target(): # Detects when the Pokémon has successfully entered the generated world.
            behaviour_state = BehaviourState.HANGING_OUT # Switches to the temporary idle-and-wander phase.
            _begin_idle_pause() # Lets the Pokémon settle briefly before choosing its first local destination.
        return # Prevents hangout timers from starting before arrival is complete.
    if behaviour_state == BehaviourState.LEAVING: # Keeps the departure target fixed once the Pokémon has decided to go.
        return # Allows normal movement processing to continue toward the selected exit without new wander choices.
    hangout_time_remaining -= delta # Counts down the total amount of time this Pokémon will remain in the world.
    if hangout_time_remaining <= 0.0: # Detects when the temporary visit has finished.
        _begin_leaving() # Chooses the nearest route gate and switches permanently to departure behaviour.
        return # Stops hangout decision processing after departure begins.
    if idle_time_remaining > 0.0: # Checks whether the Pokémon is intentionally pausing between movements.
        idle_time_remaining = maxf(idle_time_remaining - delta, 0.0) # Counts the pause down without accumulating a negative value.
        if idle_time_remaining <= 0.0: # Detects the end of the current pause.
            movement_target = _choose_wander_target() # Chooses another nearby walkable generated-world cell.
        return # Keeps the character stationary for the rest of an active idle pause.
    if _has_reached_target(): # Detects arrival at the current wandering destination.
        _begin_idle_pause() # Stops for a short random interval before wandering again.

func _get_desired_horizontal_velocity() -> Vector3: # Calculates horizontal travel while respecting deliberate idle pauses.
    if behaviour_state == BehaviourState.HANGING_OUT and idle_time_remaining > 0.0: # Detects an intentional stationary hangout moment.
        return Vector3.ZERO # Lets acceleration decelerate the Pokémon smoothly to a stop.
    var to_target: Vector3 = movement_target - global_position # Measures displacement from the Pokémon to its active destination.
    to_target.y = 0.0 # Keeps movement planning on the horizontal plane while physics follows terrain height.
    if to_target.length_squared() <= target_reach_distance * target_reach_distance: # Avoids normalizing extremely small target vectors.
        return Vector3.ZERO # Stops horizontal movement once the destination is effectively reached.
    return to_target.normalized() * move_speed # Travels toward the destination at this Pokémon's individual roaming speed.

func _begin_idle_pause() -> void: # Starts a natural stationary period between local roaming movements.
    idle_time_remaining = random.randf_range(1.25, 4.5) # Gives the Pokémon enough time to visibly hang out rather than constantly pace.
    movement_target = global_position # Keeps the current position as the active target during the deliberate pause.
    stalled_time = 0.0 # Clears stale progress state while the Pokémon is intentionally stationary.

func _begin_leaving() -> void: # Chooses a generated-world route gate and permanently switches into departure behaviour.
    behaviour_state = BehaviourState.LEAVING # Prevents any further idle or wandering decisions after departure begins.
    idle_time_remaining = 0.0 # Cancels an active pause so departure starts immediately.
    movement_target = world_builder.get_exit_target_from(global_position) # Sends the Pokémon toward whichever off-map route gate is nearest.
    stalled_time = 0.0 # Gives the departure route a fresh progress timer.

func _choose_wander_target() -> Vector3: # Chooses a nearby walkable destination that respects water, forest blockers, and generated elevation.
    return world_builder.get_random_walkable_world_position_near(global_position, random.randf_range(4.0, 9.0), random) # Delegates terrain policy to the world builder instead of reproducing map rules here.

func _update_stall_detection(delta: float) -> void: # Detects local movement deadlocks caused by other Pokémon or forest geometry.
    if behaviour_state == BehaviourState.HANGING_OUT and idle_time_remaining > 0.0: # Ignores progress while the Pokémon is intentionally idle.
        previous_position = global_position # Keeps the reference position current without accumulating stalled time.
        stalled_time = 0.0 # Clears any prior movement stall.
        return # Avoids treating deliberate stillness as navigation failure.
    var moved_squared: float = global_position.distance_squared_to(previous_position) # Measures actual physics displacement since the previous update.
    if moved_squared < 0.0004 and not _has_reached_target(): # Detects a character that wants to move but is making essentially no progress.
        stalled_time += delta # Counts how long the obstruction persists.
    else: # Resets the timer whenever useful movement occurs or the target is reached.
        stalled_time = 0.0 # Clears accumulated stall duration.
    previous_position = global_position # Stores the current location for the next physics update.
    if stalled_time < 1.5: # Allows short collisions with other roaming Pokémon to resolve naturally.
        return # Keeps the existing target while the obstruction is brief.
    stalled_time = 0.0 # Resets the timer before selecting a replacement target.
    if behaviour_state == BehaviourState.HANGING_OUT: # Replans only free-roaming movement rather than route-gate arrival or departure.
        movement_target = _choose_wander_target() # Chooses another nearby safe cell to route around the obstruction informally.

func _has_reached_target() -> bool: # Tests destination arrival using horizontal distance only.
    var offset: Vector3 = movement_target - global_position # Measures the remaining displacement to the current destination.
    offset.y = 0.0 # Ignores vertical differences caused by generated hills and floor snapping.
    return offset.length_squared() <= target_reach_distance * target_reach_distance # Uses squared distance to avoid a square root in the per-frame arrival test.
