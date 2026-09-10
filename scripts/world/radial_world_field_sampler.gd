class_name RadialWorldFieldSampler # Defines the deterministic infinite radial world topology and terrain fields.
extends RefCounted # Keeps infinite world mathematics independent from streamed scene nodes.

const BIOME_NORMAL: int = 0 # Uses Normal as the neutral central hub for existing habitat systems.
const OUTER_BIOMES: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16] # Places every non-Normal Generation IV type around the hub.
const CENTER_RADIUS_CELLS: float = 80.0 # Gives the neutral centre a large circular footprint before outer type territory begins.
const CENTER_EDGE_VARIATION: float = 10.0 # Makes the neutral-to-type boundary organic instead of geometrically circular.
const SECTOR_COUNT: int = 16 # Matches the number of non-Normal Generation IV type regions.
const SECTOR_ANGLE: float = TAU / float(SECTOR_COUNT) # Gives every outer type exactly the same mean angular share.
const ROUTE_HALF_WIDTH: float = 1.55 # Defines the core width of the radial and ring routes in terrain cells.

var world_seed: int # Stores the deterministic seed used by every radial field.
var height_noise: FastNoiseLite = FastNoiseLite.new() # Produces broad continuous landform variation at any world coordinate.
var detail_noise: FastNoiseLite = FastNoiseLite.new() # Adds smaller terrain variation without changing region topology.
var ridge_noise: FastNoiseLite = FastNoiseLite.new() # Supplies stronger relief for mountain-oriented type regions.
var boundary_noise: FastNoiseLite = FastNoiseLite.new() # Blobs the neutral hub boundary around its mean radius.
var sector_noise: FastNoiseLite = FastNoiseLite.new() # Warps outer sector borders gradually as distance from the centre increases.
var scatter_noise: FastNoiseLite = FastNoiseLite.new() # Supplies deterministic vegetation density for streamed chunks.

func _init(seed_value: int) -> void: # Configures all infinite fields from one stable world seed.
    world_seed = seed_value # Retains the seed so chunk-local hashes can remain reproducible.
    _configure_noise(height_noise, 11, 0.010, FastNoiseLite.FRACTAL_FBM, 4) # Creates broad rolling terrain with low-frequency continuity.
    _configure_noise(detail_noise, 29, 0.038, FastNoiseLite.FRACTAL_FBM, 3) # Adds moderate local surface variation.
    _configure_noise(ridge_noise, 47, 0.021, FastNoiseLite.FRACTAL_RIDGED, 4) # Creates coherent mountain ridges for highland regions.
    _configure_noise(boundary_noise, 71, 0.018, FastNoiseLite.FRACTAL_FBM, 3) # Gives the central neutral boundary a broad irregular outline.
    _configure_noise(sector_noise, 97, 0.006, FastNoiseLite.FRACTAL_FBM, 3) # Makes type borders meander slowly while preserving equal average sector width.
    _configure_noise(scatter_noise, 131, 0.027, FastNoiseLite.FRACTAL_FBM, 2) # Produces broad patches for streamed scenery placement.

func sample_biome(cell_position: Vector2) -> int: # Resolves one neutral hub or one infinite outer type sector from world coordinates.
    var radius: float = cell_position.length() # Measures distance from the centre independently of loaded chunk bounds.
    var neutral_edge: float = get_neutral_boundary_radius(cell_position) # Reads the blobbed central boundary in this direction.
    if radius <= neutral_edge: # Keeps every point inside the centre assigned to the neutral hub.
        return BIOME_NORMAL # Uses the established Normal biome index for neutral gameplay compatibility.
    var angle: float = fposmod(atan2(cell_position.y, cell_position.x), TAU) # Converts the outer world position into a stable polar angle.
    var warp: float = sector_noise.get_noise_2d(cell_position.x, cell_position.y) * SECTOR_ANGLE * 0.28 # Lets borders wobble without allowing one type to dominate the ring.
    var warped_angle: float = fposmod(angle + warp + SECTOR_ANGLE * 0.5, TAU) # Centres sectors on evenly spaced radial axes.
    var sector_index: int = clampi(floori(warped_angle / SECTOR_ANGLE), 0, SECTOR_COUNT - 1) # Chooses one of sixteen equal mean outer sectors.
    return OUTER_BIOMES[sector_index] # Returns a type region that continues indefinitely away from the centre.

func get_neutral_boundary_radius(cell_position: Vector2) -> float: # Returns the organic neutral-hub radius for one world direction.
    var radius: float = maxf(cell_position.length(), 0.001) # Avoids division problems at the exact world origin.
    var direction: Vector2 = cell_position / radius # Samples boundary noise by direction so the outline stays stable at every distance.
    var sample_point: Vector2 = direction * CENTER_RADIUS_CELLS # Anchors noise around the mean circumference rather than the queried radius.
    var variation: float = boundary_noise.get_noise_2d(sample_point.x, sample_point.y) * CENTER_EDGE_VARIATION # Produces smooth inward and outward lobes.
    return CENTER_RADIUS_CELLS + variation # Returns the final blobbed central boundary radius.

func get_biome_axis_angle(biome_kind: int) -> float: # Returns the evenly spaced centre angle for an outer type region.
    var outer_index: int = OUTER_BIOMES.find(biome_kind) # Resolves the stable radial slot assigned to this type.
    if outer_index < 0: # Handles the neutral hub and unexpected biome values.
        return 0.0 # Uses the positive X axis as an irrelevant neutral fallback.
    return float(outer_index) * SECTOR_ANGLE # Returns the centre line that continues outward forever through this type region.

func get_biome_landmark_cell(biome_kind: int) -> Vector2: # Places one landmark near the inner edge of each infinite type world.
    if biome_kind == BIOME_NORMAL: # Keeps the neutral landmark at the centre of the shared hub.
        return Vector2.ZERO # Places Heartstone Plaza at the world origin.
    var angle: float = get_biome_axis_angle(biome_kind) # Reads the type region's evenly spaced radial axis.
    var radius: float = CENTER_RADIUS_CELLS + 24.0 # Places the landmark inside its type territory while remaining near the central hub.
    return Vector2(cos(angle), sin(angle)) * radius # Returns a deterministic ring of outer landmarks.

func sample_route_distance(cell_position: Vector2) -> float: # Measures distance to the circular hub route or nearest infinite radial route.
    var radius: float = cell_position.length() # Measures radial position for both route families.
    var ring_distance: float = absf(radius - (CENTER_RADIUS_CELLS - 12.0)) # Creates one complete route around the inside of the neutral boundary.
    var radial_distance: float = INF # Starts above any useful route distance before testing outer axes.
    if radius >= CENTER_RADIUS_CELLS - 14.0: # Starts outward routes near the hub ring instead of cutting across the central plaza.
        var angle: float = atan2(cell_position.y, cell_position.x) # Reads the queried polar angle once for all sector axes.
        for outer_index: int in range(SECTOR_COUNT): # Tests the centre line of every infinite outer type sector.
            var axis_angle: float = float(outer_index) * SECTOR_ANGLE # Resolves this type world's outward route direction.
            var delta: float = wrapf(angle - axis_angle, -PI, PI) # Finds the shortest angular separation from this axis.
            if absf(delta) > PI * 0.5: # Rejects the backwards half-line because each route extends outward only.
                continue # Leaves the opposite side to its own type sector route.
            radial_distance = minf(radial_distance, absf(sin(delta)) * radius) # Converts angular separation into perpendicular cell distance from the ray.
    return minf(ring_distance, radial_distance) # Returns the nearest route family for terrain shading and grade smoothing.

func sample_height(cell_position: Vector2) -> float: # Produces continuous terrain at arbitrary coordinates without a finite height cache.
    var biome_kind: int = sample_biome(cell_position) # Resolves regional terrain character directly from the infinite topology.
    var broad: float = height_noise.get_noise_2d(cell_position.x, cell_position.y) # Samples broad terrain once at the requested coordinate.
    var detail: float = detail_noise.get_noise_2d(cell_position.x, cell_position.y) # Samples smaller-scale relief once at the requested coordinate.
    var ridge: float = clampf((ridge_noise.get_noise_2d(cell_position.x, cell_position.y) + 1.0) * 0.5, 0.0, 1.0) # Converts ridged noise into a predictable positive contribution.
    var height: float = 1.2 + broad * 2.1 + detail * 0.65 # Establishes the shared rolling base used continuously across every region boundary.
    if biome_kind != BIOME_NORMAL: # Adds regional relief only outside the shared neutral hub.
        var relief_weight: float = _get_outer_relief_weight(cell_position) # Fades type-specific elevation to zero at both radial and neighboring-type boundaries.
        height += _get_biome_relief(biome_kind, broad, detail, ridge) * relief_weight # Preserves distinct regional terrain without introducing boundary cliffs.
    var route_distance: float = sample_route_distance(cell_position) # Reads proximity to an infinite route at the same coordinate.
    if route_distance < 4.5: # Softens severe local noise where characters are expected to travel frequently.
        var route_weight: float = 1.0 - smoothstep(ROUTE_HALF_WIDTH, 4.5, route_distance) # Blends from full route grade into natural terrain.
        var route_base: float = 1.35 + broad * 1.1 # Keeps routes following macro terrain without small steep noise.
        height = lerpf(height, route_base, route_weight * 0.72) # Makes radial travel paths consistently easier to traverse.
    if biome_kind == BIOME_NORMAL: # Keeps the shared central neutral area calmer than the infinite type worlds.
        var neutral_edge: float = get_neutral_boundary_radius(cell_position) # Reads the actual blobbed central boundary for a matching transition.
        var centre_weight: float = 1.0 - smoothstep(0.0, maxf(neutral_edge, 1.0), cell_position.length()) # Increases flattening smoothly toward the world origin.
        height = lerpf(height, 1.0 + broad * 0.55, centre_weight * 0.78) # Produces a broad welcoming neutral basin around the central plaza.
    return height # Returns the deterministic terrain elevation for this global cell coordinate.

func sample_scatter(cell_position: Vector2) -> float: # Returns deterministic broad scenery density at any infinite-world coordinate.
    return scatter_noise.get_noise_2d(cell_position.x, cell_position.y) # Uses one reusable noise field so chunk seams do not affect placement.

func get_biome_color(biome_kind: int) -> Color: # Returns the restrained terrain palette used by streamed radial chunks.
    match biome_kind: # Maps each existing biome index to a stable ground colour.
        0: return Color(0.38, 0.48, 0.29, 1.0) # Uses neutral meadow green for the shared central hub.
        1: return Color(0.43, 0.22, 0.14, 1.0) # Uses volcanic earth for Fire.
        2: return Color(0.24, 0.42, 0.48, 1.0) # Uses cool damp ground for Water.
        3: return Color(0.48, 0.45, 0.22, 1.0) # Uses dry yellow-green ground for Electric.
        4: return Color(0.17, 0.39, 0.18, 1.0) # Uses deep forest green for Grass.
        5: return Color(0.79, 0.84, 0.83, 1.0) # Uses pale blue-grey ground for Ice.
        6: return Color(0.43, 0.28, 0.21, 1.0) # Uses warm plateau earth for Fighting.
        7: return Color(0.28, 0.33, 0.21, 1.0) # Uses muted marsh ground for Poison.
        8: return Color(0.49, 0.34, 0.18, 1.0) # Uses ochre badland earth for Ground.
        9: return Color(0.43, 0.52, 0.49, 1.0) # Uses cool open highland ground for Flying.
        10: return Color(0.35, 0.44, 0.29, 1.0) # Uses restrained garden green for Psychic.
        11: return Color(0.33, 0.40, 0.16, 1.0) # Uses mossy woodland ground for Bug.
        12: return Color(0.36, 0.34, 0.29, 1.0) # Uses weathered stone for Rock.
        13: return Color(0.22, 0.23, 0.29, 1.0) # Uses cold slate ground for Ghost.
        14: return Color(0.32, 0.33, 0.31, 1.0) # Uses muted highland stone for Dragon.
        15: return Color(0.16, 0.18, 0.17, 1.0) # Uses near-charcoal woodland ground for Dark.
        16: return Color(0.42, 0.44, 0.43, 1.0) # Uses mineral grey terrain for Steel.
    return Color(0.38, 0.48, 0.29, 1.0) # Falls back to the neutral central palette for unexpected values.

func _get_outer_relief_weight(cell_position: Vector2) -> float: # Fades type-specific elevation smoothly near neutral and neighboring-type borders.
    var radius: float = maxf(cell_position.length(), 0.001) # Measures distance from the hub while avoiding zero-radius division.
    var neutral_edge: float = get_neutral_boundary_radius(cell_position) # Reads the organic neutral boundary in this direction.
    var radial_weight: float = smoothstep(0.0, 12.0, radius - neutral_edge) # Introduces outer terrain character gradually after leaving the central hub.
    var angle: float = fposmod(atan2(cell_position.y, cell_position.x), TAU) # Resolves the raw polar angle at this coordinate.
    var warp: float = sector_noise.get_noise_2d(cell_position.x, cell_position.y) * SECTOR_ANGLE * 0.28 # Reuses exactly the same border warp as biome ownership.
    var sector_fraction: float = fposmod(angle + warp + SECTOR_ANGLE * 0.5, SECTOR_ANGLE) / SECTOR_ANGLE # Measures progress across the current warped type sector.
    var border_distance: float = minf(sector_fraction, 1.0 - sector_fraction) * 2.0 # Converts sector progress into zero-at-border and one-at-centre distance.
    var angular_weight: float = smoothstep(0.0, 0.34, border_distance) # Fades terrain character across a broad boundary band shared by neighboring types.
    return radial_weight * angular_weight # Requires both sufficient distance from the hub and sufficient interior distance from type borders.

func _get_biome_relief(biome_kind: int, broad: float, detail: float, ridge: float) -> float: # Returns the signed regional elevation character before boundary blending.
    match biome_kind: # Keeps type terrain identities compact and independent from topology math.
        1: return 2.2 + ridge * 3.5 # Builds elevated volcanic terrain for Fire.
        2: return -1.1 # Keeps the Water world visually lower without creating an abrupt basin wall.
        4: return detail * 0.8 # Adds organic rolling variation beneath Grass scenery.
        5: return 2.4 + broad * 0.8 # Produces a broad elevated Ice shelf.
        8: return ridge * 2.8 # Adds repeated Ground badland ridges.
        9: return 2.8 + broad * 0.6 # Raises the Flying world into open high terrain.
        12: return 3.0 + ridge * 6.0 # Gives the Rock world strong mountain relief.
        13: return -0.9 # Drops the Ghost world into a shallow hollow.
        14: return 4.0 + ridge * 7.0 # Makes the Dragon world the strongest highland terrain.
        15: return -0.35 # Keeps the Dark world comparatively sheltered.
        16: return 1.8 + broad * 0.35 # Gives the Steel world a flatter raised shelf.
    return 0.0 # Leaves remaining type worlds on the shared continuous base terrain.

func _configure_noise(noise: FastNoiseLite, salt: int, frequency: float, fractal_type: FastNoiseLite.FractalType, octaves: int) -> void: # Applies one compact deterministic FastNoiseLite configuration.
    noise.seed = world_seed + salt # Separates each field while preserving reproducibility from the world seed.
    noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH # Uses smooth simplex noise for continuous chunk boundaries.
    noise.frequency = frequency # Sets the physical feature scale for this field.
    noise.fractal_type = fractal_type # Selects ordinary or ridged multi-octave structure.
    noise.fractal_octaves = octaves # Limits sampling cost while retaining useful terrain complexity.
    noise.fractal_gain = 0.5 # Uses a conventional amplitude falloff between octaves.
    noise.fractal_lacunarity = 2.0 # Doubles feature frequency between successive octaves.
