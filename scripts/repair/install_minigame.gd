class_name InstallMinigame
extends RepairMinigame

## Part installation minigame (alignment & snap).
## Player adjusts component position with move_left/move_right, then confirms with interact.

@export var move_speed: float = 1.2
@export var alignment_tolerance: float = 0.20

var component_pos: float = 0.1  ## 0.0 - 1.0
var target_slot_pos: float = 0.5  ## 0.0 - 1.0

@onready var title_label: Label = get_node_or_null("Panel/VBox/TitleLabel") as Label
@onready var bar_container: Control = get_node_or_null("Panel/VBox/BarContainer") as Control
@onready var slot_rect: ColorRect = get_node_or_null("Panel/VBox/BarContainer/TargetSlot") as ColorRect
@onready var component_rect: ColorRect = get_node_or_null("Panel/VBox/BarContainer/Component") as ColorRect
@onready var timer_label: Label = get_node_or_null("Panel/VBox/TimerLabel") as Label


func _init() -> void:
	minigame_type_name = "install"


func _on_minigame_started(device: Device, fault: FaultData) -> void:
	var tier: int = 1
	if device and device.device_data:
		tier = device.device_data.difficulty_tier

	match tier:
		1:
			alignment_tolerance = 0.25
		2:
			alignment_tolerance = 0.18
		3:
			alignment_tolerance = 0.10

	target_slot_pos = randf_range(0.3, 0.7)
	component_pos = 0.05 if target_slot_pos > 0.5 else 0.95
	_update_ui()


func _process_minigame(delta: float) -> void:
	var player_idx: int = owning_player_index
	var left_action := MultiplayerInput.action_name(player_idx, "move_left")
	var right_action := MultiplayerInput.action_name(player_idx, "move_right")

	var input_x: float = 0.0
	if Input.is_action_pressed(left_action) or (player_idx == 0 and (Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT))):
		input_x -= 1.0
	if Input.is_action_pressed(right_action) or (player_idx == 0 and (Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT))):
		input_x += 1.0

	if input_x != 0.0:
		component_pos = clampf(component_pos + input_x * move_speed * delta, 0.0, 1.0)
		_update_ui()


func _handle_minigame_input(event: InputEvent) -> void:
	var player_idx: int = owning_player_index
	var interact := MultiplayerInput.action_name(player_idx, MultiplayerInput.BASE_INTERACT)

	if event.is_action_pressed(interact) or (player_idx == 0 and event is InputEventKey and event.pressed and (event.keycode == KEY_E or event.keycode == KEY_SPACE)):
		_on_confirm_snap()
		get_viewport().set_input_as_handled()


func _on_confirm_snap() -> void:
	var distance: float = absf(component_pos - target_slot_pos)
	if distance <= alignment_tolerance * 0.5:
		var rating: int = 3 if distance <= alignment_tolerance * 0.2 else 2
		_complete_minigame(rating)
	else:
		# Misaligned: bounce back
		component_pos = clampf(component_pos + (0.2 if component_pos < target_slot_pos else -0.2), 0.0, 1.0)
		_update_ui()


func _update_ui() -> void:
	if timer_label:
		timer_label.text = "⏱ %.1fs left" % maxf(0.0, time_limit - time_elapsed)

	if bar_container and slot_rect and component_rect:
		var bar_w: float = bar_container.size.x
		if bar_w > 0.0:
			var slot_w: float = bar_w * alignment_tolerance
			slot_rect.size.x = slot_w
			slot_rect.position.x = (bar_w * target_slot_pos) - (slot_w * 0.5)

			var comp_w: float = slot_w * 0.8
			component_rect.size.x = comp_w
			component_rect.position.x = clampf((bar_w * component_pos) - (comp_w * 0.5), 0.0, bar_w - comp_w)
