class_name WorkbenchStation
extends BaseStation

## Primary hardware repair workbench for Overclocked.
## Performs hardware repair operations: disassembly, component installation, and reassembly.
## Accepts devices in DIAGNOSED, DISASSEMBLED, and PART_REPLACED states.
## Physical screwdriver tool requirement is removed; repairs are performed directly on this bench.

@export var disassembly_time: float = 2.0
@export var reassembly_time: float = 2.0
@export var work_time: float = 2.0

@export_group("Tool Requirements")
@export var requires_tool: bool = false
@export var required_tool_id: String = "screwdriver"
@export var required_tool_name: String = "screwdriver"

var _target_next_state: String = ""
var _bench_tool: ToolItem = null


func _ready() -> void:
	station_name = "Workbench"
	station_type = "workbench"
	processing_time = work_time
	accepted_device_states = ["DIAGNOSED", "DISASSEMBLED", "PART_REPLACED"]
	add_to_group("workbenches")
	add_to_group("repair_tables")
	super._ready()


func _clean_bench_tool() -> void:
	if _bench_tool != null:
		if not is_instance_valid(_bench_tool) or _bench_tool.is_held or _bench_tool.is_queued_for_deletion():
			_bench_tool = null
		elif _bench_tool.get_parent() != self and (device_slot == null or _bench_tool.get_parent() != device_slot):
			_bench_tool = null


func get_bench_tool() -> ToolItem:
	_clean_bench_tool()
	return _bench_tool


## Checks if a player has the required tool available (always true now that physical tools are removed)
func _has_required_tool(_player: PlayerCharacter) -> bool:
	if not requires_tool:
		return true
	_clean_bench_tool()
	if _bench_tool != null and is_instance_valid(_bench_tool):
		return true
	if _player and _player.carry_system and _player.carry_system.is_carrying():
		var held: Carriable = _player.carry_system.get_held_item()
		if held is ToolItem:
			return true
	return true


func _has_wrong_tool(_player: PlayerCharacter) -> bool:
	return false


## Place tool on workbench if carrying one (preserved for compatibility)
func _try_place_tool(player: PlayerCharacter) -> bool:
	if not player or not player.carry_system or not player.carry_system.is_carrying():
		return false

	_clean_bench_tool()
	var held: Carriable = player.carry_system.get_held_item()
	if held is ToolItem and _bench_tool == null:
		var tool: ToolItem = held as ToolItem
		player.carry_system.place_on_station(self)

		_bench_tool = tool
		if tool.get_parent():
			tool.get_parent().remove_child(tool)
		if device_slot:
			device_slot.add_child(tool)
			tool.position = Vector3(0.35, 0.0, 0.0)
		else:
			add_child(tool)
			tool.position = Vector3(0.35, 0.9, 0.0)
		_update_visual_state()
		return true

	return false


## Pick up tool from workbench (preserved for compatibility)
func _try_pick_up_tool(player: PlayerCharacter) -> bool:
	if _bench_tool and is_instance_valid(_bench_tool) and player and player.carry_system and player.carry_system.can_pick_up():
		var tool: ToolItem = _bench_tool
		_bench_tool = null
		if tool.get_parent():
			tool.get_parent().remove_child(tool)
		player.carry_system.pick_up(tool)
		_update_visual_state()
		return true
	return false


func can_accept_device(device: Carriable) -> bool:
	return super.can_accept_device(device) and _can_accept_workbench_item(device)


func _can_accept_workbench_item(item: Carriable) -> bool:
	if not item:
		return false
	if item is Device:
		var dev := item as Device
		if dev.assigned_fault and dev.assigned_fault.skip_states.has("DISASSEMBLED"):
			return false
		return dev.current_repair_state in [
			RepairState.State.DIAGNOSED,
			RepairState.State.DISASSEMBLED,
			RepairState.State.PART_REPLACED,
		]
	if item.has_method("get_repair_state"):
		var s: String = str(item.get_repair_state())
		return s in ["DIAGNOSED", "DISASSEMBLED", "PART_REPLACED"]
	return item.item_type == "device"


func can_player_interact(player: PlayerCharacter) -> bool:
	if not super.can_player_interact(player):
		return false
	if _is_processing:
		return false
	if not player or not player.carry_system:
		return false

	var carry: CarrySystem = player.carry_system

	# Case 1: Bench has no device
	if not placed_device:
		if carry.is_carrying():
			var held: Carriable = carry.get_held_item()
			if held is ToolItem:
				return true
			return _can_accept_workbench_item(held)
		_clean_bench_tool()
		if _bench_tool != null and is_instance_valid(_bench_tool):
			return carry.can_pick_up()
		return false

	# Case 2: Generic carriable fallback
	if not placed_device.has_method("get_repair_state"):
		return carry.can_pick_up()

	# Case 3: Overheated device
	if placed_device.has_meta("is_overheated"):
		return carry.can_pick_up()

	var r_state: String = str(placed_device.get_repair_state())
	match r_state:
		"DIAGNOSED":
			return true
		"DISASSEMBLED":
			if carry.is_carrying():
				var held: Carriable = carry.get_held_item()
				if held.item_type == "part":
					return _is_valid_replacement_part(placed_device, held)
			return true
		"PART_REPLACED":
			return true
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

	# Case 1: Bench has no device
	if not placed_device:
		if carry.is_carrying():
			var held: Carriable = carry.get_held_item()
			if held is ToolItem:
				_clean_bench_tool()
				if _bench_tool == null:
					return "Place %s on Workbench" % held.item_name
				return "Drop %s to Ground (Bench has tool)" % held.item_name
			if held is Device:
				var dev := held as Device
				if dev.assigned_fault and dev.assigned_fault.skip_states.has("DISASSEMBLED"):
					return "No hardware repair needed (Use Software Station)"
				if dev.current_repair_state == RepairState.State.RECEIVED:
					return "Diagnose at Diagnostic Bench first"
				if dev.current_repair_state == RepairState.State.REASSEMBLED:
					return "Hardware repaired (Use Software Station)"
				if dev.current_repair_state == RepairState.State.TESTED:
					return "Device tested (Take to Delivery Counter)"
			if _can_accept_workbench_item(held):
				return "Place Device on Workbench"
		elif _bench_tool != null and is_instance_valid(_bench_tool):
			if carry.can_pick_up():
				return "Pick Up %s" % _bench_tool.tool_display_name
			return "Hands Full - Cannot Pick Up %s" % _bench_tool.tool_display_name
		return ""

	# Case 2: Generic Carriable fallback
	if not placed_device.has_method("get_repair_state"):
		return "Pick Up Device"

	# Case 3: Overheated device
	if placed_device.has_meta("is_overheated"):
		if carry.can_pick_up():
			return "Pick Up Overheated Device (Cool Down)"
		return "Hands Full - Cannot Cool Device"

	var r_state: String = str(placed_device.get_repair_state())
	match r_state:
		"DIAGNOSED":
			return "Inspect & Disassemble"

		"DISASSEMBLED":
			if carry.is_carrying():
				var held: Carriable = carry.get_held_item()
				if held.item_type == "part":
					if _is_valid_replacement_part(placed_device, held):
						return "Install %s" % held.item_name
					return "Wrong Part - Need matching component"
			return "Need replacement part (Get from Parts Shelf)"

		"PART_REPLACED":
			return "Inspect & Reassemble"

		"REASSEMBLED":
			if carry.can_pick_up():
				return "Pick Up Reassembled Device"
			return "Hands Full"

		_:
			if carry.can_pick_up():
				return "Pick Up Device"
			return ""


func _on_interacted(player: PlayerCharacter) -> void:
	if not can_player_interact(player):
		return

	super._on_interacted(player)
	if not player or not player.carry_system:
		return

	var carry: CarrySystem = player.carry_system

	# Case 1: Empty workbench
	if not placed_device:
		if carry.is_carrying():
			var held: Carriable = carry.get_held_item()
			if held is ToolItem:
				_clean_bench_tool()
				if _bench_tool == null:
					_try_place_tool(player)
				else:
					player.carry_system.drop_item()
				return
			if _can_accept_workbench_item(held):
				_try_place_device(player)
				return
		elif _bench_tool != null and is_instance_valid(_bench_tool):
			_try_pick_up_tool(player)
		return

	# Case 2: Overheated device
	if placed_device.has_meta("is_overheated"):
		_try_pick_up(player)
		return

	# Case 3: Interaction by repair state
	var r_state: String = str(placed_device.get_repair_state()) if placed_device.has_method("get_repair_state") else ""
	match r_state:
		"DIAGNOSED":
			open_examination_workstation(player)
		"DISASSEMBLED":
			if carry.is_carrying():
				var held: Carriable = carry.get_held_item()
				if held.item_type == "part":
					if _is_valid_replacement_part(placed_device, held):
						_try_install_part(player)
					else:
						_flash_wrong_part()
						SignalBus.hazard_activated.emit("Wrong Part", "wrong_part")
				else:
					open_examination_workstation(player)
			else:
				open_examination_workstation(player)
		"PART_REPLACED":
			open_examination_workstation(player)
		"REASSEMBLED":
			if carry.can_pick_up() and not carry.is_carrying():
				_try_pick_up(player)
			else:
				open_examination_workstation(player)
		_:
			if carry.can_pick_up() and not carry.is_carrying():
				_try_pick_up(player)
			else:
				open_examination_workstation(player)


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

	current_state = StationState.OCCUPIED
	_update_visual_state()
	return true


func _start_disassembly() -> void:
	_target_next_state = "DISASSEMBLED"
	processing_time = disassembly_time
	start_processing()


func _try_install_part(player: PlayerCharacter) -> bool:
	var carry: CarrySystem = player.carry_system
	if not carry.is_carrying() or not placed_device:
		return false

	var part: Carriable = carry.get_held_item()
	if not part or part.item_type != "part":
		return false

	if not _is_valid_replacement_part(placed_device, part):
		_flash_wrong_part()
		SignalBus.hazard_activated.emit("Wrong Part", "wrong_part")
		return false

	set_active_user(player)

	if placed_device is Device:
		var dev := placed_device as Device
		var comp: ComponentData = part.get_meta("component_data") as ComponentData if part.has_meta("component_data") else null
		if comp:
			dev.try_install_component(comp)
		carry.place_on_station(self)
		part.queue_free()
		var advanced: bool = dev.install_part()
		_update_device_status_label()
		if not advanced:
			current_state = StationState.OCCUPIED
			_update_visual_state()
			return true
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


func _flash_wrong_part() -> void:
	if station_label:
		station_label.text = "✗ WRONG PART"
		station_label.modulate = Color(1.0, 0.2, 0.2)
		var tween := create_tween()
		if tween:
			tween.tween_interval(1.5)
			tween.tween_callback(func() -> void:
				if station_label and is_instance_valid(station_label):
					station_label.text = station_name.to_upper()
					station_label.modulate = Color.WHITE
			)
	if progress_label:
		progress_label.visible = true
		progress_label.text = "WRONG PART"


func _start_reassembly() -> void:
	_target_next_state = "REASSEMBLED"
	processing_time = reassembly_time
	start_processing()


func _try_pick_up(player: PlayerCharacter) -> bool:
	var carry: CarrySystem = player.carry_system
	if not placed_device:
		return false

	if not carry.can_pick_up():
		return false

	var dev: Carriable = remove_device()
	carry.pick_up(dev)
	current_state = StationState.IDLE
	clear_active_user(player)
	_update_visual_state()
	return true


func _on_processing_done() -> void:
	if not placed_device:
		return

	if placed_device is Device:
		var dev := placed_device as Device
		match _target_next_state:
			"DISASSEMBLED":
				dev.advance_state(RepairState.State.DISASSEMBLED)
			"REASSEMBLED":
				dev.advance_state(RepairState.State.REASSEMBLED)
	elif placed_device.has_method("advance_repair_state"):
		placed_device.advance_repair_state()

	_target_next_state = ""
	current_state = StationState.OCCUPIED
	_update_visual_state()


func _update_device_status_label() -> void:
	if not placed_device or not placed_device is Device:
		if station_label:
			station_label.text = station_name.to_upper()
		return
	var device := placed_device as Device
	if not device.assigned_fault or not device.assigned_fault.is_multi_fault:
		return

	var required: Array[ComponentData] = device.assigned_fault.get_required_components()
	var missing: Array[ComponentData] = device.get_missing_components()
	var status_lines: PackedStringArray = []
	for comp: ComponentData in required:
		if comp:
			var is_installed: bool = not missing.any(func(m: ComponentData) -> bool: return m != null and m.component_id == comp.component_id)
			status_lines.append("%s %s" % ["✓" if is_installed else "○", comp.component_name])

	if station_label:
		station_label.text = "%s\n%s" % [station_name.to_upper(), "\n".join(status_lines)]


func remove_device() -> Carriable:
	var dev := super.remove_device()
	if station_label:
		station_label.text = station_name.to_upper()
	return dev


func _is_valid_replacement_part(device: Carriable, part: Carriable) -> bool:
	if not part or part.item_type != "part":
		return false

	if device is Device:
		var dev := device as Device
		var comp: ComponentData = part.get_meta("component_data") as ComponentData if part.has_meta("component_data") else null
		if comp:
			if dev.assigned_fault:
				var missing := dev.get_missing_components()
				return missing.any(func(c: ComponentData) -> bool: return c != null and c.component_id == comp.component_id)
			return true
		if dev.assigned_fault:
			return not dev.get_missing_components().is_empty()
		return true

	return true
