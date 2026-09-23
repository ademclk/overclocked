class_name RepairMinigame
extends Control

## Base class for interactive workbench repair minigames.
## Emits completion, failure, and skip signals. Supports accessibility skip with penalty.

signal minigame_completed(rating: int)
signal minigame_failed()
signal minigame_skipped()

@export var owning_player_index: int = 0
@export var minigame_type_name: String = "generic"
@export var time_limit: float = 8.0
@export var skip_penalty: float = Constants.MINIGAME_SKIP_PENALTY_TIER_1

var is_active: bool = false
var time_elapsed: float = 0.0
var _current_device: Device = null
var _current_fault: FaultData = null
var _owning_player: PlayerCharacter = null


func _ready() -> void:
	visible = false


func start_minigame(player: PlayerCharacter, device: Device, fault: FaultData = null) -> void:
	_owning_player = player
	if player:
		owning_player_index = player.player_index
		player.set_movement_locked(true)
	_current_device = device
	_current_fault = fault
	time_elapsed = 0.0
	is_active = true
	visible = true

	var tier: int = 1
	if device and device.device_data:
		tier = device.device_data.difficulty_tier

	match tier:
		1:
			skip_penalty = Constants.MINIGAME_SKIP_PENALTY_TIER_1
		2:
			skip_penalty = Constants.MINIGAME_SKIP_PENALTY_TIER_2
		3:
			skip_penalty = Constants.MINIGAME_SKIP_PENALTY_TIER_3

	_on_minigame_started(device, fault)
	SignalBus.minigame_started.emit(owning_player_index, minigame_type_name)


func _process(delta: float) -> void:
	if not is_active:
		return

	time_elapsed += delta
	_process_minigame(delta)

	if time_elapsed >= time_limit:
		_on_minigame_failed()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active:
		return

	# Check for skip input (Tab key / Select button)
	if event.is_action_pressed(&"examine") or (event is InputEventKey and event.pressed and event.keycode == KEY_TAB):
		skip_minigame()
		get_viewport().set_input_as_handled()
		return

	_handle_minigame_input(event)


func skip_minigame() -> void:
	if not is_active:
		return

	is_active = false
	visible = false
	if _owning_player and is_instance_valid(_owning_player):
		_owning_player.set_movement_locked(false)

	minigame_skipped.emit()
	SignalBus.minigame_skipped.emit(owning_player_index, minigame_type_name)


func _complete_minigame(rating: int = 2) -> void:
	if not is_active:
		return

	is_active = false
	visible = false
	if _owning_player and is_instance_valid(_owning_player):
		_owning_player.set_movement_locked(false)

	minigame_completed.emit(rating)
	SignalBus.minigame_completed.emit(owning_player_index, minigame_type_name, rating)


func _on_minigame_failed() -> void:
	if not is_active:
		return

	is_active = false
	visible = false
	if _owning_player and is_instance_valid(_owning_player):
		_owning_player.set_movement_locked(false)

	minigame_failed.emit()
	SignalBus.minigame_failed.emit(owning_player_index, minigame_type_name)


## Virtual methods to be overridden by subclasses
func _on_minigame_started(_device: Device, _fault: FaultData) -> void:
	pass


func _process_minigame(_delta: float) -> void:
	pass


func _handle_minigame_input(_event: InputEvent) -> void:
	pass
