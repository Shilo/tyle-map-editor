@tool
extends Control

signal update_overlay

enum PaintTool {
	NONE,
	DRAW,
	LINE,
	RECT,
	BUCKET,
	PICK,
	ERASE,
}

@onready var draw_button: Button = %Draw
@onready var line_button: Button = %Line
@onready var rect_button: Button = %Rect
@onready var fill_button: Button = %Fill
@onready var pick_button: Button = %Pick
@onready var erase_button: Button = %Erase

@onready var layer_up: Button = %LayerUp
@onready var layer_down: Button = %LayerDown
@onready var layer_highlight: Button = %LayerHighlight
@onready var layer_grid: Button = %LayerGrid

@onready var quick_mode_button: Button = %QuickMode

@onready var add_terrain_button: Button = %AddTerrain
@onready var edit_terrain_button: Button = %EditTerrain
@onready var move_up_button: Button = %MoveUp
@onready var move_down_button: Button = %MoveDown
@onready var remove_terrain_button: Button = %RemoveTerrain

@onready var terrain_grid: HFlowContainer = %TerrainGrid
@onready var scroll_container: ScrollContainer = %TerrainScroll
@onready var empty_label: Label = %EmptyLabel

var tilemap: TileMapLayer = null:
	set(v):
		tilemap = v
		if v:
			tileset = v.tile_set
		else:
			tileset = null

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

var flattened_terrains: Array[Dictionary] = []  # [{set, idx, name, color, icon_texture, icon_region}]
var selected_index: int = -1             # -1 = erase
var paint_tool: PaintTool = PaintTool.DRAW
var _prev_tool: PaintTool = PaintTool.DRAW

var draw_overlay: bool = false
var mouse_down: bool = false
var mouse_start: Vector2i = Vector2i.ZERO
var mouse_current: Vector2i = Vector2i.ZERO
var mouse_prev: Vector2i = Vector2i.ZERO
var mouse_on_canvas: bool = false
var drag_erasing: bool = false
var drag_action_index: int = 0
var drag_action_count: int = 0


func _ready() -> void:
	draw_button.icon = get_theme_icon("Edit", "EditorIcons")
	line_button.icon = get_theme_icon("Line", "EditorIcons")
	rect_button.icon = get_theme_icon("Rectangle", "EditorIcons")
	fill_button.icon = get_theme_icon("Bucket", "EditorIcons")
	pick_button.icon = get_theme_icon("ColorPick", "EditorIcons")
	erase_button.icon = get_theme_icon("Eraser", "EditorIcons")

	layer_up.icon = get_theme_icon("MoveUp", "EditorIcons")
	layer_down.icon = get_theme_icon("MoveDown", "EditorIcons")
	layer_highlight.icon = get_theme_icon("TileMapHighlightSelected", "EditorIcons")
	layer_grid.icon = get_theme_icon("Grid", "EditorIcons")

	add_terrain_button.icon = get_theme_icon("Add", "EditorIcons")
	edit_terrain_button.icon = get_theme_icon("Tools", "EditorIcons")
	move_up_button.icon = get_theme_icon("ArrowUp", "EditorIcons")
	move_down_button.icon = get_theme_icon("ArrowDown", "EditorIcons")
	remove_terrain_button.icon = get_theme_icon("Remove", "EditorIcons")
	quick_mode_button.icon = get_theme_icon("GuiVisibilityVisible", "EditorIcons")

	draw_button.pressed.connect(_on_tool_changed.bind(PaintTool.DRAW))
	line_button.pressed.connect(_on_tool_changed.bind(PaintTool.LINE))
	rect_button.pressed.connect(_on_tool_changed.bind(PaintTool.RECT))
	fill_button.pressed.connect(_on_tool_changed.bind(PaintTool.BUCKET))
	pick_button.toggled.connect(_on_pick_toggled)

	layer_up.pressed.connect(_on_layer_up)
	layer_down.pressed.connect(_on_layer_down)
	layer_highlight.toggled.connect(_on_layer_highlight_toggled)
	layer_grid.toggled.connect(_on_layer_grid_toggled)

	quick_mode_button.pressed.connect(_on_quick_mode_toggled)

	add_terrain_button.pressed.connect(_on_add_terrain)
	edit_terrain_button.pressed.connect(_on_edit_terrain)
	move_up_button.pressed.connect(_on_move_terrain.bind(false))
	move_down_button.pressed.connect(_on_move_terrain.bind(true))
	remove_terrain_button.pressed.connect(_on_remove_terrain)

	draw_button.button_pressed = true
	_show_empty(true)


func _process(_delta: float) -> void:
	scroll_container.scroll_horizontal = 0


func _on_tool_changed(tool: PaintTool) -> void:
	_prev_tool = paint_tool
	paint_tool = tool
	pick_button.button_pressed = false


func _on_pick_toggled(v: bool) -> void:
	if v:
		paint_tool = PaintTool.PICK


func _on_tileset_changed() -> void:
	_refresh_terrains.call_deferred()


# ---- TERRAIN READING & GRID ----

var _icon_cache: Dictionary = {}


func _refresh_terrains() -> void:
	for c in terrain_grid.get_children():
		c.queue_free()

	flattened_terrains.clear()

	if not tileset:
		_show_empty(true)
		return

	_build_icon_cache()

	var terrain_count := 0
	for set_idx in tileset.get_terrain_sets_count():
		for ter_idx in tileset.get_terrains_count(set_idx):
			var name := tileset.get_terrain_name(set_idx, ter_idx)
			var color := tileset.get_terrain_color(set_idx, ter_idx)
			var key := "%d:%d" % [set_idx, ter_idx]
			var icon: Dictionary = _icon_cache.get(key, {})
			flattened_terrains.append({
				set = set_idx,
				idx = ter_idx,
				name = name,
				color = color,
				icon_texture = icon.get("texture", null),
				icon_region = icon.get("region", Rect2i())
			})
			terrain_count += 1

	if terrain_count == 0:
		_show_empty(true)
		return

	_show_empty(false)

	for i in flattened_terrains.size():
		_create_terrain_entry(flattened_terrains[i], i)

	if selected_index >= flattened_terrains.size():
		selected_index = -1

	_update_management_buttons()


func _show_empty(show: bool) -> void:
	empty_label.visible = show
	scroll_container.visible = not show


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
			_icon_cache[key_center] = _make_icon(source, coord, alt_id)


func _discover_terrain_icon(set_idx: int, ter_idx: int) -> Dictionary:
	return _icon_cache.get("%d:%d" % [set_idx, ter_idx], {})


func _make_icon(source: TileSetAtlasSource, coord: Vector2i, alt_id: int) -> Dictionary:
	if not source or not source.texture:
		return {}
	var atlas_tex := AtlasTexture.new()
	atlas_tex.atlas = source.texture
	var region := source.get_tile_texture_region(coord, 0)
	atlas_tex.region = region
	return {
		texture = atlas_tex,
		region = region
	}


func _create_terrain_entry(data: Dictionary, index: int) -> void:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(80, 80)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn.toggle_mode = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.expand_icon = true
	btn.flat = true
	btn.name = "Terrain%d" % index

	if data.icon_texture:
		btn.icon = data.icon_texture
	btn.tooltip_text = "%s (Set %d, Terrain %d)" % [data.name, data.set, data.idx]
	btn.self_modulate = Color(data.color, 0.6)

	btn.pressed.connect(_on_terrain_selected.bind(index))
	terrain_grid.add_child(btn)


func _on_terrain_selected(index: int) -> void:
	selected_index = index
	for c in terrain_grid.get_children():
		var btn := c as Button
		if not btn:
			continue
		btn.button_pressed = (c.get_index() == index)
	_update_management_buttons()


func _update_management_buttons() -> void:
	var editable := selected_index >= 0 and selected_index < flattened_terrains.size()
	edit_terrain_button.disabled = not editable
	move_up_button.disabled = not editable or selected_index == 0
	move_down_button.disabled = not editable or selected_index >= flattened_terrains.size() - 1
	remove_terrain_button.disabled = not editable


func _on_quick_mode_toggled() -> void:
	add_terrain_button.visible = not quick_mode_button.button_pressed
	edit_terrain_button.visible = not quick_mode_button.button_pressed
	move_up_button.visible = not quick_mode_button.button_pressed
	move_down_button.visible = not quick_mode_button.button_pressed
	remove_terrain_button.visible = not quick_mode_button.button_pressed


# ---- SAVE / RESTORE CELL STATE ----

func _save_cells(coords: Array) -> Dictionary:
	var state := {}
	for c in coords:
		var src := tilemap.get_cell_source_id(c)
		state[c] = {
			has_cell = src != -1,
			source_id = src if src != -1 else 0,
			atlas_coords = tilemap.get_cell_atlas_coords(c) if src != -1 else Vector2i.ZERO,
			alternative_tile = tilemap.get_cell_alternative_tile(c) if src != -1 else 0
		}
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
	if not tilemap or not tileset:
		return false

	if not event is InputEventMouse:
		return false

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN or event.button_index == MOUSE_BUTTON_WHEEL_LEFT or event.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
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
			if paint_tool == PaintTool.DRAW:
				_do_paint_stroke()

	var released: bool = event is InputEventMouseButton and not event.pressed
	var clicked: bool = event is InputEventMouseButton and event.pressed

	if released:
		mouse_down = false
		if paint_tool == PaintTool.LINE or paint_tool == PaintTool.RECT:
			_commit_paint_action()
		drag_erasing = false
		draw_overlay = false
		update_overlay.emit()
		return true

	if clicked:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			drag_erasing = true
		elif event.button_index == MOUSE_BUTTON_LEFT:
			drag_erasing = erase_button.button_pressed
		else:
			return false

		if event.is_command_or_control_pressed() and not event.shift_pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_pick_at_mouse()
			return true

		if paint_tool == PaintTool.PICK and event.button_index == MOUSE_BUTTON_LEFT:
			_pick_at_mouse()
			pick_button.button_pressed = false
			paint_tool = _prev_tool
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
		PaintTool.DRAW:
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
		else:
			if src != target_src:
				continue

		result.append(p)
		for nb in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			pending.append(p + nb)

	return result


func _pick_at_mouse() -> void:
	var td := tilemap.get_cell_tile_data(mouse_current)
	if not td:
		return
	var ts := td.terrain_set
	var tr := td.terrain
	if ts < 0 or tr < 0:
		return

	for i in flattened_terrains.size():
		var f = flattened_terrains[i]
		if f.set == ts and f.idx == tr:
			selected_index = i
			_update_selection_buttons()
			return


func _update_selection_buttons() -> void:
	for i in terrain_grid.get_child_count():
		var btn := terrain_grid.get_child(i) as Button
		if not btn:
			continue
		var idx = i if i < flattened_terrains.size() else -1
		btn.button_pressed = (idx == selected_index)
	_update_management_buttons()


func _get_selected_terrain() -> Dictionary:
	if selected_index >= 0 and selected_index < flattened_terrains.size():
		return flattened_terrains[selected_index]
	return {}


# ---- CANVAS OVERLAY ----

func canvas_draw(overlay: Control) -> void:
	if not draw_overlay or not tilemap:
		return

	if not mouse_down:
		if paint_tool == PaintTool.PICK or erase_button.button_pressed:
			var td := tilemap.get_cell_tile_data(mouse_current)
			if not td or td.terrain_set < 0 or td.terrain < 0:
				return

	var color: Color
	if mouse_down and drag_erasing:
		color = Color(0.0, 0.0, 0.0, 0.35)
	elif erase_button.button_pressed or selected_index < 0:
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


# ---- BRESENHAM / LINE ----

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
				if sign.x == 0:
					current += Vector2i(sign.y, 0)
				else:
					current += Vector2i(sign.x if bool(current.y % 2) != (sign.x < 0) else 0, sign.y)
				err -= err_step.x
			else:
				current += Vector2i(sign.x, 0)
				err += err_step.y
			points.append(Vector2i(current.y, current.x) if transposed else current)
	else:
		var err_step := delta.abs()
		while current != t:
			err += err_step.x
			if err > 0:
				if sign.x == 0:
					current += Vector2i(0, sign.y)
				else:
					current += Vector2i(sign.x if bool(current.y % 2) != (sign.x < 0) else 0, sign.y)
				err -= err_step.y
			else:
				if sign.x == 0:
					current += Vector2i(0, sign.y)
				else:
					current += Vector2i(-sign.x if bool(current.y % 2) != (sign.x > 0) else 0, sign.y)
				err += err_step.y
			points.append(Vector2i(current.y, current.x) if transposed else current)

	return points


# ---- TERRAIN MANAGEMENT ----

func _on_add_terrain() -> void:
	if not tileset:
		return

	var terrain_set := 0
	if tileset.get_terrain_sets_count() == 0:
		undo_manager.create_action("Add Terrain Set", UndoRedo.MERGE_DISABLE, tileset)
		undo_manager.add_do_method(tileset, "add_terrain_set")
		undo_manager.add_undo_method(tileset, "remove_terrain_set", 0)
		undo_manager.commit_action()
		await get_tree().process_frame

	terrain_set = tileset.get_terrain_sets_count() - 1
	if terrain_set < 0:
		terrain_set = 0

	var ter_pos := tileset.get_terrains_count(terrain_set)
	undo_manager.create_action("Add Terrain", UndoRedo.MERGE_DISABLE, tileset)
	undo_manager.add_do_method(tileset, "add_terrain", terrain_set, ter_pos)
	undo_manager.add_do_method(tileset, "set_terrain_name", terrain_set, ter_pos, "New Terrain")
	var h := float(ter_pos % 16) / 16.0
	undo_manager.add_do_method(tileset, "set_terrain_color", terrain_set, ter_pos, Color.from_hsv(h, 0.5, 0.5))
	undo_manager.add_do_method(tileset, "set_terrain_mode", terrain_set, ter_pos, TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES)
	undo_manager.add_undo_method(self, "_refresh_terrains")
	undo_manager.add_do_method(self, "_refresh_terrains")
	undo_manager.commit_action()


func _on_edit_terrain() -> void:
	if not tileset or selected_index < 0:
		return

	var t: Dictionary = flattened_terrains[selected_index]

	var dialog := AcceptDialog.new()
	dialog.title = "Edit Terrain"
	dialog.ok_button_text = "Save"
	dialog.custom_minimum_size = Vector2(300, 0)

	var vbox := VBoxContainer.new()
	dialog.add_child(vbox)

	var name_edit := LineEdit.new()
	name_edit.text = t.name
	name_edit.placeholder_text = "Terrain name"
	vbox.add_child(name_edit)

	var color_picker := ColorPickerButton.new()
	color_picker.color = t.color
	vbox.add_child(color_picker)

	EditorInterface.popup_dialog_centered(dialog)
	var confirmed := await _await_dialog(dialog)
	dialog.queue_free()

	if confirmed:
		undo_manager.create_action("Edit Terrain", UndoRedo.MERGE_DISABLE, tileset)
		undo_manager.add_do_method(tileset, "set_terrain_name", t.set, t.idx, name_edit.text)
		undo_manager.add_do_method(tileset, "set_terrain_color", t.set, t.idx, color_picker.color)
		undo_manager.add_undo_method(tileset, "set_terrain_name", t.set, t.idx, t.name)
		undo_manager.add_undo_method(tileset, "set_terrain_color", t.set, t.idx, t.color)
		undo_manager.add_do_method(self, "_refresh_terrains")
		undo_manager.add_undo_method(self, "_refresh_terrains")
		undo_manager.commit_action()


func _on_remove_terrain() -> void:
	if not tileset or selected_index < 0:
		return

	var t: Dictionary = flattened_terrains[selected_index]

	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "Remove terrain '%s'?" % t.name
	EditorInterface.popup_dialog_centered(dialog)
	var confirmed := await _await_dialog(dialog)
	dialog.queue_free()

	if confirmed:
		undo_manager.create_action("Remove Terrain", UndoRedo.MERGE_DISABLE, tileset)
		undo_manager.add_do_method(tileset, "remove_terrain", t.set, t.idx)
		undo_manager.add_undo_method(tileset, "add_terrain", t.set, t.idx)
		undo_manager.add_undo_method(tileset, "set_terrain_name", t.set, t.idx, t.name)
		undo_manager.add_undo_method(tileset, "set_terrain_color", t.set, t.idx, t.color)
		undo_manager.add_do_method(self, "_refresh_terrains")
		undo_manager.add_undo_method(self, "_refresh_terrains")
		undo_manager.commit_action()
		selected_index = -1


func _on_move_terrain(down: bool) -> void:
	if not tileset or selected_index < 0:
		return

	var index_to := selected_index + (1 if down else -1)
	if index_to < 0 or index_to >= flattened_terrains.size():
		return

	var t: Dictionary = flattened_terrains[selected_index]

	undo_manager.create_action("Move Terrain", UndoRedo.MERGE_DISABLE, tileset)
	undo_manager.add_do_method(tileset, "move_terrain", t.set, t.idx, index_to)
	undo_manager.add_undo_method(tileset, "move_terrain", t.set, index_to, selected_index)
	undo_manager.add_do_method(self, "_refresh_terrains")
	undo_manager.add_undo_method(self, "_refresh_terrains")
	undo_manager.commit_action()

	selected_index = index_to
	_refresh_terrains()


# ---- LAYER CONTROLS ----

func _find_builtin_button_by_icon(our_icon: Texture2D, fallback_name: String) -> Button:
	var base := EditorInterface.get_base_control()
	if not base:
		return null
	var editors := base.find_children("*", "TileMapLayerEditor", true, false)
	if editors.is_empty():
		return null
	var fresh_icon := get_theme_icon(fallback_name, "EditorIcons")
	var buttons := editors[0].find_children("*", "Button", true, false)
	for btn: Button in buttons:
		if btn.icon == fresh_icon or btn.icon == our_icon:
			return btn
	return null


func _on_layer_up() -> void:
	var btn := _find_builtin_button_by_icon(layer_up.icon, "MoveUp")
	if btn:
		btn.pressed.emit()


func _on_layer_down() -> void:
	var btn := _find_builtin_button_by_icon(layer_down.icon, "MoveDown")
	if btn:
		btn.pressed.emit()


func _on_layer_highlight_toggled(toggled: bool) -> void:
	var settings := EditorInterface.get_editor_settings()
	settings.set_setting("editors/tiles_editor/highlight_selected_layer", toggled)
	settings.emit_changed()
	update_overlay.emit()


func _on_layer_grid_toggled(toggled: bool) -> void:
	var settings := EditorInterface.get_editor_settings()
	settings.set_setting("editors/tiles_editor/display_grid", toggled)
	settings.emit_changed()
	update_overlay.emit()


func about_to_be_visible() -> void:
	if tilemap and tileset != tilemap.tile_set:
		tileset = tilemap.tile_set
	var settings := EditorInterface.get_editor_settings()
	layer_highlight.set_pressed_no_signal(settings.get_setting("editors/tiles_editor/highlight_selected_layer"))
	layer_grid.set_pressed_no_signal(settings.get_setting("editors/tiles_editor/display_grid"))


# ---- UTILITY ----

func _await_dialog(dialog: AcceptDialog) -> bool:
	var confirmed := false
	dialog.confirmed.connect(func(): confirmed = true; dialog.hide())
	dialog.canceled.connect(dialog.hide)
	await dialog.visibility_changed
	return confirmed
