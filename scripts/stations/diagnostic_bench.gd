class_name DiagnosticBench
extends BaseStation

## Diagnostic bench station where players place undiagnosed devices to reveal their faults.
## Devices in RECEIVED state are diagnosed after a brief processing period.

@export var diagnosis_time: float = 2.0


func _ready() -> void:
	station_name = "Diagnostic Bench"
	station_type = "diagnostic"
	processing_time = diagnosis_time
	accepted_device_states = ["RECEIVED"]
	super._ready()


func can_player_interact(player: PlayerCharacter) -> bool:
	if _is_processing:
		return false
	if not player or not player.carry_system:
		return false

	# If empty, can interact if holding a valid received device
	if not placed_device and player.carry_system.is_carrying():
		return _is_valid_device_state(player.carry_system.get_held_item())

	# If diagnosed and complete, player can pick up if hands are free
	if placed_device and current_state == StationState.COMPLETE:
		return player.carry_system.can_pick_up()

	return false


func get_interaction_prompt(player: PlayerCharacter) -> String:
	if _is_processing:
		return "Diagnosing..."

	if not placed_device and player and player.carry_system and player.carry_system.is_carrying():
		if _is_valid_device_state(player.carry_system.get_held_item()):
			return "Diagnose Device"

	if placed_device and current_state == StationState.COMPLETE:
		if player and player.carry_system and player.carry_system.can_pick_up():
			return "Pick Up Diagnosed Device"

	return ""


func _on_interacted(player: PlayerCharacter) -> void:
	super._on_interacted(player)
	if not player or not player.carry_system:
		return

	if not placed_device and player.carry_system.is_carrying():
		var device: Carriable = player.carry_system.get_held_item()
		if _is_valid_device_state(device):
			player.carry_system.place_on_station(self)
			accept_device(device)
			start_processing()
	elif placed_device and current_state == StationState.COMPLETE:
		if player.carry_system.can_pick_up():
			var device: Carriable = remove_device()
			player.carry_system.pick_up(device)


func _on_processing_done() -> void:
	if placed_device and placed_device.has_method("diagnose"):
		placed_device.diagnose()


func _is_valid_device_state(device: Carriable) -> bool:
	if device == null:
		return false
	if device.has_method("get_repair_state"):
		return str(device.get_repair_state()) == "RECEIVED"
	# Fallback before Phase 1D device system is wired
	return true
