class_name WorkbenchStation
extends BaseStation

## Multi-step workbench station for disassembling devices, installing replacement parts,
## and reassembling devices.
## Accepts devices in DIAGNOSED, DISASSEMBLED, and PART_REPLACED states.

@export var work_time: float = 1.5

var _target_next_state: String = ""


func _ready() -> void:
	station_name = "Workbench"
	station_type = "workbench"
	processing_time = work_time
	accepted_device_states = ["DIAGNOSED", "DISASSEMBLED", "PART_REPLACED"]
	super._ready()


func can_player_interact(player: PlayerCharacter) -> bool:
	if _is_processing:
		return false
	if not player or not player.carry_system:
		return false

	# Case 1: Workbench is empty
	if not placed_device:
		if player.carry_system.is_carrying():
			var item: Carriable = player.carry_system.get_held_item()
			return _can_accept_workbench_item(item)
		return false

	# Case 2: Workbench has a placed item/device
	var device: Carriable = placed_device
	if not device.has_method("get_repair_state"):
		# Fallback before Phase 1D: allow picking up placed item
		return player.carry_system.can_pick_up()

	var r_state: String = str(device.get_repair_state())
	match r_state:
		"DIAGNOSED":
			return true
		"DISASSEMBLED":
			if player.carry_system.is_carrying():
				var held: Carriable = player.carry_system.get_held_item()
				return _is_valid_replacement_part(device, held)
			return false
		"PART_REPLACED":
			return true
		"REASSEMBLED":
			return player.carry_system.can_pick_up()
		_:
			return player.carry_system.can_pick_up()


func get_interaction_prompt(player: PlayerCharacter) -> String:
	if _is_processing:
		return "Working..."
	if not player or not player.carry_system:
		return ""

	if not placed_device:
		if player.carry_system.is_carrying():
			return "Place Device on Workbench"
		return ""

	var device: Carriable = placed_device
	if not device.has_method("get_repair_state"):
		return "Pick Up Device"

	var r_state: String = str(device.get_repair_state())
	match r_state:
		"DIAGNOSED":
			return "Disassemble Device"
		"DISASSEMBLED":
			if player.carry_system.is_carrying():
				return "Install Replacement Part"
			return "Need Replacement Part"
		"PART_REPLACED":
			return "Reassemble Device"
		"REASSEMBLED":
			return "Pick Up Reassembled Device"
		_:
			return "Pick Up Device"


func _on_interacted(player: PlayerCharacter) -> void:
	super._on_interacted(player)
	if not player or not player.carry_system:
		return

	# If workbench is empty, place carried item on bench
	if not placed_device:
		if player.carry_system.is_carrying():
			var item: Carriable = player.carry_system.get_held_item()
			if _can_accept_workbench_item(item):
				player.carry_system.place_on_station(self)
				accept_device(item)
		return

	var device: Carriable = placed_device
	if not device.has_method("get_repair_state"):
		if player.carry_system.can_pick_up():
			var removed: Carriable = remove_device()
			player.carry_system.pick_up(removed)
		return

	var r_state: String = str(device.get_repair_state())
	match r_state:
		"DIAGNOSED":
			_target_next_state = "DISASSEMBLED"
			start_processing()
		"DISASSEMBLED":
			if player.carry_system.is_carrying():
				var part: Carriable = player.carry_system.get_held_item()
				if _is_valid_replacement_part(device, part):
					player.carry_system.place_on_station(self)
					part.queue_free()
					if device.has_method("install_part"):
						device.install_part()
					elif device.has_method("advance_repair_state"):
						device.advance_repair_state()
					_update_visual_state()
		"PART_REPLACED":
			_target_next_state = "REASSEMBLED"
			start_processing()
		"REASSEMBLED":
			if player.carry_system.can_pick_up():
				var removed: Carriable = remove_device()
				player.carry_system.pick_up(removed)
		_:
			if player.carry_system.can_pick_up():
				var removed: Carriable = remove_device()
				player.carry_system.pick_up(removed)


func _on_processing_done() -> void:
	if placed_device:
		if placed_device.has_method("advance_repair_state"):
			placed_device.advance_repair_state()
		elif placed_device.has_method("set_repair_state") and not _target_next_state.is_empty():
			placed_device.set_repair_state(_target_next_state)
	_target_next_state = ""
	current_state = StationState.OCCUPIED
	_update_visual_state()


func _can_accept_workbench_item(item: Carriable) -> bool:
	if not item:
		return false
	if item.has_method("get_repair_state"):
		var s: String = str(item.get_repair_state())
		return s in ["DIAGNOSED", "DISASSEMBLED", "PART_REPLACED"]
	return true


func _is_valid_replacement_part(_device: Carriable, part: Carriable) -> bool:
	if not part:
		return false
	return part.item_type == "part"
