class_name EZTileMapEditor
extends CanvasLayer

enum ActivationEdge { TOP, BOTTOM, LEFT, RIGHT }

const DEFAULT_INPUT_BINDINGS := {
	"ez_tile_select": KEY_S,
	"ez_tile_draw": KEY_D,
	"ez_tile_line": KEY_L,
	"ez_tile_rect": KEY_R,
	"ez_tile_fill": KEY_B,
	"ez_tile_pick": KEY_P,
	"ez_tile_erase": KEY_E,
}

const PANEL_SCENE := preload("res://addons/ez_tile_map_editor/ez_tile_map_editor_panel.tscn")

@export var enabled: bool = true:
	set(value):
		enabled = value
		if is_inside_tree() and _split:
			_split.visible = enabled

@export var activation_edge: ActivationEdge = ActivationEdge.BOTTOM:
	set(value):
		activation_edge = value
		if is_inside_tree():
			_layout_dock()

@export_range(1, 256, 1, "or_greater") var activation_thickness_px: int = 12
@export_range(0.0, 2.0, 0.01) var animation_duration: float = 0.15
@export var showing: bool = false:
	set(value):
		_showing = value
		if is_inside_tree():
			_apply_showing(value, true)
	get:
		return _showing

@export var excluded_controls: Array[NodePath] = []
@export var excluded_rects: Array[Rect2] = []
@export var discover_root_path: NodePath
@export var install_default_input_actions: bool = false

var _split: SplitContainer
var _game_area: Control
var _panel: Control
var _undo_redo := UndoRedo.new()
var _layers: Array[TileMapLayer] = []
var _showing := false
var _hover_armed := true
var _tween: Tween


class GameArea extends Control:
	var host: EZTileMapEditor

	func _draw() -> void:
		if host:
			host._draw_runtime_overlay(self)


func _ready() -> void:
	layer = 100
	if install_default_input_actions:
		_setup_default_input_actions()

	_build_nodes()
	get_viewport().size_changed.connect(_layout_dock)
	refresh_layers()
	_layout_dock()
	_apply_showing(showing, false)


func _process(_delta: float) -> void:
	if not enabled or showing:
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var in_zone := _is_in_activation_zone(mouse_pos)
	if not in_zone:
		_hover_armed = true
		return
	if _hover_armed and not _is_excluded_position(mouse_pos):
		open()


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or not showing or not _panel:
		return
	if _panel.canvas_input(event):
		get_viewport().set_input_as_handled()
		_queue_overlay_redraw()


func refresh_layers() -> void:
	_layers.clear()
	var root := _get_discover_root()
	if root:
		_collect_visible_tilemap_layers(root, _layers)
	if _panel:
		if _panel.tilemap == null or not _layers.has(_panel.tilemap):
			_panel.tilemap = _layers[0] if not _layers.is_empty() else null
		_panel.about_to_be_visible()


func set_tilemap(layer: TileMapLayer) -> void:
	if not _panel:
		return
	if layer and not _layers.has(layer):
		_layers.append(layer)
	_panel.tilemap = layer
	_panel.about_to_be_visible()
	_queue_overlay_redraw()


func set_editing_enabled(value: bool) -> void:
	enabled = value


func open(animated: bool = true) -> void:
	_apply_showing(true, animated)


func close(animated: bool = true) -> void:
	_apply_showing(false, animated)


func _apply_showing(value: bool, animated: bool) -> void:
	_showing = value
	if value and not enabled:
		return
	_hover_armed = not _is_in_activation_zone(get_viewport().get_mouse_position())
	if value:
		_hover_armed = true
		_layout_dock()
		if _panel:
			_panel.about_to_be_visible()
		_show_panel(animated)
	elif _panel:
		_panel.canvas_mouse_exited()
		_hide_panel(animated)


func undo() -> void:
	if _undo_redo.has_undo():
		_undo_redo.undo()
		_queue_overlay_redraw()


func redo() -> void:
	if _undo_redo.has_redo():
		_undo_redo.redo()
		_queue_overlay_redraw()


func _build_nodes() -> void:
	_split = SplitContainer.new()
	_split.name = "SplitContainer"
	_split.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_split.set_anchors_preset(Control.PRESET_FULL_RECT)
	_split.visible = enabled
	add_child(_split)

	_game_area = GameArea.new()
	_game_area.name = "GameArea"
	_game_area.host = self
	_game_area.clip_contents = true
	_game_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_game_area.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_panel = PANEL_SCENE.instantiate()
	_panel.runtime_mode = true
	_panel.undo_manager = _undo_redo
	_panel.layer_provider = Callable(self, "_get_layers_for_panel")
	_panel.layer_selected_callback = Callable(self, "_on_panel_layer_selected")
	_panel.canvas_transform_provider = Callable(self, "_get_canvas_transform_for_panel")
	_panel.viewport_size_provider = Callable(self, "_get_viewport_size_for_panel")
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.update_overlay.connect(_queue_overlay_redraw)
	if _panel.has_signal("close_requested"):
		_panel.close_requested.connect(close)
	_configure_split_children()


func _layout_dock() -> void:
	if not _split:
		return
	_split.set_anchors_preset(Control.PRESET_FULL_RECT)
	_split.vertical = activation_edge == ActivationEdge.TOP or activation_edge == ActivationEdge.BOTTOM
	_configure_split_children()
	if _panel:
		_panel.custom_minimum_size = Vector2.ZERO
		_apply_panel_size_flags()
	_apply_split_offset()
	_queue_overlay_redraw()


func _panel_should_be_first() -> bool:
	return activation_edge == ActivationEdge.TOP or activation_edge == ActivationEdge.LEFT


func _configure_split_children() -> void:
	if not _split or not _panel or not _game_area:
		return
	var desired := [_panel, _game_area] if _panel_should_be_first() else [_game_area, _panel]
	if _split.get_child_count() == desired.size() and _split.get_child(0) == desired[0] and _split.get_child(1) == desired[1]:
		return
	for child in [_panel, _game_area]:
		if child.get_parent() == _split:
			_split.remove_child(child)
	for child in desired:
		_split.add_child(child)


func _apply_panel_size_flags() -> void:
	var side_dock := activation_edge == ActivationEdge.LEFT or activation_edge == ActivationEdge.RIGHT
	if side_dock:
		_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if activation_edge == ActivationEdge.LEFT else Control.SIZE_SHRINK_END
		_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN if activation_edge == ActivationEdge.TOP else Control.SIZE_SHRINK_END
	_game_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_game_area.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _apply_split_offset() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var panel_min := _panel.get_combined_minimum_size()
	if _split.vertical:
		var panel_height := panel_min.y
		_split.split_offset = int(roundf(panel_height if _panel_should_be_first() else maxf(0.0, viewport_size.y - panel_height)))
	else:
		var panel_width := panel_min.x
		_split.split_offset = int(roundf(panel_width if _panel_should_be_first() else maxf(0.0, viewport_size.x - panel_width)))


func _show_panel(animated: bool) -> void:
	if not _panel:
		return
	if _tween:
		_tween.kill()
	_panel.visible = true
	if not animated or animation_duration <= 0.0:
		_panel.modulate.a = 1.0
		return
	_panel.modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", 1.0, animation_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _hide_panel(animated: bool) -> void:
	if not _panel:
		return
	if _tween:
		_tween.kill()
	if not animated or animation_duration <= 0.0:
		_panel.visible = false
		_panel.modulate.a = 1.0
		_queue_overlay_redraw()
		return
	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", 0.0, animation_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(func():
		_panel.visible = false
		_panel.modulate.a = 1.0
		_queue_overlay_redraw()
	)


func _is_in_activation_zone(pos: Vector2) -> bool:
	var viewport_size := get_viewport().get_visible_rect().size
	var thickness := max(1.0, float(activation_thickness_px))
	match activation_edge:
		ActivationEdge.TOP:
			return pos.y <= thickness
		ActivationEdge.BOTTOM:
			return pos.y >= viewport_size.y - thickness
		ActivationEdge.LEFT:
			return pos.x <= thickness
		ActivationEdge.RIGHT:
			return pos.x >= viewport_size.x - thickness
	return false


func _is_excluded_position(pos: Vector2) -> bool:
	for rect in excluded_rects:
		if rect.has_point(pos):
			return true
	for path in excluded_controls:
		if path.is_empty():
			continue
		var node := get_node_or_null(path)
		if node is Control and node.visible and node.get_global_rect().has_point(pos):
			return true
	return false


func _get_discover_root() -> Node:
	if not discover_root_path.is_empty():
		var configured := get_node_or_null(discover_root_path)
		if configured:
			return configured
	if get_tree() and get_tree().current_scene:
		return get_tree().current_scene
	var parent_root: Node = self
	while parent_root.get_parent():
		parent_root = parent_root.get_parent()
	return parent_root


func _collect_visible_tilemap_layers(node: Node, result: Array[TileMapLayer]) -> void:
	if node is TileMapLayer and node.visible:
		result.append(node)
	for child in node.get_children():
		_collect_visible_tilemap_layers(child, result)


func _get_layers_for_panel() -> Array[TileMapLayer]:
	refresh_layers()
	return _layers


func _on_panel_layer_selected(layer: TileMapLayer) -> void:
	set_tilemap(layer)


func _get_canvas_transform_for_panel(layer: TileMapLayer) -> Transform2D:
	if not layer:
		return Transform2D.IDENTITY
	return layer.get_viewport_transform() * layer.global_transform


func _get_viewport_size_for_panel() -> Vector2:
	return get_viewport().get_visible_rect().size


func _draw_runtime_overlay(target: Control) -> void:
	if not enabled or not showing or not _panel:
		return
	target.draw_set_transform(-target.global_position, 0.0, Vector2.ONE)
	_panel.canvas_draw(target)
	if _panel.is_layer_highlight_enabled() and _panel.tilemap:
		_draw_layer_highlight(target, _panel.tilemap)
	target.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_layer_highlight(target: Control, layer: TileMapLayer) -> void:
	var used_rect := layer.get_used_rect()
	if not used_rect.has_area() or not layer.tile_set:
		return
	var tform := _get_canvas_transform_for_panel(layer)
	var cell_size := Vector2(layer.tile_set.tile_size)
	var top_left := tform * layer.map_to_local(used_rect.position)
	var bottom_right_cell := used_rect.position + used_rect.size - Vector2i.ONE
	var bottom_right := tform * layer.map_to_local(bottom_right_cell)
	var rect := Rect2(top_left, bottom_right - top_left).abs()
	rect = rect.grow(max(cell_size.x, cell_size.y) * 0.5)
	target.draw_rect(rect, Color(0.3, 0.7, 1.0, 0.25), false, 2.0)


func _queue_overlay_redraw() -> void:
	if _game_area:
		_game_area.queue_redraw()


func _setup_default_input_actions() -> void:
	for action: String in DEFAULT_INPUT_BINDINGS:
		if InputMap.has_action(action):
			continue
		var ev := InputEventKey.new()
		ev.keycode = DEFAULT_INPUT_BINDINGS[action]
		ev.command_or_control_autoremap = false
		InputMap.add_action(action)
		InputMap.action_add_event(action, ev)
