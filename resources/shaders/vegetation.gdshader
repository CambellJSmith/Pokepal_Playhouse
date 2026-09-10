shader_type spatial; // Lights the merged vegetation meshes in the existing renderer.
render_mode cull_disabled; // Renders thin leaves and blades from either side.

varying float height_shade; // Carries ground-to-canopy colour variation.

void vertex() { // Applies gentle wind entirely on the GPU.
    vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; // Gives every plant a stable wind phase.
    float sway = sin(TIME * 1.15 + world.x * 0.22 + world.z * 0.17); // Creates slow traveling gusts.
    VERTEX.x += sway * UV.y * 0.075; // Bends foliage while keeping trunks and roots anchored.
    VERTEX.z += cos(TIME * 0.86 + world.x * 0.15) * UV.y * 0.04; // Adds a smaller crosswind movement.
    height_shade = clamp(UV.y, 0.0, 1.0); // Retains the leaf weight for subtle colour shading.
} // Ends vegetation movement.

void fragment() { // Preserves authored bark and foliage colours within a shared mesh.
    ALBEDO = COLOR.rgb * mix(0.91, 1.06, height_shade); // Darkens roots and brightens the exposed canopy.
    ROUGHNESS = 0.95; // Gives organic surfaces a soft dry response.
    SPECULAR = 0.16; // Prevents plastic-looking leaves.
} // Ends vegetation shading.
