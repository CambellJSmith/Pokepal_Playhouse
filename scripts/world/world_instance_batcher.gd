class_name WorldInstanceBatcher # Groups repeated scenery into independently culled spatial batches.
extends RefCounted # Keeps batching outside the scene's frame-processing lifecycle.

const CHUNK_SIZE: float = 48.0 # Controls the spatial granularity of scenery visibility.

static func build(parent: Node3D, label: String, mesh: Mesh, transforms: Array[Transform3D], view_distance: float = 0.0, shadows: bool = true) -> void: # Creates bounded instance groups sharing one reusable mesh.
    var chunks: Dictionary[Vector2i, Array] = {} # Collects transforms by horizontal spatial region.
    for transform: Transform3D in transforms: # Assigns every prepared object to one chunk.
        var key: Vector2i = Vector2i(floori(transform.origin.x / CHUNK_SIZE), floori(transform.origin.z / CHUNK_SIZE)) # Computes its stable chunk address.
        if not chunks.has(key): # Allocates each chunk only when it contains scenery.
            chunks[key] = [] # Starts an empty transform collection.
        chunks[key].append(transform) # Retains the complete object transform.
    for key: Vector2i in chunks: # Emits one render object for each occupied chunk.
        var entries: Array = chunks[key] # Reads this chunk's prepared transforms.
        var multi: MultiMesh = MultiMesh.new() # Allocates the shared GPU instance resource.
        multi.transform_format = MultiMesh.TRANSFORM_3D # Enables full three-dimensional transforms.
        multi.mesh = mesh # Shares the same source geometry across all chunks.
        multi.instance_count = entries.size() # Allocates the exact required instance capacity.
        var origin: Vector3 = Vector3(float(key.x) * CHUNK_SIZE, 0.0, float(key.y) * CHUNK_SIZE) # Keeps local chunk coordinates compact.
        var bounds: AABB = AABB() # Accumulates actual transformed mesh bounds for safe culling.
        for index: int in range(entries.size()): # Uploads each transform once during generation.
            var transform: Transform3D = entries[index] # Reads one typed scenery transform.
            transform.origin -= origin # Converts the object position to chunk-local space.
            multi.set_instance_transform(index, transform) # Uploads its fixed placement to the GPU.
            var item_bounds: AABB = transform * mesh.get_aabb() # Includes complete crowns, branches, and vertical extent.
            bounds = item_bounds if index == 0 else bounds.merge(item_bounds) # Extends the chunk bounds to include the object.
        multi.custom_aabb = bounds.grow(0.6) # Leaves space for shader-driven foliage movement.
        var instance: MultiMeshInstance3D = MultiMeshInstance3D.new() # Creates the scene's cullable render object.
        instance.name = "%s_%s_%s" % [label, key.x, key.y] # Gives chunks readable inspector names.
        instance.position = origin # Places the local transforms in their world region.
        instance.multimesh = multi # Attaches the prepared instance resource.
        instance.visibility_range_end = view_distance # Limits tiny detail while retaining distant tree silhouettes.
        instance.visibility_range_end_margin = 12.0 if view_distance > 0.0 else 0.0 # Adds visibility hysteresis around detail boundaries.
        instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # Reserves shadow rendering for substantial scenery.
        parent.add_child(instance) # Adds the completed chunk without per-frame script work.
