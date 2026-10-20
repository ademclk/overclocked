class_name WorldLabel
extends PanelContainer

## Screen-space label that tracks a 3D world position.
## Station tags are distinguishable from afar by their unique style, color, and icon badge.
## Text only appears when a player approaches within proximity distance.

@export var target_node: Node3D = null
@export var world_offset: Vector3 = Vector3(0, 1.5, 0)  ## Offset above target
@export var min_font_size: int = Constants.WORLD_LABEL_MIN_FONT_SIZE
@export var max_font_size: int = Constants.WORLD_LABEL_MAX_FONT_SIZE
@export var show_background: bool = false
@export var background_color: Color = Color(0, 0, 0, 0)
@export var proximity_distance: float = 3.6  ## Distance within which station text appears
@export var hide_text_at_distance: bool = true

var _hbox: HBoxContainer = null
var _icon_label: Label = null
var _icon_rect: TextureRect = null
var _label: Label = null
var _camera: Camera3D = null
var _stylebox: StyleBoxFlat = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_setup_ui()
	_update_camera()


func _setup_ui() -> void:
	_hbox = HBoxContainer.new()
	_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hbox.add_theme_constant_override("separation", 6)
	add_child(_hbox)

	_icon_label = Label.new()
	_icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_icon_label.visible = false
	_hbox.add_child(_icon_label)

	_icon_rect = TextureRect.new()
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.custom_minimum_size = Constants.STATION_ICON_SIZE
	_icon_rect.visible = false
	_hbox.add_child(_icon_rect)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hbox.add_child(_label)

	if show_background:
		_stylebox = StyleBoxFlat.new()
		_stylebox.bg_color = background_color
		_stylebox.corner_radius_top_left = 6
		_stylebox.corner_radius_top_right = 6
		_stylebox.corner_radius_bottom_left = 6
		_stylebox.corner_radius_bottom_right = 6
		_stylebox.content_margin_left = 6
		_stylebox.content_margin_right = 6
		_stylebox.content_margin_top = 2
		_stylebox.content_margin_bottom = 2
		add_theme_stylebox_override("panel", _stylebox)
	else:
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	_apply_font_size(min_font_size)


func _update_camera() -> void:
	var vp := get_viewport()
	if vp:
		_camera = vp.get_camera_3d()


func _process(_delta: float) -> void:
	if not _camera or not is_instance_valid(_camera):
		_update_camera()
		if not _camera:
			visible = false
			return

	if not target_node or not is_instance_valid(target_node) or not target_node.is_inside_tree():
		visible = false
		return

	if not target_node.is_visible_in_tree():
		visible = false
		return

	# Proximity check: only display full text when player is close to station
	var is_near: bool = not hide_text_at_distance
	if hide_text_at_distance:
		var players: Array[Node] = get_tree().get_nodes_in_group("players")
		for p in players:
			if p is Node3D and is_instance_valid(p):
				if p.global_position.distance_to(target_node.global_position) <= proximity_distance:
					is_near = true
					break

	if not is_near or (_label and _label.text.is_empty()):
		visible = false
		return

	if _label:
		_label.visible = true

	var world_pos: Vector3 = target_node.global_position + world_offset
	if not _camera.is_position_behind(world_pos):
		var screen_pos: Vector2 = _camera.unproject_position(world_pos)
		position = screen_pos - size * 0.5
		visible = true
	else:
		visible = false


func set_text(text: String) -> void:
	if _label:
		_label.text = text


func set_text_color(color: Color) -> void:
	if _label:
		_label.add_theme_color_override("font_color", color)


func set_icon_text(symbol: String, color: Color = Color.WHITE) -> void:
	if _icon_label:
		if symbol.is_empty():
			_icon_label.visible = false
		else:
			_icon_label.text = symbol
			_icon_label.add_theme_color_override("font_color", color)
			_icon_label.visible = true


func set_icon_texture(texture: Texture2D) -> void:
	if _icon_rect:
		if texture:
			_icon_rect.texture = texture
			_icon_rect.visible = true
		else:
			_icon_rect.visible = false


## Applies distinct visual style per station type (color, border, icon)
func set_station_style(station_type: String) -> void:
	var icon := get_station_icon_symbol(station_type)
	match station_type:
		"workbench":
			set_icon_text(icon, Color(1.0, 0.75, 0.25))
			_set_panel_theme(Color(0.14, 0.08, 0.04, 0.92), Color(1.0, 0.55, 0.15, 0.95))
		"repair_table":
			set_icon_text(icon, Color(0.4, 0.85, 1.0))
			_set_panel_theme(Color(0.04, 0.10, 0.14, 0.92), Color(0.25, 0.65, 0.95, 0.95))
		"trash", "trash_bin":
			set_icon_text(icon, Color(0.85, 0.45, 0.45))
			_set_panel_theme(Color(0.12, 0.06, 0.06, 0.92), Color(0.8, 0.35, 0.35, 0.95))
		"diagnostic", "diagnostic_bench":
			set_icon_text(icon, Color(0.35, 0.85, 1.0))
			_set_panel_theme(Color(0.04, 0.08, 0.14, 0.92), Color(0.2, 0.75, 1.0, 0.95))
		"parts_shelf", "shelf":
			set_icon_text(icon, Color(0.45, 0.95, 0.55))
			_set_panel_theme(Color(0.04, 0.10, 0.06, 0.92), Color(0.3, 0.85, 0.45, 0.95))
		"software", "software_station":
			set_icon_text(icon, Color(0.9, 0.5, 1.0))
			_set_panel_theme(Color(0.10, 0.05, 0.12, 0.92), Color(0.85, 0.35, 0.95, 0.95))
		"reception", "reception_desk":
			set_icon_text(icon, Color(0.95, 0.9, 0.8))
			_set_panel_theme(Color(0.08, 0.08, 0.10, 0.92), Color(0.9, 0.85, 0.7, 0.95))
		"delivery", "delivery_counter":
			set_icon_text(icon, Color(0.45, 1.0, 0.35))
			_set_panel_theme(Color(0.05, 0.11, 0.06, 0.92), Color(0.4, 0.95, 0.3, 0.95))
		_:
			set_icon_text(icon, Color(1.0, 0.85, 0.3))
			_set_panel_theme(Color(0.06, 0.07, 0.1, 0.9), Color(0.3, 0.5, 0.8, 0.8))


func _set_panel_theme(bg: Color, border: Color) -> void:
	if not _stylebox:
		_stylebox = StyleBoxFlat.new()
		add_theme_stylebox_override("panel", _stylebox)
	_stylebox.bg_color = bg
	_stylebox.border_color = border
	_stylebox.border_width_left = 2
	_stylebox.border_width_top = 2
	_stylebox.border_width_right = 2
	_stylebox.border_width_bottom = 2
	_stylebox.corner_radius_top_left = 8
	_stylebox.corner_radius_top_right = 8
	_stylebox.corner_radius_bottom_left = 8
	_stylebox.corner_radius_bottom_right = 8


func _apply_font_size(font_size: int) -> void:
	var clamped_size: int = clampi(font_size, min_font_size, max_font_size)
	if _label:
		_label.add_theme_font_size_override("font_size", clamped_size)
	if _icon_label:
		_icon_label.add_theme_font_size_override("font_size", clamped_size + 4)


static func get_station_icon_symbol(station_type: String) -> String:
	match station_type:
		"workbench":
			return "🔧"
		"repair_table":
			return "🛠️"
		"trash", "trash_bin":
			return "🗑️"
		"diagnostic", "diagnostic_bench":
			return "🔍"
		"parts_shelf", "shelf":
			return "📦"
		"software", "software_station":
			return "💻"
		"reception", "reception_desk":
			return "📋"
		"delivery", "delivery_counter":
			return "✅"
		_:
			return "⚙"
