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
	if not super.can_player_interact(player):
		return false
	if _is_processing:
		return false
	if not player or not player.carry_system:
		return false

	if not placed_device and player.carry_system.is_carrying():
		return _is_valid_device_state(player.carry_system.get_held_item())

	if placed_device:
		return true

	return false


func get_interaction_prompt(player: PlayerCharacter) -> String:
	if _active_user != null and _active_user != player and is_instance_valid(_active_user):
		return "In use by P%d" % (_active_user.player_index + 1)

	if _is_processing:
		return "Installing Software..."

	if not placed_device and player and player.carry_system and player.carry_system.is_carrying():
		if _is_valid_device_state(player.carry_system.get_held_item()):
			return "Install Software"

	if placed_device:
		var is_tested: bool = (current_state == StationState.COMPLETE) or (placed_device.has_method("get_repair_state") and str(placed_device.get_repair_state()) == "TESTED")
		if is_tested:
			if player and player.carry_system:
				if player.carry_system.can_pick_up():
					return "Pick Up Tested Device"
				elif player.carry_system.is_carrying() and player.carry_system.get_held_item() is ToolItem:
					return "Pick Up Tested Device (Drop Tool)"
			return "Tested (Hands Full)"
		return "Inspect & Flash OS"

	return ""


func _on_interacted(player: PlayerCharacter) -> void:
	if not can_player_interact(player):
		return

	super._on_interacted(player)
	if not player or not player.carry_system:
		return

	var is_tested: bool = placed_device != null and ((current_state == StationState.COMPLETE) or (placed_device.has_method("get_repair_state") and str(placed_device.get_repair_state()) == "TESTED"))

	if not placed_device and player.carry_system.is_carrying():
		var device: Carriable = player.carry_system.get_held_item()
		if _is_valid_device_state(device):
			set_active_user(player)
			player.carry_system.place_on_station(self)
			accept_device(device)
			if not (device is Device):
				start_processing()
			else:
				current_state = StationState.OCCUPIED
				_update_visual_state()
	elif placed_device and is_tested:
		if player.carry_system.is_carrying() and player.carry_system.get_held_item() is ToolItem:
			player.carry_system.drop_item()
		if player.carry_system.can_pick_up():
			var dev = remove_device()
			if dev:
				player.carry_system.pick_up(dev)
	elif placed_device:
		open_examination_workstation(player)


func _on_processing_done() -> void:
	if placed_device:
		if placed_device.has_method("install_software"):
			placed_device.install_software()
		elif placed_device.has_method("advance_repair_state"):
			placed_device.advance_repair_state()
	if _active_user != null and not _focusing_players.has(_active_user):
		clear_active_user()


func can_accept_device(device: Carriable) -> bool:
	return super.can_accept_device(device) and _is_valid_device_state(device)


func _is_valid_device_state(device: Carriable) -> bool:
	if device == null:
		return false
	if device is Device:
		var dev := device as Device
		if dev.assigned_fault and dev.assigned_fault.skip_states.has("DISASSEMBLED"):
			if dev.current_repair_state == RepairState.State.DIAGNOSED:
				return true
		return dev.current_repair_state in [
			RepairState.State.REASSEMBLED,
			RepairState.State.SOFTWARE_INSTALLED,
		]
	if device.has_method("get_repair_state"):
		return str(device.get_repair_state()) in ["REASSEMBLED", "SOFTWARE_INSTALLED"]
	return device.item_type == "device"
