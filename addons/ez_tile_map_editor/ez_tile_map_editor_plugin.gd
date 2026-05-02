@tool
extends EditorPlugin

const DEBUG := true

func _log(msg: String) -> void:
	if DEBUG:
		print("[EZ-Tile-Plugin] ", msg)


var _panel: Control
var _button: Button
var _overlay: Control


const DEFAULT_INPUT_BINDINGS := {
	"ez_tile_draw": KEY_D,
	"ez_tile_line": KEY_L,
	"ez_tile_rect": KEY_R,
	"ez_tile_fill": KEY_B,
	"ez_tile_pick": KEY_P,
	"ez_tile_erase": KEY_E,
}

func _enter_tree() -> void:
	_log("_enter_tree")
	_setup_input_actions()
	_panel = preload("res://addons/ez_tile_map_editor/ez_tile_map_editor_panel.tscn").instantiate()
	_panel.plugin = self
	_button = add_control_to_bottom_panel(_panel, "EZ TileMap")
	_button.visible = false

	_panel.undo_manager = get_undo_redo()

	_panel.update_overlay.connect(update_overlays)
	_log("  connected update_overlay -> update_overlays")

	var main_screen := get_editor_interface().get_editor_main_screen()
	main_screen.mouse_exited.connect(_panel.canvas_mouse_exited)
	_log("  connected mouse_exited -> canvas_mouse_exited")

	_button.toggled.connect(func(v: bool):
		_log("button toggled: %s" % v)
		if v:
			_panel.about_to_be_visible()
	)


func _exit_tree() -> void:
	_log("_exit_tree")
	_teardown_input_actions()
	if _panel:
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
		_panel = null
	_button = null


func _setup_input_actions() -> void:
	for action: String in DEFAULT_INPUT_BINDINGS:
		var path: String = "input/" + action
		if not ProjectSettings.has_setting(path):
			var ev := InputEventKey.new()
			ev.keycode = DEFAULT_INPUT_BINDINGS[action]
			ev.command_or_control_autoremap = false
			ProjectSettings.set_setting(path, {"deadzone": 0.5, "events": [ev]})
			InputMap.add_action(action)
			InputMap.action_add_event(action, ev)
			_log("  added input action: %s (key=%d)" % [action, DEFAULT_INPUT_BINDINGS[action]])


func _teardown_input_actions() -> void:
	for action: String in DEFAULT_INPUT_BINDINGS:
		var path: String = "input/" + action
		if ProjectSettings.has_setting(path):
			ProjectSettings.clear(path)
		if InputMap.has_action(action):
			InputMap.erase_action(action)
			_log("  removed input action: %s" % action)


func _handles(object: Object) -> bool:
	var result := object is TileMapLayer
	_log("_handles: %s -> %s" % [object, result])
	return result


func _edit(object: Object) -> void:
	if object is TileMapLayer:
		_log("_edit: %s (visible_in_tree=%s visible=%s)" % [object.name, object.is_visible_in_tree(), object.visible])
		_panel.tilemap = object
		if _button and _button.button_pressed:
			_log("  button pressed, calling _re_show deferred")
			_re_show.call_deferred()


func _make_visible(visible: bool) -> void:
	_log("_make_visible: visible=%s" % visible)
	if visible and _button:
		_button.visible = true
		_button.button_pressed = true
		make_bottom_panel_item_visible(_panel)
		_re_show.call_deferred()
	elif _button:
		_button.visible = false
		_button.button_pressed = false


func _re_show() -> void:
	_log("_re_show: button_pressed=%s" % (_button.button_pressed if _button else "no_button"))
	if _button and _button.button_pressed:
		make_bottom_panel_item_visible(_panel)
		_panel.about_to_be_visible()
		_re_show2.call_deferred()


func _re_show2() -> void:
	_log("_re_show2: button_pressed=%s" % (_button.button_pressed if _button else "no_button"))
	if _button and _button.button_pressed:
		make_bottom_panel_item_visible(_panel)
		_panel.about_to_be_visible()


func _clear() -> void:
	_log("_clear")
	_panel.tilemap = null


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if not _panel.is_visible_in_tree():
		return false
	return _panel.canvas_input(event)


func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	_overlay = overlay
	if _panel.is_visible_in_tree():
		_panel.canvas_draw(overlay)


func _queue_overlay_redraw() -> void:
	if _overlay:
		_overlay.queue_redraw()
