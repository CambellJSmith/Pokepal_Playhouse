class_name WildPokemon # Controls one temporary overworld Pokémon as it enters, wanders, idles, leaves, and despawns.
extends CharacterBody3D # Uses ordinary 3D character collision and floor handling for roaming overworld movement.

enum BehaviourState { ENTERING, HANGING_OUT, LEAVING } # Defines the three phases of a temporary Pokémon visit.

@onready var visual: BillboardCharacterVisual = $pokemon_visual as BillboardCharacterVisual # References the reusable billboard renderer owned by this character.

var random: RandomNumberGenerator = RandomNumberGenerator.new() # Gives each Pokémon independent movement and timing choices.
var behaviour_state: BehaviourState = BehaviourState.ENTERING # Starts the character in its route-gate arrival phase.
var world_builder: HgssWorldBuilder # References the generated world's walkability and gateway service.
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

func setup(sprite_directory: String, generated_world: HgssWorldBuilder, initial_target: Vector3, random_seed: int) -> void: # Configures a newly spawned Pokémon before its first physics update.
    random.seed = random_seed # Gives this instance deterministic independent random values based on the spawner-provided seed.
    world_builder = generated_world # Stores the generated terrain service for all future wandering and departure decisions.
    move_speed = random.randf_range(1.25, 2.05) # Gives individual Pokémon a small amount of natural walking-speed variation.
    hangout_time_remaining = random.randf_range(14.0, 32.0) # Gives the larger world longer, more readable temporary visits.
    visual.set_sprite_frames(PokemonSpriteLibrary.get_sprite_frames(sprite_directory)) # Assigns the selected species/form animation resource to the shared renderer.
    behaviour_state = BehaviourState.ENTERING # Ensures the first movement phase walks inward from the map edge.
    previous_position = global_position # Initializes progress tracking from the actual spawn point.
    configured = world_builder != null # Enables physics only when a valid generated-world service exists.
    if configured: # Builds the first route only after a valid world reference has been stored.
        _set_destination(initial_target) # Routes the new visitor from the map edge toward its initial interior position.

func _physics_process(delta: float) -> void: # Advances behaviour, route following, gravity, collision response, and directional animation each physics frame.
    if not configured: # Guards the brief scene-tree period before setup completes or a structurally invalid spawn.
        return # Avoids moving or animating with incomplete runtime data.
    var camera: Camera3D = get_viewport().get_camera_3d() # Reads the active camera for camera-relative HGSS facing selection.
    if camera == null: # Guards startup or transition frames where no active camera exists.
        return # Delays character processing until a camera is available.
    _update_behaviour(delta) # Advances arrival, lingering, wandering, pausing, and departure decisions.
    _advance_path_if_needed() # Selects the next A* turning-point waypoint whenever the current waypoint has been reached.
    var desired_velocity: Vector3 = _get_desired_horizontal_velocity() # Converts the current route waypoint into a horizontal travel request.
    velocity.x = move_toward(velocity.x, desired_velocity.x, acceleration * delta) # Smoothly approaches the desired X movement speed.
    velocity.z = move_toward(velocity.z, desired_velocity.z, acceleration * delta) # Smoothly approaches the desired Z movement speed.
    if is_on_floor(): # Keeps roaming Pokémon attached to generated terrain and slopes.
        velocity.y = -0.1 # Applies a small downward bias so floor contact remains stable.
    else: # Applies gravity whenever the character leaves the ground.
        velocity.y -= gravity * delta # Integrates vertical acceleration into the body's velocity.
    move_and_slide() # Moves the CharacterBody3D while resolving generated terrain, player, and Pokémon collision.
    visual.update_motion(get_real_velocity(), camera) # Selects idle or walk animation and camera-relative facing from actual resulting motion.
    _update_stall_detection(delta) # Replans movement when another character creates a persistent local deadlock.
    if behaviour_state == BehaviourState.LEAVING and _has_reached_destination(): # Detects a departing Pokémon reaching its visible route-edge destination.
        queue_free() # Removes the temporary character after it has walked back to a map exit.

func _update_behaviour(delta: float) -> void: # Advances the finite-state behaviour without coupling it to rendering.
    if behaviour_state == BehaviourState.ENTERING: # Handles the initial route from a map edge toward the interior.
        if _has_reached_destination(): # Detects when the Pokémon has successfully entered the generated world.
            behaviour_state = BehaviourState.HANGING_OUT # Switches to the temporary idle-and-wander phase.
            _begin_idle_pause() # Lets the Pokémon settle briefly before choosing its first local destination.
        return # Prevents hangout timers from starting before arrival is complete.
    if behaviour_state == BehaviourState.LEAVING: # Keeps the departure destination fixed once the Pokémon has decided to go.
        return # Allows route following to continue without new wander choices.
    hangout_time_remaining -= delta # Counts down the total amount of time this Pokémon will remain in the world.
    if hangout_time_remaining <= 0.0: # Detects when the temporary visit has finished.
        _begin_leaving() # Chooses the nearest route gate and switches permanently to departure behaviour.
        return # Stops hangout decision processing after departure begins.
    if idle_time_remaining > 0.0: # Checks whether the Pokémon is intentionally pausing between movements.
        idle_time_remaining = maxf(idle_time_remaining - delta, 0.0) # Counts the pause down without accumulating a negative value.
        if idle_time_remaining <= 0.0: # Detects the end of the current pause.
            _set_destination(_choose_wander_target()) # Builds an A* route to another nearby walkable generated-world cell.
        return # Keeps the character stationary for the rest of an active idle pause.
    if _has_reached_destination(): # Detects arrival at the current wandering destination after every route waypoint has been followed.
        _begin_idle_pause() # Stops for a short random interval before wandering again.

func _get_desired_horizontal_velocity() -> Vector3: # Calculates horizontal travel while respecting deliberate idle pauses and the current route waypoint.
    if behaviour_state == BehaviourState.HANGING_OUT and idle_time_remaining > 0.0: # Detects an intentional stationary hangout moment.
        return Vector3.ZERO # Lets acceleration decelerate the Pokémon smoothly to a stop.
    var to_target: Vector3 = movement_target - global_position # Measures displacement from the Pokémon to its active A* waypoint.
    to_target.y = 0.0 # Keeps steering horizontal while physics follows generated terrain height.
    if to_target.length_squared() <= target_reach_distance * target_reach_distance: # Avoids normalizing extremely small waypoint vectors.
        return Vector3.ZERO # Stops horizontal movement until path progression selects the next waypoint.
    return to_target.normalized() * move_speed # Travels toward the waypoint at this Pokémon's individual roaming speed.

func _set_destination(destination: Vector3) -> void: # Builds or rebuilds a compact shared-grid route to one final generated-world destination.
    destination_position = destination # Stores the final behaviour destination separately from intermediate route corners.
    movement_path = HgssWorldNavigation.get_world_path(world_builder, global_position, destination_position) # Requests a route that avoids water and hard forest cells.
    movement_path_index = 0 # Starts every newly calculated route from its first turning-point waypoint.
    if movement_path.is_empty(): # Handles a same-cell route or an unexpectedly disconnected destination.
        movement_target = destination_position # Falls back to short direct steering rather than freezing in place.
        return # Stops before indexing an empty route.
    movement_target = movement_path[0] # Begins steering toward the first compressed A* waypoint.

func _advance_path_if_needed() -> void: # Moves to the next A* waypoint after the current one has been reached.
    if movement_path.is_empty(): # Treats a direct fallback destination as a one-step route.
        return # Leaves movement_target equal to destination_position.
    if not _has_reached_waypoint(): # Keeps the current route waypoint while meaningful travel remains.
        return # Avoids changing direction prematurely.
    if movement_path_index >= movement_path.size() - 1: # Detects arrival at the final stored A* waypoint.
        movement_target = destination_position # Preserves the exact final destination used by behaviour completion checks.
        return # Leaves the completed path in place until behaviour selects another destination.
    movement_path_index += 1 # Advances to the next route corner or final cell centre.
    movement_target = movement_path[movement_path_index] # Steers the CharacterBody3D toward the newly selected waypoint.

func _begin_idle_pause() -> void: # Starts a natural stationary period between local roaming routes.
    idle_time_remaining = random.randf_range(1.25, 4.5) # Gives the Pokémon enough time to visibly hang out rather than constantly pace.
    movement_path.clear() # Removes the completed route so deliberate stillness has no stale waypoints.
    destination_position = global_position # Treats the current position as the final destination during the pause.
    movement_target = global_position # Keeps steering intent stationary throughout the deliberate pause.
    stalled_time = 0.0 # Clears stale progress state while the Pokémon is intentionally stationary.

func _begin_leaving() -> void: # Chooses a generated-world route edge and permanently switches into departure behaviour.
    behaviour_state = BehaviourState.LEAVING # Prevents any further idle or wandering decisions after departure begins.
    idle_time_remaining = 0.0 # Cancels an active pause so departure starts immediately.
    var off_map_exit: Vector3 = world_builder.get_exit_target_from(global_position) # Uses the off-map helper point only to determine which gateway is nearest.
    var solid_exit: Vector3 = world_builder.get_nearest_walkable_world_position(off_map_exit) # Converts that gateway to its nearest solid route-edge cell.
    _set_destination(solid_exit) # Routes around rivers and forest instead of steering straight through obstacles.
    stalled_time = 0.0 # Gives the departure route a fresh dynamic-obstacle timer.

func _choose_wander_target() -> Vector3: # Chooses a nearby walkable destination that respects water, forest blockers, and generated elevation.
    return world_builder.get_random_walkable_world_position_near(global_position, random.randf_range(4.0, 9.0), random) # Delegates terrain policy to the world builder instead of reproducing map rules here.

func _update_stall_detection(delta: float) -> void: # Detects local movement deadlocks caused by the player or other roaming Pokémon.
    if behaviour_state == BehaviourState.HANGING_OUT and idle_time_remaining > 0.0: # Ignores progress while the Pokémon is intentionally idle.
        previous_position = global_position # Keeps the reference position current without accumulating stalled time.
        stalled_time = 0.0 # Clears any prior movement stall.
        return # Avoids treating deliberate stillness as navigation failure.
    var moved_squared: float = global_position.distance_squared_to(previous_position) # Measures actual physics displacement since the previous update.
    if moved_squared < 0.0004 and not _has_reached_waypoint(): # Detects a character that wants to move but is making essentially no progress.
        stalled_time += delta # Counts how long the dynamic obstruction persists.
    else: # Resets the timer whenever useful movement occurs or the waypoint is reached.
        stalled_time = 0.0 # Clears accumulated stall duration.
    previous_position = global_position # Stores the current location for the next physics update.
    if stalled_time < 1.5: # Allows short collisions with other roaming characters to resolve naturally.
        return # Keeps the existing A* route while the obstruction is brief.
    stalled_time = 0.0 # Resets the timer before recalculating movement intent.
    if behaviour_state == BehaviourState.HANGING_OUT: # Gives free-roaming characters permission to choose another local destination around a crowd.
        _set_destination(_choose_wander_target()) # Chooses and routes toward another nearby safe cell.
        return # Stops after assigning the replacement hangout route.
    _set_destination(destination_position) # Recalculates the same arrival or departure route from the character's current cell after a persistent obstruction.

func _has_reached_waypoint() -> bool: # Tests arrival at the current intermediate A* waypoint using horizontal distance only.
    var offset: Vector3 = movement_target - global_position # Measures the remaining displacement to the active route waypoint.
    offset.y = 0.0 # Ignores vertical differences caused by generated hills and floor snapping.
    return offset.length_squared() <= target_reach_distance * target_reach_distance # Uses squared distance to avoid a square root in the per-frame waypoint test.

func _has_reached_destination() -> bool: # Tests whether the final behaviour destination has been reached after route following.
    var offset: Vector3 = destination_position - global_position # Measures the remaining displacement to the final requested position.
    offset.y = 0.0 # Ignores vertical differences caused by generated hills and floor snapping.
    return offset.length_squared() <= target_reach_distance * target_reach_distance # Uses squared distance to keep this per-frame completion test inexpensive.
