shader_type spatial; // Renders river and lake surfaces with ordinary scene lighting.
render_mode cull_disabled; // Keeps the water visible from free camera angles.

varying vec3 world_position; // Anchors moving ripples across separate water chunks.

void vertex() { // Preserves the level surface used by bridge and shore geometry.
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; // Supplies continuous ripple coordinates.
} // Ends water vertex preparation.

void fragment() { // Shades opaque water without screen-reading or transparency sorting.
    vec2 p = world_position.xz; // Uses horizontal world coordinates for the flow.
    float wave_a = sin(p.x * 1.1 + p.y * 0.31 + sin(p.y * 0.37) * 1.2 + TIME * 0.75); // Generates a broad traveling ripple.
    float wave_b = sin(p.y * 0.83 - p.x * 0.27 + sin(p.x * 0.21) - TIME * 0.56); // Breaks up the first ripple with crossing flow.
    float ripple = wave_a * 0.65 + wave_b * 0.35; // Combines the two independent wave directions.
    float shore = 1.0 - smoothstep(0.02, 0.85, UV2.y); // Measures shallow water using the actual bed depth.
    ALBEDO = mix(vec3(0.035, 0.14, 0.17), vec3(0.14, 0.27, 0.23), shore) + ripple * 0.002; // Blends deep water through shallow banks.
    ALBEDO += vec3(0.015, 0.022, 0.014) * pow(shore, 5.0) * (0.55 + ripple * 0.12); // Adds a restrained shoreline glint.
    NORMAL_MAP = vec3(0.5 + wave_a * 0.006, 0.5 + wave_b * 0.006, 1.0); // Perturbs reflected light without moving the shoreline.
    ROUGHNESS = 0.38; // Broadens the reflected sunlight.
    SPECULAR = 0.35; // Makes the water respond visibly to the sky and sun.
} // Ends water shading.
