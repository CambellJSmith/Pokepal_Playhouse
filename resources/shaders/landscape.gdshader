shader_type spatial; // Shades continuous terrain in world space.
render_mode diffuse_burley; // Keeps terrain lit by the scene's sun and sky.

uniform vec3 path_color = vec3(0.40, 0.34, 0.25); // Defines weathered earth on walking routes.
uniform float water_level = -0.62; // Aligns damp banks with the shared water surface.
varying vec3 world_position; // Carries stable surface coordinates across terrain chunks.
varying vec3 world_normal; // Carries slope information independently of the camera.

float hash(vec2 p) { // Produces repeatable fine surface variation.
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); // Scrambles the lattice coordinates.
} // Ends the lattice hash.

float noise(vec2 p) { // Interpolates a continuous natural surface pattern.
    vec2 i = floor(p); // Selects the surrounding lattice cell.
    vec2 f = fract(p); // Measures progress across that cell.
    f = f * f * (3.0 - 2.0 * f); // Softens the interpolation at cell boundaries.
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y); // Blends the four lattice corners.
} // Ends continuous surface noise.

void vertex() { // Computes coordinates shared by neighboring mesh chunks.
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; // Anchors surface detail to the landscape.
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL); // Retains the actual terrain slope.
} // Ends terrain vertex preparation.

void fragment() { // Blends soil, ground cover, exposed rock, and wet banks.
    vec2 p = world_position.xz; // Projects ground detail onto the landscape.
    float broad = noise(p * 0.17); // Breaks up large uniform areas.
    float grain = noise(p * 8.4); // Adds readable close ground detail.
    float path = 1.0 - smoothstep(0.85, 1.95, UV2.x + (broad - 0.5) * 0.28); // Feathers the route edges without changing navigation.
    float cliff = smoothstep(0.10, 0.43, 1.0 - world_normal.y); // Exposes rock on inclined faces.
    vec3 grass = COLOR.rgb * mix(0.91, 1.06, broad); // Modulates the smoothly blended biome palette.
    vec3 rock = vec3(0.32, 0.31, 0.28) * mix(0.94, 1.05, grain); // Provides neutral mineral detail.
    vec3 surface = mix(grass, rock, cliff * 0.74); // Blends geology through the ground cover.
    surface = mix(surface, path_color * mix(0.95, 1.05, grain), path); // Wears the route into the landscape.
    float wet = 1.0 - smoothstep(water_level + 0.12, water_level + 1.0, world_position.y); // Darkens the banks near standing water.
    ALBEDO = surface * mix(0.98, 1.02, grain) * mix(1.0, 0.72, wet); // Outputs restrained textured surface colour.
    ROUGHNESS = mix(0.96, 0.62, wet); // Gives damp earth a softer sheen.
    SPECULAR = 0.18; // Keeps ordinary ground from looking polished.
} // Ends landscape shading.
