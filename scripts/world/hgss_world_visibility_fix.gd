class_name HgssWorldVisibilityFix # Applies a defensive rendering fix to generated terrain after the world builder has created its meshes.
extends Node # Runs once after the world-builder sibling has completed its ready step.

func _ready() -> void: # Makes generated terrain double-sided so procedural winding cannot hide the world from the camera.
    var world_builder: HgssWorldBuilder = get_tree().get_first_node_in_group(&"world_builder") as HgssWorldBuilder # Resolves the generated world through its semantic group rather than a fragile scene path.
    if world_builder == null: # Detects a malformed main scene with no generated-world component.
        push_error("HgssWorldVisibilityFix could not find the world builder.") # Makes a missing world-builder dependency obvious in the debugger.
        return # Stops because there are no generated terrain meshes to inspect.
    var terrain_mesh_count: int = 0 # Tracks how many generated terrain mesh nodes were successfully found.
    for child: Node in world_builder.get_children(): # Inspects only runtime children created by the world builder.
        if not child is MeshInstance3D: # Ignores collision and other generated helper nodes.
            continue # Moves directly to the next generated child.
        var mesh_instance: MeshInstance3D = child as MeshInstance3D # Narrows the generated child to the terrain renderer type.
        if not mesh_instance.name.begins_with("terrain_"): # Leaves non-terrain meshes untouched if more generated visuals are added later.
            continue # Keeps this workaround narrowly scoped to procedural ground surfaces.
        terrain_mesh_count += 1 # Records one visible terrain batch for startup diagnostics.
        var terrain_mesh: Mesh = mesh_instance.mesh # Reads the procedural ArrayMesh through its Mesh base API.
        if terrain_mesh == null: # Guards an unexpectedly empty generated renderer.
            continue # Leaves the invalid renderer for the final diagnostic rather than throwing another error.
        for surface_index: int in range(terrain_mesh.get_surface_count()): # Applies the fix to every material surface in the generated batch.
            var material: Material = terrain_mesh.surface_get_material(surface_index) # Reads the material assigned by SurfaceTool during world construction.
            if material is BaseMaterial3D: # Restricts the setting to Godot's 3D material family that exposes culling control.
                var base_material: BaseMaterial3D = material as BaseMaterial3D # Narrows the material so the cull property is statically available.
                base_material.cull_mode = BaseMaterial3D.CULL_DISABLED # Draws both sides so the current procedural triangle winding remains visible from above.
    if terrain_mesh_count == 0: # Detects the distinct failure mode where the builder never produced visual terrain at all.
        push_error("HGSS world builder produced no terrain MeshInstance3D children. Check the debugger for an earlier world-generation error.") # Gives the next debugging step directly in Godot's output.
