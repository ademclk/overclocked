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
	if not super.can_player_interact(player):
		return false
	if _is_processing:
		return false
	if not player or not player.carry_system:
		return false

	# If empty, can interact if holding a valid received device
	if not placed_device and player.carry_system.is_carrying():
		return _is_valid_device_state(player.carry_system.get_held_item())

	# If device on bench, can interact to inspect/work
	if placed_device:
		return true

	return false


func get_interaction_prompt(player: PlayerCharacter) -> String:
	if _active_user != null and _active_user != player and is_instance_valid(_active_user):
		return "In use by P%d" % (_active_user.player_index + 1)

	if _is_processing:
		return "Diagnosing..."

	if not placed_device and player and player.carry_system and player.carry_system.is_carrying():
		if _is_valid_device_state(player.carry_system.get_held_item()):
			return "Diagnose Device"

	if placed_device:
		var is_diag: bool = (current_state == StationState.COMPLETE) or (placed_device is Device and (placed_device as Device).is_diagnosed)
		if is_diag:
			if player and player.carry_system and player.carry_system.can_pick_up():
				return "Pick Up Diagnosed Device"
			return "Diagnosed (Hands Full)"
		return "Inspect & Diagnose"

	return ""


func _on_interacted(player: PlayerCharacter) -> void:
	if not can_player_interact(player):
		return

	super._on_interacted(player)
	if not player or not player.carry_system:
		return

	var is_diag: bool = placed_device != null and ((current_state == StationState.COMPLETE) or (placed_device is Device and (placed_device as Device).is_diagnosed))

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
	elif placed_device and is_diag and player.carry_system.can_pick_up():
		var device: Carriable = remove_device()
		player.carry_system.pick_up(device)
	elif placed_device:
		open_examination_workstation(player)


func _on_processing_done() -> void:
	if placed_device and placed_device.has_method("diagnose"):
		placed_device.diagnose()
	if placed_device is Device:
		_display_diagnosis(placed_device as Device)


## Updates station label and progress label to reveal diagnosis, including all tags for multi-fault
func _display_diagnosis(device: Device) -> void:
	if not device or not device.assigned_fault:
		return
	var fault: FaultData = device.assigned_fault
	var fault_text := ""
	if fault.is_multi_fault:
		var tag_list: String = ", ".join(fault.fault_display_tags) if not fault.fault_display_tags.is_empty() else fault.fault_name
		fault_text = "Fault: %s\nNeeds: %s" % [fault.fault_name, tag_list]
	else:
		fault_text = "Fault: %s" % fault.fault_name

	if progress_label:
		progress_label.visible = true
		progress_label.text = fault_text
		progress_label.modulate = Color(0.2, 0.9, 0.4)
	if station_label:
		station_label.text = "%s\n%s" % [station_name.to_upper(), fault_text]


func remove_device() -> Carriable:
	var dev := super.remove_device()
	if station_label:
		station_label.text = station_name.to_upper()
	if progress_label:
		progress_label.visible = false
	return dev


func can_accept_device(device: Carriable) -> bool:
	return super.can_accept_device(device) and _is_valid_device_state(device)


func _is_valid_device_state(device: Carriable) -> bool:
	if device == null:
		return false
	if device is Device:
		return (device as Device).current_repair_state == RepairState.State.RECEIVED
	if device.has_method("get_repair_state"):
		return str(device.get_repair_state()) == "RECEIVED"
	# Fallback for generic Carriable in station unit tests
	return device.item_type == "device"
