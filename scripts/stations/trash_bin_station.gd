class_name TrashBin
extends BaseStation

## Disposal station for discarding wrong or unwanted components.
## Disallows discarding tools (screwdrivers) and customer devices.
## When parts are thrown away, increases the chance of creating a mess/hazard around the bin.

signal item_disposed(item_name: String)

@export var trash_mess_chance: float = 0.35  ## Chance (0-1) to spawn a mess hazard nearby when used

var _trashed_count: int = 0


func _ready() -> void:
	station_name = "Trash Bin"
	station_type = "trash"
	accepted_device_states = []
	add_to_group("trash_bins")
	super._ready()


func can_accept_device(_device: Carriable) -> bool:
	return false


func can_player_interact(player: PlayerCharacter) -> bool:
	if not super.can_player_interact(player):
		return false
	if not player or not player.carry_system or not player.carry_system.is_carrying():
		return false

	var held: Carriable = player.carry_system.get_held_item()
	if not held:
		return false

	# Tools and devices are never allowed to be thrown into the trash
	if held.item_type == "tool" or held is Device or held.item_type == "device":
		return false

	return true


func get_interaction_prompt(player: PlayerCharacter) -> String:
	if _active_user != null and _active_user != player and is_instance_valid(_active_user):
		return "In use by P%d" % (_active_user.player_index + 1)

	if not player or not player.carry_system or not player.carry_system.is_carrying():
		return ""

	var held: Carriable = player.carry_system.get_held_item()
	if not held:
		return ""

	if held.item_type == "tool":
		return "Cannot trash tools!"
	if held is Device or held.item_type == "device":
		return "Cannot trash customer devices!"

	return "Throw %s in Trash" % held.item_name


func _on_interacted(player: PlayerCharacter) -> void:
	if not can_player_interact(player):
		return

	super._on_interacted(player)
	dispose_item(player)


## Disposes of the carried item, rejecting tools and devices. Triggers mess hazard with probability.
func dispose_item(player: PlayerCharacter) -> bool:
	if not player or not player.carry_system or not player.carry_system.is_carrying():
		return false

	var held: Carriable = player.carry_system.get_held_item()
	if not held:
		return false

	if held.item_type == "tool" or held is Device or held.item_type == "device":
		return false

	var item_name: String = held.item_name
	player.carry_system.place_on_station(self)
	held.queue_free()

	_trashed_count += 1
	item_disposed.emit(item_name)
	SignalBus.item_dropped.emit(item_name, player.player_index)

	# Trigger visual feedback on trash bin
	_flash_trash_feedback()

	# Check for mess generation around the trash bin
	if randf() < trash_mess_chance:
		_spawn_trash_mess()

	return true


func _flash_trash_feedback() -> void:
	if station_label:
		station_label.text = "🗑️ TRASHED!"
		station_label.modulate = Color(0.9, 0.4, 0.4)
		var tw := create_tween()
		if tw:
			tw.tween_interval(1.2)
			tw.tween_callback(func() -> void:
				if station_label and is_instance_valid(station_label):
					station_label.text = station_name.to_upper()
					station_label.modulate = Color.WHITE
			)


func _spawn_trash_mess() -> void:
	if not is_inside_tree():
		return

	# Random offset around the trash bin
	var angle: float = randf() * TAU
	var dist: float = randf_range(0.8, 1.8)
	var mess_pos: Vector3 = global_position + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
	mess_pos.y = 0.0

	var hm := get_tree().get_first_node_in_group("hazard_managers") as HazardManager
	if hm and is_instance_valid(hm):
		if hm.has_method("spawn_floor_hazard_at"):
			hm.spawn_floor_hazard_at(mess_pos)
		elif hm.has_method("_spawn_floor_hazard"):
			hm._spawn_floor_hazard(mess_pos)
	else:
		# Standalone fallback: instantiate floor spill hazard directly
		var spill_scene := load("res://scenes/hazards/FloorSpillHazard.tscn") as PackedScene
		if spill_scene:
			var spill := spill_scene.instantiate() as FloorSpillHazard
			if spill:
				var parent_node: Node = get_parent() if get_parent() else self
				parent_node.add_child(spill)
				spill.global_position = mess_pos
				spill.spill_type = FloorSpillHazard.SpillType.SCREWS if randf() < 0.5 else FloorSpillHazard.SpillType.COFFEE
				spill.spawn_with_warning()
