class_name WorkbenchStation
extends BaseStation

## Tool distribution and storage workbench.
## Holds limited physical tools (e.g. screwdrivers) for players to pick up and use at Repair Tables.
## Does NOT accept devices (hardware repairs are performed on dedicated Repair Tables).

@export var work_time: float = 2.0
@export var disassembly_time: float = 2.0
@export var reassembly_time: float = 2.0

@export_group("Tool Requirements")
@export var requires_tool: bool = false
@export var required_tool_id: String = "screwdriver"
@export var required_tool_name: String = "screwdriver"

var _bench_tool: ToolItem = null


func _ready() -> void:
	station_name = "Workbench"
	station_type = "workbench"
	processing_time = work_time
	accepted_device_states = []
	add_to_group("workbenches")
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


## Checks if a player has the required tool available
func _has_required_tool(player: PlayerCharacter) -> bool:
	if not requires_tool:
		return true

	# Check 1: Is the player carrying the right tool?
	if player and player.carry_system and player.carry_system.is_carrying():
		var held: Carriable = player.carry_system.get_held_item()
		if held is ToolItem and (held as ToolItem).tool_id == required_tool_id:
			return true

	# Check 2: Is there a tool on the workbench?
	_clean_bench_tool()
	if _bench_tool != null and is_instance_valid(_bench_tool):
		if _bench_tool is ToolItem and (_bench_tool as ToolItem).tool_id == required_tool_id:
			return true

	return false


## Place tool on workbench if carrying one and bench has space
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


## Pick up tool from workbench
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


func can_accept_device(_device: Carriable) -> bool:
	# Faulty devices are NEVER accepted on Workbench. Use Repair Table instead.
	return false


func _can_accept_workbench_item(_item: Carriable) -> bool:
	# Devices cannot be placed on Workbench.
	return false


func can_player_interact(player: PlayerCharacter) -> bool:
	if not super.can_player_interact(player):
		return false
	if _is_processing:
		return false
	if not player or not player.carry_system:
		return false

	var carry: CarrySystem = player.carry_system

	# Recovery case: if workbench somehow has a device on it, allow picking it up
	if placed_device != null:
		return carry.can_pick_up() or (carry.is_carrying() and carry.get_held_item() is ToolItem)

	# Case 1: Workbench has no device
	if carry.is_carrying():
		var held: Carriable = carry.get_held_item()
		if held is ToolItem:
			return true
		# Carrying device: interaction allowed to show prompt or menu explaining it cannot be placed
		return false

	# Empty hands: can pick up tool if one is on the bench
	_clean_bench_tool()
	if _bench_tool != null and is_instance_valid(_bench_tool):
		return carry.can_pick_up()

	return false


func get_interaction_prompt(player: PlayerCharacter) -> String:
	if _active_user != null and _active_user != player and is_instance_valid(_active_user):
		return "In use by P%d" % (_active_user.player_index + 1)

	if _is_processing:
		return "Working..."
	if not player or not player.carry_system:
		return ""

	var carry: CarrySystem = player.carry_system

	# Recovery case: device sitting on workbench
	if placed_device != null:
		if carry.is_carrying() and carry.get_held_item() is ToolItem:
			return "Pick Up Device (Stow/Drop Tool)"
		if carry.can_pick_up():
			return "Pick Up Device"
		return "Hands Full - Cannot Pick Up Device"

	# Workbench has no device
	if carry.is_carrying():
		var held: Carriable = carry.get_held_item()
		if held is ToolItem:
			_clean_bench_tool()
			if _bench_tool == null:
				return "Place %s on Workbench" % held.item_name
			return "Drop %s to Ground (Bench has tool)" % held.item_name
		if held is Device or held.item_type == "device":
			return "Cannot place device on Workbench (Use Repair Table)"
		return ""
	elif _bench_tool != null and is_instance_valid(_bench_tool):
		if carry.can_pick_up():
			return "Pick Up %s" % _bench_tool.tool_display_name
		return "Hands Full - Cannot Pick Up %s" % _bench_tool.tool_display_name

	return ""


func _on_interacted(player: PlayerCharacter) -> void:
	if not can_player_interact(player):
		return

	super._on_interacted(player)
	if not player or not player.carry_system:
		return

	var carry: CarrySystem = player.carry_system

	# Recovery case: pick up device if one is accidentally on the workbench
	if placed_device != null:
		_try_pick_up(player)
		return

	# Empty bench interaction
	if carry.is_carrying():
		var held: Carriable = carry.get_held_item()
		if held is ToolItem:
			_clean_bench_tool()
			if _bench_tool == null:
				_try_place_tool(player)
			else:
				player.carry_system.drop_item()
			return
	elif _bench_tool != null and is_instance_valid(_bench_tool):
		_try_pick_up_tool(player)


## Helper: Picks up device from workbench (for bug-recovery / stuck device rescue)
func _try_pick_up(player: PlayerCharacter) -> bool:
	if not player or not player.carry_system or not placed_device:
		return false

	# If carrying a tool, auto-stow tool on bench if space allows, or drop to ground
	if player.carry_system.is_carrying():
		var held: Carriable = player.carry_system.get_held_item()
		if held is ToolItem:
			_clean_bench_tool()
			if _bench_tool == null:
				_try_place_tool(player)
			else:
				player.carry_system.drop_item()

	if not player.carry_system.can_pick_up() or not placed_device:
		return false

	var removed: Carriable = remove_device()
	player.carry_system.pick_up(removed)
	current_state = StationState.IDLE
	clear_active_user(player)
	_update_visual_state()
	return true
