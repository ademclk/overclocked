class_name ScrewMinigame
extends RepairMinigame

## Timing-based screw minigame for disassembly and reassembly.
## Sweeping indicator bounces across bar; player presses interact when aligned with sweet spot.

@export var screw_count: int = 4
@export var sweet_spot_width: float = 0.30  ## Percentage of bar width
@export var indicator_speed: float = 2.0   ## Sweeps per second

var current_screw: int = 0
var indicator_position: float = 0.0  ## 0.0 - 1.0
var indicator_direction: float = 1.0
var sweet_spot_center: float = 0.5
var perfect_hits: int = 0

@onready var title_label: Label = get_node_or_null("Panel/VBox/TitleLabel") as Label
@onready var progress_label: Label = get_node_or_null("Panel/VBox/ProgressLabel") as Label
@onready var bar_container: Control = get_node_or_null("Panel/VBox/BarContainer") as Control
@onready var sweet_spot_rect: ColorRect = get_node_or_null("Panel/VBox/BarContainer/SweetSpot") as ColorRect
@onready var indicator_rect: ColorRect = get_node_or_null("Panel/VBox/BarContainer/Indicator") as ColorRect
@onready var timer_label: Label = get_node_or_null("Panel/VBox/TimerLabel") as Label


func _init() -> void:
	minigame_type_name = "screw"


func _on_minigame_started(device: Device, _fault: FaultData) -> void:
	var tier: int = 1
	if device and device.device_data:
		tier = device.device_data.difficulty_tier

	match tier:
		1:
			screw_count = 4
			sweet_spot_width = 0.30
			indicator_speed = 1.5
		2:
			screw_count = 6
			sweet_spot_width = 0.20
			indicator_speed = 2.0
		3:
			screw_count = 8
			sweet_spot_width = 0.12
			indicator_speed = 2.5

	current_screw = 0
	perfect_hits = 0
	indicator_position = 0.0
	indicator_direction = 1.0
	_randomize_sweet_spot()
	_update_ui()


func _process_minigame(delta: float) -> void:
	indicator_position += indicator_speed * indicator_direction * delta

	if indicator_position >= 1.0:
		indicator_position = 1.0
		indicator_direction = -1.0
	elif indicator_position <= 0.0:
		indicator_position = 0.0
		indicator_direction = 1.0

	_update_ui()


func _handle_minigame_input(event: InputEvent) -> void:
	var player_idx: int = owning_player_index
	var interact := MultiplayerInput.action_name(player_idx, MultiplayerInput.BASE_INTERACT)

	if event.is_action_pressed(interact) or (player_idx == 0 and event is InputEventKey and event.pressed and (event.keycode == KEY_E or event.keycode == KEY_SPACE)):
		_on_player_hit()
		get_viewport().set_input_as_handled()


func _on_player_hit() -> void:
	var distance: float = absf(indicator_position - sweet_spot_center)
	if distance <= sweet_spot_width * 0.5:
		# Hit!
		current_screw += 1
		if distance <= sweet_spot_width * 0.18:
			perfect_hits += 1

		if current_screw >= screw_count:
			var rating: int = 3 if perfect_hits >= int(screw_count * 0.6) else 2
			_complete_minigame(rating)
		else:
			_randomize_sweet_spot()
	else:
		# Miss! Reset indicator
		indicator_position = 0.0
		indicator_direction = 1.0


func _randomize_sweet_spot() -> void:
	sweet_spot_center = randf_range(0.2, 0.8)


func _update_ui() -> void:
	if progress_label:
		progress_label.text = "Screws Remaining: %d / %d" % [screw_count - current_screw, screw_count]
	if timer_label:
		timer_label.text = "⏱ %.1fs left" % maxf(0.0, time_limit - time_elapsed)

	if bar_container and sweet_spot_rect and indicator_rect:
		var bar_w: float = bar_container.size.x
		if bar_w > 0.0:
			var spot_w: float = bar_w * sweet_spot_width
			var spot_x: float = (bar_w * sweet_spot_center) - (spot_w * 0.5)
			sweet_spot_rect.position.x = spot_x
			sweet_spot_rect.size.x = spot_w

			var ind_w: float = 6.0
			indicator_rect.size.x = ind_w
			indicator_rect.position.x = clampf(bar_w * indicator_position - ind_w * 0.5, 0.0, bar_w - ind_w)
