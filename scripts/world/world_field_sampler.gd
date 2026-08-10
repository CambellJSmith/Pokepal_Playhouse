class_name WorldFieldSampler # Samples deterministic continuous fields used by the procedural world generator.
extends RefCounted # Keeps generation math independent from the scene tree and rendering nodes.

const BIOME_NORMAL: int = 0 # Mirrors HgssWorldBuilder.BiomeKind without creating a circular script dependency.
const BIOME_FIRE: int = 1 # Mirrors the fire biome index used by the world layout.
const BIOME_WATER: int = 2 # Mirrors the water biome index used by the world layout.
const BIOME_ELECTRIC: int = 3 # Mirrors the electric biome index used by the world layout.
const BIOME_GRASS: int = 4 # Mirrors the grass biome index used by the world layout.
const BIOME_ICE: int = 5 # Mirrors the ice biome index used by the world layout.
const BIOME_FIGHTING: int = 6 # Mirrors the fighting biome index used by the world layout.
const BIOME_POISON: int = 7 # Mirrors the poison biome index used by the world layout.
const BIOME_GROUND: int = 8 # Mirrors the ground biome index used by the world layout.
const BIOME_FLYING: int = 9 # Mirrors the flying biome index used by the world layout.
const BIOME_PSYCHIC: int = 10 # Mirrors the psychic biome index used by the world layout.
const BIOME_BUG: int = 11 # Mirrors the bug biome index used by the world layout.
const BIOME_ROCK: int = 12 # Mirrors the rock biome index used by the world layout.
const BIOME_GHOST: int = 13 # Mirrors the ghost biome index used by the world layout.
const BIOME_DRAGON: int = 14 # Mirrors the dragon biome index used by the world layout.
const BIOME_DARK: int = 15 # Mirrors the dark biome index used by the world layout.
const BIOME_STEEL: int = 16 # Mirrors the steel biome index used by the world layout.

var world_seed: int # Stores the deterministic seed shared by every mathematical field in this sampler.
var biome_centers: Array[Vector2] = [] # Stores stable biome anchors while warped scoring creates irregular borders around them.
var macro_noise: FastNoiseLite = FastNoiseLite.new() # Produces broad rolling continental elevation.
var detail_noise: FastNoiseLite = FastNoiseLite.new() # Produces smaller terrain undulation without changing the macro silhouette.
var ridge_noise: FastNoiseLite = FastNoiseLite.new() # Produces mountain-chain ridges for rocky and high-altitude regions.
var badland_noise: FastNoiseLite = FastNoiseLite.new() # Produces sharper repeated forms for badlands and volcanic terrain.
var biome_warp_x: FastNoiseLite = FastNoiseLite.new() # Distorts biome coordinates horizontally so borders do not read as Voronoi polygons.
var biome_warp_y: FastNoiseLite = FastNoiseLite.new() # Distorts biome coordinates vertically using an independent field.
var biome_detail_noise: FastNoiseLite = FastNoiseLite.new() # Adds local variation to biome ownership scores.
var moisture_noise: FastNoiseLite = FastNoiseLite.new() # Supplies a continuous wetness field for biome scoring and vegetation density.
var temperature_noise: FastNoiseLite = FastNoiseLite.new() # Supplies a continuous temperature field for biome scoring.
var river_noise: FastNoiseLite = FastNoiseLite.new() # Supplies continuous zero-contours used as carved stream channels.
var forest_cluster_noise: FastNoiseLite = FastNoiseLite.new() # Supplies large vegetation clusters instead of independent random trees.
var forest_detail_noise: FastNoiseLite = FastNoiseLite.new() # Supplies local density variation within vegetation clusters.
var rock_cluster_noise: FastNoiseLite = FastNoiseLite.new() # Supplies clustered rocky outcrops driven by terrain character.
var grass_cluster_noise: FastNoiseLite = FastNoiseLite.new() # Supplies broad grass and ground-cover patches.
var color_noise: FastNoiseLite = FastNoiseLite.new() # Supplies subtle terrain color breakup without texture assets.
var route_noise: FastNoiseLite = FastNoiseLite.new() # Supplies smooth deterministic lateral route curvature.

func _init(seed_value: int, centers: Array[Vector2]) -> void: # Configures every independent field from one deterministic world seed.
    world_seed = seed_value # Stores the requested seed so all later field queries remain reproducible.
    for center: Vector2 in centers: # Copies biome anchors into a strongly typed local array.
        biome_centers.append(center) # Preserves the source ordering expected by the biome constants above.
    _configure_noise(macro_noise, 11, 0.010, FastNoiseLite.FRACTAL_FBM, 5, 0.48, 2.05, true, 15.0) # Builds broad domain-warped elevation.
    _configure_noise(detail_noise, 23, 0.035, FastNoiseLite.FRACTAL_FBM, 4, 0.50, 2.15, true, 5.0) # Builds smaller terrain undulation.
    _configure_noise(ridge_noise, 37, 0.020, FastNoiseLite.FRACTAL_RIDGED, 5, 0.52, 2.10, true, 9.0) # Builds coherent mountain ridges.
    _configure_noise(badland_noise, 47, 0.052, FastNoiseLite.FRACTAL_PING_PONG, 4, 0.53, 2.25, true, 5.0) # Builds sharper eroded-looking bands.
    _configure_noise(biome_warp_x, 61, 0.012, FastNoiseLite.FRACTAL_FBM, 3, 0.48, 2.00, false, 0.0) # Builds the horizontal biome warp field.
    _configure_noise(biome_warp_y, 71, 0.012, FastNoiseLite.FRACTAL_FBM, 3, 0.48, 2.00, false, 0.0) # Builds the vertical biome warp field.
    _configure_noise(biome_detail_noise, 83, 0.027, FastNoiseLite.FRACTAL_FBM, 3, 0.50, 2.00, true, 4.0) # Builds local biome-boundary irregularity.
    _configure_noise(moisture_noise, 97, 0.009, FastNoiseLite.FRACTAL_FBM, 4, 0.50, 2.00, true, 10.0) # Builds broad wet and dry regions.
    _configure_noise(temperature_noise, 109, 0.008, FastNoiseLite.FRACTAL_FBM, 4, 0.48, 2.00, true, 8.0) # Builds broad warm and cold regions.
    _configure_noise(river_noise, 127, 0.014, FastNoiseLite.FRACTAL_FBM, 3, 0.48, 2.05, true, 14.0) # Builds meandering continuous stream contours.
    _configure_noise(forest_cluster_noise, 149, 0.018, FastNoiseLite.FRACTAL_FBM, 4, 0.52, 2.00, true, 9.0) # Builds large forest masses and clearings.
    _configure_noise(forest_detail_noise, 163, 0.075, FastNoiseLite.FRACTAL_FBM, 3, 0.52, 2.10, false, 0.0) # Builds fine vegetation breakup.
    _configure_noise(rock_cluster_noise, 181, 0.040, FastNoiseLite.FRACTAL_RIDGED, 4, 0.50, 2.10, true, 5.0) # Builds grouped exposed-stone fields.
    _configure_noise(grass_cluster_noise, 199, 0.026, FastNoiseLite.FRACTAL_FBM, 4, 0.52, 2.00, true, 6.0) # Builds broad ground-cover patches.
    _configure_noise(color_noise, 223, 0.090, FastNoiseLite.FRACTAL_FBM, 3, 0.48, 2.00, false, 0.0) # Builds low-cost vertex-color variation.
    _configure_noise(route_noise, 241, 0.020, FastNoiseLite.FRACTAL_FBM, 3, 0.50, 2.00, false, 0.0) # Builds smooth route curvature independent from terrain noise.

func sample_biome(local: Vector2) -> int: # Resolves an irregular but contiguous type region from warped distance and climate fields.
    var warped_local: Vector2 = local + Vector2(biome_warp_x.get_noise_2d(local.x, local.y), biome_warp_y.get_noise_2d(local.x + 211.0, local.y - 137.0)) * 13.0 # Warps coordinates before measuring region ownership.
    var moisture: float = sample_moisture(local) # Reads wetness once for all biome score comparisons.
    var temperature: float = sample_temperature(local) # Reads temperature once for all biome score comparisons.
    var detail_x: float = biome_detail_noise.get_noise_2d(local.x, local.y) # Samples one shared boundary-irregularity axis instead of querying noise separately for every biome.
    var detail_y: float = biome_detail_noise.get_noise_2d(local.x + 173.0, local.y - 229.0) # Samples a second independent axis used to decorrelate biome boundary scores cheaply.
    var best_biome: int = BIOME_NORMAL # Falls back to the central Normal region if no candidate improves the score.
    var best_score: float = INF # Starts above every practical distance score.
    for biome_kind: int in range(biome_centers.size()): # Evaluates every type-region anchor using the same continuous fields.
        var center: Vector2 = biome_centers[biome_kind] # Reads the stable anchor for this candidate region.
        var distance_score: float = warped_local.distance_to(center) # Preserves broad contiguous ownership around each anchor.
        var detail_phase: float = float(biome_kind) * 2.399963229728653 # Uses a golden-angle phase so neighboring biome scores receive decorrelated combinations of the shared noise axes.
        var detail_score: float = (detail_x * cos(detail_phase) + detail_y * sin(detail_phase)) * 5.5 # Roughens boundaries with only two noise samples per world position.
        var climate_score: float = _climate_bias(biome_kind, moisture, temperature) # Slightly favors biomes where the environmental fields make sense.
        var score: float = distance_score + detail_score + climate_score # Combines broad placement, irregularity, and environmental preference.
        if score < best_score: # Detects the strongest ownership score at this position.
            best_score = score # Stores the improved score for subsequent comparisons.
            best_biome = biome_kind # Stores the region that currently owns this position.
    return best_biome # Returns the deterministic type region selected by the continuous field competition.

func sample_height(local: Vector2) -> float: # Produces continuous terrain from layered warped noise, regional landforms, and river carving.
    var macro: float = macro_noise.get_noise_2d(local.x, local.y) * 1.35 # Establishes broad rolling elevation across the whole map.
    var detail: float = detail_noise.get_noise_2d(local.x, local.y) * 0.34 # Adds smaller terrain undulation without overwhelming the macro terrain.
    var ridge: float = clampf((ridge_noise.get_noise_2d(local.x, local.y) + 1.0) * 0.5, 0.0, 1.0) # Converts ridged noise into a stable positive mountain mask.
    var badland: float = clampf((badland_noise.get_noise_2d(local.x, local.y) + 1.0) * 0.5, 0.0, 1.0) # Converts ping-pong noise into repeated erosion-like forms.
    var height: float = macro + detail # Starts with terrain shared continuously by every biome.
    var rock_weight: float = _region_weight(local, BIOME_ROCK, 42.0) # Measures influence from the Rock mountain range.
    var dragon_weight: float = _region_weight(local, BIOME_DRAGON, 39.0) # Measures influence from the Dragon peaks.
    var ice_weight: float = _region_weight(local, BIOME_ICE, 38.0) # Measures influence from the elevated Ice shelf.
    var flying_weight: float = _region_weight(local, BIOME_FLYING, 39.0) # Measures influence from the Flying plateau.
    var fire_weight: float = _region_weight(local, BIOME_FIRE, 39.0) # Measures influence from the volcanic basin.
    var ground_weight: float = _region_weight(local, BIOME_GROUND, 42.0) # Measures influence from the eroded Ground badlands.
    var fighting_weight: float = _region_weight(local, BIOME_FIGHTING, 34.0) # Measures influence from the Fighting plateau.
    var steel_weight: float = _region_weight(local, BIOME_STEEL, 34.0) # Measures influence from the Steel district shelf.
    var psychic_weight: float = _region_weight(local, BIOME_PSYCHIC, 32.0) # Measures influence from the Psychic garden rise.
    var grass_weight: float = _region_weight(local, BIOME_GRASS, 38.0) # Measures influence from rolling forest terrain.
    var ghost_weight: float = _region_weight(local, BIOME_GHOST, 36.0) # Measures influence from the Ghost hollow depression.
    var water_weight: float = _region_weight(local, BIOME_WATER, 42.0) # Measures influence from the Water district basin.
    var poison_weight: float = _region_weight(local, BIOME_POISON, 38.0) # Measures influence from Poison marsh lowlands.
    height += rock_weight * (1.6 + ridge * 6.2) # Raises the Rock region into multiple connected ridges instead of one rounded mound.
    height += dragon_weight * (2.0 + ridge * 6.8) # Makes Dragon one of the world's highest and sharpest regions.
    height += ice_weight * (2.7 + ridge * 1.5) # Creates a broad high glacial shelf with subdued ridge breakup.
    height += flying_weight * (3.0 + macro * 0.35) # Creates an open high plateau with broad rather than noisy relief.
    height += fire_weight * (2.6 + ridge * 2.4) # Raises the volcanic basin rim using the shared ridge field.
    height -= _region_weight(local, BIOME_FIRE, 12.0) * 4.2 # Cuts a real central crater into the raised volcanic region.
    height += ground_weight * (1.5 + (badland - 0.35) * 2.5) # Creates repeated badland ridges from a dedicated sharp field.
    height += fighting_weight * 1.7 # Raises the Fighting region into a broad traversable plateau.
    height += steel_weight * 1.5 # Raises the Steel region into a comparatively level industrial shelf.
    height += psychic_weight * 0.9 # Gives the Psychic region a gentle garden rise rather than a dramatic mountain.
    height += grass_weight * detail * 0.7 # Gives the forest rolling local terrain while keeping its macro silhouette soft.
    height -= ghost_weight * 1.3 # Creates a broad hollow around the Ghost region.
    height -= water_weight * 1.8 # Creates a coherent low basin where lakes and channels can occupy low terrain.
    height -= poison_weight * 0.9 # Keeps the Poison region low enough to support marsh pools.
    var river_strength: float = sample_river_strength(local) # Measures proximity to a continuous generated stream contour.
    var moisture: float = sample_moisture(local) # Reads local wetness so dry highlands are less aggressively carved.
    height -= river_strength * clampf((moisture + 1.0) * 0.42, 0.15, 0.75) # Carves shallow channels into the same terrain field used for later water placement.
    return height # Returns one continuous elevation value without biome-border steps.

func sample_moisture(local: Vector2) -> float: # Returns a stable wetness field in approximately the FastNoiseLite negative-to-positive range.
    return moisture_noise.get_noise_2d(local.x, local.y) # Samples the broad domain-warped moisture field.

func sample_temperature(local: Vector2) -> float: # Returns a broad temperature field with a small north-south gradient.
    var noise_value: float = temperature_noise.get_noise_2d(local.x, local.y) # Samples the continuous temperature variation.
    var latitude_bias: float = clampf(-local.y / 180.0, -0.45, 0.45) # Adds a gentle geographic trend without overriding local noise.
    return clampf(noise_value + latitude_bias, -1.0, 1.0) # Keeps the combined field within a predictable range for scoring.

func sample_river_strength(local: Vector2) -> float: # Returns a narrow continuous mask around zero-contours of the river field.
    var river_signal: float = absf(river_noise.get_noise_2d(local.x, local.y)) # Measures distance in noise-value space from a meandering zero contour.
    return clampf(1.0 - river_signal / 0.075, 0.0, 1.0) # Converts the signal into a soft channel mask used by terrain and water.

func is_water(local: Vector2, biome_kind: int, terrain_height: float, water_level: float) -> bool: # Decides where carved low terrain receives visible water.
    var river_strength: float = sample_river_strength(local) # Reuses the exact channel field that already carved the terrain.
    var moisture: float = sample_moisture(local) # Uses wetness to suppress streams through extremely dry terrain.
    if biome_kind == BIOME_WATER: # Gives the dedicated Water region the broadest connected water coverage.
        var basin_water: bool = terrain_height < water_level + 0.62 and moisture > -0.55 # Fills sufficiently low basin terrain while preserving islands and banks.
        var channel_water: bool = river_strength > 0.70 and terrain_height < water_level + 0.85 # Keeps narrow channels connected around the larger basin.
        return basin_water or channel_water # Combines lake-like basin water and meandering channels.
    if biome_kind == BIOME_POISON: # Gives the Poison biome shallow fragmented marsh water.
        return terrain_height < water_level + 0.34 and moisture > 0.02 and river_strength > 0.22 # Restricts pools to wet low ground near drainage contours.
    var natural_stream: bool = river_strength > 0.83 and moisture > 0.08 and terrain_height < water_level + 0.42 # Allows occasional narrow streams to cross ordinary regions.
    return natural_stream # Returns only terrain-driven streams outside the two water-heavy biomes.

func sample_tree_density(local: Vector2, biome_kind: int) -> float: # Returns clustered tree probability before route, slope, and deterministic spacing rules are applied.
    var cluster: float = clampf((forest_cluster_noise.get_noise_2d(local.x, local.y) + 1.0) * 0.5, 0.0, 1.0) # Creates large coherent forest masses and clearings.
    var detail: float = clampf((forest_detail_noise.get_noise_2d(local.x, local.y) + 1.0) * 0.5, 0.0, 1.0) # Breaks up density locally inside those masses.
    var moisture: float = clampf((sample_moisture(local) + 1.0) * 0.5, 0.0, 1.0) # Converts wetness into a vegetation-friendly positive range.
    var base_density: float = 0.08 # Gives ordinary regions sparse occasional trees instead of uniform empty ground.
    match biome_kind: # Assigns type-specific forest character without hardcoding individual tree positions.
        BIOME_GRASS: # Makes the Grass biome the broadest living forest.
            base_density = 0.86 # Sets a high capacity for dense tree clusters and deliberate clearings.
        BIOME_BUG: # Makes the Bug biome a lighter but still substantial woodland.
            base_density = 0.72 # Leaves more navigable gaps than the Grass forest.
        BIOME_DARK: # Makes the Dark biome a dense enclosed forest.
            base_density = 0.90 # Allows the strongest tree concentration in favorable field regions.
        BIOME_GHOST: # Gives the Ghost hollow sparse dead-looking woodland coverage.
            base_density = 0.34 # Keeps sightlines more open around ruins and depressions.
        BIOME_NORMAL: # Gives the central meadow a small amount of edge vegetation.
            base_density = 0.18 # Preserves the meadow identity while avoiding a completely empty plane.
        BIOME_WATER, BIOME_POISON: # Adds limited bank vegetation to wet regions.
            base_density = 0.20 # Keeps shoreline and marsh trees occasional rather than dominant.
        BIOME_PSYCHIC: # Adds controlled garden-like clusters to the Psychic region.
            base_density = 0.22 # Keeps the region open enough for the landmark to read from a distance.
        _: # Keeps exposed mountain, plateau, volcanic, and industrial regions comparatively open.
            base_density = 0.07 # Allows only sparse isolated trees outside forest-oriented biomes.
    var clustered_density: float = base_density * lerpf(0.12, 1.15, cluster * cluster) # Converts low-frequency noise into clear masses and open spaces.
    return clampf(clustered_density * lerpf(0.55, 1.15, detail) * lerpf(0.65, 1.15, moisture), 0.0, 1.0) # Combines clustering, local breakup, and wetness into final probability.

func sample_rock_density(local: Vector2, biome_kind: int) -> float: # Returns clustered exposed-rock probability before slope and deterministic sampling are applied.
    var cluster: float = clampf((rock_cluster_noise.get_noise_2d(local.x, local.y) + 1.0) * 0.5, 0.0, 1.0) # Produces coherent outcrop groups rather than even random stones.
    var base_density: float = 0.10 # Gives ordinary terrain a small amount of natural stone detail.
    match biome_kind: # Assigns stronger outcrop fields to geologically exposed regions.
        BIOME_ROCK: # Makes the Rock region heavily outcropped.
            base_density = 0.82 # Supports repeated mountain stone clusters.
        BIOME_DRAGON: # Makes the Dragon peaks strongly rocky.
            base_density = 0.72 # Leaves enough clear ground for traversal between peaks.
        BIOME_GROUND: # Makes badlands visibly eroded and stone-rich.
            base_density = 0.56 # Adds substantial grouped boulder coverage.
        BIOME_FIRE: # Adds volcanic stone around the crater and basin.
            base_density = 0.48 # Keeps the region harsh without filling every cell.
        BIOME_ICE: # Adds exposed stone through the snow shelf.
            base_density = 0.26 # Keeps rock secondary to the open glacial character.
        BIOME_FLYING, BIOME_FIGHTING, BIOME_STEEL: # Adds sparse outcrops to raised plateaus.
            base_density = 0.24 # Breaks up broad shelves while keeping them readable.
        _: # Uses the ordinary low stone density elsewhere.
            base_density = 0.10 # Preserves subtle geological detail across softer regions.
    return clampf(base_density * lerpf(0.25, 1.20, cluster * cluster), 0.0, 1.0) # Converts the field into a clustered placement probability.

func sample_grass_density(local: Vector2, biome_kind: int) -> float: # Returns ground-cover density used for inexpensive MultiMesh grass clumps.
    var cluster: float = clampf((grass_cluster_noise.get_noise_2d(local.x, local.y) + 1.0) * 0.5, 0.0, 1.0) # Creates broad patches rather than uniform coverage.
    var moisture: float = clampf((sample_moisture(local) + 1.0) * 0.5, 0.0, 1.0) # Makes wetter ground naturally support denser cover.
    var base_density: float = 0.42 # Gives most soft-ground regions visible small-scale detail.
    if biome_kind in [BIOME_ROCK, BIOME_DRAGON, BIOME_GROUND, BIOME_FIRE, BIOME_ICE, BIOME_STEEL, BIOME_FLYING]: # Detects exposed stone and harsh regions.
        base_density = 0.10 # Keeps grass sparse where geology or climate should dominate.
    elif biome_kind in [BIOME_GRASS, BIOME_BUG, BIOME_NORMAL]: # Detects the strongest soft-ground regions.
        base_density = 0.72 # Supports dense but still patchy ground cover.
    return clampf(base_density * lerpf(0.30, 1.10, cluster) * lerpf(0.55, 1.10, moisture), 0.0, 1.0) # Returns final patch density after environmental modulation.

func sample_color_variation(local: Vector2) -> float: # Returns subtle signed terrain-color breakup for vertex shading.
    return color_noise.get_noise_2d(local.x, local.y) # Reuses one inexpensive continuous field across all terrain materials.

func sample_route_offset(edge_index: int, progress: float, edge_length: float) -> float: # Produces smooth lateral curvature while keeping route endpoints fixed on biome anchors.
    var safe_progress: float = clampf(progress, 0.0, 1.0) # Keeps mathematical route queries inside the intended edge interval.
    var phase: float = float((edge_index * 37 + world_seed) % 360) * PI / 180.0 # Gives each edge a deterministic phase without consuming mutable RNG state.
    var broad_wave: float = sin(safe_progress * TAU + phase) * 0.45 # Adds one readable broad bend over the route length.
    var secondary_wave: float = sin(safe_progress * TAU * 2.0 - phase * 0.63) * 0.18 # Adds a weaker second bend so routes do not all share one arc.
    var noise_value: float = route_noise.get_noise_2d(float(edge_index) * 43.0, safe_progress * 120.0) * 0.58 # Adds smooth irregularity without jagged cell-to-cell changes.
    var endpoint_falloff: float = sin(safe_progress * PI) # Forces zero lateral displacement at both connected biome centers.
    var amplitude: float = minf(edge_length * 0.085, 8.5) # Scales bends with route length while capping extreme detours.
    return (broad_wave + secondary_wave + noise_value) * endpoint_falloff * amplitude # Returns the final signed normal offset in local cell-space units.

func _configure_noise(noise: FastNoiseLite, seed_offset: int, frequency: float, fractal_type: int, octaves: int, gain: float, lacunarity: float, domain_warp: bool, warp_amplitude: float) -> void: # Applies consistent high-quality FastNoiseLite settings to one field.
    noise.seed = world_seed + seed_offset # Derives an independent deterministic stream from the shared world seed.
    noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH # Uses smooth simplex noise to reduce directional grid artifacts in heightmaps.
    noise.frequency = frequency # Sets the spatial scale appropriate to this field's role.
    noise.fractal_type = fractal_type # Selects FBM, ridged, or ping-pong octave combination for the field.
    noise.fractal_octaves = octaves # Sets detail depth without requiring manual repeated noise sampling.
    noise.fractal_gain = gain # Controls how strongly successive octaves contribute.
    noise.fractal_lacunarity = lacunarity # Controls how quickly successive octave frequencies increase.
    noise.domain_warp_enabled = domain_warp # Enables coordinate distortion only on fields that benefit from natural irregularity.
    if domain_warp: # Configures the built-in secondary warp field only when requested.
        noise.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX_REDUCED # Uses the cheaper smooth warp suitable for startup-time world generation.
        noise.domain_warp_amplitude = warp_amplitude # Sets maximum coordinate displacement for this field.
        noise.domain_warp_frequency = frequency * 0.65 # Keeps warping broader than the detail being sampled.
        noise.domain_warp_fractal_type = FastNoiseLite.DOMAIN_WARP_FRACTAL_PROGRESSIVE # Progressively warps octaves for coherent natural distortion.
        noise.domain_warp_fractal_octaves = 3 # Limits warp cost while still avoiding obviously regular noise structure.
        noise.domain_warp_fractal_gain = 0.5 # Keeps higher warp octaves progressively weaker.
        noise.domain_warp_fractal_lacunarity = 2.0 # Uses conventional octave spacing for stable broad distortion.

func _region_weight(local: Vector2, biome_kind: int, radius: float) -> float: # Returns a smooth radial influence used to blend large biome landforms without border seams.
    if biome_kind < 0 or biome_kind >= biome_centers.size(): # Guards malformed biome indices before reading an anchor.
        return 0.0 # Gives invalid regions no terrain influence.
    var distance: float = local.distance_to(biome_centers[biome_kind]) # Measures distance to the requested regional anchor.
    var normalized: float = clampf(1.0 - distance / radius, 0.0, 1.0) # Converts the radius into a normalized inside-to-outside weight.
    return normalized * normalized * (3.0 - 2.0 * normalized) # Applies smoothstep shaping for continuous first-order transitions.

func _climate_bias(biome_kind: int, moisture: float, temperature: float) -> float: # Nudges warped region ownership toward compatible climate without overriding geographic anchors.
    match biome_kind: # Applies only small score adjustments so every fixed type region remains guaranteed.
        BIOME_FIRE: # Prefers warm and relatively dry positions around the Fire anchor.
            return -temperature * 2.4 + moisture * 0.8 # Lowers the score in warm dry field pockets.
        BIOME_WATER: # Prefers wet terrain around the Water anchor.
            return -moisture * 2.2 # Lowers the score where the moisture field is positive.
        BIOME_GRASS, BIOME_BUG: # Prefers wet living terrain for forest-oriented regions.
            return -moisture * 1.5 # Slightly expands forest regions into wetter neighboring terrain.
        BIOME_ICE: # Prefers cold terrain around the Ice anchor.
            return temperature * 2.2 # Lowers the score where temperature is negative.
        BIOME_POISON: # Prefers wet lowland character around the Poison anchor.
            return -moisture * 1.7 # Slightly expands marsh ownership into wetter pockets.
        BIOME_GROUND: # Prefers dry terrain around the Ground anchor.
            return moisture * 1.4 # Lowers the score where moisture is negative.
        BIOME_DARK, BIOME_GHOST: # Prefers cooler damp terrain for darker regions.
            return temperature * 0.6 - moisture * 0.6 # Adds a subtle climate preference without changing their broad location.
        _: # Leaves other region ownership primarily controlled by warped distance.
            return 0.0 # Applies no climate score adjustment to neutral cases.
