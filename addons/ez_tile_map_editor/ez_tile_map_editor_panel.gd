@tool
extends Control

signal update_overlay

enum PaintTool { NONE, SEL, DRAW, LINE, RECT, BUCKET, PICK, ERASE }

@onready var draw_button: Button = %Draw
@onready var line_button: Button = %Line
@onready var rect_button: Button = %Rect
@onready var fill_button: Button = %Fill
@onready var pick_button: Button = %Pick
@onready var select_button: Button = %Select
@onready var erase_button: Button = %Erase
@onready var erase_all_button: Button = %EraseAll

@onready var layer_highlight: Button = %LayerHighlight
@onready var layer_grid: Button = %LayerGrid
@onready var layer_select: OptionButton = %LayerSelect

@onready var terrain_grid: HFlowContainer = %TerrainGrid
@onready var scroll_container: ScrollContainer = %TerrainScroll
@onready var empty_label: Label = %EmptyLabel

var tilemap: TileMapLayer = null:
	set(v):
		if tilemap and tilemap.visibility_changed.is_connected(_on_tilemap_visibility_changed):
			tilemap.visibility_changed.disconnect(_on_tilemap_visibility_changed)
		tilemap = v
		if tilemap:
			if not tilemap.visibility_changed.is_connected(_on_tilemap_visibility_changed):
				tilemap.visibility_changed.connect(_on_tilemap_visibility_changed)
		tileset = v.tile_set if v else null
		_update_layer_dropdown.call_deferred()
		_update_erase_buttons.call_deferred()

var tileset: TileSet = null:
	set(v):
		if tileset and tileset.changed.is_connected(_on_tileset_changed):
			tileset.changed.disconnect(_on_tileset_changed)
		tileset = v
		if tileset:
			if not tileset.changed.is_connected(_on_tileset_changed):
				tileset.changed.connect(_on_tileset_changed)
		_refresh_terrains()

var undo_manager: EditorUndoRedoManager

var flattened_terrains: Array[Dictionary] = []
var selected_index: int = -1
var paint_tool: PaintTool = PaintTool.DRAW
var _prev_tool: PaintTool = PaintTool.DRAW
var _tool_buttons: Array[Button] = []

var draw_overlay: bool = false
var mouse_down: bool = false
var mouse_start: Vector2i = Vector2i.ZERO
var mouse_current: Vector2i = Vector2i.ZERO
var mouse_prev: Vector2i = Vector2i.ZERO
var drag_erasing: bool = false
var selection_rect: Rect2i = Rect2i()
var drag_action_index: int = 0
var drag_action_count: int = 0
var plugin: EditorPlugin = null
var _native_tilemap_editor: Object = null
var _native_grid_button: BaseButton = null
var _native_highlight_button: BaseButton = null
var _syncing_native: bool = false

func _ready() -> void:
	select_button.icon = get_theme_icon("ToolSelect", "EditorIcons")
	draw_button.icon = get_theme_icon("Edit", "EditorIcons")
	line_button.icon = get_theme_icon("Line", "EditorIcons")
	rect_button.icon = get_theme_icon("Rectangle", "EditorIcons")
	fill_button.icon = get_theme_icon("Bucket", "EditorIcons")
	pick_button.icon = get_theme_icon("ColorPick", "EditorIcons")
	erase_button.icon = get_theme_icon("Eraser", "EditorIcons")
	erase_all_button.icon = get_theme_icon("Clear", "EditorIcons")
	erase_all_button.self_modulate = Color(1.0, 0.3, 0.3, 1.0)

	select_button.pressed.connect(_on_tool_changed.bind(PaintTool.SEL))
	draw_button.pressed.connect(_on_tool_changed.bind(PaintTool.DRAW))

	layer_highlight.icon = get_theme_icon("TileMapHighlightSelected", "EditorIcons")
	layer_grid.icon = get_theme_icon("Grid", "EditorIcons")
	line_button.pressed.connect(_on_tool_changed.bind(PaintTool.LINE))
	rect_button.pressed.connect(_on_tool_changed.bind(PaintTool.RECT))
	fill_button.pressed.connect(_on_tool_changed.bind(PaintTool.BUCKET))
	pick_button.pressed.connect(_on_tool_changed.bind(PaintTool.PICK))
	erase_button.pressed.connect(_on_tool_changed.bind(PaintTool.ERASE))
	erase_all_button.pressed.connect(_on_erase_all)

	layer_select.item_selected.connect(_on_layer_selected)
	layer_highlight.toggled.connect(_on_layer_highlight_toggled)
	layer_grid.toggled.connect(_on_layer_grid_toggled)

	draw_button.button_pressed = true
	_tool_buttons = [null, select_button, draw_button, line_button, rect_button, fill_button, pick_button, erase_button]
	_update_empty_state()

func _is_tilemap_editable() -> bool:
	return tilemap != null and tilemap.is_visible_in_tree()

func _update_empty_state() -> void:
	if not tilemap:
		empty_label.text = "No terrain sets defined.\nUse the TileSet bottom panel to add terrains."
		empty_label.visible = true
		scroll_container.visible = false
	elif not tilemap.is_visible_in_tree():
		empty_label.text = "The TileMapLayer is disabled or invisible"
		empty_label.visible = true
		scroll_container.visible = false
	elif not tileset or flattened_terrains.is_empty():
		empty_label.text = "No terrain sets defined.\nUse the TileSet bottom panel to add terrains."
		empty_label.visible = true
		scroll_container.visible = false
	else:
		empty_label.visible = false
		scroll_container.visible = true
	_update_tool_buttons()

func _update_tool_buttons() -> void:
	var editable := _is_tilemap_editable()

	draw_button.disabled = not editable
	line_button.disabled = not editable
	rect_button.disabled = not editable
	fill_button.disabled = not editable
	pick_button.disabled = not editable
	select_button.disabled = not editable

func _on_tilemap_visibility_changed() -> void:
	_update_empty_state.call_deferred()

func _on_tool_changed(tool: PaintTool) -> void:
	if paint_tool != PaintTool.PICK and paint_tool != PaintTool.SEL:
		_prev_tool = paint_tool
	paint_tool = tool
	selection_rect = Rect2i()
	_ensure_editor_select_mode()

func _select_tool_button(tool: PaintTool) -> void:
	paint_tool = tool
	if tool > 0 and tool < _tool_buttons.size():
		_tool_buttons[tool].button_pressed = true

func _on_tileset_changed() -> void:
	_refresh_terrains.call_deferred()

# ---- TERRAIN GRID ----

var _icon_cache: Dictionary = {}

func _refresh_terrains() -> void:
	for c in terrain_grid.get_children():
		terrain_grid.remove_child(c)
		c.free()
	flattened_terrains.clear()
	if not tileset:
		_update_empty_state()
		return
	_build_icon_cache()
	var terrain_count := 0
	for set_idx in tileset.get_terrain_sets_count():
		for ter_idx in tileset.get_terrains_count(set_idx):
			var name := tileset.get_terrain_name(set_idx, ter_idx)
			var color := tileset.get_terrain_color(set_idx, ter_idx)
			var key := "%d:%d" % [set_idx, ter_idx]
			var icon: Dictionary = _icon_cache.get(key, {})
			flattened_terrains.append({set = set_idx, idx = ter_idx, name = name, color = color, icon_texture = icon.get("texture", null)})
			terrain_count += 1
	if terrain_count == 0:
		_update_empty_state()
		return

	for i in flattened_terrains.size():
		_create_terrain_entry(flattened_terrains[i], i)
	if selected_index == -1 and flattened_terrains.size() > 0:
		selected_index = 0
	if selected_index >= flattened_terrains.size():
		selected_index = -1
	_update_empty_state()
	_update_selection_buttons()
	_update_erase_buttons.call_deferred()
	call_deferred("_update_layer_dropdown")

func _build_icon_cache() -> void:
	_icon_cache.clear()
	if not tileset:
		return
	for src_i in tileset.get_source_count():
		var source := tileset.get_source(tileset.get_source_id(src_i)) as TileSetAtlasSource
		if not source or not source.texture:
			continue
		for tile_i in source.get_tiles_count():
			var coord := source.get_tile_id(tile_i)
			for alt_i in source.get_alternative_tiles_count(coord):
				var alt_id := source.get_alternative_tile_id(coord, alt_i)
				var td: TileData = source.get_tile_data(coord, alt_id)
				if td and td.terrain_set >= 0:
					_cache_terrain_icon(td, source, coord, alt_id)

func _cache_terrain_icon(td: TileData, source: TileSetAtlasSource, coord: Vector2i, alt_id: int) -> void:
	var set_idx := td.terrain_set
	if set_idx < 0:
		return
	if td.terrain >= 0:
		var key_center := "%d:%d" % [set_idx, td.terrain]
		if not _icon_cache.has(key_center) and source.texture:
			_icon_cache[key_center] = _make_icon(source, coord)

func _make_icon(source: TileSetAtlasSource, coord: Vector2i) -> Dictionary:
	if not source or not source.texture:
		return {}
	var atlas_tex := AtlasTexture.new()
	atlas_tex.atlas = source.texture
	var region := source.get_tile_texture_region(coord, 0)
	atlas_tex.region = region
	return {texture = atlas_tex}

func _create_terrain_entry(data: Dictionary, index: int) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(72, 72)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_PASS

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 0)
	panel.add_child(inner)

	var tex := TextureRect.new()
	tex.custom_minimum_size = Vector2(68, 52)
	tex.size_flags_horizontal = Control.SIZE_FILL
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	if data.icon_texture:
		tex.texture = data.icon_texture
	inner.add_child(tex)

	var label := Label.new()
	label.text = data.name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	inner.add_child(label)

	panel.gui_input.connect(_on_entry_gui_input.bind(panel, index))
	terrain_grid.add_child(panel)

	if index == selected_index:
		_update_entry_style(panel, true)

func _on_entry_gui_input(event: InputEvent, panel: PanelContainer, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected_index = index
		_update_selection_buttons()

func _update_entry_style(panel: PanelContainer, selected: bool) -> void:
	if selected:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_color = Color(1.0, 1.0, 1.0, 0.8)
		style.content_margin_left = 0
		style.content_margin_right = 0
		style.content_margin_top = 0
		style.content_margin_bottom = 0
		panel.add_theme_stylebox_override("panel", style)
	else:
		var empty_style := StyleBoxFlat.new()
		empty_style.bg_color = Color(0, 0, 0, 0)
		empty_style.content_margin_left = 0
		empty_style.content_margin_right = 0
		empty_style.content_margin_top = 0
		empty_style.content_margin_bottom = 0
		panel.add_theme_stylebox_override("panel", empty_style)

func _update_selection_buttons() -> void:
	for i in terrain_grid.get_child_count():
		var panel := terrain_grid.get_child(i) as PanelContainer
		if not panel:
			continue
		_update_entry_style(panel, i == selected_index)

func _update_erase_buttons() -> void:
	pass

func _update_layer_dropdown() -> void:
	layer_select.clear()
	if not tilemap:
		layer_select.disabled = true
		return
	var root := EditorInterface.get_edited_scene_root()
	if not root:
		layer_select.disabled = true
		layer_select.add_item(tilemap.name)
		layer_select.select(0)
		return
	var siblings: Array[Node] = []
	_collect_visible_tilemap_layers(root, siblings)

	if siblings.size() <= 1:
		layer_select.disabled = true
		layer_select.add_item(tilemap.name)
		layer_select.select(0)
		return
	for i in siblings.size():
		var lyr: TileMapLayer = siblings[i]
		layer_select.add_item(lyr.name)
		if lyr == tilemap:
			layer_select.select(i)
	layer_select.disabled = false

func _collect_visible_tilemap_layers(node: Node, result: Array[Node]) -> void:
	for child in node.get_children():
		if child is TileMapLayer and child.visible:
			result.append(child)
		if child is Node:
			_collect_visible_tilemap_layers(child, result)

func _on_layer_selected(idx: int) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if not root:
		return
	var siblings: Array[Node] = []
	_collect_visible_tilemap_layers(root, siblings)
	if idx >= 0 and idx < siblings.size():
		EditorInterface.edit_node(siblings[idx])

func _on_layer_highlight_toggled(toggled: bool) -> void:
	if _syncing_native:
		return

	var settings := EditorInterface.get_editor_settings()
	settings.set_setting("editors/tiles_editor/highlight_selected_layer", toggled)
	settings.emit_changed()
	_toggle_native("Highlight Selected TileMap Layer", toggled)
	if plugin and plugin.has_method("_queue_overlay_redraw"):
		plugin._queue_overlay_redraw()
	update_overlay.emit()

func _on_layer_grid_toggled(toggled: bool) -> void:
	if _syncing_native:
		return

	var settings := EditorInterface.get_editor_settings()
	settings.set_setting("editors/tiles_editor/display_grid", toggled)
	settings.emit_changed()
	_toggle_native("Toggle grid visibility.", toggled)
	if plugin and plugin.has_method("_queue_overlay_redraw"):
		plugin._queue_overlay_redraw()
	update_overlay.emit()

func _toggle_native(tooltip: String, pressed: bool) -> void:
	var editor := _ensure_native_tilemap_editor()
	if editor:
		_find_and_toggle_in(editor, tooltip, pressed)
	else:
		_find_and_toggle_in(EditorInterface.get_base_control(), tooltip, pressed)

func _find_and_toggle_in(node: Node, tooltip: String, pressed: bool) -> void:
	for child in node.get_children():
		if child is BaseButton:
			var btn: BaseButton = child
			if btn.tooltip_text == tooltip:
				btn.set_pressed_no_signal(pressed)
				btn.toggled.emit(pressed)
				_connect_native_button(btn, tooltip)
				return
		_find_and_toggle_in(child, tooltip, pressed)

func _connect_native_button(btn: BaseButton, tooltip: String) -> void:
	if tooltip == "Toggle grid visibility.":
		if _native_grid_button != btn:
			if _native_grid_button and _native_grid_button.toggled.is_connected(_on_native_grid_toggled):
				_native_grid_button.toggled.disconnect(_on_native_grid_toggled)
			_native_grid_button = btn
			if not btn.toggled.is_connected(_on_native_grid_toggled):
				btn.toggled.connect(_on_native_grid_toggled)
	elif tooltip == "Highlight Selected TileMap Layer":
		if _native_highlight_button != btn:
			if _native_highlight_button and _native_highlight_button.toggled.is_connected(_on_native_highlight_toggled):
				_native_highlight_button.toggled.disconnect(_on_native_highlight_toggled)
			_native_highlight_button = btn
			if not btn.toggled.is_connected(_on_native_highlight_toggled):
				btn.toggled.connect(_on_native_highlight_toggled)
func _on_native_grid_toggled(pressed: bool) -> void:
	if _syncing_native:
		return
	_syncing_native = true

	layer_grid.set_pressed_no_signal(pressed)
	var settings := EditorInterface.get_editor_settings()
	settings.set_setting("editors/tiles_editor/display_grid", pressed)
	_syncing_native = false

func _on_native_highlight_toggled(pressed: bool) -> void:
	if _syncing_native:
		return
	_syncing_native = true

	layer_highlight.set_pressed_no_signal(pressed)
	var settings := EditorInterface.get_editor_settings()
	settings.set_setting("editors/tiles_editor/highlight_selected_layer", pressed)
	_syncing_native = false

func _ensure_native_tilemap_editor() -> Object:
	if _native_tilemap_editor and is_instance_valid(_native_tilemap_editor):
		return _native_tilemap_editor
	var editor_base := EditorInterface.get_base_control()
	_native_tilemap_editor = _find_tilemap_editor_in_tree(editor_base)
	return _native_tilemap_editor

func _find_tilemap_editor_in_tree(node: Node) -> Object:
	if node.name == "TileMap" and node.is_class("TileMapLayerEditor"):
		return node
	for child in node.get_children():
		var found := _find_tilemap_editor_in_tree(child)
		if found:
			return found
	return null

func about_to_be_visible() -> void:
	if tilemap and tileset != tilemap.tile_set:
		tileset = tilemap.tile_set
	var settings := EditorInterface.get_editor_settings()
	var hl := settings.get_setting("editors/tiles_editor/highlight_selected_layer")
	var grid := settings.get_setting("editors/tiles_editor/display_grid")

	layer_highlight.set_pressed_no_signal(hl)
	layer_grid.set_pressed_no_signal(grid)
	_update_empty_state()

func _get_selected_terrain() -> Dictionary:
	if selected_index >= 0 and selected_index < flattened_terrains.size():
		return flattened_terrains[selected_index]
	return {}

# ---- SAVE / RESTORE ----

func _save_cells(coords: Array) -> Dictionary:
	var state := {}
	for c in coords:
		var src := tilemap.get_cell_source_id(c)
		state[c] = {has_cell = src != -1, source_id = src if src != -1 else 0, atlas_coords = tilemap.get_cell_atlas_coords(c) if src != -1 else Vector2i.ZERO, alternative_tile = tilemap.get_cell_alternative_tile(c) if src != -1 else 0}
	return state

func _restore_cells(saved: Dictionary, tm: TileMapLayer) -> void:
	for c in saved:
		var s: Dictionary = saved[c]
		if s.has_cell:
			tm.set_cell(c, s.source_id, s.atlas_coords, s.alternative_tile)
		else:
			tm.erase_cell(c)

# ---- CANVAS INPUT ----

func canvas_input(event: InputEvent) -> bool:
	if not _is_tilemap_editable():
		return false
	if not tileset:
		return false
	if not event is InputEventMouse:
		return false
	if not _is_editor_select_mode():
		return false
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			return false

	var transform := _canvas_tilemap_transform()
	var pos: Vector2 = transform.affine_inverse() * event.position
	mouse_prev = mouse_current
	mouse_current = tilemap.local_to_map(pos)

	if event is InputEventMouseMotion:
		if mouse_current == mouse_prev:
			return false
		if not mouse_down:
			draw_overlay = true
			update_overlay.emit()
		elif mouse_down:
			draw_overlay = true
			update_overlay.emit()
			if paint_tool == PaintTool.DRAW or paint_tool == PaintTool.ERASE or drag_erasing:
				_do_paint_stroke()

	var released: bool = event is InputEventMouseButton and not event.pressed
	var clicked: bool = event is InputEventMouseButton and event.pressed

	if released:
		if not mouse_down:
			return false
		mouse_down = false
		if paint_tool == PaintTool.LINE or paint_tool == PaintTool.RECT:
			_commit_paint_action()
		elif paint_tool == PaintTool.SEL:
			selection_rect = Rect2i(mouse_start, mouse_current - mouse_start).abs()
		drag_erasing = false
		draw_overlay = false
		update_overlay.emit()
		return true

	if clicked:
		if paint_tool == PaintTool.SEL:
			if event.button_index == MOUSE_BUTTON_LEFT:
				mouse_down = true
				mouse_start = mouse_current
				mouse_prev = mouse_current
				selection_rect = Rect2i()
				draw_overlay = true
				update_overlay.emit()
			return true

		if event.button_index == MOUSE_BUTTON_RIGHT:
			drag_erasing = true
		elif event.button_index == MOUSE_BUTTON_LEFT:
			drag_erasing = paint_tool == PaintTool.ERASE
		else:
			return false

		if event.is_command_or_control_pressed() and not event.shift_pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_pick_at_mouse()
			return true

		if paint_tool == PaintTool.PICK and event.button_index == MOUSE_BUTTON_LEFT:
			if _pick_at_mouse():
				_select_tool_button(_prev_tool)
			return true

		mouse_down = true
		mouse_start = mouse_current
		mouse_prev = mouse_current
		draw_overlay = true
		update_overlay.emit()
		drag_action_index += 1
		drag_action_count = 0
		if paint_tool == PaintTool.BUCKET:
			_do_bucket_fill(drag_erasing)
			mouse_down = false
			draw_overlay = false
			update_overlay.emit()
		else:
			_do_paint_stroke()
		return true
	return false

func canvas_mouse_exited() -> void:
	draw_overlay = false
	update_overlay.emit()

func _commit_paint_action() -> void:
	if paint_tool != PaintTool.LINE and paint_tool != PaintTool.RECT:
		return
	if not undo_manager or not tileset:
		return
	var cells := _get_brush_cells()

	if cells.is_empty():
		return
	var saved := _save_cells(_expand_cells(cells))
	var t := _get_selected_terrain()
	if drag_erasing or selected_index < 0:
		undo_manager.create_action("Erase Action", UndoRedo.MERGE_DISABLE, tilemap)
		for c in cells:
			undo_manager.add_do_method(tilemap, "erase_cell", c)
		undo_manager.add_undo_method(self, "_restore_cells", saved, tilemap)
	else:
		undo_manager.create_action("Paint Action", UndoRedo.MERGE_DISABLE, tilemap)
		undo_manager.add_do_method(tilemap, "set_cells_terrain_connect", cells, t.set, t.idx, true)
		undo_manager.add_undo_method(self, "_restore_cells", saved, tilemap)
	undo_manager.commit_action()

func _do_paint_stroke() -> void:
	var cells := _get_stroke_cells()
	if cells.is_empty():
		return
	if not undo_manager:
		return
	var expand := _expand_cells(cells)
	var saved := _save_cells(expand)
	var t := _get_selected_terrain()
	if drag_erasing or selected_index < 0:
		undo_manager.create_action("Erase Terrain" + str(drag_action_index), UndoRedo.MERGE_ALL, tilemap, true)
		for c in cells:
			undo_manager.add_do_method(tilemap, "erase_cell", c)
		undo_manager.add_undo_method(self, "_restore_cells", saved, tilemap)
	elif not t.is_empty():
		undo_manager.create_action("Paint Terrain" + str(drag_action_index), UndoRedo.MERGE_ALL, tilemap, true)
		undo_manager.add_do_method(tilemap, "set_cells_terrain_connect", cells, t.set, t.idx, true)
		undo_manager.add_undo_method(self, "_restore_cells", saved, tilemap)
	else:
		return
	undo_manager.commit_action()
	drag_action_count += 1

func _get_stroke_cells() -> Array[Vector2i]:
	match paint_tool:
		PaintTool.DRAW, PaintTool.ERASE:
			if mouse_prev == mouse_current:
				return [mouse_current]
			return _bresenham_line(mouse_prev, mouse_current)
		PaintTool.RECT, PaintTool.LINE:
			return []
	return []

func _expand_cells(cells: Array[Vector2i]) -> Array:
	var all := {}
	for c in cells:
		all[c] = true
		for peering in [0, 3, 4, 7, 8, 11, 12, 15]:
			var nb := tilemap.get_neighbor_cell(c, peering)
			if nb != c:
				all[nb] = true
	return all.keys()

func _get_brush_cells() -> Array[Vector2i]:
	match paint_tool:
		PaintTool.DRAW:
			return [mouse_current]
		PaintTool.LINE:
			return _tileset_line(mouse_start, mouse_current)
		PaintTool.RECT:
			var area := Rect2i(mouse_start, mouse_current - mouse_start).abs()
			var cells: Array[Vector2i] = []
			for y in range(area.position.y, area.end.y + 1):
				for x in range(area.position.x, area.end.x + 1):
					cells.append(Vector2i(x, y))
			return cells
	return []

func _do_bucket_fill(erasing: bool) -> void:
	var cells := _flood_fill(mouse_current)
	if cells.is_empty():
		return
	if not undo_manager:
		return
	var saved := _save_cells(_expand_cells(cells))
	var t := _get_selected_terrain()
	if erasing or selected_index < 0:
		undo_manager.create_action("Erase Fill", UndoRedo.MERGE_DISABLE, tilemap)
		for c in cells:
			undo_manager.add_do_method(tilemap, "erase_cell", c)
		undo_manager.add_undo_method(self, "_restore_cells", saved, tilemap)
	elif not t.is_empty():
		undo_manager.create_action("Paint Fill", UndoRedo.MERGE_DISABLE, tilemap)
		undo_manager.add_do_method(tilemap, "set_cells_terrain_connect", cells, t.set, t.idx, true)
		undo_manager.add_undo_method(self, "_restore_cells", saved, tilemap)
	else:
		return
	undo_manager.commit_action()

func _flood_fill(start: Vector2i) -> Array:
	var target_src := tilemap.get_cell_source_id(start)
	var bounds := tilemap.get_used_rect()
	bounds = bounds.grow(1)
	var checked := {}
	var pending := [start]
	var result: Array[Vector2i] = []
	while not pending.is_empty():
		var p: Vector2i = pending.pop_front()
		if p in checked:
			continue
		checked[p] = true
		if not bounds.has_point(p):
			continue
		var src := tilemap.get_cell_source_id(p)
		if target_src == -1:
			if src != -1:
				continue
		elif src != target_src:
			continue
		result.append(p)
		for nb in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			pending.append(p + nb)
	return result

func _pick_at_mouse() -> bool:
	var td := tilemap.get_cell_tile_data(mouse_current)
	if not td:
		return false
	var ts := td.terrain_set
	var tr := td.terrain
	if ts < 0 or tr < 0:
		return false
	for i in flattened_terrains.size():
		var f: Dictionary = flattened_terrains[i]
		if f.set == ts and f.idx == tr:
			selected_index = i
			_update_selection_buttons()
			return true
	return false

# ---- CANVAS OVERLAY ----

func canvas_draw(overlay: Control) -> void:
	if not _is_tilemap_editable() or not tileset:
		return
	_draw_our_grid(overlay)

	if paint_tool == PaintTool.SEL:
		var sel := selection_rect
		if mouse_down:
			sel = Rect2i(mouse_start, mouse_current - mouse_start).abs()
		if sel.has_area():
			var transform := _canvas_tilemap_transform()
			var cell_size := tileset.tile_size
			var color := Color(0.2, 0.6, 1.0, 0.4)
			var outline_color := Color(0.3, 0.7, 1.0, 0.8)
			for x in range(sel.position.x, sel.position.x + sel.size.x):
				for y in range(sel.position.y, sel.position.y + sel.size.y):
					var c := Vector2i(x, y)
					var center := tilemap.map_to_local(c)
					var half := Vector2(cell_size) / 2.0
					var top_left := transform * (center - half)
					var top_right := transform * (center + Vector2(half.x, -half.y))
					var bottom_right := transform * (center + half)
					var bottom_left := transform * (center + Vector2(-half.x, half.y))
					overlay.draw_rect(Rect2(top_left, bottom_right - top_left), color)
					overlay.draw_line(top_left, top_right, outline_color, -1.0, false)
					overlay.draw_line(top_right, bottom_right, outline_color, -1.0, false)
					overlay.draw_line(bottom_right, bottom_left, outline_color, -1.0, false)
					overlay.draw_line(bottom_left, top_left, outline_color, -1.0, false)
		if not mouse_down:
			return
		return

	if not draw_overlay:
		return
	if not mouse_down:
		if paint_tool == PaintTool.PICK or paint_tool == PaintTool.ERASE:
			var td := tilemap.get_cell_tile_data(mouse_current)
			if not td or td.terrain_set < 0 or td.terrain < 0:
				return
	var color: Color
	if paint_tool == PaintTool.PICK:
		color = Color(0.2, 0.8, 1.0, 0.35)
	elif mouse_down and drag_erasing:
		color = Color(0.0, 0.0, 0.0, 0.35)
	elif paint_tool == PaintTool.ERASE or selected_index < 0:
		color = Color(0.0, 0.0, 0.0, 0.35)
	else:
		color = Color(1.0, 1.0, 1.0, 0.35)
	var cells: Array
	if paint_tool == PaintTool.BUCKET and not mouse_down:
		cells = _flood_fill(mouse_current)
	elif mouse_down:
		cells = _get_brush_cells()
	if cells.is_empty():
		cells = [mouse_current]
	var transform := _canvas_tilemap_transform()
	var cell_size := tileset.tile_size
	const HALF := 0.5
	var polygon := PackedVector2Array([Vector2(-HALF, -HALF), Vector2(HALF, -HALF), Vector2(HALF, HALF), Vector2(-HALF, HALF)])
	for c in cells:
		var cell_transform := Transform2D(0.0, cell_size, 0.0, tilemap.map_to_local(c))
		overlay.draw_colored_polygon(transform * cell_transform * polygon, color)

func _draw_our_grid(overlay: Control) -> void:
	var settings := EditorInterface.get_editor_settings()
	if not settings.get_setting("editors/tiles_editor/display_grid"):
		return

	var cell_size := tileset.tile_size
	var tform := _canvas_tilemap_transform()
	var inv := tform.affine_inverse()

	# Scale fading: hide grid when on-screen tile size < 5 pixels
	var hint_distance: Vector2 = tform.get_scale() * Vector2(cell_size)
	var scale_fading := minf(1.0, (minf(absf(hint_distance.x), absf(hint_distance.y)) - 5.0) / 5.0)
	if scale_fading <= 0.0:
		return

	# Calculate viewport bounds in tile space
	var viewport := EditorInterface.get_editor_viewport_2d()
	var screen_size := viewport.get_visible_rect().size
	var corners: Array = [
		inv * Vector2.ZERO,
		inv * Vector2(screen_size.x, 0),
		inv * Vector2(screen_size.x, screen_size.y),
		inv * Vector2(0, screen_size.y),
	]
	var screen_rect := Rect2i(tilemap.local_to_map(corners[0]), Vector2i.ZERO)
	for i: int in range(1, 4):
		screen_rect = screen_rect.expand(tilemap.local_to_map(corners[i]))
	screen_rect = screen_rect.grow(1)

	# Intersect with used rect, add fade margin of 5 cells
	var used_rect := tilemap.get_used_rect()
	const FADING := 5
	var intersected := used_rect.intersection(screen_rect)
	if not intersected.has_area():
		return
	var displayed_rect := intersected.grow(FADING)
	if displayed_rect.size.x <= 0 or displayed_rect.size.y <= 0:
		return

	# Performance clamp: max 100x100 cells visible
	const MAX_SIZE := 100
	if displayed_rect.size.x > MAX_SIZE:
		var excess := (displayed_rect.size.x - MAX_SIZE) / 2
		displayed_rect = Rect2i(displayed_rect.position.x + excess, displayed_rect.position.y, MAX_SIZE, displayed_rect.size.y)
	if displayed_rect.size.y > MAX_SIZE:
		var excess := (displayed_rect.size.y - MAX_SIZE) / 2
		displayed_rect = Rect2i(displayed_rect.position.x, displayed_rect.position.y + excess, displayed_rect.size.x, MAX_SIZE)

	# Default native grid color: Color(1.0, 0.5, 0.2, 0.5)
	var grid_color: Color = settings.get_setting("editors/tiles_editor/grid_color")

	# Square tile shape: draw 4-line outline per cell (matches native renderer)
	if tileset.tile_shape == TileSet.TILE_SHAPE_SQUARE:
		for x in range(displayed_rect.position.x, displayed_rect.position.x + displayed_rect.size.x):
			for y in range(displayed_rect.position.y, displayed_rect.position.y + displayed_rect.size.y):
				var pos_in_rect := Vector2i(x, y) - displayed_rect.position

				# Fade out at edges: 5-cell gradient
				var left_opacity := clampf(inverse_lerp(0.0, float(FADING), float(pos_in_rect.x)), 0.0, 1.0)
				var right_opacity := clampf(inverse_lerp(float(displayed_rect.size.x), float(displayed_rect.size.x - FADING), float(pos_in_rect.x + 1)), 0.0, 1.0)
				var top_opacity := clampf(inverse_lerp(0.0, float(FADING), float(pos_in_rect.y)), 0.0, 1.0)
				var bottom_opacity := clampf(inverse_lerp(float(displayed_rect.size.y), float(displayed_rect.size.y - FADING), float(pos_in_rect.y + 1)), 0.0, 1.0)
				var opacity := clampf(minf(left_opacity, minf(right_opacity, minf(top_opacity, bottom_opacity))) + 0.1, 0.0, 1.0)

				var center := tilemap.map_to_local(Vector2i(x, y))
				var half := Vector2(cell_size) / 2.0
				var top_left := tform * (center - half)
				var top_right := tform * (center + Vector2(half.x, -half.y))
				var bottom_right := tform * (center + half)
				var bottom_left := tform * (center + Vector2(-half.x, half.y))

				var color := grid_color
				color.a *= opacity * scale_fading

				overlay.draw_line(top_left, top_right, color, -1.0, false)
				overlay.draw_line(top_right, bottom_right, color, -1.0, false)
				overlay.draw_line(bottom_right, bottom_left, color, -1.0, false)
				overlay.draw_line(bottom_left, top_left, color, -1.0, false)
	else:
		# Non-square shapes: use per-cell polyline outline
		var polygon: PackedVector2Array = _get_tile_shape_polygon()
		for x in range(displayed_rect.position.x, displayed_rect.position.x + displayed_rect.size.x):
			for y in range(displayed_rect.position.y, displayed_rect.position.y + displayed_rect.size.y):
				var pos_in_rect := Vector2i(x, y) - displayed_rect.position
				var left_opacity := clampf(inverse_lerp(0.0, float(FADING), float(pos_in_rect.x)), 0.0, 1.0)
				var right_opacity := clampf(inverse_lerp(float(displayed_rect.size.x), float(displayed_rect.size.x - FADING), float(pos_in_rect.x + 1)), 0.0, 1.0)
				var top_opacity := clampf(inverse_lerp(0.0, float(FADING), float(pos_in_rect.y)), 0.0, 1.0)
				var bottom_opacity := clampf(inverse_lerp(float(displayed_rect.size.y), float(displayed_rect.size.y - FADING), float(pos_in_rect.y + 1)), 0.0, 1.0)
				var opacity := clampf(minf(left_opacity, minf(right_opacity, minf(top_opacity, bottom_opacity))) + 0.1, 0.0, 1.0)

				var tile_xform := Transform2D(0.0, cell_size, 0.0, tilemap.map_to_local(Vector2i(x, y)))
				var world_polygon := tform * tile_xform * polygon
				var color := grid_color
				color.a *= opacity * scale_fading
				overlay.draw_polyline(world_polygon, color, -1.0, false)

func _get_tile_shape_polygon() -> PackedVector2Array:
	match tileset.tile_shape:
		TileSet.TILE_SHAPE_SQUARE:
			return PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5), Vector2(-0.5, -0.5)])
		TileSet.TILE_SHAPE_ISOMETRIC:
			return PackedVector2Array([Vector2(0.0, -0.5), Vector2(-0.5, 0.0), Vector2(0.0, 0.5), Vector2(0.5, 0.0), Vector2(0.0, -0.5)])
		_:
			var overlap: float = 0.25 if tileset.tile_shape == TileSet.TILE_SHAPE_HEXAGON else 0.0
			var pts := PackedVector2Array([
				Vector2(0.0, -0.5),
				Vector2(-0.5, overlap - 0.5),
				Vector2(-0.5, 0.5 - overlap),
				Vector2(0.0, 0.5),
				Vector2(0.5, 0.5 - overlap),
				Vector2(0.5, overlap - 0.5),
				Vector2(0.0, -0.5),
			])
			if tileset.tile_offset_axis == TileSet.TILE_OFFSET_AXIS_VERTICAL:
				for i in pts.size():
					pts[i] = Vector2(pts[i].y, pts[i].x)
			return pts

func _canvas_tilemap_transform() -> Transform2D:
	if not tilemap:
		return Transform2D.IDENTITY
	var transform := tilemap.get_viewport_transform() * tilemap.global_transform
	var editor_viewport := EditorInterface.get_editor_viewport_2d()
	if tilemap.get_viewport() != editor_viewport:
		var container := tilemap.get_viewport().get_parent() as SubViewportContainer
		if container:
			transform = editor_viewport.global_canvas_transform * container.get_transform() * transform
	return transform

# ---- LINE ALGORITHMS ----

func _bresenham_line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if from == to:
		return [to]
	var points: Array[Vector2i] = []
	var delta := (to - from).abs() * 2
	var step := (to - from).sign()
	var current := from
	if delta.x > delta.y:
		var err := delta.x / 2
		while current.x != to.x:
			points.append(current)
			err -= delta.y
			if err < 0:
				current.y += step.y
				err += delta.x
			current.x += step.x
	else:
		var err := delta.y / 2
		while current.y != to.y:
			points.append(current)
			err -= delta.x
			if err < 0:
				current.x += step.x
				err += delta.y
			current.y += step.y
	points.append(current)
	return points

func _tileset_line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if tileset.tile_shape == TileSet.TILE_SHAPE_SQUARE:
		return _bresenham_line(from, to)
	var points: Array[Vector2i] = []
	var transposed := tileset.get_tile_offset_axis() == TileSet.TILE_OFFSET_AXIS_VERTICAL
	var f := from
	var t := to
	if transposed:
		f = Vector2i(from.y, from.x)
		t = Vector2i(to.y, to.x)
	var delta := Vector2i(2 * (t.x - f.x) + abs(posmod(t.y, 2)) - abs(posmod(f.y, 2)), t.y - f.y)
	var sign := delta.sign()
	var current := f
	points.append(Vector2i(current.y, current.x) if transposed else current)
	var err := 0
	if abs(delta.y) < abs(delta.x):
		var err_step := 3 * delta.abs()
		while current != t:
			err += err_step.y
			if err > abs(delta.x):
				current.x += (sign.x if bool(current.y % 2) != (sign.x < 0) else 0) if sign.x != 0 else sign.y
				current.y += sign.y
				err -= err_step.x
			else:
				current.x += sign.x
				err += err_step.y
			points.append(Vector2i(current.y, current.x) if transposed else current)
	else:
		var err_step := delta.abs()
		while current != t:
			err += err_step.x
			if err > 0:
				current.x += (sign.x if bool(current.y % 2) != (sign.x < 0) else 0) if sign.x != 0 else sign.y
				current.y += sign.y
				err -= err_step.y
			else:
				current.x += (-sign.x if bool(current.y % 2) != (sign.x > 0) else 0) if sign.x != 0 else sign.y
				current.y += sign.y
				err += err_step.y
			points.append(Vector2i(current.y, current.x) if transposed else current)
	return points

# ---- ERASE ALL ----

func _on_erase_all() -> void:
	if not tilemap or not undo_manager:
		return
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "Erase ALL tiles on layer '%s'?" % tilemap.name
	dialog.get_ok_button().text = "Erase All"
	EditorInterface.popup_dialog_centered(dialog)
	dialog.confirmed.connect(func():
		_erase_all_tiles()
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)

func _erase_all_tiles() -> void:
	if not tilemap or not undo_manager:
		return
	var cells := tilemap.get_used_cells()
	var saved := _save_cells(cells)
	undo_manager.create_action("Erase All on " + tilemap.name, UndoRedo.MERGE_DISABLE, tilemap)
	for c in cells:
		undo_manager.add_do_method(tilemap, "erase_cell", c)
	undo_manager.add_undo_method(self, "_restore_cells", saved, tilemap)
	undo_manager.commit_action()

# ---- UTILITY ----

func _await_dialog(dialog: AcceptDialog) -> bool:
	var confirmed := false
	dialog.confirmed.connect(func(): confirmed = true; dialog.hide())
	dialog.canceled.connect(dialog.hide)
	await dialog.visibility_changed
	return confirmed

func _is_editor_select_mode() -> bool:
	if not Engine.is_editor_hint():
		return true
	var btn := _find_canvas_select_mode_button()
	if not btn:
		return true
	return btn.button_pressed

func _ensure_editor_select_mode() -> void:
	if not Engine.is_editor_hint():
		return
	var btn := _find_canvas_select_mode_button()
	if btn and not btn.button_pressed:
		btn.set_pressed_no_signal(true)
		btn.toggled.emit(true)

func _find_canvas_select_mode_button() -> BaseButton:
	var vp := EditorInterface.get_editor_viewport_2d()
	if not vp:
		return null
	var node: Node = vp
	for _i in 6:
		node = node.get_parent()
		if not node:
			return null
		var result := _find_first_toggle_in(node)
		if result:
			return result
	return null

func _find_first_toggle_in(node: Node) -> BaseButton:
	for child in node.get_children():
		if child is HBoxContainer:
			for btn in child.get_children():
				if btn is BaseButton and btn.toggle_mode:
					return btn
		var found := _find_first_toggle_in(child)
		if found:
			return found
	return null
