shader_type spatial; // Shades continuous ground-aligned bridge decking.

void fragment() { // Draws restrained plank joints and wood grain along each crossing.
    float joint = smoothstep(0.94, 0.99, fract(UV.x * 3.2)); // Separates planks across the direction of travel.
    float grain = sin(UV.y * 45.0 + sin(UV.x * 9.0) * 1.4); // Adds fine irregular wood fibres along each plank.
    float variation = fract(sin(floor(UV.x * 3.2) * 12.31) * 413.17); // Varies the tone slightly between adjacent planks.
    ALBEDO = vec3(0.31, 0.23, 0.15) * (0.91 + variation * 0.12 + grain * 0.035) * mix(1.0, 0.46, joint); // Gives weathered wood a quiet natural surface.
    ROUGHNESS = 0.92; // Keeps the deck dry and softly lit.
    SPECULAR = 0.16; // Prevents polished highlights on ordinary timber.
} // Ends bridge surface shading.
