class_name InspectionHotspot
extends Control

## Resident Evil style 3D interactive inspection hotspot badge.
## Features a circular action glyph (e.g. (X) or [E]), a downward arrow pointing
## directly to a 3D coordinate on the device model, and an action description pill.

signal activated(hotspot: InspectionHotspot)

var target_3d_pos: Vector3 = Vector3.ZERO
var target_normal: Vector3 = Vector3.UP
var action_id: String = ""
var action_label: String = ""
var action_callable: Callable = Callable()
var glyph: String = "X"
var is_enabled: bool = true
var disabled_reason: String = ""
var is_defect_highlight: bool = false

var is_hovered: bool = false
var pulse_time: float = 0.0

const BADGE_RADIUS: float = 16.0
const ARROW_HEIGHT: float = 8.0
const ARROW_WIDTH: float = 14.0


func _init(id: String = "", label: String = "", pos3d: Vector3 = Vector3.ZERO, callback: Callable = Callable()) -> void:
	action_id = id
	action_label = label
	target_3d_pos = pos3d
	action_callable = callback
	mouse_filter = MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(160, 48)
	size = custom_minimum_size


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _process(delta: float) -> void:
	pulse_time += delta * 4.0
	queue_redraw()


func _on_mouse_entered() -> void:
	is_hovered = true
	queue_redraw()


func _on_mouse_exited() -> void:
	is_hovered = false
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			trigger_action()
			accept_event()


func trigger_action() -> void:
	if not is_enabled:
		return
	activated.emit(self)
	if action_callable.is_valid():
		action_callable.call()


func _draw() -> void:
	var center_x := size.x * 0.5
	var circle_center := Vector2(center_x, BADGE_RADIUS + 4.0)

	var ring_color: Color = Color(1.0, 1.0, 1.0, 0.95)
	var fill_color: Color = Color(0.06, 0.08, 0.12, 0.90)

	if is_defect_highlight:
		var pulse := (sin(pulse_time) + 1.0) * 0.5
		ring_color = Color(1.0, 0.25, 0.25, 0.95)
		fill_color = Color(0.5 + pulse * 0.4, 0.05, 0.05, 0.92)
	elif is_hovered:
		ring_color = Color(1.0, 0.85, 0.25, 1.0)
		fill_color = Color(0.18, 0.15, 0.05, 0.95)
	elif not is_enabled:
		ring_color = Color(0.5, 0.5, 0.55, 0.6)
		fill_color = Color(0.08, 0.08, 0.1, 0.7)

	# 1. Subtle glowing pulse aura when hovered
	if is_hovered:
		var glow_rad := BADGE_RADIUS + 4.0 + sin(pulse_time * 1.5) * 2.0
		draw_arc(circle_center, glow_rad, 0, TAU, 32, Color(1.0, 0.85, 0.25, 0.35), 3.0)

	# 2. Main circular badge fill & outline
	draw_circle(circle_center, BADGE_RADIUS, fill_color)
	draw_arc(circle_center, BADGE_RADIUS, 0, TAU, 32, ring_color, 2.0, true)

	# 3. Downward pointing arrow ▼ (attached to bottom of circle)
	var arrow_top_y := circle_center.y + BADGE_RADIUS
	var arrow_tip_y := arrow_top_y + ARROW_HEIGHT
	var arrow_pts: PackedVector2Array = [
		Vector2(center_x - ARROW_WIDTH * 0.5, arrow_top_y - 1.0),
		Vector2(center_x + ARROW_WIDTH * 0.5, arrow_top_y - 1.0),
		Vector2(center_x, arrow_tip_y)
	]
	draw_colored_polygon(arrow_pts, ring_color)

	# 4. Glyph text inside circle (e.g. X, E, 🔧)
	var font := ThemeDB.fallback_font
	var font_size := 14
	var glyph_text := glyph if is_enabled else "—"
	var text_size := font.get_string_size(glyph_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := circle_center + Vector2(-text_size.x * 0.5, text_size.y * 0.35)
	draw_string(font, text_pos, glyph_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, ring_color)

	# 5. Label pill below or above
	if not action_label.is_empty():
		var label_font_size := 12
		var display_text := action_label
		if not is_enabled and not disabled_reason.is_empty():
			display_text = "%s (%s)" % [action_label, disabled_reason]

		var l_size := font.get_string_size(display_text, HORIZONTAL_ALIGNMENT_CENTER, -1, label_font_size)
		var pill_rect := Rect2(
			center_x - (l_size.x * 0.5) - 6.0,
			arrow_tip_y + 4.0,
			l_size.x + 12.0,
			l_size.y + 4.0
		)
		var pill_bg := Color(0.04, 0.05, 0.08, 0.88)
		draw_rect(pill_rect, pill_bg, true)
		draw_rect(pill_rect, ring_color * Color(1, 1, 1, 0.6), false, 1.0)
		var l_pos := Vector2(center_x - (l_size.x * 0.5), pill_rect.position.y + l_size.y)
		var l_col := Color.WHITE if is_enabled else Color(0.65, 0.65, 0.7)
		draw_string(font, l_pos, display_text, HORIZONTAL_ALIGNMENT_CENTER, -1, label_font_size, l_col)
