class_name WorkbenchStation
extends BaseStation

## Multi-step workbench station for disassembling devices, installing replacement parts,
## and reassembling devices.
## Accepts devices in DIAGNOSED, DISASSEMBLED, and PART_REPLACED states.
## Requires a tool (e.g. screwdriver) for disassembly and reassembly operations.

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
	super._ready()


func get_bench_tool() -> ToolItem:
	return _bench_tool


## Checks if a player has the required tool available for workbench operations
func _has_required_tool(player: PlayerCharacter) -> bool:
	if not requires_tool:
		return true

	# Check 1: Is the player carrying the right tool?
	if player and player.carry_system and player.carry_system.is_carrying():
		var held: Carriable = player.carry_system.get_held_item()
		if held is ToolItem and (held as ToolItem).tool_id == required_tool_id:
			return true

	# Check 2: Is there a tool on the workbench?
	if _bench_tool != null and is_instance_valid(_bench_tool):
		if _bench_tool is ToolItem and (_bench_tool as ToolItem).tool_id == required_tool_id:
			return true

	return false


## Checks if the player is carrying an incorrect tool
func _has_wrong_tool(player: PlayerCharacter) -> bool:
	if not requires_tool:
		return false
	if player and player.carry_system and player.carry_system.is_carrying():
		var held: Carriable = player.carry_system.get_held_item()
		if held is ToolItem and (held as ToolItem).tool_id != required_tool_id:
			return true
	return false


## Updated interaction: place tool on bench if carrying one and bench has space
func _try_place_tool(player: PlayerCharacter) -> bool:
	if not player or not player.carry_system or not player.carry_system.is_carrying():
		return false

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


## Pick up the bench tool (when no device to pick up, or bench has tool but no device)
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


func can_player_interact(player: PlayerCharacter) -> bool:
	if not super.can_player_interact(player):
		return false
	if _is_processing:
		return false
	if not player or not player.carry_system:
		return false

	var carry: CarrySystem = player.carry_system

	# Case 1: Workbench has no device
	if not placed_device:
		if carry.is_carrying():
			var held: Carriable = carry.get_held_item()
			if held is ToolItem:
				return _bench_tool == null
			return _can_accept_workbench_item(held)
		# Player has empty hands: can pick up tool if one is on the bench
		if _bench_tool != null and is_instance_valid(_bench_tool):
			return carry.can_pick_up()
		return false

	# Case 2: Generic carriable fallback (for unit tests)
	if not placed_device.has_method("get_repair_state"):
		if carry.is_carrying() and carry.get_held_item() is ToolItem and _bench_tool == null:
			return true
		return carry.can_pick_up()

	# Case 3: Overheated device
	if placed_device.has_meta("is_overheated"):
		return carry.can_pick_up()

	# If carrying wrong tool, interaction is blocked
	if _has_wrong_tool(player):
		return false

	# Case 4: Carrying the required tool when bench has device but no bench tool
	if carry.is_carrying():
		var held: Carriable = carry.get_held_item()
		if held is ToolItem:
			if (held as ToolItem).tool_id == required_tool_id and _bench_tool == null:
				return true
			return false

	var r_state: String = str(placed_device.get_repair_state())
	match r_state:
		"DIAGNOSED":
			return _has_required_tool(player)
		"DISASSEMBLED":
			if carry.is_carrying():
				var held: Carriable = carry.get_held_item()
				if held is ToolItem and _bench_tool == null:
					return true
				if held.item_type == "part":
					return _is_valid_replacement_part(placed_device, held)
			return false
		"PART_REPLACED":
			if not _has_required_tool(player):
				return false
			return carry.can_pick_up() or (carry.is_carrying() and carry.get_held_item() is ToolItem and _bench_tool == null)
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

	# Case 1: Workbench has no device
	if not placed_device:
		if carry.is_carrying():
			var held: Carriable = carry.get_held_item()
			if held is ToolItem:
				if _bench_tool == null:
					return "Place %s on Workbench" % held.item_name
				return "Workbench already has a tool"
			if held is Device:
				var dev := held as Device
				if dev.assigned_fault and dev.assigned_fault.skip_states.has("DISASSEMBLED"):
					return "No hardware repair needed"
			if _can_accept_workbench_item(held):
				return "Place Device on Workbench"
		elif _bench_tool != null and is_instance_valid(_bench_tool):
			if carry.can_pick_up():
				return "Pick Up %s" % _bench_tool.tool_display_name
			return "Hands Full - Cannot Pick Up %s" % _bench_tool.tool_display_name
		return ""

	# Case 2: Generic Carriable fallback
	if not placed_device.has_method("get_repair_state"):
		if carry.is_carrying() and carry.get_held_item() is ToolItem and _bench_tool == null:
			return "Place %s on Workbench" % carry.get_held_item().item_name
		return "Pick Up Device"

	# Case 3: Overheated device
	if placed_device.has_meta("is_overheated"):
		if carry.can_pick_up():
			return "Pick Up Overheated Device (Cool Down)"
		return "Hands Full - Cannot Cool Device"

	# Case 4: Wrong tool feedback
	if _has_wrong_tool(player):
		return "Wrong Tool: Needs %s" % required_tool_name

	var r_state: String = str(placed_device.get_repair_state())
	match r_state:
		"DIAGNOSED":
			if carry.is_carrying():
				var held: Carriable = carry.get_held_item()
				if held is ToolItem and (held as ToolItem).tool_id == required_tool_id:
					return "Disassemble Device"
			if not _has_required_tool(player):
				return "Needs %s" % required_tool_name
			return "Disassemble Device"

		"DISASSEMBLED":
			if carry.is_carrying():
				var held: Carriable = carry.get_held_item()
				if held is ToolItem and _bench_tool == null:
					return "Place %s on Workbench" % held.item_name
				if held.item_type == "part":
					var part_name: String = held.item_name if not held.item_name.is_empty() else "Replacement Part"
					if _is_valid_replacement_part(placed_device, held):
						return "Install %s" % part_name
					return "Wrong Replacement Part"
				return "Wrong Item"
			if placed_device is Device:
				var dev := placed_device as Device
				if dev.assigned_fault and dev.assigned_fault.is_multi_fault:
					var missing: Array[ComponentData] = dev.get_missing_components()
					if not missing.is_empty():
						var names: PackedStringArray = []
						for m in missing:
							if m:
								names.append(m.component_name)
						return "Needs: %s" % ", ".join(names)
			return "Need Replacement Part"

		"PART_REPLACED":
			if carry.is_carrying():
				var held: Carriable = carry.get_held_item()
				if held is ToolItem and (held as ToolItem).tool_id == required_tool_id and _bench_tool == null:
					return "Place %s and Reassemble" % held.item_name
			if not _has_required_tool(player):
				return "Needs %s to reassemble" % required_tool_name
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
		if placed_device and placed_device.has_method("get_repair_state") and str(placed_device.get_repair_state()) == "DISASSEMBLED":
			if player and player.carry_system and player.carry_system.is_carrying():
				var held: Carriable = player.carry_system.get_held_item()
				if held and held.item_type == "part":
					_try_install_part(player)
		return

	super._on_interacted(player)
	if not player or not player.carry_system:
		return

	var carry: CarrySystem = player.carry_system

	# Branch 1: Bench has no device
	if not placed_device:
		if carry.is_carrying():
			var held: Carriable = carry.get_held_item()
			if held is ToolItem:
				_try_place_tool(player)
				return
			_try_place_device(player)
			return
		elif _bench_tool != null:
			_try_pick_up_tool(player)
			return
		return

	# Branch 2: Generic carriable fallback
	if not placed_device.has_method("get_repair_state"):
		if carry.is_carrying() and carry.get_held_item() is ToolItem and _bench_tool == null:
			_try_place_tool(player)
			return
		_try_pick_up(player)
		return

	# Branch 3: Overheated device pickup
	if placed_device.has_meta("is_overheated"):
		_try_pick_up(player)
		return

	# Branch 4: Player carrying a tool -> place tool on bench
	if carry.is_carrying() and carry.get_held_item() is ToolItem and _bench_tool == null:
		var placed_ok := _try_place_tool(player)
		if placed_ok and placed_device:
			var r_state_check: String = str(placed_device.get_repair_state())
			if r_state_check == "DIAGNOSED" and _has_required_tool(player):
				set_active_user(player)
				_start_disassembly()
		return

	# Branch 5: Device multi-step pipeline
	var r_state: String = str(placed_device.get_repair_state())
	match r_state:
		"DIAGNOSED":
			if _has_required_tool(player):
				set_active_user(player)
				_start_disassembly()
		"DISASSEMBLED":
			if carry.is_carrying():
				_try_install_part(player)
			else:
				_try_pick_up(player)
		"PART_REPLACED":
			if _has_required_tool(player):
				_try_reassemble(player)
		"REASSEMBLED":
			_try_pick_up(player)
		_:
			_try_pick_up(player)


## Helper: Places a carried device onto empty workbench and auto-starts disassembly if diagnosed and tool present
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

	# Auto-start disassembly for DIAGNOSED devices if tool is available
	var is_diag: bool = false
	if item is Device:
		is_diag = (item as Device).current_repair_state == RepairState.State.DIAGNOSED
	elif item.has_method("get_repair_state"):
		is_diag = str(item.get_repair_state()) == "DIAGNOSED"

	if is_diag:
		if _has_required_tool(player):
			_start_disassembly()
		else:
			current_state = StationState.OCCUPIED
			_update_visual_state()

	return true


## Helper: Starts disassembly processing
func _start_disassembly() -> void:
	_target_next_state = "DISASSEMBLED"
	processing_time = disassembly_time
	start_processing()


## Helper: Installs carried component into disassembled device, rejecting invalid parts
func _try_install_part(player: PlayerCharacter) -> bool:
	var carry: CarrySystem = player.carry_system
	if not carry.is_carrying() or not placed_device:
		return false

	var part: Carriable = carry.get_held_item()
	if not part or part.item_type != "part":
		return false

	if not _is_valid_replacement_part(placed_device, part):
		# WRONG PART REJECTION
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
		progress_label.modulate = Color(1.0, 0.2, 0.2)


## Helper: Starts reassembly processing
func _try_reassemble(player: PlayerCharacter) -> bool:
	if not _has_required_tool(player):
		return false

	if not player.carry_system.can_pick_up() and not (player.carry_system.is_carrying() and player.carry_system.get_held_item() is ToolItem):
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
		if r_state == "DIAGNOSED" and current_state == StationState.OCCUPIED:
			if not _has_required_tool(null):
				progress_label.visible = true
				progress_label.text = "NEED %s" % required_tool_name.to_upper()
				progress_label.modulate = Color(0.95, 0.35, 0.2)
		elif r_state == "DISASSEMBLED" and current_state == StationState.OCCUPIED:
			progress_label.visible = true
			if placed_device is Device and (placed_device as Device).assigned_fault and (placed_device as Device).assigned_fault.is_multi_fault:
				var missing_count: int = (placed_device as Device).get_missing_components().size()
				if missing_count > 0:
					progress_label.text = "NEED PART (%d LEFT)" % missing_count
				else:
					progress_label.text = "PARTS INSTALLED"
			else:
				progress_label.text = "NEED PART"
			progress_label.modulate = Color(0.95, 0.65, 0.15)
		elif r_state == "PART_REPLACED" and current_state == StationState.OCCUPIED:
			if not _has_required_tool(null):
				progress_label.visible = true
				progress_label.text = "NEED %s" % required_tool_name.to_upper()
				progress_label.modulate = Color(0.95, 0.35, 0.2)

	_update_device_status_label()


## Updates the station label to show component slots for multi-fault devices
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
		# Fallback if part has no component metadata
		if dev.assigned_fault:
			return not dev.get_missing_components().is_empty()
		return true

	return true
