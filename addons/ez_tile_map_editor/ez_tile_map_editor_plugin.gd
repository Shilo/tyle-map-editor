@tool
extends EditorPlugin


var _panel: Control
var _button: Button


func _enter_tree() -> void:
	_panel = preload("res://addons/ez_tile_map_editor/ez_tile_map_editor_panel.tscn").instantiate()
	_button = add_control_to_bottom_panel(_panel, "EZ TileMap")
	_button.visible = false

	_panel.undo_manager = get_undo_redo()

	_panel.update_overlay.connect(update_overlays)

	var main_screen := get_editor_interface().get_editor_main_screen()
	main_screen.mouse_exited.connect(_panel.canvas_mouse_exited)

	_button.toggled.connect(func(v: bool):
		if v:
			_panel.about_to_be_visible()
	)


func _exit_tree() -> void:
	if _panel:
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
		_panel = null
	_button = null


func _handles(object: Object) -> bool:
	return object is TileMapLayer


func _edit(object: Object) -> void:
	if object is TileMapLayer:
		_panel.tilemap = object
		if _button and _button.button_pressed:
			_re_show.call_deferred()


func _make_visible(visible: bool) -> void:
	if visible and _button:
		_button.visible = true
		_button.button_pressed = true
		make_bottom_panel_item_visible(_panel)
		_re_show.call_deferred()
	elif _button:
		_button.visible = false
		_button.button_pressed = false


func _re_show() -> void:
	if _button and _button.button_pressed:
		make_bottom_panel_item_visible(_panel)
		_re_show2.call_deferred()


func _re_show2() -> void:
	if _button and _button.button_pressed:
		make_bottom_panel_item_visible(_panel)


func _clear() -> void:
	_panel.tilemap = null


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if not _panel.is_visible_in_tree():
		return false
	return _panel.canvas_input(event)


func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if _panel.is_visible_in_tree():
		_panel.canvas_draw(overlay)
