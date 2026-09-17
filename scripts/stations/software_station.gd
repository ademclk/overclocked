class_name SoftwareStation
extends BaseStation

## Software station where reassembled devices are flashed with operating systems,
## firmware, and diagnostic test suites.
## Transitions devices from REASSEMBLED to TESTED state.

@export var software_install_time: float = 2.5


func _ready() -> void:
	station_name = "Software Station"
	station_type = "software"
	processing_time = software_install_time
	accepted_device_states = ["REASSEMBLED"]
	super._ready()


func can_player_interact(player: PlayerCharacter) -> bool:
	if _is_processing:
		return false
	if not player or not player.carry_system:
		return false

	if not placed_device and player.carry_system.is_carrying():
		return _is_valid_device_state(player.carry_system.get_held_item())

	if placed_device and current_state == StationState.COMPLETE:
		return player.carry_system.can_pick_up()

	return false


func get_interaction_prompt(player: PlayerCharacter) -> String:
	if _is_processing:
		return "Installing Software..."

	if not placed_device and player and player.carry_system and player.carry_system.is_carrying():
		if _is_valid_device_state(player.carry_system.get_held_item()):
			return "Install Software"

	if placed_device and current_state == StationState.COMPLETE:
		if player and player.carry_system and player.carry_system.can_pick_up():
			return "Pick Up Tested Device"

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
	if placed_device:
		if placed_device.has_method("install_software"):
			placed_device.install_software()
		elif placed_device.has_method("advance_repair_state"):
			placed_device.advance_repair_state()


func can_accept_device(device: Carriable) -> bool:
	return super.can_accept_device(device) and _is_valid_device_state(device)


func _is_valid_device_state(device: Carriable) -> bool:
	if device == null:
		return false
	if device is Device:
		var dev := device as Device
		return dev.current_repair_state in [
			RepairState.State.REASSEMBLED,
			RepairState.State.SOFTWARE_INSTALLED,
		]
	if device.has_method("get_repair_state"):
		return str(device.get_repair_state()) in ["REASSEMBLED", "SOFTWARE_INSTALLED"]
	return device.item_type == "device"
