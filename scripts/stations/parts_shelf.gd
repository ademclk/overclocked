class_name PartsShelf
extends BaseStation

## Parts shelf station dispensing replacement components.
## Does not accept devices; players pick up needed components from here.
## Auto-dispenses the appropriate component matching the active diagnosed device's fault.

@export var dispensed_part_name: String = "Replacement Part"
@export var dispensed_part_type: String = "part"
@export var part_scene: PackedScene = null
@export var available_parts: Array[ComponentData] = []


func _ready() -> void:
	station_name = "Parts Shelf"
	station_type = "shelf"
	_load_default_parts()
	super._ready()


func can_accept_device(_device: Carriable) -> bool:
	return false


func can_player_interact(player: PlayerCharacter) -> bool:
	return (
		player != null
		and player.carry_system != null
		and player.carry_system.can_pick_up()
	)


func get_interaction_prompt(player: PlayerCharacter) -> String:
	if player and player.carry_system and not player.carry_system.can_pick_up():
		return "Hands Full"

	var needed: ComponentData = _get_needed_part()
	if needed and _has_active_diagnosed_device():
		return "Take %s" % needed.component_name

	return "Take %s" % dispensed_part_name


func _on_interacted(player: PlayerCharacter) -> void:
	super._on_interacted(player)
	if not player or not player.carry_system or not player.carry_system.can_pick_up():
		return

	var needed: ComponentData = _get_needed_part()
	var part: Carriable = _create_part_instance(needed)
	if not part:
		return

	if get_parent():
		get_parent().add_child(part)
	else:
		add_child(part)

	player.carry_system.pick_up(part)


## Returns the replacement component needed by the active repair order/device
func _get_needed_part() -> ComponentData:
	var tree := get_tree()
	if tree:
		var devices: Array[Node] = tree.get_nodes_in_group("devices")
		for node: Node in devices:
			if is_instance_valid(node) and not node.is_queued_for_deletion() and node is Device:
				var dev := node as Device
				if dev.is_diagnosed and dev.assigned_fault and dev.assigned_fault.broken_component:
					if dev.current_repair_state in [
						RepairState.State.DIAGNOSED,
						RepairState.State.DISASSEMBLED
					]:
						return dev.assigned_fault.broken_component

	if not available_parts.is_empty():
		return available_parts[0]

	return null


## Checks if an active diagnosed device is currently waiting for parts
func _has_active_diagnosed_device() -> bool:
	var tree := get_tree()
	if tree:
		var devices: Array[Node] = tree.get_nodes_in_group("devices")
		for node: Node in devices:
			if is_instance_valid(node) and not node.is_queued_for_deletion() and node is Device:
				var dev := node as Device
				if dev.is_diagnosed and dev.assigned_fault and dev.assigned_fault.broken_component:
					if dev.current_repair_state in [
						RepairState.State.DIAGNOSED,
						RepairState.State.DISASSEMBLED
					]:
						return true
	return false


## Spawns a Carriable representation of the component with metadata
func _create_part_instance(component: ComponentData) -> Carriable:
	var part: Carriable = null
	if part_scene:
		var instance: Node = part_scene.instantiate()
		if instance is Carriable:
			part = instance as Carriable
			if component:
				part.set_meta("component_data", component)
				part.item_name = component.component_name

	if not part:
		part = Carriable.new()
		part.name = component.component_id if component else "ComponentItem"
		part.item_name = component.component_name if component else dispensed_part_name
		part.item_type = dispensed_part_type
		if component:
			part.set_meta("component_data", component)

		var mesh_inst := MeshInstance3D.new()
		mesh_inst.name = "MeshInstance3D"
		var box := BoxMesh.new()
		box.size = Vector3(0.2, 0.1, 0.2)
		mesh_inst.mesh = box

		var mat := StandardMaterial3D.new()
		if component:
			match component.component_type:
				"screen":
					mat.albedo_color = Color(0.2, 0.7, 0.9)
				"battery":
					mat.albedo_color = Color(0.95, 0.8, 0.2)
				"software":
					mat.albedo_color = Color(0.65, 0.3, 0.85)
				_:
					mat.albedo_color = Color(0.3, 0.8, 0.4)
		else:
			mat.albedo_color = Color(0.1, 0.8, 0.9)

		mesh_inst.material_override = mat
		part.add_child(mesh_inst)

	part.setup_interaction_zone()
	return part


func _load_default_parts() -> void:
	if not available_parts.is_empty():
		return

	var paths: Array[String] = [
		"res://resources/components/screen.tres",
		"res://resources/components/battery.tres",
		"res://resources/components/os_installer.tres",
	]
	for path in paths:
		if ResourceLoader.exists(path):
			var res: Resource = load(path)
			if res is ComponentData:
				available_parts.append(res as ComponentData)
