class_name OverheatingHazard
extends Node

## Tracks devices on workbenches and triggers overheating if left too long.
## Attached to the WorkshopDebug (or level root), monitors all workbenches.

signal device_overheating(device: Device, station: BaseStation)
signal device_cooled(device: Device)

@export var overheat_time: float = Constants.DEFAULT_OVERHEAT_TIME  ## 20.0 seconds
@export var overheat_penalty_time: float = 5.0
@export var warning_threshold: float = 0.75

## Tracks each device on a workbench: {device_instance_id: {timer, device, station, warned, overheated}}
var _device_timers: Dictionary = {}
var _monitored_workbenches: Array[WorkbenchStation] = []


func _ready() -> void:
	add_to_group("overheating_hazards")
	_discover_workbenches()


func _physics_process(delta: float) -> void:
	# Check monitored workbenches for vulnerable devices sitting on them
	for wb in _monitored_workbenches:
		if is_instance_valid(wb) and wb.placed_device is Device:
			var dev := wb.placed_device as Device
			if dev.current_repair_state in [
				RepairState.State.DISASSEMBLED,
				RepairState.State.PART_REPLACED
			]:
				var id: int = dev.get_instance_id()
				if not _device_timers.has(id):
					_device_timers[id] = {
						"timer": 0.0,
						"device": dev,
						"station": wb,
						"warned": false,
						"overheated": false,
					}

	var to_remove: Array[int] = []
	for device_id: int in _device_timers:
		var data: Dictionary = _device_timers[device_id]
		var device: Device = data.get("device") as Device
		var station: BaseStation = data.get("station") as BaseStation

		if not is_instance_valid(device) or not is_instance_valid(station):
			to_remove.append(device_id)
			continue

		# Only tick overheat for vulnerable states
		if device.current_repair_state not in [
			RepairState.State.DISASSEMBLED,
			RepairState.State.PART_REPLACED
		]:
			if data.get("warned", false) or data.get("overheated", false):
				_remove_overheat_warning(device)
			to_remove.append(device_id)
			continue

		data["timer"] += delta

		# Warning stage — visual feedback on device
		if data["timer"] >= overheat_time * warning_threshold and not data.get("warned", false):
			data["warned"] = true
			_apply_overheat_warning(device)

		# Overheat triggered
		if data["timer"] >= overheat_time and not data.get("overheated", false):
			data["overheated"] = true
			_trigger_overheat(device, station)

	for device_id in to_remove:
		_device_timers.erase(device_id)


## Registers a workbench station to monitor
func register_workbench(wb: WorkbenchStation) -> void:
	if not wb or _monitored_workbenches.has(wb):
		return
	_monitored_workbenches.append(wb)
	wb.device_accepted.connect(_on_device_placed.bind(wb))
	wb.device_removed.connect(_on_device_removed.bind(wb))

	# If device is already placed on bench upon registration
	if wb.placed_device is Device:
		_on_device_placed(wb.placed_device, wb)


func _discover_workbenches() -> void:
	var tree := get_tree()
	if not tree:
		return
	for node in tree.get_nodes_in_group("stations"):
		if node is WorkbenchStation:
			register_workbench(node as WorkbenchStation)
	for node in tree.get_nodes_in_group("workbenches"):
		if node is WorkbenchStation:
			register_workbench(node as WorkbenchStation)
	if _monitored_workbenches.is_empty():
		var root_node: Node = get_parent() if get_parent() else tree.current_scene
		if root_node:
			var found = root_node.find_children("*", "WorkbenchStation", true, false)
			for child in found:
				if child is WorkbenchStation:
					register_workbench(child as WorkbenchStation)


func _on_device_placed(device: Carriable, station: WorkbenchStation) -> void:
	if device is Device:
		var dev := device as Device
		if dev.current_repair_state in [
			RepairState.State.DISASSEMBLED,
			RepairState.State.PART_REPLACED
		]:
			_device_timers[dev.get_instance_id()] = {
				"timer": 0.0,
				"device": dev,
				"station": station,
				"warned": false,
				"overheated": false,
			}


func _on_device_removed(device: Carriable, _station: WorkbenchStation) -> void:
	if device:
		var dev_id := device.get_instance_id()
		if _device_timers.has(dev_id):
			var data: Dictionary = _device_timers[dev_id]
			var was_overheated: bool = data.get("overheated", false)
			_device_timers.erase(dev_id)

			if device is Device:
				var dev := device as Device
				_remove_overheat_warning(dev)
				if was_overheated:
					device_cooled.emit(dev)
					SignalBus.hazard_cleared.emit("Overheat")


var _original_device_labels: Dictionary = {}


func _trigger_overheat(device: Device, station: BaseStation) -> void:
	_apply_overheat_effect(device)
	device.set_meta("is_overheated", true)
	device_overheating.emit(device, station)
	SignalBus.hazard_activated.emit("Overheat", "device_overheat")


func _apply_overheat_warning(device: Device) -> void:
	var mesh: MeshInstance3D = device.get_node_or_null("DeviceMesh") as MeshInstance3D
	if mesh:
		var mat := _get_or_create_override_material(mesh)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.6, 0.0)
		mat.emission_energy_multiplier = 2.0

	var label: Label3D = device.get_node_or_null("DeviceLabel") as Label3D
	if label:
		if not _original_device_labels.has(device.get_instance_id()):
			_original_device_labels[device.get_instance_id()] = label.text
		label.text = "⚠ HOT: %s" % _original_device_labels[device.get_instance_id()]
		label.modulate = Color(1.0, 0.6, 0.0)


func _apply_overheat_effect(device: Device) -> void:
	var mesh: MeshInstance3D = device.get_node_or_null("DeviceMesh") as MeshInstance3D
	if mesh:
		var mat := _get_or_create_override_material(mesh)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.15, 0.05)
		mat.emission_energy_multiplier = 3.5

	var label: Label3D = device.get_node_or_null("DeviceLabel") as Label3D
	if label:
		if not _original_device_labels.has(device.get_instance_id()):
			_original_device_labels[device.get_instance_id()] = label.text
		label.text = "🔥 OVERHEATED"
		label.modulate = Color(1.0, 0.2, 0.2)


func _remove_overheat_warning(device: Device) -> void:
	device.remove_meta("is_overheated")
	device.visible = true

	var mesh: MeshInstance3D = device.get_node_or_null("DeviceMesh") as MeshInstance3D
	if mesh:
		mesh.material_override = null
		mesh.visible = true

	var label: Label3D = device.get_node_or_null("DeviceLabel") as Label3D
	if label:
		var dev_id := device.get_instance_id()
		_original_device_labels.erase(dev_id)
		label.modulate = Color.WHITE
		label.visible = true
		if device.has_method("_update_label"):
			device._update_label()
		elif device.has_method("get_display_name"):
			label.text = device.get_display_name()


func _get_or_create_override_material(mesh: MeshInstance3D) -> StandardMaterial3D:
	if mesh.material_override is StandardMaterial3D:
		return mesh.material_override as StandardMaterial3D
	var base_mat: Material = mesh.get_active_material(0)
	var new_mat: StandardMaterial3D = null
	if base_mat is StandardMaterial3D:
		new_mat = (base_mat as StandardMaterial3D).duplicate() as StandardMaterial3D
	else:
		new_mat = StandardMaterial3D.new()
	mesh.material_override = new_mat
	return new_mat


## Returns whether a device is currently overheated
func is_device_overheated(device: Device) -> bool:
	if not device or not _device_timers.has(device.get_instance_id()):
		return false
	return _device_timers[device.get_instance_id()].get("overheated", false)


## Returns whether a device is currently being tracked for overheat
func is_device_tracked(device: Device) -> bool:
	return device != null and _device_timers.has(device.get_instance_id())
