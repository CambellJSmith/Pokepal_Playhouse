class_name HgssTileGallery # Displays converted PDSMS HGSS tiles and smart-drawing groups so their real IDs can be verified visually.
extends Node3D # Keeps the inspection scene entirely separate from the playable world.

enum GalleryMode { TILES, SMART_GRIDS } # Switches between the complete tile catalog and the PDSMS smart-drawing groups.

const CATALOG_PATH: String = "res://assets/world/hgss/pdsms/generated/catalog.json" # Points at the local generated catalog produced by the setup script.
const GENERATED_ROOT: String = "res://assets/world/hgss/pdsms/generated" # Resolves generated mesh paths stored relative to the catalog.
const TILES_PER_PAGE: int = 48 # Keeps each inspection page small enough for stable editor rendering and readable labels.
const TILE_COLUMNS: int = 8 # Arranges ordinary tile pages into a compact grid.
const SLOT_SIZE: float = 8.0 # Leaves room for PDSMS tiles that span several logical map cells.

@onready var camera: Camera3D = $camera as Camera3D # Repositions the gallery camera whenever the page layout changes.
@onready var status_label: Label = $hud/margin/panel/text/status as Label # Shows current mode, page, and local setup problems.
@onready var instructions_label: Label = $hud/margin/panel/text/instructions as Label # Keeps the inspection controls visible while reviewing tiles.

var catalog: Dictionary = {} # Stores the generated tile metadata and PDSMS smart grids.
var tile_entries_by_id: Dictionary = {} # Maps integer tile IDs to their catalog entries for inexpensive smart-grid lookup.
var gallery_root: Node3D # Owns only the currently visible page so changing pages can free everything at once.
var gallery_mode: GalleryMode = GalleryMode.TILES # Starts with the complete catalog because it exposes every available source tile.
var page_index: int = 0 # Tracks the current tile page or smart-grid group.

func _ready() -> void: # Loads the local catalog and displays the first inspection page.
    instructions_label.text = "Left / Right  •  change page     G  •  tiles / smart grids" # Documents only controls used by this isolated tool scene.
    gallery_root = Node3D.new() # Creates a replaceable parent for page-local mesh and label nodes.
    gallery_root.name = "gallery_page" # Gives the runtime page a clear Remote Scene Tree name.
    add_child(gallery_root) # Parents page content beneath the inspection scene.
    if not _load_catalog(): # Detects a clone where the local PDSMS conversion has not been run yet.
        return # Leaves the explanatory HUD visible instead of producing repeated resource errors.
    _index_tiles() # Builds direct ID lookup before smart-grid inspection can request arbitrary tiles.
    _render_current_page() # Displays the first page after all local metadata is available.

func _unhandled_key_input(event: InputEvent) -> void: # Handles gallery-only keyboard navigation without adding permanent project input actions.
    var key_event: InputEventKey = event as InputEventKey # Narrows the event to physical keyboard input.
    if key_event == null or not key_event.pressed or key_event.echo: # Ignores releases, repeats, and non-keyboard events.
        return # Prevents one press from skipping multiple pages.
    if key_event.physical_keycode == KEY_LEFT: # Moves backward through the active gallery mode.
        _change_page(-1) # Wraps around when moving before the first page.
    elif key_event.physical_keycode == KEY_RIGHT: # Moves forward through the active gallery mode.
        _change_page(1) # Wraps around when moving beyond the final page.
    elif key_event.physical_keycode == KEY_G: # Toggles between individual tile pages and PDSMS smart-drawing groups.
        _toggle_mode() # Resets to the first page so mode changes remain predictable.

func _load_catalog() -> bool: # Reads the generated JSON without making the game depend on locally ignored source assets.
    if not FileAccess.file_exists(CATALOG_PATH): # Detects that setup_hgss_3d_tiles.sh has not produced local assets yet.
        status_label.text = "HGSS 3D tiles are not installed. Run: bash setup_hgss_3d_tiles.sh" # Gives the exact recovery command in the running scene.
        push_warning(status_label.text) # Mirrors the setup problem into Godot's Output panel.
        return false # Stops before attempting to load missing OBJ resources.
    var file: FileAccess = FileAccess.open(CATALOG_PATH, FileAccess.READ) # Opens the generated metadata as ordinary text.
    if file == null: # Guards filesystem permission or transient import failures.
        status_label.text = "Could not open generated HGSS tile catalog." # Keeps the visible failure concise.
        push_error(status_label.text) # Makes the failure easy to locate in the debugger.
        return false # Avoids parsing an invalid handle.
    var parsed: Variant = JSON.parse_string(file.get_as_text()) # Parses the converter's deterministic JSON catalog.
    if not parsed is Dictionary: # Rejects incomplete or manually corrupted catalog files.
        status_label.text = "Generated HGSS tile catalog is not valid JSON object data." # Explains which local artifact needs rebuilding.
        push_error(status_label.text) # Surfaces the malformed catalog in the debugger.
        return false # Prevents unsafe dictionary access below.
    catalog = parsed # Stores the validated dictionary for page rendering.
    return true # Reports that the local tile catalog is available.

func _index_tiles() -> void: # Builds an integer-keyed lookup used by smart-grid pages.
    tile_entries_by_id.clear() # Removes stale entries if the scene is reloaded after regenerating assets.
    var tile_entries: Array = catalog.get("tiles", []) # Reads the complete converter-generated tile list.
    for value: Variant in tile_entries: # Traverses catalog entries without assuming manually edited JSON is perfectly typed.
        if not value is Dictionary: # Ignores malformed entries instead of breaking the whole inspection tool.
            continue # Moves directly to the next catalog entry.
        var entry: Dictionary = value # Narrows the valid entry for typed dictionary access.
        var tile_id: int = int(entry.get("id", -1)) # Reads the source PDSMS tile index used throughout map data.
        if tile_id >= 0: # Rejects missing IDs that cannot be addressed by smart-grid data.
            tile_entries_by_id[tile_id] = entry # Stores one canonical catalog entry per PDSMS tile ID.

func _toggle_mode() -> void: # Switches inspection between all tiles and the smart-drawing group definitions embedded in the tileset.
    if gallery_mode == GalleryMode.TILES: # Detects the ordinary catalog view.
        gallery_mode = GalleryMode.SMART_GRIDS # Changes to the 5×3 PDSMS smart-grid definitions.
    else: # Handles returning from smart-grid inspection.
        gallery_mode = GalleryMode.TILES # Restores the complete sequential tile catalog.
    page_index = 0 # Starts each mode from its first page so screenshots are easy to discuss by index.
    _render_current_page() # Rebuilds visible content for the new mode.

func _change_page(direction: int) -> void: # Moves through the active gallery mode with wraparound.
    var page_count: int = _get_page_count() # Calculates mode-specific page count from the generated catalog.
    if page_count <= 0: # Guards a tileset with no usable tile or smart-grid metadata.
        return # Leaves the current diagnostic page unchanged.
    page_index = posmod(page_index + direction, page_count) # Wraps page navigation in both directions.
    _render_current_page() # Replaces only the current page content.

func _get_page_count() -> int: # Returns the number of pages available in the active inspection mode.
    if gallery_mode == GalleryMode.SMART_GRIDS: # Gives each embedded smart-grid definition its own page.
        var smart_grids: Array = catalog.get("smart_grids", []) # Reads all 5×3 smart-drawing groups from the converted PDSMS file.
        return smart_grids.size() # Uses one group per page so every tile ID remains readable.
    var tile_entries: Array = catalog.get("tiles", []) # Reads the full tile list for ordinary browsing.
    return int(ceil(float(tile_entries.size()) / float(TILES_PER_PAGE))) # Divides the catalog into fixed-size pages.

func _render_current_page() -> void: # Clears prior nodes and renders the selected tile or smart-grid page.
    for child: Node in gallery_root.get_children(): # Traverses only page-local inspection nodes.
        child.queue_free() # Releases previous meshes and labels before new content is added.
    if gallery_mode == GalleryMode.SMART_GRIDS: # Chooses the embedded PDSMS smart-drawing renderer.
        _render_smart_grid_page() # Displays one exact 5×3 tile-ID matrix from the source tileset.
    else: # Handles ordinary sequential tile inspection.
        _render_tile_page() # Displays up to forty-eight real source tiles with ID labels.

func _render_tile_page() -> void: # Displays one sequential catalog page using the real converted PDSMS meshes.
    var tile_entries: Array = catalog.get("tiles", []) # Reads all source tiles from the generated catalog.
    var first_index: int = page_index * TILES_PER_PAGE # Calculates the first catalog index visible on this page.
    var end_index: int = mini(first_index + TILES_PER_PAGE, tile_entries.size()) # Clamps the page to the final tile entry.
    for catalog_index: int in range(first_index, end_index): # Creates only nodes required by the active page.
        var value: Variant = tile_entries[catalog_index] # Reads one converter-generated tile entry.
        if not value is Dictionary: # Skips malformed metadata without hiding every other tile.
            continue # Moves to the next entry.
        var entry: Dictionary = value # Narrows the valid catalog object.
        var local_index: int = catalog_index - first_index # Converts catalog position into this page's compact grid coordinates.
        var column: int = local_index % TILE_COLUMNS # Selects the page-grid column.
        var row: int = local_index / TILE_COLUMNS # Selects the page-grid row.
        var tile_id: int = int(entry.get("id", -1)) # Reads the PDSMS source tile ID shown beneath the mesh.
        _add_tile(entry, Vector3(float(column) * SLOT_SIZE, 0.0, float(row) * SLOT_SIZE), "#" + str(tile_id)) # Places the real mesh and an unambiguous ID label.
    var page_count: int = maxi(_get_page_count(), 1) # Keeps status math valid for an unexpectedly empty catalog.
    status_label.text = "Tiles  •  page %d / %d  •  showing IDs %d–%d" % [page_index + 1, page_count, first_index, maxi(end_index - 1, first_index)] # Makes screenshots self-identifying.
    _position_camera_for_grid(TILE_COLUMNS, 6) # Frames the fixed page grid consistently while browsing.

func _render_smart_grid_page() -> void: # Displays one exact smart-grid matrix stored inside the PDSMS HGSS tileset.
    var smart_grids: Array = catalog.get("smart_grids", []) # Reads all source smart-drawing definitions.
    if smart_grids.is_empty(): # Detects a tileset that does not define smart drawing.
        status_label.text = "This PDSMS tileset contains no smart-grid groups." # Explains why the mode has nothing to display.
        return # Leaves the empty page intentionally.
    page_index = clampi(page_index, 0, smart_grids.size() - 1) # Keeps the selected group valid after any local catalog regeneration.
    var grid_value: Variant = smart_grids[page_index] # Reads the selected 5×3 source matrix.
    if not grid_value is Array: # Guards malformed generated JSON.
        status_label.text = "Smart-grid group %d is malformed." % page_index # Identifies the exact converter output needing inspection.
        return # Avoids unsafe nested array access.
    var grid: Array = grid_value # Narrows the valid matrix outer array.
    for x: int in range(grid.size()): # Traverses the source matrix's five columns.
        var column_value: Variant = grid[x] # Reads one vertical column of source tile IDs.
        if not column_value is Array: # Skips malformed columns while preserving the rest of the group.
            continue # Moves to the next smart-grid column.
        var column: Array = column_value # Narrows the nested array for typed iteration.
        for z: int in range(column.size()): # Traverses the source matrix's three rows.
            var tile_id: int = int(column[z]) # Reads the exact PDSMS tile ID assigned to this smart-drawing slot.
            if tile_id < 0 or not tile_entries_by_id.has(tile_id): # Preserves intentionally empty smart-grid slots without loading invalid meshes.
                _add_empty_slot(Vector3(float(x) * SLOT_SIZE, 0.0, float(z) * SLOT_SIZE), str(tile_id)) # Shows the empty source value so screenshots remain complete.
                continue # Moves to the next slot.
            var entry: Dictionary = tile_entries_by_id[tile_id] # Resolves the smart-grid ID to its converted tile metadata.
            _add_tile(entry, Vector3(float(x) * SLOT_SIZE, 0.0, float(z) * SLOT_SIZE), "#" + str(tile_id)) # Displays the exact mesh used by this source smart-drawing slot.
    status_label.text = "Smart grid %d / %d  •  screenshot this page when it represents a terrain family we should use" % [page_index + 1, smart_grids.size()] # Tells the local validation step exactly what information is useful.
    _position_camera_for_grid(5, 3) # Frames the smaller source matrix tightly.

func _add_tile(entry: Dictionary, world_position: Vector3, label_text: String) -> void: # Adds one converted mesh plus its source ID label to the current page.
    var relative_mesh_path: String = String(entry.get("mesh", "")) # Reads the converter-generated path relative to the local output root.
    if relative_mesh_path.is_empty(): # Rejects catalog entries without a generated mesh path.
        _add_empty_slot(world_position, label_text + " missing mesh") # Makes the bad entry visible in the gallery instead of silently omitting it.
        return # Stops before asking ResourceLoader for an empty path.
    var mesh_path: String = GENERATED_ROOT.path_join(relative_mesh_path) # Converts catalog-relative mesh paths into Godot resource paths.
    if not ResourceLoader.exists(mesh_path, "Mesh"): # Detects OBJ files that Godot has not imported yet or a failed local conversion.
        _add_empty_slot(world_position, label_text + " not imported") # Gives the tile's failure directly in the scene.
        return # Avoids repeated ResourceLoader error spam.
    var mesh: Mesh = ResourceLoader.load(mesh_path, "Mesh") as Mesh # Loads the imported static OBJ as the Mesh resource type documented by Godot.
    if mesh == null: # Guards an importer failure after the resource path was recognized.
        _add_empty_slot(world_position, label_text + " load failed") # Keeps the exact source ID visible for diagnosis.
        return # Stops before creating a renderer with no mesh.
    var mesh_instance: MeshInstance3D = MeshInstance3D.new() # Creates one temporary inspection renderer for this page.
    mesh_instance.name = "tile_" + label_text.trim_prefix("#") # Gives Remote Scene Tree entries the source tile ID where possible.
    mesh_instance.mesh = mesh # Assigns the actual converted PDSMS geometry and imported materials.
    mesh_instance.position = world_position # Places the tile on the gallery's X/Z grid without altering its source geometry.
    mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # Keeps the inspection scene inexpensive and visually clear.
    gallery_root.add_child(mesh_instance) # Adds the source mesh to the visible page.
    _add_label(world_position, label_text) # Adds a camera-facing source ID above the tile.

func _add_empty_slot(world_position: Vector3, label_text: String) -> void: # Preserves empty or failed source slots so smart-grid layouts remain spatially accurate.
    _add_label(world_position, label_text) # Uses the label itself as the diagnostic marker.

func _add_label(world_position: Vector3, label_text: String) -> void: # Adds a fixed-size camera-facing identifier above one gallery slot.
    var label: Label3D = Label3D.new() # Creates lightweight 3D text without adding UI nodes per tile.
    label.text = label_text # Displays the exact PDSMS tile ID or local import problem.
    label.font_size = 24 # Keeps IDs readable without dominating the source art.
    label.pixel_size = 0.012 # Scales the label into the gallery's world-unit range.
    label.fixed_size = true # Keeps source IDs legible across camera repositioning.
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED # Faces every identifier toward the inspection camera automatically.
    label.position = world_position + Vector3(0.0, 3.0, 0.0) # Lifts the label above typical low-profile HGSS terrain geometry.
    gallery_root.add_child(label) # Adds the identifier to the same disposable page container.

func _position_camera_for_grid(columns: int, rows: int) -> void: # Frames the active inspection layout from a consistent elevated HGSS-like angle.
    var width: float = maxf(float(columns - 1) * SLOT_SIZE, SLOT_SIZE) # Measures the visible grid width in world units.
    var depth: float = maxf(float(rows - 1) * SLOT_SIZE, SLOT_SIZE) # Measures the visible grid depth in world units.
    var centre: Vector3 = Vector3(width * 0.5, 0.0, depth * 0.5) # Finds the centre of the current page layout.
    camera.position = centre + Vector3(0.0, maxf(30.0, depth * 1.1), maxf(30.0, depth * 0.9)) # Places the camera far enough back for the largest ordinary page.
    camera.look_at(centre, Vector3.UP) # Aims directly at the page centre after every mode or page change.
