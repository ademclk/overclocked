class_name WorkbenchStation
extends BaseStation

## Multi-step workbench station for disassembling devices, installing replacement parts,
## and reassembling devices.
## Accepts devices in DIAGNOSED, DISASSEMBLED, and PART_REPLACED states.

@export var disassembly_time: float = 2.0
@export var reassembly_time: float = 2.0
@export var work_time: float = 2.0

var _target_next_state: String = ""


func _ready() -> void:
	station_name = "Workbench"
	station_type = "workbench"
	processing_time = work_time
	accepted_device_states = ["DIAGNOSED", "DISASSEMBLED", "PART_REPLACED"]
	add_to_group("workbenches")
	super._ready()


func can_accept_device(device: Carriable) -> bool:
	return super.can_accept_device(device) and _can_accept_workbench_item(device)


func can_player_interact(player: PlayerCharacter) -> bool:
	if not super.can_player_interact(player):
		return false
	if _is_processing:
		return false
	if not player or not player.carry_system:
		return false

	var carry: CarrySystem = player.carry_system

	# Case 1: Workbench is empty
	if not placed_device:
		if carry.is_carrying():
			return _can_accept_workbench_item(carry.get_held_item())
		return false

	# Case 2: Generic carriable fallback (for unit tests)
	if not placed_device.has_method("get_repair_state"):
		return carry.can_pick_up()

	# Case 3: Device on bench
	if placed_device.has_meta("is_overheated"):
		return carry.can_pick_up()

	var r_state: String = str(placed_device.get_repair_state())
	match r_state:
		"DIAGNOSED":
			return true
		"DISASSEMBLED":
			if carry.is_carrying():
				return _is_valid_replacement_part(placed_device, carry.get_held_item())
			return false
		"PART_REPLACED":
			return carry.can_pick_up()
		"REASSEMBLED":
			return carry.can_pick_up()
		_:
			return carry.can_pick_up()


func get_interaction_prompt(player: PlayerCharacter) -> String:
	if _active_user != null and _active_user != player and is_instance_valid(_active_user):
		return "In use by P%d" % (_active_user.player_index + 1)

	if _is_processing:
		return "Working..."
	if not player or not player.carry_system:
		return ""

	var carry: CarrySystem = player.carry_system

	# Workbench empty
	if not placed_device:
		if carry.is_carrying():
			var held: Carriable = carry.get_held_item()
			if _can_accept_workbench_item(held):
				return "Place Device on Workbench"
		return ""

	# Generic Carriable fallback
	if not placed_device.has_method("get_repair_state"):
		return "Pick Up Device"

	if placed_device.has_meta("is_overheated"):
		if carry.can_pick_up():
			return "Pick Up Overheated Device (Cool Down)"
		return "Hands Full - Cannot Cool Device"

	var r_state: String = str(placed_device.get_repair_state())
	match r_state:
		"DIAGNOSED":
			return "Disassemble Device"
		"DISASSEMBLED":
			if carry.is_carrying():
				var held: Carriable = carry.get_held_item()
				if _is_valid_replacement_part(placed_device, held):
					var part_name: String = held.item_name if not held.item_name.is_empty() else "Replacement Part"
					return "Install %s" % part_name
				return "Wrong Replacement Part"
			return "Need Replacement Part"
		"PART_REPLACED":
			if carry.can_pick_up():
				return "Reassemble Device"
			return "Hands Full - Cannot Reassemble"
		"REASSEMBLED":
			if carry.can_pick_up():
				return "Pick Up Reassembled Device"
			return "Hands Full - Cannot Pick Up"
		_:
			return "Pick Up Device"


func _on_interacted(player: PlayerCharacter) -> void:
	if not can_player_interact(player):
		return

	super._on_interacted(player)
	if not player or not player.carry_system:
		return

	var carry: CarrySystem = player.carry_system

	# Branch 1: Bench is empty -> Try place device
	if not placed_device:
		_try_place_device(player)
		return

	# Branch 2: Generic carriable fallback
	if not placed_device.has_method("get_repair_state"):
		_try_pick_up(player)
		return

	# Branch 3: Overheated device pickup
	if placed_device.has_meta("is_overheated"):
		_try_pick_up(player)
		return

	# Branch 4: Device multi-step pipeline
	var r_state: String = str(placed_device.get_repair_state())
	match r_state:
		"DIAGNOSED":
			set_active_user(player)
			_start_disassembly()
		"DISASSEMBLED":
			if carry.is_carrying():
				_try_install_part(player)
			else:
				_try_pick_up(player)
		"PART_REPLACED":
			_try_reassemble(player)
		"REASSEMBLED":
			_try_pick_up(player)
		_:
			_try_pick_up(player)


## Helper: Places a carried device onto empty workbench and auto-starts disassembly if diagnosed
func _try_place_device(player: PlayerCharacter) -> bool:
	var carry: CarrySystem = player.carry_system
	if not carry.is_carrying():
		return false

	var item: Carriable = carry.get_held_item()
	if not _can_accept_workbench_item(item):
		return false

	set_active_user(player)
	carry.place_on_station(self)
	accept_device(item)

	# Auto-start disassembly for DIAGNOSED devices
	if item is Device:
		var dev := item as Device
		if dev.current_repair_state == RepairState.State.DIAGNOSED:
			_start_disassembly()
	elif item.has_method("get_repair_state") and str(item.get_repair_state()) == "DIAGNOSED":
		_start_disassembly()

	return true


## Helper: Starts disassembly processing
func _start_disassembly() -> void:
	_target_next_state = "DISASSEMBLED"
	processing_time = disassembly_time
	start_processing()


## Helper: Installs carried component into disassembled device
func _try_install_part(player: PlayerCharacter) -> bool:
	var carry: CarrySystem = player.carry_system
	if not carry.is_carrying() or not placed_device:
		return false

	var part: Carriable = carry.get_held_item()
	if not _is_valid_replacement_part(placed_device, part):
		return false

	set_active_user(player)

	if placed_device is Device:
		var dev := placed_device as Device
		var comp: ComponentData = part.get_meta("component_data", null) as ComponentData
		if comp:
			dev.try_install_component(comp)
		carry.place_on_station(self)
		part.queue_free()
		dev.advance_state(RepairState.State.PART_REPLACED)
	elif placed_device.has_method("install_part"):
		carry.place_on_station(self)
		part.queue_free()
		placed_device.install_part()
	elif placed_device.has_method("advance_repair_state"):
		carry.place_on_station(self)
		part.queue_free()
		placed_device.advance_repair_state()

	current_state = StationState.OCCUPIED
	_update_visual_state()
	return true


## Helper: Starts reassembly processing
func _try_reassemble(player: PlayerCharacter) -> bool:
	if not player.carry_system.can_pick_up():
		return false

	set_active_user(player)
	_target_next_state = "REASSEMBLED"
	processing_time = reassembly_time
	start_processing()
	return true


## Helper: Picks up device from workbench
func _try_pick_up(player: PlayerCharacter) -> bool:
	if not player.carry_system.can_pick_up() or not placed_device:
		return false

	var removed: Carriable = remove_device()
	player.carry_system.pick_up(removed)
	return true


func _on_processing_done() -> void:
	if placed_device:
		if placed_device is Device:
			var dev := placed_device as Device
			if _target_next_state == "DISASSEMBLED":
				dev.advance_state(RepairState.State.DISASSEMBLED)
				current_state = StationState.OCCUPIED
			elif _target_next_state == "REASSEMBLED":
				dev.advance_state(RepairState.State.REASSEMBLED)
				current_state = StationState.COMPLETE
			elif dev.current_repair_state == RepairState.State.DIAGNOSED:
				dev.advance_state(RepairState.State.DISASSEMBLED)
				current_state = StationState.OCCUPIED
			elif dev.current_repair_state == RepairState.State.PART_REPLACED:
				dev.advance_state(RepairState.State.REASSEMBLED)
				current_state = StationState.COMPLETE
		elif placed_device.has_method("advance_repair_state"):
			placed_device.advance_repair_state()
			if str(placed_device.get_repair_state()) == "DISASSEMBLED":
				current_state = StationState.OCCUPIED
			else:
				current_state = StationState.COMPLETE
		elif placed_device.has_method("set_repair_state") and not _target_next_state.is_empty():
			placed_device.set_repair_state(_target_next_state)
			if _target_next_state == "DISASSEMBLED":
				current_state = StationState.OCCUPIED
			else:
				current_state = StationState.COMPLETE

	_target_next_state = ""
	_update_visual_state()
	if _active_user != null and not _focusing_players.has(_active_user):
		clear_active_user()


func _update_visual_state() -> void:
	super._update_visual_state()
	if not progress_label:
		return

	if placed_device and placed_device.has_method("get_repair_state"):
		var r_state: String = str(placed_device.get_repair_state())
		if r_state == "DISASSEMBLED" and current_state == StationState.OCCUPIED:
			progress_label.visible = true
			progress_label.text = "NEED PART"
			progress_label.modulate = Color(0.95, 0.65, 0.15)


func _can_accept_workbench_item(item: Carriable) -> bool:
	if not item:
		return false
	if item is Device:
		var dev := item as Device
		return dev.current_repair_state in [
			RepairState.State.DIAGNOSED,
			RepairState.State.DISASSEMBLED,
			RepairState.State.PART_REPLACED,
		]
	if item.has_method("get_repair_state"):
		var s: String = str(item.get_repair_state())
		return s in ["DIAGNOSED", "DISASSEMBLED", "PART_REPLACED"]
	return item.item_type == "device"


func _is_valid_replacement_part(device: Carriable, part: Carriable) -> bool:
	if not part or part.item_type != "part":
		return false

	if device is Device:
		var dev := device as Device
		var comp: ComponentData = part.get_meta("component_data", null) as ComponentData
		if comp:
			if dev.assigned_fault and dev.assigned_fault.broken_component:
				return comp.component_id == dev.assigned_fault.broken_component.component_id
			return true
		# Fallback if part has no component metadata
		return dev.assigned_fault == null or dev.assigned_fault.broken_component == null

	return true
